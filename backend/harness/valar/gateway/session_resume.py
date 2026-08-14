"""Resume a Journal diary into the live WebSocket session.

Protocol choice (Slice 3): resume seeds a *new* session_id with the old
transcript. It does not continue the archived session_id, so ledger rows and
the next diary write stay cleanly separated from the archived one.

Source of truth is Engram ``Thoughts/<slug>/chatlog.md`` — the same file the
Sessions tab already lists via ``GET /journal/session/{slug}``.
"""

from __future__ import annotations

import logging
import re
from pathlib import Path

from .context import Turn
from .journal import _engram_root

logger = logging.getLogger("valar.session_resume")

_HEADING_RE = re.compile(
    r"(?m)^###\s+(User|Assistant)\s*\([^)]*\)\s*$"
)


def parse_chatlog(text: str) -> list[Turn]:
    """Parse brain_sync chatlog.md into ordered user/assistant turns."""
    if not text or not text.strip():
        return []

    parts = _HEADING_RE.split(text)
    if len(parts) < 3:
        return []

    pending_user: str | None = None
    turns: list[Turn] = []

    for i in range(1, len(parts) - 1, 2):
        role = parts[i].strip().lower()
        body = parts[i + 1]
        body = re.sub(r"(?m)^\s*---\s*$", "", body).strip()
        if role == "user":
            if pending_user is not None:
                turns.append(Turn(user=pending_user, assistant=""))
            pending_user = body
        elif role == "assistant":
            if pending_user is not None:
                turns.append(Turn(user=pending_user, assistant=body))
                pending_user = None
            elif body:
                turns.append(Turn(user="", assistant=body))

    if pending_user is not None:
        turns.append(Turn(user=pending_user, assistant=""))

    return turns


def load_journal_turns(slug: str, repo_root: Path | None = None) -> list[Turn] | None:
    """Load turns for a Thoughts slug, or None if the diary/chatlog is missing."""
    if not slug or "/" in slug or "\\" in slug or ".." in slug:
        return None

    root = _engram_root(repo_root or Path("."))
    if root is None:
        logger.warning("resume: Engram unavailable")
        return None

    chatlog = root / "Thoughts" / slug / "chatlog.md"
    if not chatlog.is_file():
        return None

    try:
        text = chatlog.read_text(encoding="utf-8", errors="replace")[:200_000]
    except OSError as exc:
        logger.warning("resume: cannot read %s: %s", chatlog, exc)
        return None

    return parse_chatlog(text)
