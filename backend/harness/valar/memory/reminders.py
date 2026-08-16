"""Reminders: a thing to be told at a time, kept in a file you can edit.

Timers are relative and live in memory, so they cannot reach tomorrow and do
not survive a restart. A reminder is the other shape: an absolute moment, on
disk, in the operator's own tree.

    $ENGRAM/Areas/reminders.md

Plain markdown, one bullet per reminder, the same convention routines use:
the record IS the state. Delete a line and the reminder is gone. There is no
database and no settings screen, and the file is readable in any editor on a
machine with no Hearth running at all.

DELIVERY, honestly stated. Nothing here speaks at you. The house has no
proactive push channel yet (the timer module says the same about itself), so
a due reminder is surfaced the way the current time and the continuity note
are: in the ambient context block, every turn, until it is dismissed. The
persona sees "this was due" and says so in the next thing it says. That is
weaker than an alarm and stronger than nothing, and it does not pretend to
be an alarm.
"""

from __future__ import annotations

import logging
import re
from datetime import datetime, timedelta
from pathlib import Path

logger = logging.getLogger("valar.reminders")

HEADING = "Reminders"
_LINE_RE = re.compile(
    r"^-\s*\[(?P<done>[ xX])\]\s*(?P<when>\d{4}-\d{2}-\d{2} \d{2}:\d{2})\s+(?P<text>.+?)\s*$"
)
_MAX_TEXT = 300
_LIST_CAP = 50


def reminders_path(root: Path) -> Path:
    return root / "Areas" / "reminders.md"


def _read(root: Path) -> list[str]:
    try:
        return reminders_path(root).read_text(encoding="utf-8").splitlines()
    except OSError:
        return []


def _write(root: Path, lines: list[str]) -> bool:
    path = reminders_path(root)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(lines).rstrip("\n") + "\n", encoding="utf-8", newline="\n")
        return True
    except OSError as exc:
        logger.warning("reminders: could not write %s (%s)", path, exc)
        return False


def parse_when(text: str, now: datetime | None = None) -> datetime | None:
    """The shapes a person actually says, and nothing more clever than that.

    Deliberately narrow: a wrong guess about WHEN is worse than asking, and
    the tool tells the model to ask when this returns None.
    """
    raw = " ".join((text or "").strip().lower().split())
    if not raw:
        return None
    now = now or datetime.now()

    m = re.match(r"^(\d{4})-(\d{2})-(\d{2})[ t]+(\d{1,2}):(\d{2})$", raw)
    if m:
        y, mo, d, h, mi = (int(g) for g in m.groups())
        try:
            return datetime(y, mo, d, h, mi)
        except ValueError:
            return None

    def _clock(part: str) -> tuple[int, int] | None:
        c = re.match(r"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$", part.strip())
        if not c:
            return None
        hour = int(c.group(1))
        minute = int(c.group(2) or 0)
        ampm = c.group(3)
        if ampm == "pm" and hour < 12:
            hour += 12
        if ampm == "am" and hour == 12:
            hour = 0
        if not ampm and hour <= 7:
            # "at 6" from someone awake and talking almost always means evening.
            hour += 12
        return (hour, minute) if 0 <= hour < 24 and 0 <= minute < 60 else None

    for prefix, days, evening in (
        ("today ", 0, False),
        ("tomorrow ", 1, False),
        ("tonight ", 0, True),
        ("this evening ", 0, True),
    ):
        if raw.startswith(prefix):
            hm = _clock(raw[len(prefix) :].replace("at ", "", 1))
            if hm:
                hour, minute = hm
                # "tonight at 8" is 8pm. The word says so, and a bare hour
                # rule that only bumps 1 through 7 gets it wrong.
                if evening and hour < 12:
                    hour += 12
                return (now + timedelta(days=days)).replace(
                    hour=hour, minute=minute, second=0, microsecond=0
                )

    hm = _clock(raw.replace("at ", "", 1))
    if hm:
        base = now.replace(hour=hm[0], minute=hm[1], second=0, microsecond=0)
        # A time already past today means the next one.
        return base if base > now else base + timedelta(days=1)

    m = re.match(r"^in (\d+) (minute|minutes|hour|hours|day|days)$", raw)
    if m:
        n = int(m.group(1))
        unit = m.group(2)
        delta = (
            timedelta(minutes=n)
            if unit.startswith("minute")
            else timedelta(hours=n)
            if unit.startswith("hour")
            else timedelta(days=n)
        )
        return (now + delta).replace(second=0, microsecond=0)
    return None


def add(root: Path, when: datetime, text: str) -> bool:
    lines = _read(root)
    if not lines:
        lines = [
            "# Reminders",
            "",
            "Things the house should bring up at a time. One line each; delete a",
            "line to cancel it, and mark [x] to dismiss it.",
            "",
            f"## {HEADING}",
            "",
        ]
    if not any(ln.strip().lower() == f"## {HEADING}".lower() for ln in lines):
        lines += ["", f"## {HEADING}", ""]
    stamp = when.strftime("%Y-%m-%d %H:%M")
    lines.append(f"- [ ] {stamp} {text.strip()[:_MAX_TEXT]}")
    return _write(root, lines)


def entries(root: Path, include_done: bool = False) -> list[dict]:
    out: list[dict] = []
    for i, ln in enumerate(_read(root)):
        m = _LINE_RE.match(ln.strip())
        if not m:
            continue
        done = m.group("done").lower() == "x"
        if done and not include_done:
            continue
        try:
            when = datetime.strptime(m.group("when"), "%Y-%m-%d %H:%M")
        except ValueError:
            continue
        out.append({"line": i, "when": when, "text": m.group("text"), "done": done})
    out.sort(key=lambda e: e["when"])
    return out[:_LIST_CAP]


def due(root: Path, now: datetime | None = None) -> list[dict]:
    now = now or datetime.now()
    return [e for e in entries(root) if e["when"] <= now]


def dismiss(root: Path, needle: str) -> dict | None:
    """Tick off the one reminder matching `needle`; None when it is not one."""
    lines = _read(root)
    hits = [e for e in entries(root) if needle.lower() in e["text"].lower()]
    if len(hits) != 1:
        return None
    e = hits[0]
    lines[e["line"]] = lines[e["line"]].replace("- [ ]", "- [x]", 1)
    return e if _write(root, lines) else None


def render_due_line(root: Path, now: datetime | None = None) -> str:
    """The ambient-context line. Empty when nothing is due."""
    items = due(root, now)
    if not items:
        return ""
    shown = "; ".join(e["text"][:70] for e in items[:3])
    more = f" (+{len(items) - 3} more)" if len(items) > 3 else ""
    return f"Reminders due now: {shown}{more}. Mention this."
