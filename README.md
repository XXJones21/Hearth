# Hearth

A companion that lives on your own machine.

Your conversations, your memory, and your persona's voice stay on your
hardware. Nothing is sent anywhere, because there is nowhere for it to go.

Hearth is pre-alpha. It is not ready for people who are not already expecting
it to be rough.

## What is here

```
desktop-client/     The app. Tauri v2, React, TypeScript. Supervises the backend.
backend/            The harness: gateway, personas, tools, memory, voice.
crates/
  hearth-probe/     Looks at a machine and decides what Hearth it can run.
apple-client/       The iOS and visionOS apps.
android-client/     The Android app. Compose; a phone client and a cover-screen home.
vendor/             Voice engine sources built during packaging.
scripts/            Builds the backend tarball the installer bundles.
wiki/               How it works, and why it is built this way.
```

The client bundles the backend and supervises it as a tree of native
processes. No WSL, no container. An installed house runs a model server, a
gateway, and a voice engine, all started and watched by the app.

## Alpha builds

The first packaged alpha (0.1.0) covers three platforms. iOS and visionOS
come later through TestFlight; they are built but need Apple's pipeline.

**Windows.** An installer built with the ship loop:
`target/release/bundle/nsis/` after
`bash scripts/pack_backend.sh && npm run tauri build`. Run it, and first run
scans the machine, plans a model tier, downloads what it needs, and boots
the house. Everything after that is local.

**macOS.** The same app, built on a Mac; the procedure for every platform
is [`wiki/releasing.md`](wiki/releasing.md).
The alpha dmg is unsigned: right-click, Open, once, and it opens normally
after that.

**Android.** A signed APK from
`cd android-client && ./gradlew assembleRelease` (signing needs a
`keystore.properties` beside the keystore; both stay out of the repository).
Sideload it, then point it at a house: the phone client pairs with a running
desktop install from Settings, and reaches it away from home over a tailnet
if the house is on one.

The Android and Apple clients are companions to a house, not houses: one
desktop install carries the models and the memory, and the small screens
connect to it.

## Running the client from source

```
cd desktop-client
npm install
npm run tauri dev
```

For the full loop, including how backend changes reach the bundle, start at
[`wiki/developing.md`](wiki/developing.md).

## The probe

The hardware scan is its own crate, so the app, a command line, and a
scripted installer all reach the same conclusions.

```
cargo run -p hearth-probe -- explain
cargo run -p hearth-probe -- explain --simulate m1-air-8gb
cargo run -p hearth-probe -- verify
```

`explain` says what this machine should run and why. `--simulate` pretends to
be a different machine, which is how the small-machine path gets tested from a
machine that is not small. `verify` checks that every model in the dictionary
still resolves.

## Reading further

Start at [`wiki/_index.md`](wiki/_index.md).

The two articles worth reading first are
[first run](wiki/first-run.md), which is what a person meets, and
[developing](wiki/developing.md), which is how you build and change it.

## A note on history

This repository starts in August 2026 with a working client and no commits
behind it. The work is older than that: it grew inside a personal project
called Valinor, which remains the testbed and carries things that will never
ship here.

What did not come across is commit archaeology. What did come across is the
comments, and there are a lot of them, because most of what is hard about this
software is not visible in the code that survived. When a comment explains why
something is the way it is, it is usually because getting there cost a day.
