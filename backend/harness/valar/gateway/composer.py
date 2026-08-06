"""The UI composition track (Generative UI Phase C) -- rule-based v1.

The composer is the single AUTHOR of `ui_component` traffic for a voice turn:
the voice loop feeds it the turn stream (today: each executed tool result;
later: the user text and answer sentences) and emits whatever ops it returns.
This is the TTS-subagent shape applied to UI -- the composer's BRAIN is
pluggable behind these hooks:

  v1 (this module)   pure rules: typed-card passthrough + a generated_view
                     "brief" fallback for tools that return useful text but no
                     typed card; session end clears the card set.
  v2 (planned)       a model pass (or dedicated service) that composes
                     `generated_view` layouts from the turn stream, keyed to
                     sentence boundaries, speaking the same ops vocabulary
                     (upsert | clear | clear_all + ttl_s).

Design bounds (operator decisions, 2026-06-06):
  - DSL: named TEMPLATES whose bodies are flat SECTIONS (text / stat /
    stat_row / image / divider). Templates style; sections carry content.
  - Images: Valar-served relative paths only (no external URLs ever).
  - Lifetime: composer-managed; session end clears all cards.

Every returned op is a dict ready to merge into the flat `ui_component` wire
message: {op?, version, type?, props?, ttl_s?}. `op` absent = upsert.
"""

from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger("valar.gateway.composer")

# Tools whose results carry useful text but no typed card: the composer wraps
# them in a generated_view "brief" so the answer is glanceable on screen too.
_BRIEF_FALLBACK_TOOLS = {
    "web_search": "Search",
    "recall": "From memory",
}

_CARD_BODY_CHARS = 280


def _clip(text: str, limit: int = _CARD_BODY_CHARS) -> str:
    text = (text or "").strip()
    if len(text) <= limit:
        return text
    cut = text[:limit].rsplit(" ", 1)[0].rstrip(",;:")
    return cut + "..."


def compose_for_result(tool_name: str, result: Any) -> list[dict]:
    """Rule-based composition for one executed tool result. Returns the
    `ui_component` ops to emit (possibly empty). Never raises -- the UI track
    must not break a voice turn."""
    try:
        data = getattr(result, "data", None) or {}
        # Rule 1: a handler-authored typed card passes through verbatim (the
        # Phase A bootstrap path -- weather_card / timer_card / brief_text).
        payload = data.get("ui_component")
        if isinstance(payload, dict):
            return [payload]
        # Rule 2: useful text with no typed card -> a generated_view brief.
        title = _BRIEF_FALLBACK_TOOLS.get(tool_name)
        if title and getattr(result, "ok", False):
            content = str(getattr(result, "content", "") or "").strip()
            if content:
                return [
                    {
                        "version": 1,
                        "type": "generated_view",
                        "props": {
                            "template": "brief",
                            "title": title,
                            "sections": [{"kind": "text", "body": _clip(content)}],
                        },
                    }
                ]
        return []
    except Exception as exc:  # noqa: BLE001 - composition never breaks the turn
        logger.warning("compose_for_result failed for %s: %s", tool_name, exc)
        return []


def session_end_ops() -> list[dict]:
    """Ops to emit when the idle watchdog ends a session: clear the card set
    (composer-managed lifetime -- the next session starts with a clean frame;
    the continuity summary is its own channel and survives)."""
    return [{"op": "clear_all"}]
