"""The rooms read side, and the operator's way into one.

Spec section 6 of docs/superpowers/specs/2026-09-02-persona-rooms-design.md.
The room is server state; the client renders it docked or expanded. Send
posts as the operator and runs an exchange; note posts to the record and
runs nothing, for steering that belongs on the transcript but does not need
three replies.

The operator is never a member, so a room can settle while they are asleep.
"""

from __future__ import annotations

import logging

from ..rooms import exchange
from ..rooms import store as rs

logger = logging.getLogger("valar.gateway.rooms_api")

READ_LIMIT = 50


def _view(room: dict, limit: int = READ_LIMIT) -> dict:
    slug = room["slug"]
    tasks = rs.tasks(slug)
    return {
        "slug": slug,
        "goal": room.get("goal", ""),
        "members": room.get("members", []),
        "convener": room.get("convener", ""),
        "state": room.get("state", "open"),
        "created": room.get("created", ""),
        # Empty until the charter round ends, which is how a client tells a
        # room that is still forming from one that opened on no deliverables.
        "chartered": room.get("chartered", ""),
        "settled": room.get("settled", ""),
        "tasks": tasks,
        "turns": rs.read(slug, limit),
        "exchange_running": slug in exchange._running,
    }


def register(app, config) -> None:
    # What a post from the operator is signed. Empty config falls back to the
    # generic word, which is what every room post said until 2026-09-03 and
    # made the operator's own messages indistinguishable from the harness's.
    operator = str(getattr(config, "operator_name", "") or "").strip() or "operator"

    @app.get("/rooms")
    async def rooms_list(all: bool = False) -> dict:
        try:
            rooms = rs.list_all() if all else rs.list_open()
        except Exception as exc:  # noqa: BLE001 - the rail never gets a 500
            logger.warning("rooms list failed: %s", exc)
            return {"rooms": []}
        out = []
        for r in rooms:
            tasks = rs.tasks(r["slug"])
            out.append(
                {
                    "slug": r["slug"],
                    "goal": r.get("goal", ""),
                    "members": r.get("members", []),
                    "convener": r.get("convener", ""),
                    "state": r.get("state", "open"),
                    "chartered": r.get("chartered", ""),
                    "tasks_done": len(
                        [t for t in tasks if t.get("status") in rs.TERMINAL]
                    ),
                    "tasks_total": len(tasks),
                    "exchange_running": r["slug"] in exchange._running,
                }
            )
        return {"rooms": out}

    @app.get("/rooms/{slug}")
    async def rooms_read(slug: str, limit: int = READ_LIMIT) -> dict:
        try:
            room = rs.load(slug)
        except Exception as exc:  # noqa: BLE001
            logger.warning("room read failed for %s: %s", slug, exc)
            room = None
        if room is None:
            return {"ok": False, "room": None}
        try:
            n = max(1, min(int(limit), 200))
        except (TypeError, ValueError):
            n = READ_LIMIT
        return {"ok": True, "room": _view(room, n)}

    @app.post("/rooms/{slug}/post")
    async def rooms_post(slug: str, payload: dict | None = None) -> dict:
        body = str((payload or {}).get("body") or "").strip()
        note = bool((payload or {}).get("note"))
        room = rs.load(slug)
        if room is None:
            return {"ok": False, "error": "no such room"}
        if not body:
            return {"ok": False, "error": "nothing to say"}
        if room.get("state") == "settled":
            return {"ok": False, "error": "that room is settled"}
        rs.post(
            slug, operator, "message", body, meta={"note": note, "operator": True}
        )
        if not note:
            # Send runs an exchange; note is for the record only.
            exchange.trigger(slug, operator)
        return {"ok": True, "room": slug, "note": note}
