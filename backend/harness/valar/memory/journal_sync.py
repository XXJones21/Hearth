"""Journal sync: promoting session records into the memory tree.

The session record is written as a conversation happens and costs nothing but
a file append. The Engram diary is the curated version: a title, a summary,
the decisions worth keeping. Writing the second one needs a model, and a model
is exactly what a shutdown does not have time for.

So the two are separated. A record is durable the moment a turn lands. Sync
promotes it later, when there is time: at session end on the normal path, and
on this clock for everything the normal path missed, which is every
conversation ended by a crash, a kill, or a client that walked away.

Sync only touches SETTLED records. A conversation whose last turn was two
minutes ago is one the operator is probably still having, and summarising it
would file a diary that is wrong by the next sentence.

The routine is its own switch, the same convention the daily review follows:
a section in ``Areas/routines.md``. Delete the section and the house stops
doing it. There is no hidden state and no settings screen.
"""

from __future__ import annotations

import asyncio
import logging
import time
from datetime import datetime
from pathlib import Path

logger = logging.getLogger("valar.journal_sync")

ROUTINE_TITLE = "Journal sync"
# A conversation is settled when nothing has been said for this long.
SETTLE_MINUTES = 30
# Same half-hour cadence as the daily review; neither is urgent.
CHECK_S = 1800.0
FIRST_CHECK_DELAY_S = 300.0
# One tick promotes a handful, so a machine that has been offline for a week
# catches up over several ticks instead of blocking the loop on fifty
# summaries.
MAX_PER_TICK = 5

_ROUTINE_BLOCK = f"""
## {ROUTINE_TITLE}

- **Who:** the house
- **When:** every half hour
- **What:** writes up conversations that ended without one. Every conversation
  is already saved word for word the moment it happens; this is the pass that
  gives the settled ones a title and a summary in the Journal.
- **Stop it:** delete this section.
"""


def engram_root() -> Path | None:
    """The memory tree, or None when there is not one."""
    from ..config.settings import HearthConfigError, hearth_engram

    try:
        root = hearth_engram()
    except HearthConfigError:
        return None
    return root if root.is_dir() else None


def _routines_file(root: Path) -> Path:
    return root / "Areas" / "routines.md"


def ensure_routine(root: Path) -> bool:
    """Write the routine's section if the record does not carry it yet."""
    path = _routines_file(root)
    try:
        text = path.read_text(encoding="utf-8") if path.exists() else ""
    except OSError:
        return False
    if ROUTINE_TITLE.lower() in text.lower():
        return False
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8", newline="\n") as fh:
            if text and not text.endswith("\n"):
                fh.write("\n")
            fh.write(_ROUTINE_BLOCK)
    except OSError as exc:
        logger.warning("journal sync: could not write the routine record (%s)", exc)
        return False
    logger.info("journal sync: routine written to %s", path)
    return True


def routine_enabled(root: Path) -> bool:
    """Whether the section still stands. The record is the switch."""
    try:
        return ROUTINE_TITLE.lower() in _routines_file(root).read_text(encoding="utf-8").lower()
    except OSError:
        return False


def _settled(record: dict, minutes: int = SETTLE_MINUTES) -> bool:
    stamp = str(record.get("last_turn_at") or "")
    if not stamp:
        return True
    try:
        last = datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%S").timestamp()
    except ValueError:
        return True
    return (time.time() - last) >= minutes * 60


def pending(minutes: int = SETTLE_MINUTES, limit: int = MAX_PER_TICK) -> list[dict]:
    """Records the journal has never been given, and which have gone quiet."""
    from .session_record import unsynced

    out = [r for r in unsynced(min_turns=1) if _settled(r, minutes)]
    return out[:limit]


async def promote(record: dict, personas, brain, config) -> bool:
    """Give one record the write-up it never got. Never raises."""
    session_id = str(record.get("session_id") or "")
    try:
        from ..gateway.session import Session
        from ..gateway.session_end import summarize_session
        from ..gateway.session_resume import parse_chatlog
        from ..tools.handlers.session_persist import persist_session
        from .session_record import mark_synced, read_record

        full = read_record(session_id)
        if not full:
            return False
        turns = parse_chatlog(str(full.get("chatlog") or ""))
        if not turns:
            # Nothing to write up, but nothing to keep asking about either.
            mark_synced(session_id, "")
            return False

        persona_name = str(record.get("persona") or "") or personas.current_name()
        try:
            persona = personas.load(persona_name)
        except Exception:  # noqa: BLE001 - a renamed persona must not strand a record
            persona = personas.current()

        # summarize_session reads a Session; the record IS the session, just
        # from disk instead of memory.
        stand_in = Session(session_id=session_id)
        stand_in.history = list(turns)
        summary = await summarize_session(stand_in, persona, brain, config)

        history_dicts: list[dict] = []
        for turn in turns:
            if turn.user:
                history_dicts.append({"role": "user", "content": turn.user})
            if turn.assistant:
                history_dicts.append({"role": "assistant", "content": turn.assistant})

        result = await persist_session(
            {
                "session_id": session_id,
                "persona": persona.name,
                "history": history_dicts,
                "summary": summary,
                # A conversation from hours ago must not become the note the
                # NEXT one opens with.
                "write_continuity": False,
            }
        )
        diary = (result.data or {}).get("diary") or {}
        mark_synced(session_id, str(diary.get("thought_slug") or ""))
        logger.info(
            "journal sync: promoted %s (%s)",
            session_id,
            diary.get("thought_slug") or diary.get("reason") or "no slug",
        )
        return bool(diary.get("saved") or diary.get("chatlog_only"))
    except Exception as exc:  # noqa: BLE001 - one bad record never stops the pass
        logger.warning("journal sync: %s could not be promoted (%s)", session_id, exc)
        return False


async def run_pass(personas, brain, config) -> int:
    """One tick's work. Returns how many records were written up."""
    root = engram_root()
    if root is None:
        return 0
    ensure_routine(root)
    if not routine_enabled(root):
        return 0
    done = 0
    for record in pending():
        if await promote(record, personas, brain, config):
            done += 1
    return done


async def journal_sync_loop(personas, brain, config) -> None:
    """The routine's clock. Started by the gateway; never raises."""
    await asyncio.sleep(FIRST_CHECK_DELAY_S)
    while True:
        try:
            written = await run_pass(personas, brain, config)
            if written:
                logger.info("journal sync: %d conversation(s) written up", written)
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001 - the clock outlives any bad tick
            logger.exception("journal sync tick failed; continuing")
        await asyncio.sleep(CHECK_S)
