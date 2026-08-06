"""Time + timers tool -- current time and an in-memory timer registry.

Two responsibilities, both standalone:

  - ``current_time`` -- the local wall-clock time/date. Pure; no deps.
  - ``set_timer`` / ``list_timers`` / ``cancel_timer`` -- a simple in-process
    timer store. Setting a timer records a fire-at instant and returns confirmation;
    listing reports remaining time; cancelling removes it.

NOTE on firing: a fired timer is a *proactive push* (Keystone 1), which is NOT
built here -- this module only owns the timer STATE and the reactive verbs (set /
list / cancel / time). The proactive scheduler that actually speaks "your timer is
done" reads ``due_timers()`` and is a separate deliverable. Keeping the state here
(rather than in the scheduler) means the reactive tool calls and the future push
daemon share one source of truth. The store is process-local and not persisted;
durable timers across restarts are a follow-up (back it with SQLite or Engram).
"""

from __future__ import annotations

import re
import threading
import time
import uuid
from datetime import datetime

from ..spec import ToolResult

# Process-global timer store. Guarded by a lock because handlers may run in the
# registry's thread executor. {id: {label, fire_at_epoch, created_epoch}}.
_LOCK = threading.Lock()
_TIMERS: dict[str, dict] = {}

# Parse "5 minutes", "1 hour 30 minutes", "90 seconds", "2h", "10m", "45s".
_DURATION_RE = re.compile(
    r"(?P<value>\d+(?:\.\d+)?)\s*(?P<unit>h(?:ours?)?|m(?:in(?:ute)?s?)?|s(?:ec(?:ond)?s?)?)",
    re.IGNORECASE,
)


def _parse_duration_seconds(text: str) -> float | None:
    total = 0.0
    found = False
    for m in _DURATION_RE.finditer(text or ""):
        found = True
        value = float(m.group("value"))
        unit = m.group("unit").lower()
        if unit.startswith("h"):
            total += value * 3600
        elif unit.startswith("m"):
            total += value * 60
        else:
            total += value
    return total if found and total > 0 else None


def _fmt_remaining(seconds: float) -> str:
    seconds = max(0, int(round(seconds)))
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    parts = []
    if h:
        parts.append(f"{h} hour" + ("s" if h != 1 else ""))
    if m:
        parts.append(f"{m} minute" + ("s" if m != 1 else ""))
    if s and not h:
        parts.append(f"{s} second" + ("s" if s != 1 else ""))
    return " ".join(parts) if parts else "0 seconds"


def _timer_card() -> dict:
    """Snapshot the live store into a `timer_card` ui_component payload
    (Generative UI Phase A). The card always carries the FULL active list --
    clients upsert by type, so last-wins gives every verb (set/list/cancel) a
    consistent refresh and an empty list clears the visible timers. Props are
    strings end-to-end; `fire_at` is epoch seconds so the client ticks the
    countdown locally; `seconds` is the remaining time at emit."""
    now = time.time()
    with _LOCK:
        rows = [
            {
                "label": t["label"],
                "fire_at": str(int(t["fire_at"])),
                "seconds": str(max(0, int(round(t["fire_at"] - now)))),
            }
            for t in sorted(_TIMERS.values(), key=lambda x: x["fire_at"])
            if t["fire_at"] > now
        ]
    return {"version": 1, "type": "timer_card", "props": {"timers": rows}}


def current_time(args: dict) -> ToolResult:
    """args: {} -- returns the local date and time."""
    now = datetime.now()
    # Avoid platform-specific strftime padding directives (%-I is POSIX-only,
    # %#I is Windows-only). Format with the portable %I and strip the leading zero.
    spoken = now.strftime("%I:%M %p")
    if spoken.startswith("0"):
        spoken = spoken[1:]
    # Day-of-month: drop a leading zero portably (no %-d / %#d).
    day = str(now.day)
    date_str = now.strftime(f"%A, %B {day}, %Y")
    return ToolResult(
        content=f"It is {spoken} on {date_str}.",
        data={"iso": now.isoformat(), "time": spoken, "date": date_str},
    )


def set_timer(args: dict) -> ToolResult:
    """args: {duration: str, label?: str}. duration is natural ('5 minutes',
    '1h30m'). Records the timer and confirms; firing is the proactive channel."""
    duration_text = str(args.get("duration") or "").strip()
    seconds = _parse_duration_seconds(duration_text)
    if seconds is None:
        return ToolResult.error(
            "I could not understand that duration -- try '5 minutes' or '1 hour 30 minutes'."
        )
    label = str(args.get("label") or "").strip() or "timer"
    timer_id = uuid.uuid4().hex[:8]
    fire_at = time.time() + seconds
    with _LOCK:
        _TIMERS[timer_id] = {"label": label, "fire_at": fire_at, "created": time.time()}
    return ToolResult(
        content=f"Okay, {label} set for {_fmt_remaining(seconds)} from now.",
        data={
            "id": timer_id,
            "label": label,
            "fire_at": fire_at,
            "seconds": seconds,
            "ui_component": _timer_card(),
        },
    )


def list_timers(args: dict) -> ToolResult:
    """args: {} -- lists active timers and remaining time."""
    now = time.time()
    with _LOCK:
        active = [(tid, t) for tid, t in _TIMERS.items() if t["fire_at"] > now]
    if not active:
        return ToolResult(
            content="You have no active timers.",
            data={"timers": [], "ui_component": _timer_card()},
        )
    lines = [
        f"{t['label']}: {_fmt_remaining(t['fire_at'] - now)} remaining" for _, t in active
    ]
    return ToolResult(
        content="Active timers -- " + "; ".join(lines) + ".",
        data={
            "timers": [{"id": tid, **t} for tid, t in active],
            "ui_component": _timer_card(),
        },
    )


def cancel_timer(args: dict) -> ToolResult:
    """args: {label?: str, id?: str}. Cancels by id, else by (first) label match,
    else all if neither given and only one exists."""
    target_id = str(args.get("id") or "").strip()
    label = str(args.get("label") or "").strip().lower()
    cancelled: str | None = None
    with _LOCK:
        if target_id and target_id in _TIMERS:
            cancelled = _TIMERS.pop(target_id)["label"]
        elif label:
            for tid, t in list(_TIMERS.items()):
                if t["label"].lower() == label:
                    _TIMERS.pop(tid)
                    cancelled = t["label"]
                    break
            else:
                return ToolResult.error(f"I don't have a timer called '{label}'.")
        elif len(_TIMERS) == 1:
            tid = next(iter(_TIMERS))
            cancelled = _TIMERS.pop(tid)["label"]
    if cancelled is None:
        return ToolResult.error("Which timer? Tell me its label.")
    # Card built AFTER the lock releases (_timer_card re-acquires the
    # non-reentrant _LOCK); it carries the refreshed list minus this timer.
    return ToolResult(
        content=f"Cancelled the {cancelled} timer.",
        data={"ui_component": _timer_card()},
    )


def due_timers(now: float | None = None) -> list[dict]:
    """Non-tool helper for the future proactive scheduler: return + remove timers
    whose fire time has passed. Not registered as a tool; the push daemon polls it."""
    now = now if now is not None else time.time()
    fired = []
    with _LOCK:
        for tid, t in list(_TIMERS.items()):
            if t["fire_at"] <= now:
                fired.append({"id": tid, **t})
                _TIMERS.pop(tid)
    return fired
