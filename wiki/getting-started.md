---
title: Getting started
status: draft
last_reviewed: 2026-08-09
related:
  - installing.md
  - first-run.md
  - clients/windows.md
  - clients/macos.md
  - clients/ios.md
  - features/personas.md
  - features/second-brain.md
  - features/voice.md
  - features/apps-and-extensions.md
  - developing.md
sources:
  - README.md
  - wiki/_index.md
  - wiki/clients/windows.md
  - wiki/clients/macos.md
  - wiki/clients/ios.md
  - wiki/first-run.md
---

# Getting started

Hearth is a companion of your own design, and it lives on your machine. You
meet Sulivan first, and from there you build a persona of your own: a name,
a temperament, a voice, a colour. Your conversations, your memory, and your
persona's voice never leave the computer they run on, because there is
nowhere for them to go.

## What you need

Hearth runs on a Windows machine with a capable GPU, or an Apple Silicon Mac
(M1 or later) with 8 GB of memory or more. On Windows, the smallest
supported tier is a GPU with around 8 GB of video memory; larger GPUs run
larger models with more headroom. On a Mac, 8 GB is the floor Hearth
supports, and it is fully supported: an 8 GB M2 MacBook Air runs a persona
and its voice at the same time.

Think of the desktop machine as the house: it downloads the model, runs the
persona, and keeps the memory. A phone is a window onto that house. The iOS
app does not run a model or a persona itself; it connects to a house running
somewhere on your network and shows you what is happening there.

## Three steps to a running house

1. **Install.** The client is the installer. It scans your hardware, plans a
   model sized to what you have, and downloads it. See
   [Installing](installing.md) for the full walkthrough.
2. **Meet Sulivan, and make your own persona.** Sulivan is the one resident
   when you first open Hearth, and he interviews you to help build a
   persona of your own, in a conversation rather than a form. See
   [First run](first-run.md).
3. **Start your second brain.** The persona you just made sets up its
   memory and takes in one real thing you are working on, so it has
   something to remember from the start. Also covered in
   [First run](first-run.md).

## Where to go next

The platform pages cover what Hearth is on each machine you might run it on
or connect to it from:

- [Hearth on Windows](clients/windows.md)
- [Hearth on macOS](clients/macos.md)
- [Hearth on iOS](clients/ios.md)

The feature pages cover the ideas the product is built around:

- [Personas](features/personas.md), the companions you design
- [The second brain](features/second-brain.md), memory you own
- [Voice](features/voice.md), designed and spoken locally
- [Apps and extensions](features/apps-and-extensions.md), cards and tools

## Before you start

Hearth is pre-alpha. Rough edges are expected: some screens are unfinished,
some platforms are ahead of others, and things will occasionally break in
ways a finished product would not. If you would rather change Hearth than
just run it, [Developing](developing.md) is the door in.
