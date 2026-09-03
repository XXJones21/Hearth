"""The house feed's read side.

Spec section 4 of docs/superpowers/specs/2026-09-02-house-feed-design.md.
Paging is by day rather than by offset, because the store is day files and
a day is what the operator thinks in; the archive boundary, when the fold
lands, stays invisible to the client.

The rail never gets a 500: a failure is an empty page, matching
routines_api's existing contract.
"""

from __future__ import annotations

import logging

from ..feed import store

logger = logging.getLogger("valar.gateway.feed_api")

MAX_LIMIT = 200
DEFAULT_LIMIT = 50


def register(app, config) -> None:
    @app.get("/house/feed")
    async def house_feed(before: str = "", limit: int = DEFAULT_LIMIT) -> dict:
        try:
            n = max(1, min(int(limit), MAX_LIMIT))
        except (TypeError, ValueError):
            n = DEFAULT_LIMIT
        try:
            return store.read_page(before=before, limit=n)
        except Exception as exc:  # noqa: BLE001 - the rail never gets a 500
            logger.warning("house feed failed: %s", exc)
            return {"entries": [], "next_before": ""}

    @app.get("/house/feed/item/{record_id}")
    async def house_feed_item(record_id: str) -> dict:
        try:
            rec = store.find(record_id)
        except Exception as exc:  # noqa: BLE001
            logger.warning("house feed item failed: %s", exc)
            rec = None
        if rec is None:
            return {"ok": False, "record": None}
        return {"ok": True, "record": rec}
