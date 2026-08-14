"""Session-continuity note — the SCX bridge between sessions.

When the idle watchdog ends a session, the persist handler writes a one-line
summary here; the context assembler renders it into the next session's
"# Current context" block ("Previous session (...): ..."), so a fresh session
opens knowing where the last one left off — information AND reasoning carry
over, harness-level, identical on every client.

Stored in Engram (the private per-machine layer) under ``state/`` — it is
operator-specific session state, not shared knowledge. All reads/writes degrade
gracefully when the Engram junction is absent on this machine.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime
from pathlib import Path

from ..config.settings import HearthConfigError, hearth_engram

logger = logging.getLogger("valar.memory.continuity")

def continuity_path() -> Path:
    """The note the next session opens with. Under the memory tree, so it
    belongs to the user rather than to the product."""
    return hearth_engram() / "state" / "hearth-continuity.json"

# A continuity note older than this is stale enough to stop surfacing — the
# operator's context has moved on. (The file is overwritten on each session end.)
MAX_AGE_DAYS = 7


def write_continuity(persona: str, summary: str, title: str = "") -> bool:
    """Persist the latest session's continuity note. Returns False (logged, not
    raised) when Engram is unavailable."""
    try:
        path = continuity_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(
                {
                    "ended_at": datetime.now().isoformat(timespec="seconds"),
                    "persona": persona,
                    "title": title,
                    "summary": summary,
                },
                indent=2,
            ),
            encoding="utf-8",
        )
        return True
    except Exception as exc:  # noqa: BLE001 - continuity is additive
        logger.warning("could not write continuity note: %s", exc)
        return False


def clear_continuity() -> bool:
    """Drop the continuity note. Used by an explicit client new_session so the
    next turn does not reopen with the session that was just dismissed."""
    try:
        path = continuity_path()
        if path.is_file():
            path.unlink()
        return True
    except Exception as exc:  # noqa: BLE001
        logger.warning("could not clear continuity note: %s", exc)
        return False


def read_continuity() -> dict | None:
    """The latest continuity note, or None when absent/stale/unreadable."""
    try:
        path = continuity_path()
        if not path.is_file():
            return None
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict) or not str(data.get("summary") or "").strip():
            return None
        ended_at = datetime.fromisoformat(str(data.get("ended_at", "")))
        if (datetime.now() - ended_at).days >= MAX_AGE_DAYS:
            return None
        return data
    except Exception as exc:  # noqa: BLE001 - continuity is additive
        logger.debug("could not read continuity note: %s", exc)
        return None


def render_continuity_line(data: dict | None) -> str:
    """One SCX line for the previous session, or empty when none."""
    if not data:
        return ""
    when = ""
    try:
        ended = datetime.fromisoformat(str(data.get("ended_at", "")))
        when = ended.strftime("%A %I:%M %p").replace(" 0", " ")
    except Exception:  # noqa: BLE001
        pass
    summary = str(data.get("summary") or "").strip()
    prefix = f"Previous session ({when}): " if when else "Previous session: "
    return prefix + summary
