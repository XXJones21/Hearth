"""The room verbs: nine names over one store.

Spec section 2 of docs/superpowers/specs/2026-09-02-persona-rooms-design.md.
The caller is always the acting persona, never an argument, so there is no
call shape that speaks as someone else. A refusal names the fact the model
needs rather than saying no: close_room lists the outstanding tasks.
"""

from __future__ import annotations

import logging
from datetime import datetime

from ...memory.acting import NoActingPersona, require_acting
from ...rooms import exchange
from ...rooms import store as rs
from ..spec import ToolResult

logger = logging.getLogger("valar.tools.rooms")

# The three handlers that start an exchange are async ON PURPOSE. A sync
# handler runs in the default executor, a thread with no running loop, so
# exchange.trigger could not create its task there and the room opened in
# silence. Found live 2026-09-03 on the first real room.

READ_LIMIT = 30


def _fail(message: str, reason: str) -> ToolResult:
    try:
        return ToolResult.error(message, reason=reason)
    except TypeError:  # Hearth's ToolResult has no reason field yet
        return ToolResult.error(message)


def _me() -> str:
    return require_acting().persona


def _acting():
    """The full acting record, for handlers that need more than the name."""
    return require_acting()


def _room_or_fail(slug: str):
    room = rs.load(slug)
    if room is None:
        return None, _fail(f"There is no room called {slug}.", "not_found")
    return room, None


async def create_room(args: dict) -> ToolResult:
    try:
        me = _me()
    except NoActingPersona as exc:
        return _fail(str(exc), "unsupported")
    name = str(args.get("name") or "").strip()
    goal = str(args.get("goal") or "").strip()
    opening = str(args.get("opening") or "").strip()
    raw = args.get("members") or []
    if isinstance(raw, str):
        raw = [m for m in raw.replace(",", " ").split() if m]
    members = [str(m).strip() for m in raw if str(m).strip()]

    # The convener's PROPOSAL, not the charter. It is amended once per member
    # in the forming round and frozen into the task list. Decision 8.
    raw_d = args.get("deliverables") or []
    deliverables: list[dict] = []
    if isinstance(raw_d, list):
        for d in raw_d:
            if isinstance(d, dict):
                dtext = str(d.get("text") or "").strip()
                downer = str(d.get("owner") or "").strip()
                if dtext and downer:
                    deliverables.append({"text": dtext, "owner": downer})

    if not name or not goal or not opening:
        return _fail(
            "A room needs a name, a goal, and an opening message saying why "
            "you opened it.",
            "bad_input",
        )
    try:
        room = rs.create(name, goal, members, me)
    except rs.RoomExists:
        return _fail(f"A room called {rs.slugify(name)} is already open.", "denied")
    slug = room["slug"]
    if deliverables:
        room["proposed"] = deliverables
        rs.save(room)
    rs.post(slug, me, "opened", opening)
    rs.milestone(slug, me, "opened", f"{me} opened #{slug}: {goal}")
    exchange.trigger(slug, me)
    return ToolResult(
        content=(
            f"#{slug} is forming with {', '.join(room['members'])}. They read "
            "your opening now and may amend the charter once. It opens for "
            "work after that round."
        ),
        data={"room": slug, "members": room["members"]},
    )


def join_room(args: dict) -> ToolResult:
    try:
        me = _me()
    except NoActingPersona as exc:
        return _fail(str(exc), "unsupported")
    slug = rs.slugify(str(args.get("room") or ""))
    room, err = _room_or_fail(slug)
    if err:
        return err
    if me in room["members"]:
        return ToolResult(content=f"You are already in #{slug}.")
    room["members"].append(me)
    rs.save(room)
    rs.post(slug, me, "joined", f"{me} joined.")
    return ToolResult(content=f"You joined #{slug}.", data={"room": slug})


def amend_charter(args: dict) -> ToolResult:
    """Change the charter during the forming round. One per member."""
    try:
        me = _me()
    except NoActingPersona as exc:
        return _fail(str(exc), "unsupported")
    slug = rs.slugify(str(args.get("room") or ""))
    room, err = _room_or_fail(slug)
    if err:
        return err
    if room.get("state") != "forming":
        rows = rs.tasks(slug)
        named = "; ".join(f"{t['id']} {t['assignee']}: {t['text']}" for t in rows)
        return _fail(
            f"#{slug} is already chartered, so the charter is closed. Its "
            f"deliverables are: {named or 'none'}. Use assign_task to add "
            "work, or say to argue for a change.",
            "denied",
        )
    if me not in room["members"]:
        return _fail(f"You are not in #{slug}.", "denied")
    amended = list(room.get("amended") or [])
    if me in amended:
        return _fail(
            f"You already amended the charter of #{slug}. One per member.",
            "denied",
        )

    why = str(args.get("why") or "").strip()
    if not why:
        return _fail("Say why the charter should change.", "bad_input")

    proposed = list(room.get("proposed") or [])
    goal = str(args.get("goal") or "").strip()
    if goal:
        room["goal"] = goal
    for d in args.get("add") or []:
        if isinstance(d, dict):
            text = str(d.get("text") or "").strip()
            owner = str(d.get("owner") or "").strip()
            if text and owner:
                proposed.append({"text": text, "owner": owner})
    drop = {str(x).strip().lower() for x in (args.get("drop") or [])}
    if drop:
        proposed = [d for d in proposed if d["text"].strip().lower() not in drop]

    room["proposed"] = proposed
    amended.append(me)
    room["amended"] = amended
    rs.save(room)
    rs.post(slug, me, "message", f"Amending the charter: {why}")
    named = "; ".join(f"{d['owner']}: {d['text']}" for d in proposed) or "none"
    return ToolResult(
        content=f"Charter of #{slug} now reads: {room['goal']} | {named}",
        data={"room": slug, "deliverables": proposed},
    )


def leave_room(args: dict) -> ToolResult:
    try:
        me = _me()
    except NoActingPersona as exc:
        return _fail(str(exc), "unsupported")
    slug = rs.slugify(str(args.get("room") or ""))
    room, err = _room_or_fail(slug)
    if err:
        return err
    if me not in room["members"]:
        return _fail(f"You are not in #{slug}.", "not_found")
    room["members"] = [m for m in room["members"] if m != me]
    rs.save(room)
    rs.post(slug, me, "left", f"{me} left.")
    return ToolResult(content=f"You left #{slug}.", data={"room": slug})


async def say(args: dict) -> ToolResult:
    try:
        act = _acting()
        me = act.persona
    except NoActingPersona as exc:
        return _fail(str(exc), "unsupported")
    slug = rs.slugify(str(args.get("room") or ""))
    # A member speaking its exchange turn is already saying something: the
    # runner posts whatever it returns. Calling say as well posted the turn
    # twice, once by this handler with no round stamp and once by the runner
    # with one. Spec section 3 forbade it in prose and nothing enforced it.
    if act.origin == f"room/{slug}":
        return _fail(
            f"You are already speaking in #{slug}. Your reply IS your say, "
            "so just answer. Use say only to speak into a room you are not "
            "currently taking a turn in.",
            "denied",
        )
    body = str(args.get("body") or "").strip()
    room, err = _room_or_fail(slug)
    if err:
        return err
    if not body:
        return _fail("There is nothing to say.", "bad_input")
    if me not in room["members"]:
        return _fail(f"You are not in #{slug}. Join it first.", "denied")
    rs.post(slug, me, "message", exchange.strip_voice_tags(body))
    exchange.trigger(slug, me)
    return ToolResult(content=f"Said in #{slug}.", data={"room": slug})


def read_room(args: dict) -> ToolResult:
    slug = rs.slugify(str(args.get("room") or ""))
    room, err = _room_or_fail(slug)
    if err:
        return err
    try:
        limit = max(1, min(int(args.get("limit") or READ_LIMIT), 100))
    except (TypeError, ValueError):
        limit = READ_LIMIT
    rows = rs.read(slug, limit)
    lines = [f"#{slug}, goal: {room['goal']}"]
    lines += [f"{r['author']}: {r['body']}" for r in rows]
    open_tasks = [t for t in rs.tasks(slug) if t.get("status") not in rs.TERMINAL]
    if open_tasks:
        lines.append(
            "Open tasks: " + "; ".join(f"{t['id']} {t['assignee']}" for t in open_tasks)
        )
    return ToolResult(content="\n".join(lines), data={"room": slug, "turns": rows})


def list_rooms(args: dict) -> ToolResult:
    rooms = rs.list_all() if args.get("all") else rs.list_open()
    if not rooms:
        return ToolResult(content="No rooms are open.", data={"rooms": []})
    lines = []
    for r in rooms:
        rows = rs.tasks(r["slug"])
        done = len([t for t in rows if t.get("status") in rs.TERMINAL])
        lines.append(
            f"#{r['slug']} ({r['state']}): {r['goal']} | "
            f"{', '.join(r['members'])} | tasks {done}/{len(rows)}"
        )
    return ToolResult(content="\n".join(lines), data={"rooms": rooms})


async def assign_task(args: dict) -> ToolResult:
    try:
        me = _me()
    except NoActingPersona as exc:
        return _fail(str(exc), "unsupported")
    slug = rs.slugify(str(args.get("room") or ""))
    assignee = str(args.get("assignee") or "").strip()
    text = str(args.get("text") or "").strip()
    room, err = _room_or_fail(slug)
    if err:
        return err
    if not assignee or not text:
        return _fail("Name who the task is for and what it is.", "bad_input")

    task = rs.add_task(slug, text, assignee)
    rs.post(slug, me, "assigned", f"{assignee}: {text}", meta={"task": task["id"]})
    rs.milestone(slug, me, "assigned", f"{me} assigned {assignee}: {text}")
    rs.set_task(slug, task["id"], status="running")

    # Dispatched, not awaited: the room keeps talking while the work runs.
    # See exchange.dispatch_task and decisions 11 and 15.
    if not exchange.dispatch_task(slug, task, room["goal"]):
        rs.set_task(slug, task["id"], status="open")
        return _fail(
            f"{task['id']} could not be started and is back to open.", "internal"
        )
    return ToolResult(
        content=(
            f"{assignee} is working {task['id']} now. The room keeps going; "
            "the result posts back when it lands."
        ),
        data={"room": slug, "task": task["id"]},
    )


async def task_done(args: dict) -> ToolResult:
    try:
        me = _me()
    except NoActingPersona as exc:
        return _fail(str(exc), "unsupported")
    slug = rs.slugify(str(args.get("room") or ""))
    task_id = str(args.get("task") or "").strip()
    body = str(args.get("result") or "").strip()
    _room, err = _room_or_fail(slug)
    if err:
        return err
    updated = rs.set_task(slug, task_id, status="done")
    if updated is None:
        return _fail(f"There is no task {task_id} in #{slug}.", "not_found")
    rs.post(slug, me, "task_done", body or f"{task_id} is done.", meta={"task": task_id})
    rs.milestone(slug, me, "task_done", f"{me} finished {task_id} in #{slug}")
    rs.refresh_state(slug)
    exchange.trigger(slug, me)
    return ToolResult(content=f"{task_id} is marked done.", data={"room": slug})


def close_room(args: dict) -> ToolResult:
    try:
        me = _me()
    except NoActingPersona as exc:
        return _fail(str(exc), "unsupported")
    slug = rs.slugify(str(args.get("room") or ""))
    summary = str(args.get("summary") or "").strip()
    room, err = _room_or_fail(slug)
    if err:
        return err
    if room.get("convener") != me:
        return _fail(f"Only {room.get('convener')} can close #{slug}.", "denied")
    if not summary:
        return _fail("A room closes with a summary of what came of it.", "bad_input")
    outstanding = [t for t in rs.tasks(slug) if t.get("status") not in rs.TERMINAL]
    if outstanding:
        listing = "; ".join(
            f"{t['id']} ({t['assignee']}): {t['text']}" for t in outstanding
        )
        return _fail(
            f"#{slug} still has open tasks: {listing}. Finish or reassign them first.",
            "denied",
        )
    room["state"] = "settled"
    room["settled"] = datetime.now().isoformat(timespec="seconds")
    rs.save(room)
    rs.post(slug, me, "settled", summary)
    rs.milestone(slug, me, "settled", f"#{slug} settled: {summary}")
    return ToolResult(content=f"#{slug} is settled.", data={"room": slug})
