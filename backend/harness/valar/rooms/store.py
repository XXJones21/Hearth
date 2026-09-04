"""A room's own tree: state, transcript, tasks.

Spec sections 1 and 5 of
docs/superpowers/specs/2026-09-02-persona-rooms-design.md, over the record
and stores in the spine spec. A room owns its directory the way a persona
owns its memory/, for the same reason: it is a working record a person can
open, and it consolidates into SQLite once its goal is met.

Rooms live under HEARTH_HOME beside Persona/, not under Engram. The feed is
the operator's shared layer; a room is the house's own working state.
"""

from __future__ import annotations

import json
import logging
import os
import re
from datetime import datetime
from pathlib import Path

from ..feed import record as feed_record
from ..feed import store as feed_store

logger = logging.getLogger("valar.rooms.store")

ROOMS_REL = "Rooms"
ROOM_FILE = "room.json"
TRANSCRIPT_FILE = "transcript.jsonl"
TASKS_FILE = "tasks.jsonl"
RECON_DIRNAME = "reconstructed"
TERMINAL = ("done", "failed", "abandoned")
READ_LIMIT = 30

_SLUG_RE = re.compile(r"[^a-z0-9-]+")


class RoomExists(Exception):
    """A room with that slug is already open."""


class RoomMissing(Exception):
    """No such room."""


def slugify(name: str) -> str:
    slug = _SLUG_RE.sub("-", str(name).strip().lower()).strip("-")
    return slug[:60] or "room"


def rooms_root() -> Path:
    home = os.environ.get("HEARTH_HOME") or os.environ.get("VALAR_HOME") or "."
    root = Path(home) / ROOMS_REL
    root.mkdir(parents=True, exist_ok=True)
    return root


def room_dir(slug: str) -> Path:
    return rooms_root() / slugify(slug)


def _read_json(path: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def _read_lines(path: Path) -> list[dict]:
    if not path.exists():
        return []
    out: list[dict] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


def _append_line(path: Path, row: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


def create(slug: str, goal: str, members: list[str], convener: str) -> dict:
    slug = slugify(slug)
    d = room_dir(slug)
    if (d / ROOM_FILE).exists():
        raise RoomExists(slug)
    d.mkdir(parents=True, exist_ok=True)
    (d / RECON_DIRNAME).mkdir(exist_ok=True)
    room = {
        "slug": slug,
        "goal": str(goal),
        "members": list(dict.fromkeys([convener, *members])),
        "convener": convener,
        "created": datetime.now().isoformat(timespec="seconds"),
        # forming, not open: a room holds one charter round before it works.
        # The goal at this point is the convener's PROPOSAL. Decision 8.
        "state": "forming",
        "chartered": "",
        "settled": "",
    }
    save(room)
    for name in room["members"]:
        post(slug, name, "joined", f"{name} is in the room.")
    return room


def load(slug: str) -> dict | None:
    return _read_json(room_dir(slug) / ROOM_FILE)


def save(room: dict) -> None:
    d = room_dir(room["slug"])
    d.mkdir(parents=True, exist_ok=True)
    (d / ROOM_FILE).write_text(
        json.dumps(room, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def list_all() -> list[dict]:
    out: list[dict] = []
    for d in sorted(rooms_root().iterdir()):
        if not d.is_dir() or d.name == RECON_DIRNAME:
            continue
        room = _read_json(d / ROOM_FILE)
        if room:
            out.append(room)
        else:
            logger.warning("rooms: %s has no readable room.json", d.name)
    return out


def list_open() -> list[dict]:
    return [r for r in list_all() if r.get("state") != "settled"]


def post(slug, author, kind, body, refs=None, meta=None) -> dict:
    rec = feed_record.make(
        author, kind, body, topic=f"room:{slugify(slug)}", refs=refs, meta=meta
    )
    _append_line(room_dir(slug) / TRANSCRIPT_FILE, rec)
    return rec


def read(slug: str, limit: int = READ_LIMIT) -> list[dict]:
    return _read_lines(room_dir(slug) / TRANSCRIPT_FILE)[-limit:]


def tasks(slug: str) -> list[dict]:
    """Append only on disk; the last row per id wins on read."""
    rows: dict[str, dict] = {}
    for row in _read_lines(room_dir(slug) / TASKS_FILE):
        if row.get("id"):
            rows[row["id"]] = row
    return list(rows.values())


def add_task(slug: str, text: str, assignee: str) -> dict:
    existing = tasks(slug)
    task = {
        "id": f"t{len(existing) + 1}",
        "text": str(text),
        "assignee": str(assignee),
        "status": "open",
        "at": datetime.now().isoformat(timespec="seconds"),
        "result_ref": "",
    }
    _append_line(room_dir(slug) / TASKS_FILE, task)
    return task


def set_task(slug: str, task_id: str, **fields) -> dict | None:
    for task in tasks(slug):
        if task.get("id") == task_id:
            task = dict(task) | fields
            _append_line(room_dir(slug) / TASKS_FILE, task)
            return task
    return None


def freeze_charter(slug: str, deliverables: list[dict]) -> dict | None:
    """End the charter round: write the deliverables as tasks, open the room.

    The charter needs no store of its own. A deliverable with an owner IS a
    task, so freezing writes them through add_task and the room's goal becomes
    decidable: refresh_state can now say when everything is done. Decision 8.

    A no-op on a room that is not forming, so a second charter round cannot
    double the task list.
    """
    room = load(slug)
    if room is None or room.get("state") != "forming":
        return room
    for d in deliverables:
        text = str(d.get("text") or "").strip()
        owner = str(d.get("owner") or "").strip()
        if text and owner:
            add_task(slug, text, owner)
    room["state"] = "open"
    room["chartered"] = datetime.now().isoformat(timespec="seconds")
    save(room)
    rows = tasks(slug)
    if rows:
        body = f"Chartered: {room['goal']}\n" + "\n".join(
            f"- {t['id']} {t['assignee']}: {t['text']}" for t in rows
        )
    else:
        body = (
            f"Chartered: {room['goal']}\nNo deliverables were named, so this "
            "room is a conversation until someone assigns one."
        )
    post(slug, room["convener"], "chartered", body)
    milestone(
        slug, room["convener"], "chartered", f"#{slug} chartered: {room['goal']}"
    )
    return room


def refresh_state(slug: str) -> str:
    """Derive open vs awaiting_close from the tasks. Never settles.

    A pure function of the task list, in BOTH directions. It used to only
    count one way: it returned early unless the state was already `open`, so a
    room that reached awaiting_close could never go back even when a task
    reopened. Decision 15 returns a failed task to `open` as a matter of
    course, which turned that into a room telling its own members "Every task
    is finished" while work was outstanding, and they believed it, closed
    ranks and spent nine turns agreeing the room was over.

    Measured 2026-09-03: the uncharted room stuck this way called a tool on
    28 percent of turns against 71 percent in a healthy one. A state machine
    that can only count one way is a room that lies to itself.

    forming and settled are not derived and are left alone: the charter round
    owns the first, close_room owns the second.
    """
    room = load(slug)
    if room is None or room.get("state") in ("forming", "settled"):
        return (room or {}).get("state", "")
    rows = tasks(slug)
    done = bool(rows) and all(t.get("status") in TERMINAL for t in rows)
    want = "awaiting_close" if done else "open"
    if room.get("state") != want:
        room["state"] = want
        save(room)
    return want


def milestone(slug: str, author: str, kind: str, body: str, refs=None) -> None:
    """Milestones cross into the house feed; chatter does not."""
    try:
        rec = feed_record.make(
            author, kind, body, refs=refs, meta={"room": slugify(slug)}
        )
        feed_store.append(rec)
    except Exception as exc:  # noqa: BLE001 - a lost milestone never costs the room
        logger.warning("room milestone not posted for %s: %s", slug, exc)
