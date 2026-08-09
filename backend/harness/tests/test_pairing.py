"""Pairing and the gate in front of the house.

Run it directly -- `python3 backend/harness/tests/test_pairing.py` -- or under
pytest. It needs no server, no ports and no fastapi: the registry is plain
Python and the middleware is raw ASGI, which is most of why they were written
that way.

The two assertions that matter most, and the reason this file is committed
rather than left in a scratchpad:

  - a REVOKED token stops working (the whole point of per-device tokens)
  - a PAIRED device still cannot reach the management routes

The second one was a comment claiming a property the code did not have. The
gate refuses the UNPAIRED; a stolen phone is by definition paired, and would
have been free to pair its thief's phone and revoke the owner's. The test
caught it because it was written from the claim rather than from the code.
"""

from __future__ import annotations

import asyncio
import importlib.util
import pathlib
import sys
import tempfile
import types

ROOT = pathlib.Path(__file__).resolve().parents[1]  # backend/harness


def _load():
    """Import the two modules without dragging in fastapi.

    `valar/gateway/__init__.py` imports the server, which imports fastapi. On a
    real install that is fine; on a development machine with no runtime it is
    not, and neither module under test needs it -- pairing's fastapi imports
    live inside register(), and auth.py is raw ASGI.
    """
    sys.path.insert(0, str(ROOT))
    try:
        from valar.gateway import auth, pairing  # noqa: F401  (real install)
        return pairing, auth
    except ImportError:
        pass
    for name, path in (("valar", ROOT / "valar"), ("valar.gateway", ROOT / "valar" / "gateway")):
        mod = types.ModuleType(name)
        mod.__path__ = [str(path)]
        sys.modules[name] = mod
    import valar.config.settings  # noqa: F401  (no fastapi in this one)

    out = []
    for name in ("pairing", "auth"):
        spec = importlib.util.spec_from_file_location(
            f"valar.gateway.{name}", ROOT / "valar" / "gateway" / f"{name}.py"
        )
        mod = importlib.util.module_from_spec(spec)
        sys.modules[f"valar.gateway.{name}"] = mod
        spec.loader.exec_module(mod)
        out.append(mod)
    return out[0], out[1]


pairing, auth = _load()


def _registry():
    return pairing.DeviceRegistry(path=pathlib.Path(tempfile.mkdtemp()) / "devices.json")


def _paired():
    reg = _registry()
    code, _ = reg.open_pairing()
    return reg, reg.redeem(code, "Joshua's iPhone")


# -- the registry -----------------------------------------------------------


def test_unknown_token_is_rejected():
    assert _registry().verify("anything") is None


def test_redeem_without_an_open_window_fails():
    assert _registry().redeem("123456", "phone") is None


def test_code_is_six_digits_and_single_use():
    reg = _registry()
    code, ttl = reg.open_pairing()
    assert len(code) == 6 and code.isdigit() and ttl == pairing.CODE_TTL_SECONDS
    assert reg.redeem(code, "phone")
    assert not reg.pairing_open()
    assert reg.redeem(code, "thief") is None, "a code must not be redeemable twice"


def test_wrong_code_is_rejected():
    reg = _registry()
    code, _ = reg.open_pairing()
    assert reg.redeem("000000" if code != "000000" else "111111", "phone") is None


def test_raw_token_is_never_written_to_disk():
    reg, token = _paired()
    on_disk = reg.path.read_text()
    assert "token_hash" in on_disk
    assert token not in on_disk, "a stolen devices.json must not yield a working token"


def test_token_survives_a_restart():
    reg, token = _paired()
    assert pairing.DeviceRegistry(path=reg.path).verify(token) is not None


def test_window_locks_out_after_repeated_failures():
    reg = _registry()
    code, _ = reg.open_pairing()
    wrong = "999999" if code != "999999" else "888888"
    for _ in range(pairing.MAX_ATTEMPTS + 1):
        reg.redeem(wrong, "attacker")
    assert not reg.pairing_open()
    assert reg.redeem(code, "attacker") is None, "even the right code after lockout"


def test_listing_never_exposes_the_hash():
    reg, _ = _paired()
    listed = reg.devices()
    assert len(listed) == 1 and listed[0]["name"] == "Joshua's iPhone"
    assert "token_hash" not in listed[0]


def test_revoking_kills_a_live_token():
    reg, token = _paired()
    assert reg.verify(token) is not None
    assert reg.revoke(reg.devices()[0]["id"])
    assert reg.verify(token) is None


# -- the gate ---------------------------------------------------------------


def _exercise(mw, kind, path, host, headers=None, qs=b""):
    """Drive the middleware over raw ASGI. Returns (reached_app, sent)."""
    reached, sent = [], []

    async def inner(scope, receive, send):
        reached.append(scope["path"])
        if scope["type"] == "websocket":
            await send({"type": "websocket.accept"})
            return
        await send({"type": "http.response.start", "status": 200, "headers": []})
        await send({"type": "http.response.body", "body": b"ok"})

    mw.app = inner
    scope = {
        "type": kind, "path": path, "client": (host, 5000),
        "headers": headers or [], "query_string": qs, "method": "GET",
    }
    msgs = iter([{"type": "websocket.connect"}])

    async def receive():
        return next(msgs, {"type": "http.request"})

    async def send(message):
        sent.append(message)

    asyncio.run(mw(scope, receive, send))
    return bool(reached), sent


def _gate():
    reg, token = _paired()
    mw = auth.PairingAuthMiddleware(None, registry=reg)
    bearer = [(b"authorization", f"Bearer {token}".encode())]
    return reg, token, mw, bearer


LAN = "192.168.0.42"


def test_loopback_needs_no_token():
    _, _, mw, _ = _gate()
    assert _exercise(mw, "http", "/journal/sessions", "127.0.0.1")[0]


def test_off_machine_without_a_token_is_refused():
    _, _, mw, _ = _gate()
    reached, sent = _exercise(mw, "http", "/journal/sessions", LAN)
    assert not reached and sent[0]["status"] == 401


def test_off_machine_with_a_paired_token_is_allowed():
    _, _, mw, bearer = _gate()
    assert _exercise(mw, "http", "/journal/sessions", LAN, bearer)[0]


def test_health_and_pair_are_open():
    _, _, mw, _ = _gate()
    assert _exercise(mw, "http", "/health", LAN)[0]
    assert _exercise(mw, "http", "/pair", LAN)[0]


def test_paired_device_cannot_reach_the_management_routes():
    """A stolen phone must not be able to pair another, or revoke the owner's."""
    _, _, mw, bearer = _gate()
    for route in ("/pair/open", "/pair/close", "/pair/devices", "/pair/revoke"):
        assert not _exercise(mw, "http", route, LAN, bearer)[0], route


def test_the_house_itself_can_manage_devices():
    _, _, mw, _ = _gate()
    for route in ("/pair/open", "/pair/devices", "/pair/revoke"):
        assert _exercise(mw, "http", route, "127.0.0.1")[0], route


def test_unpaired_websocket_is_closed_with_policy_violation():
    _, _, mw, _ = _gate()
    reached, sent = _exercise(mw, "websocket", "/ws", LAN)
    assert not reached
    assert sent[-1]["type"] == "websocket.close" and sent[-1]["code"] == 1008


def test_paired_websocket_connects_by_header_or_query():
    _, token, mw, bearer = _gate()
    assert _exercise(mw, "websocket", "/ws", LAN, bearer)[0]
    assert _exercise(mw, "websocket", "/ws", LAN, qs=f"token={token}".encode())[0]


def test_revoked_token_is_refused_at_the_gate():
    reg, _, mw, bearer = _gate()
    reg.revoke(reg.devices()[0]["id"])
    reached, sent = _exercise(mw, "http", "/journal/sessions", LAN, bearer)
    assert not reached and sent[0]["status"] == 401


if __name__ == "__main__":
    import logging

    logging.disable(logging.CRITICAL)  # the gate logs every refusal, by design
    tests = [(n, f) for n, f in sorted(globals().items())
             if n.startswith("test_") and callable(f)]
    failed = []
    for name, fn in tests:
        try:
            fn()
            print(f"  PASS  {name}")
        except AssertionError as exc:
            print(f"  FAIL  {name}: {exc}")
            failed.append(name)
    print(f"\n{len(tests) - len(failed)}/{len(tests)} passed")
    sys.exit(1 if failed else 0)
