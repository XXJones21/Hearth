"""The spine record: one shape for a house event, a room message and a
channel turn.

Spec section 1 of
docs/superpowers/specs/2026-09-02-room-and-feed-spine-design.md. The
harness stamps id, at and author; a model supplies body and sometimes
refs and never the rest. Same rule as the persona note files, and for the
same reason: a stamp a model wrote is not a stamp.
"""

from __future__ import annotations

import hashlib
from datetime import datetime

KINDS = frozenset(
    {
        "message",
        "opened",
        "joined",
        "left",
        "assigned",
        "task_done",
        "settled",
        "report",
        "review",
        "checkin",
        "skip",
        "failure",
    }
)


def record_id(author: str, kind: str, at: str, seed: str) -> str:
    """Stable for the same event, so an ingest that runs twice writes once."""
    raw = f"{at}|{author}|{kind}|{seed}".encode("utf-8")
    return hashlib.sha1(raw).hexdigest()[:16]


def make(
    author: str,
    kind: str,
    body: str,
    topic: str = "",
    refs: list[str] | None = None,
    meta: dict | None = None,
    at: str = "",
) -> dict:
    if kind not in KINDS:
        raise ValueError(f"unknown kind {kind!r}")
    at = at or datetime.now().isoformat(timespec="seconds")
    refs = list(refs or [])
    seed = refs[0] if refs else body[:120]
    return {
        "id": record_id(author, kind, at, seed),
        "at": at,
        "author": str(author),
        "kind": kind,
        "topic": str(topic),
        "body": str(body),
        "refs": refs,
        "meta": dict(meta or {}),
    }
