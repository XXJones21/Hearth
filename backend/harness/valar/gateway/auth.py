"""The gate in front of every route, and the one exemption that matters.

## Loopback is exempt, and that is the whole design

A request whose peer address is 127.0.0.1 or ::1 came from this machine. The
desktop client is on this machine, supervises the backend, and already has
filesystem access to everything the gateway could hand it -- so a token would
protect nothing it does not already have.

Two things follow, and both are the point:

- **Existing installs change behaviour not at all.** They write
  HEARTH_HOST=127.0.0.1, so every request is loopback, so every request is
  exempt. This lands dark.
- **There is no toggle to forget.** The moment the bind widens to 0.0.0.0, the
  traffic that arrives is not loopback and must present a token. Authentication
  turns itself on by being reached from somewhere else, rather than by someone
  remembering to enable it.

The failure mode a separate `HEARTH_AUTH=1` would have: a person opens the bind
to reach their phone, does not know the flag exists, and serves an
unauthenticated house to their network. The safe configuration must not be the
one you have to know about.

## Why raw ASGI

Starlette's BaseHTTPMiddleware does not see websocket scopes, and the websocket
IS the interesting surface here -- it is the whole conversation. This is written
against the ASGI interface directly so one gate covers `http` and `websocket`.

## Where the token rides

`Authorization: Bearer <token>` for HTTP. Websockets get the same header when
the client can set one (URLSessionWebSocketTask can, via URLRequest), and a
`?token=` query parameter when it cannot -- browsers cannot set headers on a
WebSocket handshake. The query form is accepted for both so a browser client
stays possible; it is second choice because query strings land in logs.
"""

from __future__ import annotations

import json
import logging
from urllib.parse import parse_qs

from .pairing import DeviceRegistry

logger = logging.getLogger("valar.auth")

LOOPBACK = {"127.0.0.1", "::1", "localhost", "::ffff:127.0.0.1"}

# Reachable without a token from anywhere.
#
#   /health  a liveness probe that already answers before any session exists,
#            and the thing a person curls to find out whether they have the
#            right address at all. Gating it would make "is my house up" and
#            "am I paired" the same unanswerable question.
#   /pair    the door itself. It has its own gate: a six-digit code the house
#            is showing on its own screen, with an attempt cap behind it.
OPEN_PATHS = {"/health", "/pair"}

# Reachable ONLY from this machine, token or not.
#
# These are the keys to the house, and a valid device token must not be enough
# to reach them. Otherwise a stolen phone -- which is by definition paired --
# could pair its thief's phone and revoke the owner's other devices, and the
# owner's only remaining move would be editing devices.json by hand.
#
# This existed as a claim in a comment before it existed as a check. The claim
# was that the gate already covered it, and the gate does not: it refuses the
# UNPAIRED, and everything here is about limiting the PAIRED. A test written
# from the comment rather than from the code is what turned that up.
LOCAL_ONLY_PATHS = {"/pair/open", "/pair/close", "/pair/devices", "/pair/revoke"}


def _client_host(scope) -> str:
    client = scope.get("client")
    return (client[0] if client else "") or ""


def _bearer(scope) -> str:
    for raw_key, raw_value in scope.get("headers") or []:
        if raw_key == b"authorization":
            value = raw_value.decode("latin-1")
            if value.lower().startswith("bearer "):
                return value[7:].strip()
    query = parse_qs((scope.get("query_string") or b"").decode("latin-1"))
    return (query.get("token") or [""])[0].strip()


class PairingAuthMiddleware:
    """Deny anything off-machine that cannot present a paired device token."""

    def __init__(self, app, registry: DeviceRegistry):
        self.app = app
        self.registry = registry

    async def __call__(self, scope, receive, send):
        if scope["type"] not in ("http", "websocket"):
            await self.app(scope, receive, send)
            return

        path = scope.get("path", "")
        is_local = _client_host(scope) in LOOPBACK

        if is_local:
            await self.app(scope, receive, send)
            return

        # Off-machine. Management routes stop here even with a good token.
        if path not in LOCAL_ONLY_PATHS and path in OPEN_PATHS:
            await self.app(scope, receive, send)
            return

        # A CORS preflight carries no Authorization header by design; rejecting
        # it turns a would-be 401 into an opaque browser error.
        if scope["type"] == "http" and scope.get("method") == "OPTIONS":
            await self.app(scope, receive, send)
            return

        if path not in LOCAL_ONLY_PATHS and self.registry.verify(_bearer(scope)) is not None:
            await self.app(scope, receive, send)
            return

        logger.warning("auth: refused %s %s from %s", scope["type"], path, _client_host(scope))
        if scope["type"] == "websocket":
            # The handshake has to be accepted-or-closed; 1008 is "policy
            # violation", which is exactly what this is.
            await receive()
            await send({"type": "websocket.close", "code": 1008})
            return

        body = json.dumps(
            {"error": "not paired", "detail": "This device is not paired with the house."}
        ).encode()
        await send(
            {
                "type": "http.response.start",
                "status": 401,
                "headers": [
                    (b"content-type", b"application/json"),
                    (b"content-length", str(len(body)).encode()),
                ],
            }
        )
        await send({"type": "http.response.body", "body": body})
