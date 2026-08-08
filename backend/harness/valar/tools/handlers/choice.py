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


def _coerce_options(raw: Any) -> list:
    """Meet the model where it is. A list is the contract; a dict of
    label-to-detail, a JSON string, or a delimited string all still mean
    options, and a 9B under interview pressure produces all of them."""
    if isinstance(raw, list):
        return raw
    if isinstance(raw, dict):
        return [{"label": k, "detail": str(v or "")} for k, v in raw.items()]
    if isinstance(raw, str):
        text = raw.strip()
        if text.startswith("[") or text.startswith("{"):
            try:
                import json

                return _coerce_options(json.loads(text))
            except ValueError:
                pass
        for sep in ("\n", "|", ";"):
            if sep in text:
                return [part.strip() for part in text.split(sep) if part.strip()]
        if text:
            return [text]
    return []


def choice_card(
    question: str = "",
    options: Any = None,
    allow_free_text: Any = True,
    **_: Any,
) -> ToolResult:
    q = str(question or "").strip()
    raw = _coerce_options(options)
    cleaned = [o for o in (_clean_option(x) for x in raw[:MAX_OPTIONS]) if o]

    if not q:
        logger.warning("choice_card rejected: no question (options=%r)", options)
        return ToolResult(
            content="A choice card needs the question it is offering answers to.",
            ok=False,
        )
    if not cleaned:
        logger.warning("choice_card rejected: no options (raw=%r)", options)
        return ToolResult(
            content=(
                "The card cannot render without options. Call choice_card again "
                "with the SAME question plus 2 to 5 options you compose, exactly "
                'like this: {"question": "' + (q[:80] or "Your question") + '", '
                '"options": [{"label": "First choice", "detail": "what it means"}, '
                '{"label": "Second choice", "detail": "what it means"}]}'
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
    # and gets replayed instead of the tool being called again. The "no answer
    # has arrived" clause is live-earned: the model once read this result and
    # replied "I see. A creative partner..." -- choosing its own first option
    # for the person and moving on.
    return ToolResult(
        content=(
            "The choices are on their screen. NO ANSWER HAS ARRIVED YET: speak "
            "your question aloud in one short sentence and stop. Do not pick "
            "for them, do not react to any option as if it were chosen."
        ),
        data={"ui_component": card},
    )
