"""The private block: what a persona sees of its own memory at turn start.

Spec section 2 of docs/superpowers/specs/2026-09-02-persona-private-memory-design.md.
Three sections from the plan 1 files, newest first, each capped by the slot
the turn will run in, then the Memory Honesty footer every persona and
worker carries. Built once per session per persona and reused; nothing in
it changes turn to turn, so the prompt prefix stays stable for the cache.
The volatile pieces (the day hint, the exact clock) are rendered
separately for the user-turn envelope.
"""

from __future__ import annotations

import logging
import os
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from pathlib import Path

from . import persona_memory as pm

logger = logging.getLogger("valar.memory.persona_block")


@dataclass(frozen=True)
class Caps:
    notes: int
    user: int
    recent: int


def caps_for(slot_ctx: int | None) -> Caps:
    """Character caps for the injected block, about eight percent of the slot."""
    if slot_ctx is None or slot_ctx >= 49152:
        return Caps(pm.NOTES_CAP, pm.USER_CAP, 900)
    if slot_ctx >= 12288:
        return Caps(1400, 900, 400)
    return Caps(900, 600, 300)


_slot_cache: dict[str, float | int | None] = {"at": 0.0, "value": None}
_SLOT_TTL_S = 600.0


def slot_context() -> int | None:
    """The context one slot gives a turn, read from llama-server's /props.

    /props reports default_generation_settings.n_ctx already divided by the
    slot count, which is exactly the number a turn has to live in. Cached
    for ten minutes; a failed GET falls back to the env the supervisor set.
    """
    now = time.monotonic()
    if now - float(_slot_cache["at"] or 0.0) < _SLOT_TTL_S:
        return _slot_cache["value"]  # type: ignore[return-value]
    value: int | None = None
    host = os.environ.get("HEARTH_LLAMA_HOST", "127.0.0.1")
    port = os.environ.get("HEARTH_LLAMA_PORT", "18080")
    try:
        import httpx

        r = httpx.get(f"http://{host}:{port}/props", timeout=2.0)
        r.raise_for_status()
        settings = (r.json() or {}).get("default_generation_settings") or {}
        n_ctx = settings.get("n_ctx")
        if isinstance(n_ctx, int) and n_ctx > 0:
            value = n_ctx
    except Exception as exc:  # noqa: BLE001 - the env fallback is the answer then
        logger.debug("slot context: /props unavailable (%s)", exc)
    if value is None:
        try:
            ctx = int(os.environ.get("HEARTH_LLAMA_CTX", "0") or 0)
            par = max(1, int(os.environ.get("HEARTH_LLAMA_PARALLEL", "1") or 1))
            value = ctx // par if ctx > 0 else None
        except ValueError:
            value = None
    _slot_cache["at"] = now
    _slot_cache["value"] = value
    return value


HONESTY_FOOTER = (
    "# Memory honesty\n"
    "The notes above are yours and dated. Anything older than your recent days "
    "comes only from a tool result (recall). When a lookup returns nothing, say "
    "plainly that you have no record of it; never reconstruct a day from a "
    "session title, a hint, or general context. Never claim something is on the "
    "operator's screen unless a tool in this conversation put it there. What "
    "another persona knows is theirs: ask them, never guess."
)


def honesty_footer() -> str:
    return HONESTY_FOOTER


def _newest_within(entries: list[str], cap: int) -> list[str]:
    """Newest entries first until the cap; the file keeps the rest."""
    out: list[str] = []
    used = 0
    for e in reversed(entries):
        if used + len(e) + 3 > cap and out:
            break
        out.append(e)
        used += len(e) + 3
    return out


def _section(title: str, path: Path, cap: int, full_cap: int) -> str:
    entries = pm.read_entries(path)
    shown = _newest_within(entries, cap)
    size = len(path.read_text(encoding="utf-8")) if path.exists() else 0
    meter = f"[{size:,} of {full_cap:,} characters]"
    if not shown:
        return f"# {title} {meter}\n(nothing yet)"
    return f"# {title} {meter}\n" + "\n".join(f"- {e}" for e in shown)


def _recent_days(root: Path, cap: int, today: date | None = None) -> str:
    today = today or date.today()
    sessions = {r["id"]: r for r in pm.read_sessions(root)}
    lines: list[str] = []

    def day_lines(d: date, label: str) -> None:
        entries = pm.read_log(root, d.isoformat())
        if not entries:
            return
        lines.append(f"{label} ({d.isoformat()}):")
        seen: set[str] = set()
        for e in entries:
            sid = str(e.get("session") or "")
            if sid in seen:
                continue
            seen.add(sid)
            row = sessions.get(sid, {})
            title = pm.head(row.get("title") or e.get("question") or "", 60)
            tools = sorted({t.split(" ")[0] for t in (e.get("touched") or []) if t})
            when = str(e.get("ts") or "")[11:16]
            origin = str(e.get("origin") or "")
            client = str(e.get("client") or "")
            tag = origin if origin.startswith(("dispatch", "routine", "room")) else client
            lines.append(f"- {when} {tag}: {title}" + (f" [{', '.join(tools)}]" if tools else ""))

    day_lines(today, "Today so far")
    day_lines(today - timedelta(days=1), "Yesterday")
    older: list[str] = []
    for i in range(2, 7):
        d = today - timedelta(days=i)
        n = len({e.get("session") for e in pm.read_log(root, d.isoformat())})
        if n:
            older.append(f"{d.isoformat()}: {n} session{'s' if n != 1 else ''}")
    if older:
        lines.append("Earlier: " + "; ".join(older))
    text = "\n".join(lines) if lines else "(no recorded days yet)"
    if len(text) > cap:
        text = text[: cap - 1].rsplit("\n", 1)[0] + "\n..."
    return "# My recent days\n" + text


def render_block(root: Path, caps: Caps, operator: str = "the operator") -> str:
    root = pm.scaffold(Path(root))
    parts = [
        _section("My notes", root / pm.NOTES_FILE, caps.notes, pm.NOTES_CAP),
        _section(f"What I know about {operator}", root / pm.USER_FILE, caps.user, pm.USER_CAP),
        _recent_days(root, caps.recent),
        HONESTY_FOOTER,
    ]
    return "\n\n".join(parts)


def day_hint(root: Path, user_text: str) -> str:
    """One line for the envelope when the user names a day or period."""
    try:
        from ..tools.handlers.memory import parse_day, parse_period
    except Exception:  # noqa: BLE001
        return ""
    day = parse_day(user_text)
    period = None if day else parse_period(user_text)
    if not day and not period:
        return ""
    if day:
        start = end = day
    else:
        start, end = period  # type: ignore[misc]
    d0, d1 = date.fromisoformat(start), date.fromisoformat(end)
    sessions = 0
    reports = 0
    d = d0
    while d <= d1:
        iso = d.isoformat()
        sessions += len({e.get("session") for e in pm.read_log(root, iso)})
        if (root / pm.DAY_DIRNAME / f"{iso}.md").exists():
            reports += 1
        d += timedelta(days=1)
    span = start if start == end else f"{start} to {end}"
    return (
        f"[Day hint: {span}. Your record for it: {sessions} session"
        f"{'s' if sessions != 1 else ''}, {reports} day report"
        f"{'s' if reports != 1 else ''}. Use recall(day=...) for the detail.]"
    )


def clock_line(device_context: dict | None) -> str:
    """The exact local time, for the envelope; the system block keeps the hour."""
    tz = str((device_context or {}).get("timezone") or "").strip()
    now = None
    if tz:
        try:
            from zoneinfo import ZoneInfo

            now = datetime.now(ZoneInfo(tz))
        except Exception:  # noqa: BLE001
            now = None
    if now is None:
        now = datetime.now()
    clock = now.strftime("%I:%M %p").lstrip("0")
    return f"[Now: {clock}]"
