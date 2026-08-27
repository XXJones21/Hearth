"""Calendar tools.

The module `tools.yaml` has pointed at since before any of this work, and
which never existed. The two entries were disabled, so nothing broke and
nothing worked.

The store is the house's own (see ``valar/memory/calendar.py``): the aim is
that the operator does not need a calendar app, so this is the real calendar
rather than a copy of one. What that costs today is that events written here
are not in anyone else's calendar; the ICS export and a CalDAV sync are how
that stops being true, and the format was built for both.
"""

from __future__ import annotations

import logging
import re
from datetime import date, datetime, timedelta

from ..spec import ToolResult

logger = logging.getLogger("valar.tools.calendar")

_MAX_SPAN_DAYS = 62


def _root():
    from ...memory.journal_sync import engram_root

    return engram_root()


def _parse_day(text: str, today: date | None = None) -> date | None:
    """The days a person names. Narrow on purpose, like the reminder parser:
    a wrong guess about a date is worse than a question."""
    raw = " ".join((text or "").strip().lower().split())
    today = today or date.today()
    if not raw or raw in ("today", "now"):
        return today
    if raw == "tomorrow":
        return today + timedelta(days=1)
    if raw == "yesterday":
        return today - timedelta(days=1)
    m = re.match(r"^(\d{4})-(\d{2})-(\d{2})$", raw)
    if m:
        try:
            return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        except ValueError:
            return None
    days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    bare = raw.replace("next ", "").replace("this ", "")
    if bare in days:
        ahead = (days.index(bare) - today.weekday()) % 7
        if ahead == 0 or raw.startswith("next "):
            ahead = ahead or 7
        return today + timedelta(days=ahead)
    return None


def _parse_clock(text: str) -> str:
    """HH:MM, or empty when it is not a time."""
    from ...memory.reminders import parse_when

    when = parse_when(text)
    return when.strftime("%H:%M") if when else ""


def _describe(ev: dict) -> str:
    when = "all day" if ev["all_day"] else (
        f"{ev['start']}" + (f" to {ev['end']}" if ev["end"] else "")
    )
    where = f" at {ev['location']}" if ev["location"] else ""
    return f"{ev['date'].isoformat()} {when}: {ev['title']}{where}"


def calendar_read(args: dict) -> ToolResult:
    """args: {range?: today|tomorrow|week|month, date?: str}. What is on."""
    root = _root()
    if root is None:
        return ToolResult.error("There is no second brain connected, so there is no calendar.")
    from ...memory.calendar import events_between

    span = str((args or {}).get("range") or "").strip().lower()
    named = str((args or {}).get("date") or "").strip()
    today = date.today()

    if named:
        day = _parse_day(named)
        if day is None:
            return ToolResult.error(
                f"I could not read {named!r} as a date. Ask them plainly, or use "
                "a range of today, tomorrow, week or month."
            )
        first = last = day
        label = "that day"
    elif span in ("week", "this week"):
        first, last, label = today, today + timedelta(days=7), "the next seven days"
    elif span == "month":
        first, last, label = today, today + timedelta(days=31), "the next month"
    elif span == "tomorrow":
        first = last = today + timedelta(days=1)
        label = "tomorrow"
    else:
        first = last = today
        label = "today"

    if (last - first).days > _MAX_SPAN_DAYS:
        last = first + timedelta(days=_MAX_SPAN_DAYS)

    events = events_between(root, first, last)
    if not events:
        return ToolResult(
            content=f"Nothing is on the calendar for {label}. Say so plainly.",
            data={"events": [], "from": first.isoformat(), "to": last.isoformat()},
        )
    lines = [f"Calendar, {label}: {len(events)} event" + ("" if len(events) == 1 else "s")]
    for ev in events[:40]:
        lines.append("- " + _describe(ev))
    logger.info("calendar_read %s..%s -> %d", first, last, len(events))
    return ToolResult(
        content="\n".join(lines),
        data={
            "events": [
                {
                    "id": e["id"],
                    "date": e["date"].isoformat(),
                    "start": e["start"],
                    "end": e["end"],
                    "title": e["title"],
                    "location": e["location"],
                }
                for e in events
            ]
        },
    )


def calendar_write(args: dict) -> ToolResult:
    """args: {action: add|move|cancel, ...}. Put something on the calendar."""
    root = _root()
    if root is None:
        return ToolResult.error("There is no second brain connected, so there is no calendar.")
    from ...memory.calendar import add_event, find, move_event, remove_event

    action = str((args or {}).get("action") or "add").strip().lower()
    title = str((args or {}).get("title") or "").strip()
    raw_day = str((args or {}).get("date") or "").strip()
    raw_time = str((args or {}).get("time") or "").strip()
    raw_end = str((args or {}).get("end_time") or "").strip()
    location = str((args or {}).get("location") or "").strip()

    if action in ("cancel", "delete", "remove"):
        if not title:
            return ToolResult.error("Which event? Name it, or read the calendar first.")
        hits = find(root, title)
        if not hits:
            return ToolResult.error(f"Nothing on the calendar matches {title!r}.")
        if len(hits) > 1:
            listed = "; ".join(_describe(e) for e in hits[:4])
            return ToolResult.error(
                f"{title!r} matches several events: {listed}. Ask which one."
            )
        gone = remove_event(root, hits[0]["id"])
        if gone is None:
            return ToolResult.error("I could not remove that event.")
        return ToolResult(
            content=f"Cancelled: {_describe(gone)}", data={"cancelled": gone["id"]}
        )

    if action == "move":
        if not title:
            return ToolResult.error("Which event is moving?")
        hits = find(root, title)
        if len(hits) != 1:
            listed = "; ".join(_describe(e) for e in hits[:4]) or "nothing"
            return ToolResult.error(
                f"{title!r} does not name exactly one event ({listed}). Ask which."
            )
        day = _parse_day(raw_day) if raw_day else hits[0]["date"]
        if day is None:
            return ToolResult.error(f"I could not read {raw_day!r} as a date.")
        clock = _parse_clock(raw_time) if raw_time else ("" if hits[0]["all_day"] else hits[0]["start"])
        moved = move_event(root, hits[0]["id"], day, clock, _parse_clock(raw_end) if raw_end else "")
        if moved is None:
            return ToolResult.error("I could not move that event.")
        return ToolResult(
            content=f"Moved: {_describe(moved)}\nSay the new time back to them.",
            data={"event": moved["id"]},
        )

    if not title:
        return ToolResult.error("An event needs a name.")
    day = _parse_day(raw_day)
    if day is None:
        return ToolResult.error(
            f"I could not read {raw_day!r} as a date. Ask them which day, plainly."
        )
    clock = _parse_clock(raw_time) if raw_time else ""
    if raw_time and not clock:
        return ToolResult.error(f"I could not read {raw_time!r} as a time. Ask them.")
    end = _parse_clock(raw_end) if raw_end else ""

    ev = add_event(root, day, title, clock, end, location)
    if ev is None:
        return ToolResult.error("I could not write that to the calendar.")
    logger.info("calendar_write add %s", ev["id"])
    return ToolResult(
        content=(
            f"On the calendar: {_describe(ev)}\n"
            "Say the day and time back to them so a misheard one is caught now."
        ),
        data={"event": ev["id"], "date": ev["date"].isoformat()},
    )
