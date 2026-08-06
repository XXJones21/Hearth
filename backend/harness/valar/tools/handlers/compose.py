"""compose_view -- let a persona put a composed card on the screen.

The renderer for `generated_view` has shipped since the M8 client, but nothing
could drive it: the only cards reaching the screen came from the consult
handlers, which build their own. A persona could describe a layout in words and
had no way to show one.

This is the small half of the Card Forge (wiki/card-forge.md in the Hearth
repo). The persona supplies a layout in a closed vocabulary and the card
appears. No code is generated, nothing is compiled, and the whole thing works
on a model small enough to run on a laptop.

Saving a composed card so it can be reused later is the other half and is not
here yet.
"""

from __future__ import annotations

import logging
from typing import Any

from ..spec import ToolResult

logger = logging.getLogger("valar.tools.compose")

TEMPLATES = {"plain", "brief", "hero_stat", "comparison"}
KINDS = {"text", "stat", "stat_row", "image", "grid", "divider"}
CELL_STYLES = {"default", "muted", "marked", "accent", "empty"}

MAX_SECTIONS = 12
MAX_CELLS = 64
MAX_COLUMNS = 12


def _clean_cell(raw: Any) -> dict | None:
    if isinstance(raw, str):
        return {"text": raw[:12], "style": "default"}
    if not isinstance(raw, dict):
        return None
    style = str(raw.get("style") or "default")
    return {
        "text": str(raw.get("text", ""))[:12],
        # An unknown style is a mistake, not an instruction. Fall back rather
        # than pass it through, so a typo cannot produce an unstyled cell.
        "style": style if style in CELL_STYLES else "default",
    }


def _clean_section(raw: Any) -> dict | None:
    """Keep what is valid, drop what is not. A model that gets one section
    wrong should still get a card, minus that section."""
    if not isinstance(raw, dict):
        return None
    kind = str(raw.get("kind") or "").strip()
    if kind not in KINDS:
        return None

    if kind == "text":
        body = str(raw.get("body") or "").strip()
        return {"kind": "text", "body": body[:800]} if body else None

    if kind == "stat":
        return {
            "kind": "stat",
            "label": str(raw.get("label") or "")[:40],
            "value": str(raw.get("value") or "")[:24],
        }

    if kind == "stat_row":
        stats = raw.get("stats")
        if not isinstance(stats, list):
            return None
        out = [
            {"label": str(s.get("label") or "")[:40], "value": str(s.get("value") or "")[:24]}
            for s in stats[:4]
            if isinstance(s, dict)
        ]
        return {"kind": "stat_row", "stats": out} if out else None

    if kind == "image":
        src = str(raw.get("src") or "").strip()
        return {"kind": "image", "src": src} if src else None

    if kind == "grid":
        cells_raw = raw.get("cells")
        if not isinstance(cells_raw, list):
            return None
        cells = [c for c in (_clean_cell(c) for c in cells_raw[:MAX_CELLS]) if c]
        if not cells:
            return None
        try:
            columns = int(raw.get("columns") or 7)
        except (TypeError, ValueError):
            columns = 7
        columns = max(1, min(columns, MAX_COLUMNS))
        out: dict = {"kind": "grid", "columns": columns, "cells": cells}
        heading = str(raw.get("heading") or "").strip()
        if heading:
            out["heading"] = heading[:60]
        return out

    return {"kind": "divider"}


def compose_view(
    title: str = "",
    template: str = "plain",
    sections: Any = None,
    **_: Any,
) -> ToolResult:
    raw = sections if isinstance(sections, list) else []
    cleaned = [s for s in (_clean_section(x) for x in raw[:MAX_SECTIONS]) if s]

    if not cleaned:
        return ToolResult(
            content=(
                "That layout had nothing renderable in it. Sections need a `kind` of "
                "text, stat, stat_row, image, grid or divider."
            ),
            ok=False,
        )

    tpl = template if template in TEMPLATES else "plain"
    card = {
        "version": 1,
        "type": "generated_view",
        "props": {
            "template": tpl,
            "title": str(title or "")[:60],
            "sections": cleaned,
        },
    }
    dropped = len(raw) - len(cleaned)
    logger.info(
        "compose_view: %d section(s), template=%s%s",
        len(cleaned),
        tpl,
        f", dropped {dropped}" if dropped > 0 else "",
    )

    # Kept short deliberately. A long instruction here survives into history and
    # the model replays it instead of calling the tool again (the lesson from
    # generate_image, 2026-08-03).
    return ToolResult(
        content="That is on the operator's screen now.",
        data={"ui_component": card},
    )
