"""The house feed's store: append-only day files under Engram.

Spec section 1 of docs/superpowers/specs/2026-09-02-house-feed-design.md.
One record per line, one file per day. The archive fold into feed.sqlite
is part 2; until it lands, read_page walks day files backwards and stops
when it has a page or runs out of window.
"""

from __future__ import annotations

import json
import logging
from datetime import date, timedelta
from pathlib import Path

logger = logging.getLogger("valar.feed.store")

FEED_REL = "Feed"
SEEN_FILE = "seen.json"
WINDOW_DAYS = 14
PAGE_DAYS = 30  # how far back read_page walks looking for a full page


def feed_root(engram_root=None) -> Path | None:
    if engram_root is None:
        from ..memory.topic import resolve_engram_root

        engram_root = resolve_engram_root(None)
    if engram_root is None:
        return None
    root = Path(engram_root) / FEED_REL
    try:
        root.mkdir(parents=True, exist_ok=True)
    except OSError as exc:  # noqa: BLE001
        logger.warning("feed root unavailable (%s)", exc)
        return None
    return root


def _day_path(root: Path, day: str) -> Path:
    return root / f"{day}.jsonl"


def append(rec: dict, engram_root=None) -> bool:
    """One record. False when there is nowhere to write, never an exception."""
    root = feed_root(engram_root)
    if root is None:
        return False
    day = str(rec.get("at") or "")[:10] or date.today().isoformat()
    try:
        with _day_path(root, day).open("a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        return True
    except OSError as exc:  # noqa: BLE001 - the producer's file still exists
        logger.warning("feed append failed for %s: %s", day, exc)
        return False


def read_day(day: str, engram_root=None) -> list[dict]:
    root = feed_root(engram_root)
    if root is None:
        return []
    path = _day_path(root, day)
    if not path.exists():
        return []
    out: list[dict] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:  # noqa: BLE001
        logger.warning("feed day %s unreadable: %s", day, exc)
        return []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue  # one bad line never costs the day
    return out


def read_page(before: str = "", limit: int = 50, engram_root=None) -> dict:
    """Newest first. `before` is a day; the page starts the day before it."""
    try:
        start = date.fromisoformat(before) - timedelta(days=1) if before else date.today()
    except ValueError:
        start = date.today()
    entries: list[dict] = []
    day = start
    walked = 0
    while len(entries) < limit and walked < PAGE_DAYS:
        rows = read_day(day.isoformat(), engram_root)
        rows.sort(key=lambda r: str(r.get("at") or ""), reverse=True)
        entries.extend(rows)
        walked += 1
        if len(entries) >= limit:
            break
        day -= timedelta(days=1)
    return {
        "entries": entries[:limit],
        "next_before": day.isoformat() if len(entries) >= limit else "",
    }


def find(record_id: str, engram_root=None) -> dict | None:
    day = date.today()
    for _ in range(PAGE_DAYS):
        for rec in read_day(day.isoformat(), engram_root):
            if rec.get("id") == record_id:
                return rec
        day -= timedelta(days=1)
    return None


def load_seen(engram_root=None) -> dict:
    root = feed_root(engram_root)
    if root is None:
        return {}
    path = root / SEEN_FILE
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def save_seen(seen: dict, engram_root=None) -> None:
    root = feed_root(engram_root)
    if root is None:
        return
    try:
        (root / SEEN_FILE).write_text(
            json.dumps(seen, ensure_ascii=False), encoding="utf-8"
        )
    except OSError as exc:  # noqa: BLE001
        logger.warning("feed seen not written: %s", exc)


def in_window(day: str, today: date | None = None) -> bool:
    """A file older than the window is never ingested."""
    today = today or date.today()
    try:
        return 0 <= (today - date.fromisoformat(day)).days <= WINDOW_DAYS
    except ValueError:
        return False
