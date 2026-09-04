---
title: Getting started
status: closed
type: concept
last_reviewed: 2026-09-04
related:
  - installing.md
  - install-macos.md
  - meeting-your-persona.md
  - clients/windows.md
  - clients/macos.md
  - developing.md
sources:
  - README.md
  - wiki/_index.md
  - wiki/clients/windows.md
  - wiki/clients/macos.md
  - wiki/clients/ios.md
  - wiki/clients/android.md
  - wiki/features/personas.md
  - wiki/first-run.md
  - wiki/installing.md
  - wiki/meeting-your-persona.md
  - wiki/releasing.md
  - crates/hearth-probe/src/plan.rs
  - crates/hearth-probe/dictionary.yaml
  - https://github.com/XXJones21/Hearth/releases
---

# Getting started

Find out what Hearth is, whether your machine can run it, and where to download the build that exists today.

## Understand what Hearth is

Hearth is an AI companion that lives on your own machine. You talk to it, it
answers out loud in a voice you designed, and it keeps what you tell it.

That companion is a persona of your own design. You meet Sulivan first, the
persona that ships with Hearth, and from there you make one of your own: a
name, a temperament, a voice, a color.

## Picture the house and its windows

Your conversations, your memory, and your persona's voice never leave the
computer they run on, because there is nowhere for them to go.

Think of the desktop machine as the house: it downloads the model, runs the
persona, and keeps the memory.

A phone is a window onto that house. The iOS app does not run a model or a
persona itself. It connects to a house running somewhere on your network and
shows you what is happening there. The Android app is a window in the same
way, paired to a desktop install from its settings.

## Check that your machine can run it

Hearth runs on a Windows machine with a capable GPU, or on an Apple Silicon
Mac (M1 or later) with 8 GB of memory or more.

On a Mac, 8 GB is the floor Hearth supports, and it is fully supported: an
8 GB M2 MacBook Air runs a persona and its voice at the same time.

On Windows, video memory decides the answer, and there are three bands:

- Below roughly 4.5 GB, Hearth declines to install and tells you why.
- Between roughly 4.5 GB and 5.4 GB, Hearth installs, and your persona thinks
  and speaks one at a time.
- Above roughly 5.4 GB, the model and the voice both stay resident, and
  neither waits for the other.

Hearth works this out for itself. It scans your hardware and plans a model
sized to what you have before it downloads anything.

## Download the build that exists today

Hearth is published on GitHub. The
[Hearth releases page](https://github.com/XXJones21/Hearth/releases) is where
builds land. Published there today is v0.1.0-alpha, from 2026-08-22, marked as
a pre-release.

That release carries a Windows installer as an `.exe` and an `.msi`, a `.dmg`
for Apple Silicon Macs, and an `.apk` for Android, with a `SHA256SUMS.txt`
beside them so you can check what you downloaded. There is no iOS or visionOS
build to download today.

The `.apk` is a window rather than a house. It runs no persona and no model of
its own, so it needs a desktop install on your network to pair with, and the
Windows or macOS build is the one to start with.

Only the Android build is signed. The macOS `.dmg` is neither signed nor
notarized, so opening it the first time takes one extra step, and
[Installing Hearth](installing.md) covers that along with everything else the
installer does.

## Make a persona of your own

Sulivan is the one resident when you first open Hearth, and he interviews you
to help build a persona of your own, in a conversation rather than a form.

The persona you make then sets up its memory and takes in one real thing you
are working on, so it has something to remember from the start.
[Meeting your persona](meeting-your-persona.md) walks through both.

## Live with your persona

You talk and they answer out loud, in the voice you designed. Their sphere
carries the color you chose and changes with the turn, from idle to listening,
thinking, and speaking.

What they remember is plain folders on your own disk: Projects, Areas,
Thoughts, and Resources, readable in any text editor and deletable whenever
you want.

![Your persona at rest in the house window](images/pending/getting-started-persona-in-use.png "CAPTURE: desktop client, the house window with a made persona at rest, the sphere in the persona color and the composer below it, no conversation open, 1280x800")

## Expect rough edges

Hearth is pre-alpha. Rough edges are expected: some screens are unfinished,
some platforms are ahead of others, and things will occasionally break in ways
a finished product would not.

If you would rather change Hearth than just run it,
[Developing on Hearth](developing.md) is the door in.
