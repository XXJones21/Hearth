"""forge_card -- the Card Forge commission tool (M10).

When no existing card can carry a content shape, the calling persona
commissions a NEW card. The handler does the deterministic half itself
(scaffold: a null-returning stub component + marker-based registration in
registry.tsx, so the beat stays the validated one-file fill-in shape) and
appends a spec beat to the card-forge plan, then dispatches the standing
"card-forge" Mentat run. The model supplies the SPEC, never paths.

Approval gate: a commissioned card renders only after the operator has seen
it (the run finishing is not silent adoption -- the registry line ships with
the scaffold, but the card only appears when the server actually emits its
type, which happens after the operator approves wiring it to a data source).
"""

from __future__ import annotations

import logging
import re
import time
from pathlib import Path

from ..spec import ToolResult

logger = logging.getLogger("valar.tools.forge")

_CLIENT = Path("/mnt/d/Tools/Valinor/hearth-client")
_PLAN_DIR = Path("/mnt/d/Tools/Valinor/tasks/card-forge")
_REGISTRY = _CLIENT / "src" / "components" / "cards" / "registry.tsx"
_CATALOG = Path(__file__).resolve().parents[1] / "card_catalog.yaml"
_STUB_SENTINEL = "the card-forge beat fills this stub"


def _load_catalog() -> list[dict]:
    try:
        import yaml

        data = yaml.safe_load(_CATALOG.read_text(encoding="utf-8")) or {}
        return list(data.get("cards") or [])
    except Exception as exc:  # noqa: BLE001
        logger.warning("card catalog unreadable: %s", exc)
        return []


def card_status(entry: dict) -> str:
    """built | building. A commissioned card is built once the beat replaced
    the scaffold stub (the sentinel comment is gone)."""
    if entry.get("builtin"):
        return "built"
    comp = str(entry.get("component") or "")
    path = _CLIENT / "src" / "components" / "cards" / f"{comp}.tsx"
    try:
        return "building" if _STUB_SENTINEL in path.read_text(encoding="utf-8") else "built"
    except OSError:
        return "building"


def find_card_for_source(source: str) -> dict | None:
    """The consult-handler seam: a BUILT catalog card fed by this tool."""
    for entry in _load_catalog():
        if entry.get("data_source") == source and card_status(entry) == "built":
            return entry
    return None


async def list_cards(args: dict) -> ToolResult:
    """args: {}. The workshop inventory: every card, its purpose, its data
    shape, and whether a commissioned one is still on the bench."""
    entries = _load_catalog()
    if not entries:
        return ToolResult.error("the workshop catalog is missing.")
    lines = []
    for e in entries:
        status = card_status(e)
        flag = "" if e.get("builtin") else f" [{status.upper()}]"
        lines.append(
            f"- {e.get('type')}{flag}: {str(e.get('purpose', '')).strip()} "
            f"(data: {e.get('data_fields', 'n/a')})"
        )
    return ToolResult(content=(
        "Cards in the workshop:\n" + "\n".join(lines)
        + "\n\nIf none of these can carry the content's visual shape, "
        "offer the operator a new card (forge_card)."
    ))

_PLAN_HEADER = """# Card Forge -- commissioned card beats

Standing plan for the card-forge Mentat run. Each item fills ONE scaffolded
stub component against its spec. The scaffold (stub + registry line) is
written deterministically by the forge_card handler at commission time; the
beat's job is ONLY the component body. Import CardProps from ../types and
narrow props; match the existing card shell idiom (rounded-2xl border-linen
bg-fluff px-4 py-3 shadow-soft; small serif-adjacent labels; warm tokens).

"""


def _pascal(name: str) -> str:
    # Strip a trailing "card" so "Ticker Insight Card" scaffolds as
    # TickerInsightCard, not TickerInsightCardCard (live 2026-07-31).
    words = [w for w in re.split(r"[^a-zA-Z0-9]+", name) if w]
    if words and words[-1].lower() == "card":
        words = words[:-1]
    return "".join(w.capitalize() for w in words)


async def forge_card(args: dict) -> ToolResult:
    """args: {card_name, purpose, data_fields, visual_elements, data_source}.
    Scaffold and commission a new UI card; the card-forge run builds it in
    the background and it goes live on its first use after the build."""
    card_name = str(args.get("card_name") or "").strip()
    purpose = str(args.get("purpose") or "").strip()
    data_fields = str(args.get("data_fields") or "").strip()
    visual = str(args.get("visual_elements") or "").strip()
    data_source = str(args.get("data_source") or "").strip()
    if not card_name or not purpose:
        return ToolResult.error(
            "a commission needs at least card_name and purpose."
        )
    type_key = re.sub(r"[^a-z0-9]+", "_", card_name.lower()).strip("_")
    comp = _pascal(card_name) + "Card"
    comp_path = _CLIENT / "src" / "components" / "cards" / f"{comp}.tsx"

    if not _REGISTRY.is_file():
        return ToolResult.error("the workshop is missing its registry; cannot scaffold.")
    registry_src = _REGISTRY.read_text(encoding="utf-8")
    if f"'{type_key}'" in registry_src or f"{type_key}:" in registry_src:
        return ToolResult.error(
            f"a card of type {type_key} already hangs in the workshop -- reuse it."
        )

    # --- deterministic scaffold (handler-side, no model judgment) ----------
    stub = (
        "import type { FC } from 'react';\n"
        "import type { CardProps } from './types';\n\n"
        f"/* {comp} -- commissioned via the Card Forge.\n"
        f" * Purpose: {purpose}\n"
        f" * Data fields (props.data): {data_fields or 'see spec in tasks/card-forge/plan.md'}\n"
        f" * Visual: {visual or 'see spec'}\n"
        " * The card-forge beat fills this stub; until then it renders nothing.\n"
        " */\n"
        f"export const {comp}: FC<CardProps> = () => null;\n"
    )
    try:
        comp_path.write_text(stub, encoding="utf-8", newline="\n")
        registry_src = registry_src.replace(
            "// FORGE:IMPORTS",
            f"import {{ {comp} }} from './{comp}';\n// FORGE:IMPORTS",
        ).replace(
            "  // FORGE:REGISTER",
            f"  {type_key}: {comp},\n  // FORGE:REGISTER",
        )
        _REGISTRY.write_text(registry_src, encoding="utf-8", newline="\n")
    except OSError as exc:
        logger.warning("forge scaffold failed: %s", exc)
        return ToolResult.error("could not scaffold the card in the workshop.")

    # --- the spec beat -----------------------------------------------------
    _PLAN_DIR.mkdir(parents=True, exist_ok=True)
    plan = _PLAN_DIR / "plan.md"
    if not plan.is_file():
        plan.write_text(_PLAN_HEADER, encoding="utf-8", newline="\n")
    beat = (
        f"- [ ] **{comp}.** Fill `src/components/cards/{comp}.tsx` (a "
        f"null-returning stub, already registered as type `{type_key}`).\n"
        f"      Purpose: {purpose}\n"
        f"      Data fields on `props.data`: {data_fields or 'unspecified -- render defensively'}\n"
        f"      Visual elements: {visual or 'card shell + clear typography'}\n"
        f"      Rules: ONE file only; import CardProps from ./types; render "
        f"nothing when required data is absent; match the warm card shell "
        f"idiom of WeatherCard.\n"
    )
    with plan.open("a", encoding="utf-8", newline="\n") as fh:
        fh.write(beat)

    # Catalog entry: how the rest of the house learns this card exists.
    # Appended as an indented yaml block so the file's header comments survive.
    try:
        import yaml

        entry = {
            "type": type_key,
            "purpose": purpose,
            "data_fields": data_fields,
            "data_source": data_source or None,
            "component": comp,
            "commissioned": time.strftime("%Y-%m-%d"),
        }
        block = yaml.safe_dump([entry], sort_keys=False, allow_unicode=True)
        indented = "".join("  " + line + "\n" for line in block.rstrip().splitlines())
        with _CATALOG.open("a", encoding="utf-8", newline="\n") as fh:
            fh.write(indented)
    except Exception as exc:  # noqa: BLE001
        logger.warning("catalog append failed (non-fatal): %s", exc)
    logger.info("forge: commissioned %s (type=%s, source=%s)", comp, type_key, data_source)

    # The commission ends at the spec. The Mentat conductor that used to pick
    # the beat up from here is a developer surface and does not ship, so the
    # scaffold and the plan entry wait for whoever builds the card.
    return ToolResult(
        content=(
            f"commissioned: {comp} (type {type_key}) is scaffolded, registered, "
            "and specced; it renders once its component is filled in. "
            "Tell the operator what was commissioned and ask whether they want "
            "this card for such information going forward."
        ),
        data={"commissioned": comp, "type": type_key, "dispatched": False},
    )
