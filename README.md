<p align="center">
  <img src="design/readme/hearth-header.jpg" alt="A warm room at sunset: a fire in the hearth, a chair, shelves of books, a small glowing lamp on the floor." width="100%">
</p>

# Hearth

A companion that lives on your own machine.

Your conversations, your memory, and your persona's voice stay on your
hardware. Local hardware ensures your data never leaves your machine because
there is no cloud to send it to.

<p align="center">
  <a href="https://raw.githubusercontent.com/XXJones21/Hearth/main/design/media/sulivan-idle-desktop.mp4">
    <img src="design/media/sulivan-idle-desktop.gif" alt="Sulivan idle on the desktop: a small flame with two capsule eyes, blinking and glancing around." width="300">
  </a>
  <br>
  <sub>Sulivan, idle, on the desktop.</sub>
</p>

The brain is Gemma 4, using the 12B quantization-aware build on larger GPUs
and the E4B or E2B builds on smaller machines, served by llama.cpp's
llama-server. The voice is OmniVoice through omnivoice.cpp, a compiled engine
that designs a voice from attributes and clones it per sentence. Hearing is a
Whisper base model on the same machine, and the hearth-probe crate performs
the hardware scan to pick the model tier.

Hearth is pre-alpha. It is not ready for people who are not already expecting
it to be rough.

## What it does

- **You make someone.** Hearth does not ship a chatbot to configure. You meet
  Sulivan, the one resident, and then you design a persona of your own: a
  name, a temperament, a voice, a colour. That someone greets you from then
  on. See [personas](wiki/features/personas.md).
- **They speak, and they look back.** Every persona has a voice designed from
  plain attributes (age, pitch, accent) and cloned locally on every turn,
  with a small vocabulary of non-verbal tags the engine performs rather than
  reads. Each has a procedural face, two capsule eyes that blink, glance and
  react, drawn from the same motion design on every screen. See
  [voice](wiki/features/voice.md) and
  [the persona face](wiki/features/persona-face.md).
- **They remember, in files you own.** A persona's memory is four folders of
  plain markdown on your disk: projects, areas, thoughts, resources. Open
  them in any editor. Delete what you like. See
  [the second brain](wiki/features/second-brain.md).
- **They draw and they act.** A persona can put a card on your screen from a
  small closed layout vocabulary, and reach into the world through tools.
  See [apps and extensions](wiki/features/apps-and-extensions.md).
- **One house, many windows.** The desktop machine is the house: it runs the
  model, the persona and the memory. The phone, the tablet and the headset
  are windows onto it, at home or over a tailnet.

## See it

Each link opens the clip directly in your browser.

- [**Every client at once**](https://raw.githubusercontent.com/XXJones21/Hearth/main/design/media/all-clients-from-vision-pro.mp4)
  (11 s). Windows, macOS, iPhone, Android and Apple Vision Pro, all
  connected to one house, seen from the headset.
- [**Sulivan in the room**](https://raw.githubusercontent.com/XXJones21/Hearth/main/design/media/visionos-walkthrough-sulivan-flame.mp4)
  (94 s). A full visionOS walkthrough of the flame body, including a second
  brain session.

## What you need

A Windows machine with a capable GPU, or an Apple Silicon Mac (M1 or later)
with 8 GB of memory or more. On Windows the smallest supported tier is a GPU
with around 8 GB of video memory; larger GPUs run larger models with more
headroom. On a Mac, 8 GB is the floor and it is fully supported: an 8 GB M2
MacBook Air runs a persona and its voice at the same time. The full picture,
including what first run does with what it finds, is in
[getting started](wiki/getting-started.md).

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
design/             Icons, and the stills and clips this page uses.
wiki/               How it works, and why it is built this way.
```

The client bundles the backend and supervises it as a tree of native
processes. No WSL, no container. An installed house runs a model server, a
gateway, and a voice engine, all started and watched by the app.

## Alpha builds

Download the Windows installer, run it, and meet Sulivan. The installer scans
your hardware, picks a model, and downloads the files, while the
[first run](wiki/first-run.md) handles the onboarding.

The first packaged alpha (0.1.0) covers three platforms. iOS and visionOS
come later through TestFlight; they are built but need Apple's pipeline.

**Windows.** An installer built with the ship loop:
`desktop-client/src-tauri/target/release/bundle/nsis/` after
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
connect to it. After installing, the [first run](wiki/first-run.md) is where
you will meet your persona.

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
