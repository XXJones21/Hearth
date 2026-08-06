"""Per-connection watcher that speaks when a drawing finishes.

A drawing outlives the turn that asked for it. `generate_image` submits the
job, returns immediately with an `image_card` in the drawing state, and a
daemon thread collects the PNG half a minute later. The card fills itself in
from `/imagery/state`, so the picture always arrives -- but nothing ever
SAID so, and the model, told to stop talking about it, would often promise
"I'll let you know when it's done" and then never speak again. Live on iOS,
2026-08-03: the turn ended, the transcript went quiet, and the operator was
left waiting on a promise the harness had no way to keep.

This closes that. It is shaped exactly like `idle_watchdog`: a per-connection
asyncio task holding the connection's own `emit`, so it needs no broadcast
registry and no thread hand-off -- the daemon thread only ever writes the
record, and this reads it from inside the event loop.

It speaks through `voice_loop.say`, the same no-LLM path the visionOS mode
cue uses, so the line lands in the persona's voice and in the transcript
without spending a turn.

Announcing is per-connection and per-job. Two clients both watching get told
once each, which is right: each is a separate person looking at a separate
screen.
"""

from __future__ import annotations

import asyncio
import logging

from ..tools.handlers import imagery

logger = logging.getLogger(__name__)

# The record is local, so this is a dictionary read rather than a request. Two
# seconds keeps the spoken line close to the picture without busying the loop.
_INTERVAL_S = 2.0


def _line(job: dict) -> str:
    """What the persona says. Short, because the picture is already on screen
    and doing the talking; the point is to close the loop, not to narrate."""
    if job.get("status") == "error":
        note = (job.get("note") or "").strip()
        return f"The drawing did not finish. {note}" if note else "The drawing did not finish."
    return "Your picture is ready."


async def easel_watchdog(session, current_persona, voice_loop, emit) -> None:
    """Watch the easel for THIS connection and speak once when it settles.

    Only jobs that start while the connection is open are announced. A client
    that connects after a drawing finished gets the card with the picture
    already in it, which needs no announcement -- and would otherwise be told
    about someone else's picture from an hour ago.
    """
    announced: set[str] = set()
    seen_running: set[str] = set()

    try:
        while True:
            await asyncio.sleep(_INTERVAL_S)

            job = imagery.latest_state()
            job_id = (job.get("job_id") or "").strip()
            status = job.get("status") or ""
            if not job_id or status == "none":
                continue

            if status == "running":
                seen_running.add(job_id)
                continue

            if status not in ("done", "error"):
                continue
            if job_id in announced or job_id not in seen_running:
                continue

            announced.add(job_id)

            # Never interrupt. The operator talking, or the persona already
            # mid-answer, both outrank a picture that is happy to wait -- the
            # card has been showing it since the moment it landed.
            if getattr(session, "state", None) is not None:
                state = str(session.state)
                if "LISTENING" in state or "THINKING" in state or "SPEAKING" in state:
                    logger.info("easel: %s settled mid-turn; card carries it", job_id)
                    continue

            try:
                await voice_loop.say(session, current_persona(), _line(job), emit)
            except Exception as exc:  # noqa: BLE001
                logger.warning("easel: could not announce %s: %s", job_id, exc)

    except asyncio.CancelledError:
        raise
    except Exception as exc:  # noqa: BLE001
        # A watcher that dies must not take the connection with it.
        logger.warning("easel watchdog stopped: %s", exc)
