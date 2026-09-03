"""The consolidation clock: every six hours, each persona's loose files
older than a week move into its archive (spec section 1 of
docs/superpowers/specs/2026-09-02-persona-private-memory-design.md, the
week clock).

Six hours rather than weekly so a house that is off on the week boundary
still consolidates the next time it is on; the operation is idempotent and
cheap when nothing is old enough. The end-of-week review, when it lands,
reads the same window and runs on the same tick.
"""

from __future__ import annotations

import asyncio
import logging

from . import persona_archive

logger = logging.getLogger("valar.memory.persona_consolidate")

CHECK_S = 21600.0
FIRST_DELAY_S = 600.0
WINDOW_DAYS = 7


def run_pass(personas) -> int:
    """One pass over every resident persona. Returns the turns moved."""
    moved = 0
    for name in personas.list_personas(platform="desktop"):
        try:
            persona = personas.load(name)
            result = persona_archive.consolidate(persona.memory_dir, WINDOW_DAYS)
            moved += result["turns"]
        except Exception as exc:  # noqa: BLE001 - one persona's failure never stops the pass
            logger.warning("consolidation skipped for %s: %s", name, exc)
    # The inbox is a handover, not an archive: the reviews and the databases
    # keep everything it held (spec section 5, the week clock). Two weeks
    # rather than one, so a house that was off for a week still hands over.
    try:
        from .persona_day_report import prune_inbox
        from .topic import resolve_engram_root

        root = resolve_engram_root(None)
        if root is not None:
            removed = prune_inbox(root)
            if removed:
                logger.info("inbox prune removed %d folder(s)", removed)
    except Exception as exc:  # noqa: BLE001 - pruning never blocks consolidation
        logger.warning("inbox prune skipped: %s", exc)
    return moved


async def persona_consolidate_loop(personas, config) -> None:
    await asyncio.sleep(FIRST_DELAY_S)
    while True:
        try:
            moved = await asyncio.to_thread(run_pass, personas)
            if moved:
                logger.info("persona consolidation moved %d turns", moved)
        except Exception as exc:  # noqa: BLE001
            logger.warning("persona consolidation pass failed: %s", exc)
        await asyncio.sleep(CHECK_S)
