---
title: Hearth wiki
status: draft
last_reviewed: 2026-09-03
related:
  - getting-started.md
  - developing.md
  - whats-not-here.md
sources: []
---

# Hearth wiki

Install Hearth, design a persona of your own, and run all of it on hardware you already own.

Hearth is an AI companion that runs on your own machine. The model, your memory,
and your persona's voice all sit on your hardware, and none of it travels
anywhere. These pages document Hearth as a product you download and install, and
nothing outside it; it is pre-alpha, and still rough.

## Getting started

Start here if you have not installed anything yet. Hearth runs on a Windows
machine with a capable GPU, or on an Apple Silicon Mac with 8 GB of memory or
more, and these pages cover whether your machine qualifies, what the install
does, and how an existing install becomes a newer one.

- [Getting started](getting-started.md)
- [Installing Hearth](installing.md)
- [Installing on macOS](install-macos.md)
- [Updating an install](updates.md)

## Meeting your persona

Your first hour is an install that proves itself by speaking to you, an
interview in which you and Sulivan build a persona together, and a handover to
the persona you made. These pages cover that arc and the three parts of a
companion: who they are, how they look back at you, and how they speak.

- [First run](first-run.md)
- [Personas](features/personas.md)
- [The persona face](features/persona-face.md)
- [Voice](features/voice.md)

## Living with a house

Once the first hour is over, a persona starts accumulating. Its memory is plain
markdown you can open or delete yourself, its day shows up in a feed you can
read back, and cards and tools are how it draws on your screen and acts in the
world.

- [The second brain](features/second-brain.md)
- [The house feed](features/house-feed.md)
- [Apps and extensions](features/apps-and-extensions.md)

## Running it on your devices

One desktop install is the house: it holds the models and the memory and does
the thinking. The phones and the headset are companions to that house rather
than houses of their own, and they reach it over your network.

- [Hearth on Windows](clients/windows.md)
- [Hearth on macOS](clients/macos.md)
- [Hearth on iOS](clients/ios.md)
- [Hearth on Android](clients/android.md)
- [Hearth on Apple Vision Pro](clients/visionos.md)

## Building and changing Hearth

These pages are for a reader who cloned the repository rather than installed the
app. They map the tree and the build loops, give the procedure for cutting a
release across every platform, and describe how the card library grows by use
rather than by release.

- [Developing on Hearth](developing.md)
- [Building a Hearth release](releasing.md)
- [The card forge](card-forge.md)

## Looking under the hood

These are the engineering record behind the product pages, written for someone
changing the house rather than running it. A reader who came to use Hearth can
stop above this line.

- [Native runtime](backend/native-runtime.md)
- [Build pipeline](backend/build-pipeline.md)
- [Packaging options](backend/packaging-options.md)
- [The voice engine](backend/voice-engine.md)
- [The tool catalog](backend/tool-catalog.md)

For the articles still to be written, and for the material that never publishes
here, see [What is not here](whats-not-here.md).
