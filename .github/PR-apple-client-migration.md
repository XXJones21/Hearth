# The Apple client, and a door on the house

25 commits. Two things that belong together: an iOS client that can hold a
conversation, and the authentication that makes it safe to let one in.

Proved on a physical iPhone against the Windows house on 2026-08-08 — speech
recognised on the phone, the reply streamed back as PCM, a weather card drawn in
the timeline.

---

## Why this is urgent rather than merely ready

`4a75455` (already on main) sets `HEARTH_HOST=0.0.0.0` so a phone can reach the
gateway. That was the right call and it landed without authentication, because
the authentication was on this branch.

**main today serves an unauthenticated house to the LAN.** `/journal/*` is
readable, `/personas/apply` rewrites a system prompt, and `/apps/apply` rewrites
`tools.yaml` and restarts the server — from any device on the network.

This branch closes it. The bind stays open; the desktop client keeps working
untouched because it dials `127.0.0.1` and loopback is exempt; everything else
must pair.

---

## Device pairing

Not OAuth. OAuth is delegated authorization — it presumes a third party and an
identity provider, and a house has neither. An external IdP contradicts *nothing
is sent anywhere* and fails offline; an internal one only moves the bootstrap
problem. What is wanted is "this device is allowed, that one is not."

1. The house shows a six-digit code. Five minutes, single use.
2. The device posts it to `/pair` with a name.
3. The house returns a long random token and stores only its SHA-256.
4. The device sends that token on every later request.

**Loopback is exempt, and that is the whole design.** Existing installs are
unaffected, and there is no toggle to forget: widening the bind means traffic
arrives from somewhere else, which means it must authenticate. A separate
`HEARTH_AUTH=1` would have had exactly one failure mode — someone opens the bind,
never learns the flag exists, and serves an unauthenticated house.

Also: `allow_origins=["*"]` replaced with an explicit list.

### The defect the tests caught

A comment claimed the management routes were loopback-only "in practice"
because the gate exempts loopback and refuses everything else. **The gate
refuses the *unpaired*.** A stolen phone is by definition paired, and would have
been free to pair its thief's phone and revoke the owner's devices. Now an
explicit `LOCAL_ONLY_PATHS` check.

*A security property that lives in a comment is not a security property.*

---

## What landed

| Area | State |
| --- | --- |
| 1, foundation | orb from bundled JSON, nothing listening |
| 2, transport and voice | live handshake on 18700 |
| 3, the turn and the cards | `ChatViewModel` + nine card views |
| 4, the iOS shell | the stage, shelf, status bar, composer, four surfaces |
| 5, widgets | not started |
| 6, visionOS | not started |

Plus: device pairing across all three trees, the desktop pairing panel, the app
icon, and `wiki/clients/apple-client.md`.

---

## Verification

- `backend/harness/tests/test_pairing.py` — 18/18, no server, no ports, no fastapi
- `tools/apple-gates.sh` — clean over 69 files
- `tsc --noEmit` and `vite build` clean
- iOS builds clean with no warnings; both first-run branches proved on simulator

**Not verified:** the desktop pairing panel against a live house. There is no
Python environment with fastapi on this Mac, so the client/server contract was
cross-checked by reading both sides rather than exercised. First real run will be
on Windows.

---

## Notable corrections made along the way

- The "Mentat poll" subtraction was recorded as non-existent in area 3 on a grep
  that returned 0. It exists — in `HouseStatusBar`, one file over. **A
  subtraction you cannot find is misfiled more often than it is imaginary.**
- `apple-gates.sh` read `git ls-files`, which lists tracked files only — blind
  exactly when an area lands new code. It shipped an RFC1918 literal through that
  hole. Now reads `--cached --others --exclude-standard`; 52 files checked
  became 69.
- `DEVELOPMENT_TEAM = ""` sat at project level, beating the xcconfig for any
  target without its own base configuration. One target resolved the team while
  two silently did not.
- `Local.xcconfig` could not override anything — it was included before the
  values it was meant to replace. A second developer could set their team and
  nothing else, while the one identifier they cannot use is
  `com.joshuajones.Hearth`.
- `redial()` dialled twice, orphaning a continuation. Only reachable on a real
  first run, which is why the simulator never showed it.

---

## After this merges

Branch again for visionOS (area 6). Widgets (area 5) need
`CODE_SIGN_ENTITLEMENTS` wired, which wants a device to prove the App Group.
