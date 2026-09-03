"""The review fork: ten turns in, one short call that asks what to keep.

Spec section 3, "prompted, not scheduled", of
docs/superpowers/specs/2026-09-02-persona-private-memory-design.md. The
honesty footer says what the notes are for; this is what makes them fill.
One tool-free call over a snapshot of the session asks two questions, with
"nothing to save" a legal and common answer. It never speaks, never blocks
the turn it follows, and a failure is a logged warning.
"""

from __future__ import annotations

import asyncio
import json
import logging
from dataclasses import replace
from datetime import date
from pathlib import Path

from ..brain.provider import BrainStreamResult, ChatMessage
from . import persona_memory as pm

logger = logging.getLogger("valar.memory.review")

EVERY_N_TURNS = 10
MAX_SNAPSHOT_CHARS = 6000
MAX_PER_FILE = 3
STATE_FILE = "review.json"

# One review per persona at a time. A second turn arriving while the first
# review is still generating would queue behind it on the single slot and
# save the same two facts twice.
_in_flight: set[str] = set()

_PROMPT = (
    "Read the exchange below, which is your own recent conversation. Answer "
    "two questions and nothing else.\n"
    "1. What did the operator reveal about themselves that will still be true "
    "next week? A preference, a plan, a fact about their life or work.\n"
    "2. What did they ask you for going forward, that you should carry into "
    "the next conversation?\n\n"
    'Reply with JSON only: {"user": ["..."], "notes": ["..."]}. Each entry '
    "one short sentence, no date (the date is added for you). Both lists may "
    "be empty; empty is the right answer more often than not. Do not save "
    "anything already obvious from who you are, and do not save the "
    "conversation itself."
)


def _state_path(root: Path) -> Path:
    return Path(root) / STATE_FILE


def due(root: Path, day: str | None = None) -> int | None:
    """The turn count that has come due, or None. Reads the plan 1 log."""
    day = day or date.today().isoformat()
    count = len(pm.read_log(root, day))
    if count == 0 or count % EVERY_N_TURNS != 0:
        return None
    path = _state_path(root)
    try:
        seen = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    except (OSError, json.JSONDecodeError):
        seen = {}
    if seen.get("day") == day and int(seen.get("count") or 0) >= count:
        return None
    return count


def _mark(root: Path, day: str, count: int) -> None:
    try:
        _state_path(root).write_text(
            json.dumps({"day": day, "count": count}), encoding="utf-8"
        )
    except OSError as exc:  # noqa: BLE001
        logger.warning("review state not written: %s", exc)


def _field(turn, key: str) -> str:
    if isinstance(turn, dict):
        return str(turn.get(key) or "")
    return str(getattr(turn, key, "") or "")


def _snapshot(history: list) -> str:
    lines: list[str] = []
    for turn in list(history)[-EVERY_N_TURNS:]:
        user = _field(turn, "user")
        assistant = _field(turn, "assistant")
        if user:
            lines.append(f"Operator: {user}")
        if assistant:
            lines.append(f"You: {assistant}")
    return "\n".join(lines)[-MAX_SNAPSHOT_CHARS:]


async def run_review(brain, opts, root: Path, persona: str, history: list) -> dict:
    saved: dict[str, list[str]] = {"notes": [], "user": []}
    snapshot = _snapshot(history)
    if not snapshot.strip():
        return saved

    review_opts = replace(opts, tools=None, enable_thinking=False, max_tokens=400)
    result = BrainStreamResult()
    parts: list[str] = []
    async for delta in brain.chat(
        [ChatMessage(role="user", content=f"{_PROMPT}\n\n{snapshot}")],
        review_opts,
        result,
    ):
        parts.append(delta)
    raw = "".join(parts).strip()
    start, end = raw.find("{"), raw.rfind("}")
    if start < 0 or end <= start:
        logger.info("%s review: no JSON in the reply, nothing saved", persona)
        return saved
    try:
        parsed = json.loads(raw[start : end + 1])
    except json.JSONDecodeError:
        logger.info("%s review: unparsable JSON, nothing saved", persona)
        return saved

    for key, filename, cap in (
        ("notes", pm.NOTES_FILE, pm.NOTES_CAP),
        ("user", pm.USER_FILE, pm.USER_CAP),
    ):
        items = parsed.get(key)
        if not isinstance(items, list):
            continue
        for item in items[:MAX_PER_FILE]:
            text = " ".join(str(item).split())
            if len(text) < 8:
                continue
            try:
                saved[key].append(pm.append_entry(Path(root) / filename, text, cap))
            except pm.CapExceeded:
                logger.info("%s review: %s is full, nothing saved there", persona, key)
                break
            except Exception as exc:  # noqa: BLE001
                logger.warning("%s review write failed: %s", persona, exc)
    logger.info(
        "%s review saved %d note(s), %d user fact(s)",
        persona, len(saved["notes"]), len(saved["user"]),
    )
    return saved


def schedule(
    brain, opts, root: Path, persona: str, history: list, day: str | None = None
) -> None:
    """Fire the review if it is due. Never blocks, never raises, one per persona."""
    day = day or date.today().isoformat()
    if persona in _in_flight:
        return
    count = due(root, day)
    if count is None:
        return
    # Marked BEFORE the call, not after: a review that dies halfway should
    # not fire again on the next turn, because the next multiple of ten is
    # only ten turns away.
    _mark(root, day, count)
    _in_flight.add(persona)
    snapshot = list(history)

    async def _go() -> None:
        try:
            await run_review(brain, opts, root, persona, snapshot)
        except Exception as exc:  # noqa: BLE001 - a review must never break a turn
            logger.warning("%s review fork failed: %s", persona, exc)
        finally:
            _in_flight.discard(persona)

    try:
        asyncio.get_running_loop().create_task(_go())
    except RuntimeError:
        _in_flight.discard(persona)
        logger.debug("no running loop; review not scheduled")
