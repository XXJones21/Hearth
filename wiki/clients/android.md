---
title: Hearth on Android
status: draft
last_reviewed: 2026-09-03
related:
  - ios.md
  - windows.md
  - visionos.md
  - ../first-run.md
sources:
  - tasks/android-client-implementation.md
  - tasks/android-client-mirror.md
  - wiki/raw/android-client-plan.md
  - wiki/raw/android-appliance-plan.md
  - wiki/raw/persona-flame-spec.md
  - android-client/appliance/runbook.md
  - android-client/app/src/main/java/com/hearth/Appliance.kt
  - backend/harness/valar/gateway/pairing.py
  - backend/harness/valar/gateway/auth.py
  - android-client/
---

# Hearth on Android

The Hearth Android app is a window onto a house running somewhere else. It
does not run a persona, a model, or any inference of its own. Everything it
shows or says comes from a house over the network.

That is the same contract the iOS app keeps, and it is deliberate: the two
phones are the same client written twice, not two products. Where they
differ, this article says so.

The app was built and proven on a Motorola Razr Plus 2023, wifi only, with no
Google account signed in. That device is not an accident. It folds, so it has
a second screen, and Hearth lives on both.

## What it does today

A voice turn runs end to end, including with the phone closed:

1. You speak. Recognition runs on the phone using Android's own recognizer,
   asked for the offline engine first, so the audio does not leave the device.
2. The house replies with streamed audio, played in order as it arrives, so
   the voice starts before the whole answer exists.
3. The persona animates from the real playback amplitude of that audio.
4. The reply fills in as a caption at the pace of the voice rather than
   arriving as a finished paragraph.
5. Cards, such as a timer counting down, arrive on the same connection.

After a turn, the app listens again for a follow-up and returns to rest on
its own if nothing comes.

Five surfaces sit behind a shelf on the right edge:

- **Sessions**: past conversations with this house.
- **Journal**: the persona's memory, shown as rooms of books.
- **Apps**: what the house can reach and who may ask, read only from here.
- **Persona**: who lives here. The prompt is editable from the phone; the
  rest is shown with a lock, because it is edited at the desk.
- **Settings**: the address, the pairing, and what the house reports about
  itself.

The app follows the system's light and dark setting.

## The persona

Which drawing a persona gets is chosen by that persona's own config, never by
its name. Nothing in the client says "if Sulivan". A persona declares a
`visualization.type` and the stage honours it:

| Type | What the phone draws |
| --- | --- |
| `sphere_particle` | The orb: a bead in a field of ninety-six orbiting dots. |
| `procedural_face` | The eyes-first face on a drawn head. |
| `flame` | A fire, wearing that same face. |
| `glb_animated` | Nothing yet. Falls back to the orb. |

The orb is the default, and it is what everything else falls back to: a model
persona whose asset has not arrived, a face whose numbers have not, a persona
the house has not described yet.

**The fire is Sulivan's.** It is drawn with vector primitives, no shader and
no 3D, from the same arithmetic the headset uses to build it as a mesh. A
flame is a surface of revolution, so its outline is the profile evaluated at
the two meridians where the horizontal coordinate is extremal. The phone
evaluates exactly what the headset evaluates, at two angles instead of
forty-four. The silhouette is not an approximation of the headset's; it is
the same curve. The full build order is in the persona flame spec this page was compiled
from.

The face on the fire is features only, in flat black. With a head drawn under
it, the result is a persona standing in front of a flame rather than a flame
with a face, and a warm brown that reads well on cream washes out on bright
gold.

Everything else about the face is unchanged from the other clients: same
director, same expression library, same blink and gaze. A persona wearing a
flame blinks exactly as it does wearing a head.

## The cover screen

The Razr's outer screen is not a widget surface. It is a real second display:
1056 by 1066 at 360dpi, its own display group, and the platform's presentation
flag set. So the client runs there, and it runs as itself rather than as a
summary of itself. One socket, one persona, one conversation. Closing the
phone continues the turn you were having.

Hearth holds the cover's home seat through `SECONDARY_HOME`, which is a real
platform role rather than a Motorola invention. There is deliberately no
`CATEGORY_HOME` on that filter, so claiming the cover cannot disturb the
launcher on the inner display.

A square strip is not a tall phone, so the layout differs in two ways:

- **The persona moves rather than shares.** On the tall screen a clock crowns
  the stage, the persona keeps the slack, and the caption sits below, all at
  once. There is no all-at-once here. The persona rides between the middle of
  an empty stage and the top of a busy one, and keeps a floor of the height
  either way.
- **What a turn leaves behind expires.** Thirty seconds after the house stops
  talking the caption goes, thirty after that the card follows, and the
  persona settles back to the middle. A timer still counting is exempt: being
  able to read a countdown without opening the phone is the whole reason a
  card belongs there.

Motorola draws its own clock, battery and navigation bar below the app's
window, so Hearth draws no clock of its own on that screen.

Motorola also gates which apps may run on the cover, one app at a time,
through a prompt it shows on the cover itself. Hearth was let through by hand.

## How pairing works

Reaching a house from a phone means the house cannot stay open: its routes
are not read only. Applying a persona rewrites a system prompt, and applying
an app can restart the server.

Pairing solves that with a short code rather than an account:

1. On the machine running the house, you open pairing and it shows a
   six-digit code, good for five minutes and usable once.
2. On the phone, you enter it.
3. The house trades the code for a long random token and stores only a
   SHA-256 hash of it, never the token.
4. The phone presents that token on every later connection.

The code can only be shown on the house's own machine. The routes that manage
pairing answer from there and nowhere else, even to a caller with a valid
token, so a stolen and already-paired phone cannot pair its thief's phone or
revoke yours. The phone's own pairing screen says where to find a code,
because a field labelled "Pairing code" with nothing else on it leaves no way
to work that out.

**The phone can always get back in.** Three situations end with the same
screen, which is the point:

- A first run, with no house and no key.
- Pointing the app at a different house. Committing a new address surrenders
  the old house's key, because presenting one house's token to another earns
  a refusal.
- The house turning this device away, because the key was revoked or a
  different house now answers at that address. The phone says so by name and
  offers to pair again.

That last one is worth stating precisely, because it hid a bug for a while.
The gate closes the connection before accepting it, so a refusal arrives as
an HTTP 403 on the upgrade rather than as a WebSocket close code. A client
that only watches for the close code sees a refused device as a flaky network
and reconnects forever against a door it has no key for.

A revoked token is not cleared from the phone. It keeps a dead key until a
new one replaces it, which is harmless, but it means "paired" on this phone
means it holds a key, never that the key still works.

## Away from home

The app reaches a house over Tailscale as readily as over the local network,
because a tailnet address is just an address. Pairing, a full voice turn and
the cover screen have all been exercised that way.

`Test` and `Apply` in Settings are deliberately different verbs. Test probes
whatever is typed and then puts the saved value back, so a wrong address is
found without taking the live connection down. It is worth knowing what Test
proves and what it does not: the house answers its health check to anyone,
and the conversation to no one without a token. An address can pass a probe
and still refuse a connection, and that means the phone needs a code, not a
different address.

## How it is built

Two Gradle modules, mirroring the split the iOS client uses between its core
package and its app target:

- **`core/`** is everything with no screen in it: the transport, the audio,
  the speech recognizer, the persona arithmetic and its director, the card
  store, the surface loaders, the config. It is where the tests are.
- **`app/`** is Compose: the stage, the five surfaces, the shared surface
  vocabulary they are all built from.

Kotlin and Jetpack Compose throughout, `com.hearth`, minSdk 33, compiled and
targeted at 35. OkHttp carries the WebSocket. There is no third-party UI
toolkit and no image library; the personas are drawn with paths and
gradients.

Two structural choices are worth knowing before editing:

- **The transport speaks in events, not callbacks.** Where the iOS client has
  roughly thirty closures, this has one sealed type on a flow. Adding a
  message from the house is a new case, and the compiler names every place
  that has to handle it.
- **Nothing at sixty frames a second goes through recomposition.** The face
  and the flame are ticked by the frame clock and drawn from a mutable pose,
  because a mouth following a voice must not drive Compose's diff. The first
  device build did the obvious thing instead and produced a fourteen-second
  frame.

## What it needs

- **A Hearth house**, running on a computer. The app installs and manages
  nothing.
- **The house's address**, entered once: a hostname, a LAN address or a
  tailnet name, and the port, 18700.
- **A pairing code from that house**, shown on the machine running it.
- **The house reachable across the network.** By default a house listens only
  on its own machine, which its desktop client can reach and a phone cannot.

If a connection is not working, `curl http://<host>:18700/health` from
another device separates "nothing is listening there" from "something
answered", which are different problems. It cannot tell you whether you are
paired.

## What it cannot do yet

- **No model personas.** Selene is `glb_animated` and the phone has no
  renderer for it, so she falls back to the orb. Tracked in
  `tasks/android-selene-model.md`.
- **No widgets.** Nothing on the home screen or the cover's own panels.
- **The thinking state has no whirl.** The flame's specification gives
  thinking a slow turn of the ember plume, and no flat client draws one, so
  thinking currently reads like idle. It is a shared gap rather than an
  Android one: adding it here alone would make the two flames different
  characters.
- **Color bands do not wander.** The headset perturbs the fire's color ramp
  with the same noise field that shapes it. A gradient cannot, so the drawn
  flame's color boundaries are level where a computed one's wander. This is
  the largest visual difference between the two and it is accepted.
- **No proactive push.** The house cannot start a turn. A timer that fires
  draws its card and counts to zero, and nothing speaks. That is a house-side
  gap, tracked in `tasks/backend/timer-tool-fix.md`.
- **One house at a time.** No directory of houses, no account.

## The appliance

Everything above describes Hearth as an app on an ordinary phone, and on an
ordinary phone that is all it is. The same APK also carries the appliance:
provisioned as device owner, it takes the phone over completely. The Razr
that proved the client is now that appliance, provisioned live on
2026-08-22. A power cycle with the lid closed lands in the pinned persona
on the cover, the tailnet comes up with nobody present, and a full voice
turn round-trips on a device with about a hundred and twenty packages
removed.

The touchpoints live in the client and are no-ops everywhere else. A
`DeviceAdminReceiver` in package `com.hearth`, so the provisioning one-shot
reads `com.hearth/.DeviceOwnerReceiver`. A kiosk routine on every resume
that, only when the app owns the device, takes both home seats, pins into
lock task, disables the shade and the keyguard, and enforces Tailscale as
always-on VPN. A boot receiver. A guarded broadcast that unpins for
development. On a phone that was never provisioned, every one of these
returns before doing anything.

Three things the device taught, each now enforced or recorded:

- **The VPN must be policy, not habit.** The first post-strip reboot landed
  in a persona that could not reach the house, because Tailscale sat
  waiting to be opened. The DPC now sets it always-on, lockdown off so a
  broken tunnel degrades to LAN rather than to nothing.
- **The cover seat is taken by preference, not by removal.** Motorola marks
  its cover launcher non-disable, so the strip cannot remove it. A
  persistent preferred activity for `SECONDARY_HOME` outvotes it instead;
  it stays installed and never runs.
- **No factory reset was needed.** `dpm set-device-owner` demands zero
  accounts, and the two on the device were stubs owned by removable apps.
  Uninstalling the owners cleared the gate, which means provisioning
  preserved everything the operator asked to keep.

The strip inventory, the restore path and the full provisioning order live
in `android-client/appliance/`, curated from this device's real package
list. The plan and its locked decisions are staged with this page's sources.
Still owed from that plan: the
cover-screen design pass, and what the lid shows during the boot window
when the house is not yet reachable.
