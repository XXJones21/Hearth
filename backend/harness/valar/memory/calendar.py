"""The house's calendar: plain files that are meant to be the real one.

This is not a convenience copy of a calendar living somewhere else. The aim
is that the operator stops needing a calendar app, which means this store is
the source of truth and anything else (an ICS export, a CalDAV sync) is a
VIEW of it rather than its master.

    $ENGRAM/Areas/Calendar/YYYY-MM.md

One file per month, one line per event, readable and editable by hand:

    - 2026-08-20 14:30-15:30  Dentist  @Main St clinic  _(a3f9c1)_
    - 2026-08-21 all-day  Rachel's birthday  _(b7d210)_

Every field maps one-to-one onto an ICS property, which is the whole reason
for the rigid shape: `to_ics()` below is a pure function of these lines, so
the export promised for later is not a rewrite, and a CalDAV sync can match
events by the stable id rather than guessing from titles.

KNOWN GAP, stated rather than half-built: no recurrence. A weekly standup has
to be written once per week today. Recurrence is where a calendar format
usually goes wrong, and the line grammar leaves room for a `~weekly` suffix
to carry an RRULE when it is done properly.
"""

from __future__ import annotations

import logging
import re
import uuid
from datetime import date, datetime, timedelta
from pathlib import Path

logger = logging.getLogger("valar.calendar")

_LINE_RE = re.compile(
    r"^-\s+(?P<date>\d{4}-\d{2}-\d{2})\s+"
    r"(?:(?P<allday>all-day)|(?P<start>\d{2}:\d{2})(?:-(?P<end>\d{2}:\d{2}))?)\s+"
    r"(?P<rest>.+?)\s*$"
)
_ID_RE = re.compile(r"_\(([0-9a-f]{6,12})\)_\s*$")
_LOC_RE = re.compile(r"\s+@(?P<loc>[^_]+?)\s*$")
_MAX_TITLE = 200


def calendar_dir(root: Path) -> Path:
    return root / "Areas" / "Calendar"


def _month_file(root: Path, when: date) -> Path:
    return calendar_dir(root) / f"{when.strftime('%Y-%m')}.md"


def _parse_line(line: str) -> dict | None:
    m = _LINE_RE.match(line.strip())
    if not m:
        return None
    rest = m.group("rest")
    ident = ""
    id_m = _ID_RE.search(rest)
    if id_m:
        ident = id_m.group(1)
        rest = rest[: id_m.start()].rstrip()
    location = ""
    loc_m = _LOC_RE.search(rest)
    if loc_m:
        location = loc_m.group("loc").strip()
        rest = rest[: loc_m.start()].rstrip()
    try:
        day = datetime.strptime(m.group("date"), "%Y-%m-%d").date()
    except ValueError:
        return None
    return {
        "date": day,
        "all_day": bool(m.group("allday")),
        "start": m.group("start") or "",
        "end": m.group("end") or "",
        "title": rest.strip()[:_MAX_TITLE],
        "location": location,
        "id": ident,
    }


def _render_line(ev: dict) -> str:
    when = "all-day" if ev.get("all_day") else (
        f"{ev['start']}-{ev['end']}" if ev.get("end") else ev["start"]
    )
    parts = [f"- {ev['date'].isoformat()} {when}", f" {ev['title'].strip()}"]
    if ev.get("location"):
        parts.append(f"  @{ev['location'].strip()}")
    parts.append(f"  _({ev['id']})_")
    return "".join(parts)


def _read_month(root: Path, when: date) -> tuple[Path, list[str]]:
    path = _month_file(root, when)
    try:
        return path, path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return path, []


def _write_month(path: Path, lines: list[str]) -> bool:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(lines).rstrip("\n") + "\n", encoding="utf-8", newline="\n")
        return True
    except OSError as exc:
        logger.warning("calendar: could not write %s (%s)", path, exc)
        return False


def events_between(root: Path, first: date, last: date) -> list[dict]:
    """Every event in the range, in order. Reads only the months it needs."""
    out: list[dict] = []
    cursor = first.replace(day=1)
    while cursor <= last:
        _path, lines = _read_month(root, cursor)
        for ln in lines:
            ev = _parse_line(ln)
            if ev and first <= ev["date"] <= last:
                out.append(ev)
        cursor = (cursor.replace(day=28) + timedelta(days=4)).replace(day=1)
    out.sort(key=lambda e: (e["date"], "" if e["all_day"] else e["start"]))
    return out


def add_event(
    root: Path,
    when: date,
    title: str,
    start: str = "",
    end: str = "",
    location: str = "",
) -> dict | None:
    ev = {
        "date": when,
        "all_day": not start,
        "start": start,
        "end": end,
        "title": title.strip()[:_MAX_TITLE],
        "location": location.strip(),
        "id": uuid.uuid4().hex[:8],
    }
    path, lines = _read_month(root, when)
    if not lines:
        lines = [f"# {when.strftime('%B %Y')}", "", "Events for this month. One line each.", ""]
    lines.append(_render_line(ev))
    # Keep the file readable: header lines first, event lines sorted after.
    header = [ln for ln in lines if not ln.strip().startswith("- ")]
    body = sorted(ln for ln in lines if ln.strip().startswith("- "))
    return ev if _write_month(path, header + body) else None


def find(root: Path, needle: str, within_days: int = 400) -> list[dict]:
    today = date.today()
    hits = [
        e
        for e in events_between(root, today - timedelta(days=within_days), today + timedelta(days=within_days))
        if needle.lower() in e["title"].lower() or needle.lower() == e["id"]
    ]
    return hits


def remove_event(root: Path, ident: str) -> dict | None:
    today = date.today()
    for ev in events_between(root, today - timedelta(days=400), today + timedelta(days=400)):
        if ev["id"] != ident:
            continue
        path, lines = _read_month(root, ev["date"])
        kept = [ln for ln in lines if not (_parse_line(ln) or {}).get("id") == ident]
        return ev if _write_month(path, kept) else None
    return None


def _minutes(clock: str) -> int | None:
    try:
        h, m = clock.split(":")
        return int(h) * 60 + int(m)
    except (ValueError, AttributeError):
        return None


def move_event(root: Path, ident: str, when: date, start: str = "", end: str = "") -> dict | None:
    """Move an event, carrying its LENGTH with it.

    "Move the dentist to four" means the appointment happens at four and still
    takes an hour. Keeping the old end time instead produces an event that
    finishes before it starts, which reads as nonsense to a person and is
    invalid in the ICS export.
    """
    old = remove_event(root, ident)
    if old is None:
        return None
    new_start = start or ("" if old["all_day"] else old["start"])
    new_end = end
    if not new_end and new_start and old.get("end") and old.get("start"):
        old_start, old_end = _minutes(old["start"]), _minutes(old["end"])
        moved_start = _minutes(new_start)
        if None not in (old_start, old_end, moved_start):
            length = max(0, old_end - old_start)
            total = (moved_start + length) % (24 * 60)
            new_end = f"{total // 60:02d}:{total % 60:02d}"
    return add_event(root, when, old["title"], new_start, new_end, old["location"])


def render_today_line(root: Path, today: date | None = None) -> str:
    """The ambient-context line: what is on today, so "what's on" needs no
    tool call, exactly as the current time needs none."""
    today = today or date.today()
    items = events_between(root, today, today)
    if not items:
        return ""
    shown = "; ".join(
        (f"{e['start']} {e['title']}" if not e["all_day"] else f"{e['title']} (all day)")[:60]
        for e in items[:4]
    )
    more = f" (+{len(items) - 4} more)" if len(items) > 4 else ""
    return f"On the calendar today: {shown}{more}."


def to_ics(root: Path, first: date, last: date) -> str:
    """The same events as an ICS file.

    Written now rather than later so the file format is held to a standard it
    has to meet, instead of one it might meet when someone tries.
    """
    def stamp(d: date, clock: str) -> str:
        return f"{d.strftime('%Y%m%d')}T{clock.replace(':', '')}00"

    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Hearth//Calendar//EN",
        "CALSCALE:GREGORIAN",
    ]
    for ev in events_between(root, first, last):
        lines.append("BEGIN:VEVENT")
        lines.append(f"UID:{ev['id']}@hearth.local")
        lines.append(f"DTSTAMP:{datetime.now().strftime('%Y%m%dT%H%M%S')}")
        if ev["all_day"]:
            lines.append(f"DTSTART;VALUE=DATE:{ev['date'].strftime('%Y%m%d')}")
            lines.append(
                f"DTEND;VALUE=DATE:{(ev['date'] + timedelta(days=1)).strftime('%Y%m%d')}"
            )
        else:
            lines.append(f"DTSTART:{stamp(ev['date'], ev['start'])}")
            if ev["end"]:
                lines.append(f"DTEND:{stamp(ev['date'], ev['end'])}")
        lines.append("SUMMARY:" + ev["title"].replace(",", "\\,"))
        if ev["location"]:
            lines.append("LOCATION:" + ev["location"].replace(",", "\\,"))
        lines.append("END:VEVENT")
    lines.append("END:VCALENDAR")
    return "\r\n".join(lines) + "\r\n"
