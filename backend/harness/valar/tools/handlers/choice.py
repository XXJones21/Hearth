"""choice_card -- let a persona offer options it wrote itself.

The interview mechanism from the first-run design (the Professor Oak beat):
when a question is hard to answer cold, the persona composes a handful of
options and the client renders them as choices beside a free composer. A
typed answer always outranks the chips, and the card says so.

Cleans rather than validates, the compose_view discipline: a model that gets
one option wrong should still get a card, minus that option.
"""

from __future__ import annotations

import logging
from typing import Any

from ..spec import ToolResult

logger = logging.getLogger("valar.tools.choice")

MAX_OPTIONS = 5


def _clean_option(raw: Any) -> dict | None:
    if isinstance(raw, str):
        label = raw.strip()
        return {"label": label[:40], "detail": ""} if label else None
    if not isinstance(raw, dict):
        return None
    label = str(raw.get("label") or "").strip()
    if not label:
        return None
    return {
        "label": label[:40],
        "detail": str(raw.get("detail") or "").strip()[:90],
    }


def choice_card(
    question: str = "",
    options: Any = None,
    allow_free_text: Any = True,
    **_: Any,
) -> ToolResult:
    q = str(question or "").strip()
    raw = options if isinstance(options, list) else []
    cleaned = [o for o in (_clean_option(x) for x in raw[:MAX_OPTIONS]) if o]

    if not q:
        return ToolResult(
            content="A choice card needs the question it is offering answers to.",
            ok=False,
        )
    if not cleaned:
        return ToolResult(
            content=(
                "No renderable options. Each needs a `label` (a few words) and "
                "may carry a one-line `detail`."
            ),
            ok=False,
        )

    card = {
        "version": 1,
        "type": "choice_card",
        "props": {
            "question": q[:160],
            "options": cleaned,
            "allow_free_text": bool(allow_free_text),
        },
    }
    logger.info("choice_card: %d option(s) for %r", len(cleaned), q[:40])
    # Short on purpose; instruction-shaped tool output survives into history
    # and gets replayed instead of the tool being called again.
    return ToolResult(
        content="The choices are on their screen. Their answer comes next; wait for it.",
        data={"ui_component": card},
    )
