"""Where the house feed's file-backed events come from.

Spec section 2 of docs/superpowers/specs/2026-09-02-house-feed-design.md.
A table, not logic scattered across the house: adding Liara's daily
summary is one row, and moving Mentat's runs into the feed is one row.

A producer that matches nothing is logged, so a renamed file surfaces as a
warning rather than as a card that quietly stopped appearing.

Three of the design's six rows are here. The runlog's skip and failure
lines need line-level parsing rather than file-level, which the ingest's
(path, mtime) key does not fit; and a persona's own day/<day>.md is the
same event as its inbox copy, which the design says the inbox wins. Both
are part 2.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from pathlib import Path

logger = logging.getLogger("valar.feed.producers")

EXCERPT_CHARS = 600

# 2026-09-02_0917_soth.md
_RUN_NAME = re.compile(r"^(\d{4}-\d{2}-\d{2})_(\d{4})_([a-z]+)\.md$")
_DAY_NAME = re.compile(r"^(\d{4}-\d{2}-\d{2})\.md$")


@dataclass(frozen=True)
class Producer:
    name: str
    kind: str
    where: str  # "repo" or "engram"
    pattern: str


PRODUCERS: list[Producer] = [
    Producer("routine-report", "report", "repo", "tasks/GTM/content/runs/*_*.md"),
    Producer("day-report", "checkin", "engram", "Inbox/*/*.md"),
    Producer("daily-review", "review", "engram", "Reviews/daily/*.md"),
]


def _base(where: str, engram_root: Path, repo_root: Path) -> Path:
    return engram_root if where == "engram" else repo_root


def scan(engram_root, repo_root) -> list[tuple[Producer, Path]]:
    out: list[tuple[Producer, Path]] = []
    for p in PRODUCERS:
        base = _base(p.where, Path(engram_root), Path(repo_root))
        try:
            matches = sorted(base.glob(p.pattern))
        except OSError as exc:  # noqa: BLE001
            logger.warning("feed producer %s could not scan %s: %s", p.name, base, exc)
            continue
        if not matches:
            logger.info("feed producer %s matched nothing under %s", p.name, base)
        for path in matches:
            out.append((p, path))
    return out


def describe(p: Producer, path: Path) -> tuple[str, str, str]:
    """(author, day, excerpt) for one match. An empty author means skip it."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return "", "", ""
    body = text.split("\n", 1)[1] if "\n" in text else text
    excerpt = body.strip()[:EXCERPT_CHARS]
    if not excerpt:
        return "", "", ""

    if p.name == "routine-report":
        m = _RUN_NAME.match(path.name)
        if not m:
            return "", "", ""
        return m.group(3).capitalize(), m.group(1), excerpt
    if p.name == "day-report":
        # Inbox/<day>/<Persona>.md, and never the log copy beside it.
        if path.name.endswith(".log.json"):
            return "", "", ""
        return path.stem, path.parent.name, excerpt
    if p.name == "daily-review":
        m = _DAY_NAME.match(path.name)
        if not m:
            return "", "", ""
        return "Selene", m.group(1), excerpt
    return "", "", ""
