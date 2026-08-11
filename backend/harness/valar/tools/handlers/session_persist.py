"""Session persist handler -- the auto session-end's write half.

Follows the standalone ``handler(args) -> ToolResult`` contract (the tool-registry
idiom) but is NOT registered in tools.yaml: the model never calls it. The idle
watchdog (gateway/session_end.py) invokes it directly when a session ends. Keeping
it a standalone handler means it is unit-testable with no live loop and shares the
graceful-degrade posture of the other Engram-backed handlers.

It performs two writes:
  1. The session diary -> Engram Thoughts via the shared
     ``Server.tools.brain_sync.save_session_to_engram`` (the same store the
     legacy server and Selene's daily review consume). The summary is passed in
     PRECOMPUTED (Valar generates it through its own brain seam) -- this process
     must never enter ModelManager's load_deep_llm path.
  2. The continuity note -> ``Engram/state/valar-continuity.json`` so the NEXT
     session's SCX opens with "Previous session: ...".
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path

from ...memory.continuity import write_continuity
from ..spec import ToolResult

logger = logging.getLogger("valar.tools.session_persist")



async def persist_session(args: dict) -> ToolResult:
    """args: {session_id: str, persona: str, history: [{role, content}],
    summary: {title, summary, ...}, write_continuity?: bool}. Writes the Engram
    diary entry (3+ user-turn threshold applies there) and optionally the
    continuity note. Continuity is skipped for an explicit client new_session
    so the next turn does not reopen with "Previous session: ...". Never raises."""
    session_id = str(args.get("session_id") or "unknown")
    persona = str(args.get("persona") or "unknown")
    history = args.get("history") or []
    summary = args.get("summary") or {}
    summary_text = str(summary.get("summary") or "").strip()
    title = str(summary.get("title") or "").strip()
    want_continuity = bool(args.get("write_continuity", True))

    # 2) Continuity note first -- it must survive even if the diary write fails.
    continuity_ok = False
    if want_continuity and summary_text:
        continuity_ok = write_continuity(persona, summary_text, title)

    # 1) Engram Thoughts diary via the shared brain_sync writer.
    saved: dict = {"saved": False, "reason": "brain_sync_unavailable"}
    try:
        from memory.brain_sync import save_session_to_engram  # type: ignore

        saved = await save_session_to_engram(
            session_id, history, persona, summary=summary or None
        )
    except Exception as exc:  # noqa: BLE001 - persistence must never raise
        logger.warning("Engram session save failed: %s", exc)
        saved = {"saved": False, "reason": str(exc)}

    detail = saved.get("thought_slug") or saved.get("reason") or ""
    logger.info(
        "session %s persisted: diary=%s (%s) continuity=%s",
        session_id,
        saved.get("saved"),
        detail,
        continuity_ok,
    )
    return ToolResult(
        content=f"session persisted (diary={saved.get('saved')}, continuity={continuity_ok})",
        ok=bool(saved.get("saved") or continuity_ok),
        data={"diary": saved, "continuity": continuity_ok},
    )
