"""Whose turn is this: the seam a memory handler resolves its files from.

Spec sections 3 and 4 of
docs/superpowers/specs/2026-09-02-persona-private-memory-design.md. A
handler must never take a persona name as an argument, because an argument
is a cross-persona read waiting to happen. It takes the acting persona
instead, set once at the top of the turn by whoever runs it: the voice loop
for a foreground turn, the subagent runner for a worker.

A contextvar rather than a parameter, for the same reason the dispatch
depth is one: a worker spawned under asyncio.gather inherits its parent's
turn without threading an argument through the handler contract.
"""

from __future__ import annotations

import contextlib
import contextvars
from dataclasses import dataclass
from pathlib import Path


class NoActingPersona(RuntimeError):
    """A memory handler ran outside a turn. Never the model's fault."""


@dataclass
class Acting:
    persona: str
    memory_dir: Path
    session: str = ""
    origin: str = "voice"
    # How many cap refusals this turn has already spent. Three is terminal:
    # a model that cannot prune its own notes should finish its reply, not
    # spend the round budget arguing with a character count.
    refusals: int = 0


_acting: contextvars.ContextVar[Acting | None] = contextvars.ContextVar(
    "valar_acting_persona", default=None
)


@contextlib.contextmanager
def acting(persona: str, memory_dir, session: str = "", origin: str = "voice"):
    token = _acting.set(
        Acting(
            persona=persona,
            memory_dir=Path(memory_dir),
            session=session,
            origin=origin,
        )
    )
    try:
        yield _acting.get()
    finally:
        _acting.reset(token)


def current_acting() -> Acting | None:
    return _acting.get()


def require_acting() -> Acting:
    a = _acting.get()
    if a is None:
        raise NoActingPersona("I cannot write to my memory outside a conversation turn.")
    return a
