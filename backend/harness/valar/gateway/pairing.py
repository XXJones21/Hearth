"""Device pairing -- who is allowed to talk to the house from off the machine.

The gateway was written for loopback and has no authentication at all. That was
correct while the only client was the desktop app on the same machine. It stops
being correct the moment a phone needs to reach it, because the routes it
exposes are not read-only: `/personas/apply` rewrites a persona's system
prompt, `/apps/apply` rewrites tools.yaml AND restarts the server, and
`/journal/*` hands over the conversation history.

## The shape, and why it is not OAuth

OAuth is a DELEGATED AUTHORIZATION protocol: it exists so you can grant a third
party access to data you hold at a second party, without giving them your
password. It presumes an identity provider.

A house has neither a third party nor an identity provider. The phone and the
house belong to the same person, and the product's thesis is that nothing is
sent anywhere -- so an external IdP is disqualified on principle, and an
internal one only moves the bootstrap problem (you would still need a first
credential to authenticate to it). What is actually wanted is far smaller:
"this device is allowed, that one is not". That is device pairing.

## How it works

1. The house shows a six-digit code, good for five minutes, single use.
2. The device posts the code to `/pair` with a name.
3. The house returns a long random token and remembers a HASH of it.
4. The device sends that token on every later request.

The token is per-device, so losing a phone costs one revocation rather than a
rotation that logs out everything. The house stores only the hash, so a stolen
devices.json does not hand over working credentials.

## What is deliberately NOT here

No expiry on issued tokens. A companion you have to re-pair with every 30 days
is a companion you stop using, and the revoke path already covers the case
expiry is meant to cover.

No password, no account, no user model. There is one person and their house.
"""

from __future__ import annotations

import hashlib
import json
import logging
import secrets
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

from ..config.settings import hearth_home

logger = logging.getLogger("valar.pairing")

# Five minutes is long enough to walk to the other room and short enough that a
# code left on screen is not a standing invitation.
CODE_TTL_SECONDS = 300

# A six-digit code is a million combinations. That is thin against an unbounded
# attacker and ample against one who gets ten tries inside five minutes, which
# is why the attempt cap below exists rather than a longer code -- the code is
# typed by a person, and length is paid for in transcription errors.
MAX_ATTEMPTS = 10


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


@dataclass
class Device:
    id: str
    name: str
    token_hash: str
    created: float
    last_seen: float = 0.0

    def public(self) -> dict:
        """What the house is willing to say about a device. Never the hash."""
        return {
            "id": self.id,
            "name": self.name,
            "created": self.created,
            "last_seen": self.last_seen,
        }


@dataclass
class _PendingCode:
    code: str
    expires: float
    attempts: int = 0


@dataclass
class DeviceRegistry:
    """Paired devices, persisted under the user's own directory.

    Lives in hearth_home() rather than the product tree, for the same reason
    memory and models do: replacing the product on an update must never revoke
    the phone in someone's pocket.
    """

    path: Path = field(default_factory=lambda: hearth_home() / "devices.json")
    _devices: dict[str, Device] = field(default_factory=dict)
    _pending: _PendingCode | None = None
    _lock: threading.Lock = field(default_factory=threading.Lock)

    def __post_init__(self) -> None:
        self._load()

    # -- persistence --------------------------------------------------------

    def _load(self) -> None:
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return
        except (OSError, ValueError) as exc:
            # A corrupt registry must not lock the owner out of their own
            # house, but it must also not silently unpair every device -- so
            # say so loudly and start empty rather than crash the gateway.
            logger.error("devices.json unreadable (%s); starting with no paired devices", exc)
            return
        for entry in raw.get("devices", []):
            try:
                device = Device(
                    id=str(entry["id"]),
                    name=str(entry.get("name") or "device"),
                    token_hash=str(entry["token_hash"]),
                    created=float(entry.get("created") or 0.0),
                    last_seen=float(entry.get("last_seen") or 0.0),
                )
            except (KeyError, TypeError, ValueError):
                continue
            self._devices[device.token_hash] = device
        logger.info("pairing: %d device(s) known", len(self._devices))

    def _save(self) -> None:
        payload = {
            "version": 1,
            "devices": [
                {
                    "id": d.id,
                    "name": d.name,
                    "token_hash": d.token_hash,
                    "created": d.created,
                    "last_seen": d.last_seen,
                }
                for d in self._devices.values()
            ],
        }
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.path.with_suffix(".json.tmp")
            tmp.write_text(json.dumps(payload, indent=2), encoding="utf-8")
            tmp.replace(self.path)
        except OSError as exc:
            logger.error("pairing: could not write %s (%s)", self.path, exc)

    # -- pairing ------------------------------------------------------------

    def open_pairing(self) -> tuple[str, int]:
        """Start a pairing window. Returns (code, seconds_valid).

        Opening a second window retires the first. Two live codes would mean a
        person reading one screen while a different code is the valid one.
        """
        with self._lock:
            code = f"{secrets.randbelow(1_000_000):06d}"
            self._pending = _PendingCode(code=code, expires=time.time() + CODE_TTL_SECONDS)
            logger.info("pairing: window open for %ds", CODE_TTL_SECONDS)
            return code, CODE_TTL_SECONDS

    def close_pairing(self) -> None:
        with self._lock:
            self._pending = None

    def pairing_open(self) -> bool:
        with self._lock:
            return self._pending is not None and time.time() < self._pending.expires

    def redeem(self, code: str, device_name: str) -> str | None:
        """Trade a valid code for a device token. None when it is not valid.

        The caller is told nothing about WHY it failed -- wrong code, expired
        window and too many attempts are one answer to anyone outside, because
        distinguishing them is a free hint.
        """
        with self._lock:
            pending = self._pending
            if pending is None or time.time() >= pending.expires:
                self._pending = None
                return None

            pending.attempts += 1
            if pending.attempts > MAX_ATTEMPTS:
                logger.warning("pairing: window closed after %d failed attempts", MAX_ATTEMPTS)
                self._pending = None
                return None

            # compare_digest, not ==: string equality returns early on the first
            # differing character and leaks the prefix by timing.
            if not secrets.compare_digest(code.strip(), pending.code):
                return None

            token = secrets.token_urlsafe(32)
            device = Device(
                id=secrets.token_hex(8),
                name=(device_name or "device").strip()[:48] or "device",
                token_hash=_hash(token),
                created=time.time(),
                last_seen=time.time(),
            )
            self._devices[device.token_hash] = device
            self._pending = None
            self._save()
            logger.info("pairing: paired %r (%s)", device.name, device.id)
            return token

    # -- verification -------------------------------------------------------

    def verify(self, token: str) -> Device | None:
        if not token:
            return None
        device = self._devices.get(_hash(token))
        if device is None:
            return None
        # Written back lazily: a timestamp per request would rewrite the file
        # on every turn, and the only reader is a human deciding what to revoke.
        now = time.time()
        if now - device.last_seen > 60:
            device.last_seen = now
            self._save()
        return device

    # -- management ---------------------------------------------------------

    def devices(self) -> list[dict]:
        return sorted(
            (d.public() for d in self._devices.values()),
            key=lambda d: d["created"],
        )

    def revoke(self, device_id: str) -> bool:
        with self._lock:
            for key, device in list(self._devices.items()):
                if device.id == device_id:
                    del self._devices[key]
                    self._save()
                    logger.info("pairing: revoked %r (%s)", device.name, device.id)
                    return True
        return False


# ---------------------------------------------------------------------------
# Routes
#
# The management routes are loopback-only by an EXPLICIT check, in auth.py's
# LOCAL_ONLY_PATHS.
#
# This comment previously claimed they were loopback-only "in practice" because
# the gate exempts loopback and refuses everything else. That was wrong, and it
# was wrong in the direction that matters: the gate refuses the UNPAIRED, and a
# stolen phone is by definition paired. It would have passed the gate and been
# free to pair its thief's phone and revoke the owner's other devices.
#
# A security property that lives in a comment is not a security property.
# ---------------------------------------------------------------------------


def register(app, registry: DeviceRegistry) -> None:
    from fastapi import Body
    from fastapi.responses import JSONResponse

    @app.post("/pair")
    async def pair(payload: dict = Body(default={})):
        """Trade a code for a token. The only unauthenticated write there is."""
        code = str(payload.get("code") or "")
        name = str(payload.get("device_name") or "device")
        token = registry.redeem(code, name)
        if token is None:
            # One answer for every failure. Which of "wrong code", "expired"
            # and "too many tries" it was is a hint, and hints are free tries.
            return JSONResponse(
                {"error": "pairing failed", "detail": "That code is not valid."},
                status_code=401,
            )
        return {"token": token}

    @app.post("/pair/open")
    async def pair_open():
        """Show a code. Loopback only -- the house's own screen."""
        code, ttl = registry.open_pairing()
        return {"code": code, "expires_in": ttl}

    @app.post("/pair/close")
    async def pair_close():
        registry.close_pairing()
        return {"ok": True}

    @app.get("/pair/devices")
    async def pair_devices():
        return {"devices": registry.devices(), "pairing_open": registry.pairing_open()}

    @app.post("/pair/revoke")
    async def pair_revoke(payload: dict = Body(default={})):
        device_id = str(payload.get("id") or "")
        return {"ok": registry.revoke(device_id)}
