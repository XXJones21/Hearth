"""Session persist handler -- the auto session-end's write half.

Follows the standalone ``handler(args) -> ToolResult`` contract (the tool-registry
idiom) but is NOT registered in tools.yaml: the model never calls it. The idle
watchdog (gateway/session_end.py) invokes it directly when a session ends. Keeping
it a standalone handler means it is unit-testable with no live loop and shares the
graceful-degrade posture of the other Engram-backed handlers.

It performs two writes:
  1. The session diary -> Engram Thoughts via the shared
     ``memory.brain_sync.save_session_to_engram`` (the same store the
     legacy server and Selene's daily review consume). The summary is passed in
     PRECOMPUTED (Valar generates it through its own brain seam) -- this process
     must never enter ModelManager's load_deep_llm path.
  2. The continuity note -> ``Engram/state/hearth-continuity.json`` so the NEXT
     session's SCX opens with "Previous session: ...".
"""

from __future__ import annotations

import logging
import os
import re
from datetime import datetime
from pathlib import Path

from ...memory.continuity import write_continuity
from ..spec import ToolResult

logger = logging.getLogger("valar.tools.session_persist")


def _engram_root() -> Path | None:
    for key in ("HEARTH_ENGRAM", "VALAR_ENGRAM"):
        raw = os.environ.get(key, "").strip()
        if raw:
            p = Path(raw)
            if p.is_dir():
                return p
    try:
        from ...gateway.journal import _engram_root as journal_root

        return journal_root(Path("."))
    except Exception:  # noqa: BLE001
        return None


def _render_chatlog(title: str, history: list) -> str:
    chunks: list[str] = []
    for msg in history:
        role = str(msg.get("role") or "user").strip().capitalize()
        if role not in ("User", "Assistant"):
            role = "User" if role.lower() == "user" else "Assistant"
        content = str(msg.get("content") or "")
        chunks.append(f"### {role} ()\n\n{content}\n")
    heading = title.strip() or "Untitled"
    return f"# Chat Log: {heading}\n\n" + "\n---\n\n".join(chunks)


def write_short_chatlog(
    session_id: str,
    history: list,
    title: str,
) -> dict | None:
    """File a chatlog-only Thoughts slug when the 3-turn diary is skipped.

    Resume reads ``chatlog.md``; the rail lists any dated folder that has one.
    Never raises.
    """
    if not history:
        return None
    root = _engram_root()
    if root is None:
        logger.warning("short chatlog skipped: Engram root missing")
        return None
    date_str = datetime.now().strftime("%Y-%m-%d")
    first_user = ""
    for msg in history:
        if str(msg.get("role") or "").lower() == "user" and str(msg.get("content") or "").strip():
            first_user = str(msg.get("content") or "").strip()
            break
    base_src = title or first_user
    if (title or "").strip().lower() in ("", "voice session", "untitled", "untitled session"):
        base_src = first_user or title
    base = re.sub(r"[^a-z0-9]+", "-", (base_src or "").lower()).strip("-")[:40]
    if not base:
        base = re.sub(r"[^a-f0-9]", "", session_id.lower())[:8] or "session"
    slug = f"{date_str}-{base}"
    thought_dir = root / "Thoughts" / slug
    counter = 2
    while thought_dir.exists():
        thought_dir = root / "Thoughts" / f"{slug}-{counter}"
        counter += 1
    heading = (title or "").strip()
    if heading.lower() in ("", "voice session", "untitled", "untitled session"):
        heading = first_user[:60] or heading or "Untitled"
    try:
        thought_dir.mkdir(parents=True, exist_ok=True)
        (thought_dir / "chatlog.md").write_text(
            _render_chatlog(heading, history),
            encoding="utf-8",
        )
    except OSError as exc:
        logger.warning("short chatlog write failed: %s", exc)
        return None
    logger.info("session %s chatlog-only Thoughts/%s", session_id, thought_dir.name)
    return {"thought_slug": thought_dir.name, "chatlog_only": True}


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

    # Keep the 3-turn diary threshold, but always file a chatlog so Resume
    # can rehydrate short desktop chats the rail would otherwise drop.
    if not saved.get("saved") and history:
        stub = write_short_chatlog(session_id, history, title)
        if stub:
            saved = {**saved, **stub}

    detail = saved.get("thought_slug") or saved.get("reason") or ""
    logger.info(
        "session %s persisted: diary=%s chatlog_only=%s (%s) continuity=%s",
        session_id,
        saved.get("saved"),
        bool(saved.get("chatlog_only")),
        detail,
        continuity_ok,
    )
    return ToolResult(
        content=f"session persisted (diary={saved.get('saved')}, continuity={continuity_ok})",
        ok=bool(saved.get("saved") or saved.get("chatlog_only") or continuity_ok),
        data={"diary": saved, "continuity": continuity_ok},
    )
