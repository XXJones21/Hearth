---
title: Hearth on iOS
status: draft
last_reviewed: 2026-09-03
related:
  - ../first-run.md
  - android.md
  - windows.md
  - macos.md
  - visionos.md
sources:
  - wiki/raw/apple-client.md
  - wiki/raw/apple-project-architecture.md
  - wiki/raw/apple-implementation.md
  - backend/harness/valar/gateway/pairing.py
  - backend/harness/valar/gateway/auth.py
  - wiki/_index.md
---

# Hearth on iOS

The Hearth iOS app is a window onto a house running somewhere else on your
network. It does not run a persona, a model, or any inference itself. It
connects to a Hearth house running on a computer, and everything the app
shows or says comes from that house over the network.

This distinction shapes the whole app. The desktop client supervises a
backend process. The iOS app supervises nothing. There is no bundled server,
and no default address baked into the build: the app deliberately does not
know where your house is until you tell it.

## What it does today

A real conversation ran end to end between an iPhone 14 Pro Max and a
Windows house on 2026-08-08. Here is what that turn looked like:

1. You speak. Speech recognition runs on the phone itself, using Apple's
   on-device recognizer, not a round trip to the house.
2. The house replies with streamed audio, played back in order as it
   arrives, so the reply starts speaking before the whole response has
   generated.
3. The persona on screen animates from the real playback amplitude of that
   audio, not a canned animation.
4. Cards, such as a weather card, arrive on the same connection and land in
   a scrolling timeline below the persona.

The app has four other surfaces, reached from a shelf on the right edge of
the screen:

- **Apps**: an honest list of what the house can do, read-only from the
  phone.
- **Persona**: the persona's system prompt and its state colors, the two
  things whose value lives entirely in the persona's own file.
- **Journal**: the persona's memory, when a persona ships with memory.
- **Settings**: where you point the app at a house.

House-side settings, such as which model a persona uses or which tools it
can call, are edited on the desktop, not on the phone. The phone only edits
what belongs to the phone: the persona's prompt and colors, and its own
on-device features like speech recognition.

## The face

A persona whose config asks for one is drawn as a face rather than an orb:
two eyes, a mouth that only appears while it is speaking, and no eyebrows.
It is drawn from a dozen numbers the persona owns (how wide the head is,
how far apart the eyes sit, how long they are), so two personas wearing the
same expressions still look like two different people.

Nothing about it is a video or a canned animation. The eyes drift and blink
on their own while it waits, look away while the house is thinking, and drop
toward the keyboard when you open it to type, because that is where the
words are coming from. While it talks, the mouth follows the actual sound of
the voice rather than the text.

The house can also name a reaction for a sentence (a laugh, a sigh, a
question, a startle), and the face plays it on that sentence and settles
back out of it. Those names come from the house, so the phone and the
desktop react in the same places.

Turning on Accessibility > Motion > Reduce Motion stops the blinking, the
gaze darting and the sway. The mouth still moves with the voice: that is
speech, not decoration.

The face lives in `HearthCore/Persona/Face/`, and its design (the pose
channels, the expression library, the timing) is written down once and
implemented from that same spec on every client. See
[The persona face](../features/persona-face.md).

## How pairing works

Until 2026-08-08, a Hearth house had no authentication at all, which was
fine while the only client was a desktop app talking to itself over
loopback. Reaching a house from a second device changes that, because the
house's routes are not read-only: applying a persona rewrites its system
prompt, and applying an app can restart the server.

Pairing solves this with a short code rather than an account or a password.
From your side, it looks like this:

1. On the house, you open pairing and it shows a six-digit code, valid for
   five minutes and usable once.
2. On the phone, you enter that code along with a name for the device.
3. The house exchanges the code for a long random token and stores only a
   SHA-256 hash of it, never the token itself.
4. The phone sends that token with every later request.

The token does not expire. Losing your phone costs one revocation on the
house side, not a password rotation that logs every device out. This is not
OAuth: there is no third party and no identity provider involved, because
the phone and the house belong to the same person.

A request from the house's own machine (127.0.0.1) never needs a token,
since the desktop client already has full filesystem access to everything
the gateway could hand it. A request from anywhere else must present one.
The routes that manage pairing itself, such as viewing or revoking paired
devices, only answer from the house's own machine, even with a valid token,
so a stolen and already-paired phone cannot pair its own thief's device or
revoke yours.

As of 2026-08-08, the house side of pairing is built and tested, but the
phone does not yet have a screen to enter a code, and the desktop app does
not yet have a panel to open pairing and show one. Until both land, a phone
can only reach a house that is still running unauthenticated, which is the
default for an install that has not opened its network bind.

## What it needs

- **A Hearth house running on a computer on the same local network.** The
  app does not install or manage a backend.
- **The house's address**, which you enter once in Settings: a hostname or
  IP address, and Hearth's port, 18700.
- **The house reachable across the network.** By default a house only
  listens on its own machine (127.0.0.1), which a desktop client on that
  same machine can reach but a phone cannot. Reaching it from a phone
  requires the house to listen more broadly and its port to be allowed
  through the machine's firewall.

If you are troubleshooting a connection, `curl http://<host>:18700/health`
from another device tells you quickly whether nothing is listening at that
address, or whether something else answered. On a development machine, a
house's own internal stack sometimes answers on a different, older port
instead, which looks like a connection succeeding but reaches the wrong
thing entirely, wearing someone else's memory and personas.

## What it cannot do yet

- **No pairing screen on the phone.** The code exchange described above is
  built on the house side; the app cannot yet enter a code or send a token.
- **No widgets yet.** Home-screen widgets are declared as a target but not
  built out.
- **No persona imagery.** Personas render as an orb or a drawn face; a 3D or
  animated persona model is not bundled with any persona yet.
- **This is not the visionOS app.** The headset has its own, described in
  [Hearth on Apple Vision Pro](visionos.md).
- **No away-from-home access.** Reaching a house from outside your own
  network, for example over Tailscale, is planned but not part of the app
  today.

## One phone, one house, for now

The app is aimed at a single house on your own network. There is no
directory of houses, and no cloud account tying your phone to a house.
Entering a house's address in Settings and, once pairing lands, entering a
code shown on that house, are the only two things the app asks of you.
