"""One idempotent pass: what the producers have written that the feed has not.

Spec section 3 of docs/superpowers/specs/2026-09-02-house-feed-design.md.
Keyed on (path, mtime), so a pass that runs twice writes once and a pass
that was missed heals on the next one. Bounded by the store's window, so
restoring an old backup cannot flood the feed.

Nothing existing learns the feed. This reads what the producers already
write, which is why a producer can be added or removed without touching
anything that runs on a clock.
"""

from __future__ import annotations

import logging
from datetime import datetime
from pathlib import Path

from . import producers, record, store

logger = logging.getLogger("valar.feed.ingest")


def _repo_root() -> Path:
    # valar/feed/ingest.py -> feed -> valar -> Valar -> repo
    return Path(__file__).resolve().parents[3]


def _clock(path: Path) -> str:
    """The file's own time where its name carries one, its mtime otherwise."""
    parts = path.stem.split("_")
    if len(parts) >= 2 and len(parts[1]) == 4 and parts[1].isdigit():
        return f"{parts[1][:2]}:{parts[1][2:]}:00"
    try:
        return datetime.fromtimestamp(path.stat().st_mtime).strftime("%H:%M:%S")
    except OSError:
        return "00:00:00"


def run_pass(engram_root=None, repo_root=None) -> int:
    """Records appended. Never raises; one bad file never ends the pass."""
    if engram_root is None:
        from ..memory.topic import resolve_engram_root

        engram_root = resolve_engram_root(None)
    if engram_root is None:
        return 0
    engram_root = Path(engram_root)
    repo_root = Path(repo_root) if repo_root else _repo_root()

    seen = store.load_seen(engram_root)
    appended = 0
    for p, path in producers.scan(engram_root, repo_root):
        try:
            key = str(path)
            mtime = path.stat().st_mtime
            if seen.get(key) == mtime:
                continue
            author, day, excerpt = producers.describe(p, path)
            if not author or not day or not excerpt:
                continue
            if not store.in_window(day):
                seen[key] = mtime  # remembered, deliberately never ingested
                continue
            rec = record.make(
                author,
                p.kind,
                excerpt,
                refs=[str(path)],
                meta={"producer": p.name},
                at=f"{day}T{_clock(path)}",
            )
            if store.append(rec, engram_root):
                seen[key] = mtime
                appended += 1
        except Exception as exc:  # noqa: BLE001 - one bad file never ends the pass
            logger.warning("feed ingest skipped %s: %s", path, exc)
    store.save_seen(seen, engram_root)
    if appended:
        logger.info("feed ingest appended %d record(s)", appended)
    return appended
