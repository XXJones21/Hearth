# Hearth

A companion that lives on your own machine.

Your conversations, your memory, and your persona's voice stay on your
hardware. Nothing is sent anywhere, because there is nowhere for it to go.

Hearth is pre-alpha. It is not ready for people who are not already expecting
it to be rough.

## What is here

```
desktop-client/     The app. Tauri v2, React, TypeScript.
crates/
  hearth-probe/     Looks at a machine and decides what Hearth it can run.
wiki/               How it works, and why it is built this way.
```

The backend is not in this repository yet. Today the client talks to a server
running elsewhere on the same machine or on the local network. Packaging that
server is the work in progress, and the plan for it is in the wiki.

## Running the client

```
cd desktop-client
npm install
npm run tauri dev
```

It will start and fail to connect, because it looks for a Hearth server on
`127.0.0.1:8700` and there is not one. That failure is correct. Settings then
Connection takes an address.

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

The two articles worth reading first are the
[component catalog](wiki/backend/component-catalog.md), which is what the
backend is actually made of, and [first run](wiki/first-run.md), which is what
a person meets.

## A note on history

This repository starts in August 2026 with a working client and no commits
behind it. The work is older than that: it grew inside a personal project
called Valinor, which remains the testbed and carries things that will never
ship here.

What did not come across is commit archaeology. What did come across is the
comments, and there are a lot of them, because most of what is hard about this
software is not visible in the code that survived. When a comment explains why
something is the way it is, it is usually because getting there cost a day.
