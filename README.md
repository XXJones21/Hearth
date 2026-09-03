<p align="center">
  <img src="design/readme/hearth-header.jpg" alt="A warm room at sunset: a fire in the hearth, a chair, shelves of books, a small glowing lamp on the floor." width="100%">
</p>

# Hearth

A companion that lives on your own machine.

Your conversations, your memory, and your persona's voice stay on your
hardware. Nothing is sent anywhere, because there is nowhere for it to go.

<p align="center">
  <a href="https://raw.githubusercontent.com/XXJones21/Hearth/main/design/media/sulivan-idle-desktop.mp4">
    <img src="design/media/sulivan-idle-desktop.gif" alt="Sulivan idle on the desktop: a small flame with two capsule eyes, blinking and glancing around." width="300">
  </a>
  <br>
  <sub>Sulivan, idle, on the desktop.</sub>
</p>

Underneath: Gemma 4 for the brain, served by llama.cpp's llama-server, the
12B quantization-aware build on larger GPUs and the E4B or E2B builds on
smaller machines. OmniVoice for the voice, through omnivoice.cpp, which
designs a voice from a few attributes and then clones it sentence by
sentence. A Whisper base model for hearing. A hardware scan picks the tier.

Hearth is pre-alpha. If you are not expecting it to be rough, wait.

## What it does

You meet Sulivan, the one resident, and you make a persona of your own: a
name, a temperament, a voice, a colour. From then on that persona is who
greets you. See [personas](https://github.com/XXJones21/Hearth/wiki/personas).

Every persona speaks in a voice designed from plain attributes such as age,
pitch and accent, cloned on your machine every turn. It can place a few
non-verbal tags in a reply, such as `[laughter]` and `[sigh]`, and the engine
performs them instead of reading them. It has a face: two capsule eyes that
blink, glance and react, drawn from one motion design on every screen. See
[voice](https://github.com/XXJones21/Hearth/wiki/voice) and
[the persona face](https://github.com/XXJones21/Hearth/wiki/persona-face).

Its memory is four folders of markdown on your disk: projects, areas,
thoughts, resources. Open them in any editor. Delete what you like. See
[the second brain](https://github.com/XXJones21/Hearth/wiki/second-brain).

It can put a card on your screen from a small closed layout vocabulary, and
reach into the world through tools. See
[apps and extensions](https://github.com/XXJones21/Hearth/wiki/apps-and-extensions).

The desktop machine is the house. It runs the model, the persona and the
memory. The phone and the headset are windows onto it, at home or over a
tailnet.

## See it

Each still links to its clip.

<a href="https://raw.githubusercontent.com/XXJones21/Hearth/main/design/media/all-clients-from-vision-pro.mp4">
  <img src="design/media/all-clients-from-vision-pro.jpg" alt="Seen through Apple Vision Pro: Sulivan floating in a room beside a MacBook, a Windows laptop and two phones, each showing the same persona." width="100%">
</a>

**Every client at once** (11 s). Windows, macOS, iPhone, Android and Apple
Vision Pro on one house, seen from the headset.

<a href="https://raw.githubusercontent.com/XXJones21/Hearth/main/design/media/visionos-walkthrough-sulivan-flame.mp4">
  <img src="design/media/visionos-walkthrough-sulivan-flame.jpg" alt="Sulivan as a flame with two eyes, hovering in a bedroom seen through Apple Vision Pro." width="100%">
</a>

**Sulivan in the room** (94 s). A visionOS walkthrough of the flame body,
with a second brain session.

## What you need

A Windows machine with a capable GPU, or an Apple Silicon Mac (M1 or later)
with 8 GB of memory or more. On Windows the smallest supported tier is a GPU
with around 8 GB of video memory; larger GPUs run larger models with more
headroom. On a Mac, 8 GB is the floor, and it is supported in full: an 8 GB
M2 MacBook Air runs a persona and its voice at the same time. See
[getting started](https://github.com/XXJones21/Hearth/wiki/getting-started).

## Your first run

Three movements, in this order. The order is the design.

**Install.** The client is the installer. It scans the machine, tells you
what it found and which model that implies, and downloads it, verifying
every file against a published hash. Where the machine is small it says so
in plain words: on 8 GB your persona will think and speak one at a time.
Everything lands under one folder, `D:\Hearth` by default, and deleting that
folder is the uninstall. Before setup ends the installer checks each part by
name, the mind, the voice, hearing, skills, an empty second brain, and then
Sulivan speaks. If you heard him, all of it works, and only you can confirm
that, so the screen asks.

**Make someone.** Sulivan interviews you and the two of you build a persona
together. He is the only resident at that point, and he says so. It is a
conversation rather than a questionnaire: one thing at a time, options
offered when a question is hard to answer cold, four exchanges usually
enough. You come away with a name, a temperament, a voice, a colour, and a
system prompt written in their voice rather than his.

**Give them a memory.** The persona you just made sets up the second brain
and takes one real thing into it, argued from their own point of view: right
now they will forget this conversation the moment it ends, and they would
rather not. If you already keep notes in a folder, they connect to that
instead of seeding a new one.

The full account, including what the scan checks and why a fresh install
starts empty, is [first run](https://github.com/XXJones21/Hearth/wiki/first-run).

## Alpha builds

The first packaged alpha (0.1.0) covers three platforms. iOS and visionOS
come later through TestFlight; they are built but need Apple's pipeline.

**Windows.** An installer built with the ship loop; see
[releasing](https://github.com/XXJones21/Hearth/wiki/releasing). Run it, and
first run takes it from there.

**macOS.** The same app, built on a Mac. The alpha dmg is unsigned:
right-click, Open, once, and it opens normally after that. The full
walkthrough is [installing on macOS](https://github.com/XXJones21/Hearth/wiki/install-macos).

**Android.** A signed APK from
`cd android-client && ./gradlew assembleRelease` (signing needs a
`keystore.properties` beside the keystore; both stay out of the repository).
Sideload it, then point it at a house: the phone client pairs with a running
desktop install from Settings, and reaches it away from home over a tailnet
if the house is on one. See [Hearth on Android](https://github.com/XXJones21/Hearth/wiki/android).

The Android and Apple clients are companions to a house, not houses: one
desktop install carries the models and the memory, and the small screens
connect to it.

## What is here

```
desktop-client/     The app. Tauri v2, React, TypeScript. Supervises the backend.
backend/            The harness: gateway, personas, tools, memory, voice.
crates/
  hearth-probe/     Looks at a machine and decides what Hearth it can run.
apple-client/       The iOS and visionOS apps.
android-client/     The Android app. Compose; a phone client and a cover-screen home.
vendor/             Voice engine sources built during packaging.
scripts/            Builds the backend tarball the installer bundles; publishes the wiki.
design/             Icons, and the stills and clips this page uses.
wiki/               The source of the GitHub wiki. Edit here; main publishes it.
```

The client bundles the backend and supervises it as a tree of native
processes. No WSL, no container. An installed house runs a model server, a
gateway, and a voice engine, all started and watched by the app.

## Developing

Building the client from source, the loop by which backend changes reach the
bundle, and the hardware probe as a command line all live in
[developing](https://github.com/XXJones21/Hearth/wiki/developing). The
[wiki](https://github.com/XXJones21/Hearth/wiki) is rendered from the
`wiki/` tree on every push to `main`; change the tree, not the wiki.

## A note on history

This repository starts in August 2026 with a working client and no commits
behind it. The work is older than that: it grew inside a personal project
called Valinor, which remains the testbed and carries things that will never
ship here.

What did not come across is commit archaeology. What did come across is the
comments, and there are a lot of them, because most of what is hard about this
software is not visible in the code that survived. When a comment explains why
something is the way it is, it is usually because getting there cost a day.
