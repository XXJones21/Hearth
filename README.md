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
apple-client/       The iOS app.
vendor/             Voice engine sources built during packaging.
scripts/            Builds the backend tarball the installer bundles.
wiki/               How it works, and why it is built this way.
```

The client bundles the backend and supervises it as a tree of native
processes. No WSL, no container. An installed house runs a model server, a
gateway, and a voice engine, all started and watched by the app.

## Running the client

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
