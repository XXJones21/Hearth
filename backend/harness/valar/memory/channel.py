"""Per-persona channel history: the durable room a bot and the operator share.

A channel is not a new store. It is a naming convention over session records,
the Hermes canonical-session lesson applied locally: a channel turn is any
record whose ``meta.topic`` is ``channel:<persona>``, stamped via
``session.topic_hint`` at open time. Opening a channel seeds the live session
from the concatenation of that persona's channel records, oldest first, so
history survives any number of connections and restarts without a stored
pointer anywhere. Delete the records and the channel history is gone, which
is the honest off switch.

Nothing here is Soth-shaped: any persona name works, which is what lets
Liara, Mentat or Selene grow a channel the day someone opens one, and what
the multi-persona dialogue room will reuse.
"""

from __future__ import annotations

import logging

logger = logging.getLogger("valar.channel")

CHANNEL_PREFIX = "channel:"
# What a reopened channel carries back into context. The full history stays
# on disk; the model does not need a month of it and the window does.
_MAX_TURNS = 30


def channel_topic(persona: str) -> str:
    return f"{CHANNEL_PREFIX}{persona.strip().lower()}"


def load_channel_turns(persona: str) -> list:
    """Every channel turn for ``persona`` across all records, oldest first,
    capped to the newest ``_MAX_TURNS``. Never raises."""
    from ..gateway.session_resume import parse_chatlog
    from .session_record import list_records, read_record

    topic = channel_topic(persona)
    turns: list = []
    try:
        records = [r for r in list_records() if (r.get("topic") or "") == topic]
        for rec in reversed(records):  # list_records is newest first
            full = read_record(str(rec.get("session_id") or ""))
            got = parse_chatlog(str((full or {}).get("chatlog") or ""))
            if got:
                turns.extend(got)
    except Exception as exc:  # noqa: BLE001 - a bad record never blocks the room
        logger.warning("channel %s: history load failed (%s)", persona, exc)
    return turns[-_MAX_TURNS:]
