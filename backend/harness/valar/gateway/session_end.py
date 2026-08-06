"""Auto session-end -- the harness-owned idle watchdog's action.

After ``VALAR_SESSION_IDLE_S`` with no turns, Valar ends the session itself:
summarize the conversation through its own brain seam, persist (Engram diary +
SCX continuity note) via the standalone ``persist_session`` handler, notify the
client (``session_ended``), and clear the history for a fresh start. Owned by
Valar so Echo, iOS, and Quest all get identical behavior with zero client logic
(the harness rule); the client just sees the reset.

Closes the loop the SCX work opened: SCX (ambient context) <-> tools (the
persist action) <-> Engram (long-term).
"""

from __future__ import annotations

import asyncio
import logging
import time

from ..brain import BrainProvider, BrainStreamResult, ChatMessage, ChatOptions
from ..config import ValarConfig
from ..persona import Persona
from .session import Session, State

logger = logging.getLogger("valar.session_end")

# Transcript caps for the summary call -- a session-end summary needs the gist,
# not the whole log; keep the prompt small so the call is fast on the daily model.
_MAX_TURNS = 20
_MAX_CHARS_PER_MSG = 400

_SUMMARY_SYSTEM = (
    "You summarize a just-ended voice conversation between an operator and their "
    "assistant. Reply with EXACTLY two lines and nothing else:\n"
    "Title: <at most 8 words>\n"
    "Summary: <2-3 sentences: what was discussed, decided, and left open>"
)


def _transcript(session: Session) -> str:
    lines: list[str] = []
    for turn in session.history[-_MAX_TURNS:]:
        if turn.user:
            lines.append("Operator: " + turn.user[:_MAX_CHARS_PER_MSG])
        if turn.assistant:
            lines.append("Assistant: " + turn.assistant[:_MAX_CHARS_PER_MSG])
    return "\n".join(lines)


def _parse_summary(text: str, fallback: str) -> tuple[str, str]:
    """(title, summary) from the two-line reply; degrade to the raw text."""
    title, summary = "", ""
    for line in text.splitlines():
        low = line.strip()
        if low.lower().startswith("title:") and not title:
            title = low[6:].strip()
        elif low.lower().startswith("summary:") and not summary:
            summary = low[8:].strip()
    if not title and not summary:
        # The model skipped the prefixes (observed on gemma): a short first line
        # followed by prose is still title + summary — split it that way rather
        # than leaking the title into the continuity text.
        lines = [ln.strip() for ln in text.strip().splitlines() if ln.strip()]
        if len(lines) >= 2 and len(lines[0]) <= 60:
            title = lines[0].rstrip(".")
            summary = " ".join(lines[1:])
    if not summary:
        summary = text.strip() or fallback
    if not title:
        title = "Voice session"
    return title, summary


async def summarize_session(
    session: Session, persona: Persona, brain: BrainProvider, config: ValarConfig
) -> dict:
    """One-shot brain call -> the summary dict ``save_session_to_engram`` expects.
    Degrades to a transcript-head summary if the brain call fails."""
    transcript = _transcript(session)
    fallback = (transcript[:200] + "...") if len(transcript) > 200 else transcript

    dm = persona.config.get("deep_model") if isinstance(persona.config, dict) else None
    dm = dm if isinstance(dm, dict) else {}
    opts = ChatOptions(
        max_tokens=160,
        temperature=0.3,
        top_p=float(dm.get("top_p", config.brain.top_p)),
        top_k=int(dm.get("top_k", config.brain.top_k)),
        model=config.brain.model,
        persona_name=persona.name,
        model_path=dm.get("path", ""),
    )
    messages = [
        ChatMessage("system", _SUMMARY_SYSTEM),
        ChatMessage("user", transcript or "(empty session)"),
    ]
    text = ""
    try:
        result = BrainStreamResult()
        chunks: list[str] = []
        async for delta in brain.chat(messages, opts, result):
            chunks.append(delta)
        text = "".join(chunks).strip()
    except Exception as exc:  # noqa: BLE001 - summary degrades, never blocks the end
        logger.warning("session summary brain call failed: %s", exc)

    title, summary = _parse_summary(text, fallback)
    return {
        "title": title,
        "summary": summary,
        "personality": persona.name,
        "related_project": "none",
        "tags": ["valar-session"],
        "key_decisions": [],
        "open_questions": [],
        "action_items": [],
    }


async def end_session(
    session: Session,
    persona: Persona,
    brain: BrainProvider,
    config: ValarConfig,
    emit,
) -> None:
    """Persist + announce + reset one idle session. Never raises."""
    turns = len(session.history)
    logger.info("ending idle session %s (%d turns)", session.session_id, turns)

    summary = await summarize_session(session, persona, brain, config)

    history_dicts: list[dict] = []
    for turn in session.history:
        if turn.user:
            history_dicts.append({"role": "user", "content": turn.user})
        if turn.assistant:
            history_dicts.append({"role": "assistant", "content": turn.assistant})

    try:
        from ..tools.handlers.session_persist import persist_session

        await persist_session(
            {
                "session_id": session.session_id,
                "persona": persona.name,
                "history": history_dicts,
                "summary": summary,
            }
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning("session persist failed: %s", exc)

    # Fresh start: the cleared history is what makes the next turn a new session.
    session.history.clear()
    session.touch()
    session.state = State.IDLE

    try:
        # Composer-managed card lifetime (Phase C): a session end clears the
        # ui_component card set so the next session opens on a clean frame
        # (the continuity summary is its own channel and survives).
        if session.capabilities.get("ui_render"):
            from .composer import session_end_ops

            for op in session_end_ops():
                await emit("ui_component", {"action": "ui_component", **op})
        await emit(
            "session_ended",
            {
                "action": "session_ended",
                "reason": "idle",
                "summary": summary.get("summary", ""),
            },
        )
    except Exception as exc:  # noqa: BLE001 - client may be gone; the persist stands
        logger.debug("session_ended emit failed (client gone?): %s", exc)


async def idle_watchdog(
    session: Session,
    current_persona,
    brain: BrainProvider,
    config: ValarConfig,
    emit,
) -> None:
    """Per-connection watchdog task: ends the session after the idle window.

    ``current_persona`` is a zero-arg callable returning the active Persona (the
    persona can switch mid-session). Runs until cancelled (on disconnect). A
    session can end multiple times over one connection -- each idle window after
    real turns persists and resets again.
    """
    idle_s = config.session_idle_s
    if idle_s <= 0:
        return
    check_every = min(10.0, max(1.0, idle_s / 4))
    while True:
        await asyncio.sleep(check_every)
        if not session.history:
            continue
        if session.state is not State.IDLE:
            continue  # never end mid-turn
        if (time.monotonic() - session.last_activity) < idle_s:
            continue
        try:
            await end_session(session, current_persona(), brain, config, emit)
        except Exception as exc:  # noqa: BLE001 - watchdog must survive anything
            logger.warning("auto session-end failed: %s", exc)
            session.touch()  # back off so a persistent failure does not hot-loop
