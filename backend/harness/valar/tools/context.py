"""What turn is this, and who is speaking.

Tool handlers receive only the model's arguments, which is right for almost
everything: a tool that reads a file needs a path, not a conversation. But a
few tools act ON the conversation rather than on the world, and they cannot
be given the session in an argument because the model does not know its own
session id and would invent one if asked.

So the loop leaves it here, per turn. Module state rather than a parameter,
because threading a context object through the registry, the loop, and every
handler signature would change forty call sites to serve three tools.

One process, one live turn at a time, which is what makes this safe.
"""

from __future__ import annotations

_CURRENT: dict = {}


def set_turn_context(**fields) -> None:
    """Called by the voice loop before the tool round-trip."""
    _CURRENT.clear()
    _CURRENT.update({k: v for k, v in fields.items() if v is not None})


def turn_context() -> dict:
    """The live turn's context, or an empty dict outside a turn."""
    return dict(_CURRENT)
