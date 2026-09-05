---
title: Hearth on macOS
status: scoped
type: platform-overview
last_reviewed: 2026-09-04
related:
  - ../installing.md
  - ../updates.md
  - ../backend/native-runtime.md
sources:
  - wiki/install-macos.md
  - wiki/raw/macos-status.md
  - wiki/raw/m1-air-runbook.md
  - wiki/backend/native-runtime.md
  - wiki/updates.md
  - wiki/_index.md
---

# Hearth on macOS

Hearth on macOS runs the persona, the model, and the voice on your own Mac,
with nothing sent anywhere else.

This page covers what the client does on a Mac, what installing it puts on
your disk, what your Mac needs, and how updates work. For the step-by-step
install, see [Installing Hearth](../installing.md).

## What it does today

Hearth gives you a persona, and Sulivan is the one you meet first. He holds a
conversation, remembers what you tell him, and speaks back in a cloned voice.

Nothing is sent anywhere: the model, the voice, and your memory all live on
your own machine.

## What installing gives you

The client is the installer: there is no separate backend to download.
Opening Hearth for the first time downloads the model weights, a voice, the
inference engine, and a private Python runtime together.

Before it downloads anything, Hearth shows you a plan. The download figure in
that plan covers two of those four, the model and the voice. The inference
engine and the Python runtime are fetched alongside them and are not counted in
that number.

Everything lands in one folder you choose (`~/Hearth` by default):

```
Hearth/
  models/          the model weights, and the voice under models/voice
  runtime/         the inference engine, the Python runtime, the backend
  home/            your memory and journal live here
  config/          one generated settings file
  logs/            what everything wrote down
  hearth-install.json    the record of what was decided and installed
```

Nothing else installs outside that folder: no system directories, no login
items, no background service that keeps running once you quit Hearth. The
exceptions are Hearth itself, in Applications, and the small webview profile it
keeps beside it.

Uninstalling is quitting Hearth, deleting that folder, and dragging Hearth to
the Trash. Copy anything you want to keep out of `home/` before you delete it,
because your memory and journal go with the folder. See
[Installing Hearth](../installing.md) for the full uninstall.

While Hearth is open, it runs five local programs that talk only to each
other and to your client, all on `127.0.0.1`:

- **harness**, at port 18700, what your client connects to
- **hearth-supervisor**, at 18765 for control and 18766 for assets, which
  starts, health-checks, and swaps the model
- **llama-server**, at 18080, the language model itself, running on Metal
- the **voice service** and the **voice engine** behind it, at 18702; on
  macOS the engine is `omnivoice.cpp`, built against Apple's GPU rather than
  the CPU-only path some builds fall back to

That build stays ahead of the conversation on the smallest machine Hearth
supports: one real tool-grounded reply synthesized at a real-time factor of
0.961, faster than real time. It is a single measurement, recorded on
2026-08-07 on an 8 GB M2 Air running macOS 27.

The full walkthrough, including the plan Hearth shows you before it downloads
anything, lives in [Installing Hearth](../installing.md).

## Start and stop the house

Hearth starts that tree when it opens and stops it when it quits, so this is
usually not something you need to think about. Closing the window is not
quitting: it hides Hearth in the menu bar and the house keeps running. Quit is
the explicit stop.

When you do need it, open **Settings > Connection** and find the row labeled
**The house**. Read the singular carefully: a differently scoped
**Connections** section, listing what the house is plugged into, sits further
down the same pane.

The row reports the house as running, with a count of its processes, as
stopped, or as unknown, and it names anything that failed along with the
reason. Three controls sit beside it: **Start**, **Stop**, and **Restart**.
Stopping frees the memory the model and the voice are holding without closing
Hearth, and starting brings them back without relaunching.

![The house row in Settings > Connection, with Start, Stop, and Restart](images/pending/macos-house-row.png "CAPTURE: Settings > Connection, the row labeled The house, backend running with its process count shown, Start, Stop and Restart all visible, 1280x800")

## What it needs

- **Apple Silicon.** An M1 or later. Hearth downloads an arm64 build of its
  inference engine and an aarch64 build of its Python runtime, and there is no
  Intel path.
- **8 GB of memory or more.** 8 GB is the smallest machine Hearth supports,
  and it is fully supported: an 8 GB M2 MacBook Air runs the persona and the
  voice at the same time. Below 8 GB, Hearth declines to install rather than
  set up something that cannot run, and tells you why.
- **Free disk.** Roughly 4.5 GB on an 8 GB Mac and 8.6 GB on a 16 GB Mac,
  because the larger machine downloads a larger model. Hearth checks before it
  starts and warns you if the space is not there.
- **macOS 27.** That is what the install has been verified on. Earlier
  versions are untested rather than known to fail.

## Updating

There is no in-app updater yet. Getting a new build today means downloading
the new app and reinstalling into the same folder you used the first time.
The installer only fetches and replaces what changed since your last
install, and it never touches `home/`, where your memory and journal live.

Hearth is not signed by Apple, which is also why an in-app updater is not
built yet: replacing an unsigned app automatically is a known rough edge on
macOS, and the project is deciding whether to sign before building that
piece. See [Updating an install](../updates.md) for the full design.

## What it cannot do yet

Hearth for macOS is pre-alpha. Some things to know before you rely on it:

- **The app is not signed by Apple.** First launch takes an extra step, which
  [Installing Hearth](../installing.md) walks you through.
- **There is no automatic updater.** Every new build is installed by hand,
  under [Updating](#updating).

Once setup finishes, Sulivan interviews you and helps you build a persona of
your own. [Meeting your persona](../meeting-your-persona.md) walks through
that flow. If something goes wrong,
[Installing Hearth](../installing.md) has a troubleshooting section covering
connection errors, silent voice, and interrupted downloads.
