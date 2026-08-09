---
title: Hearth on macOS
status: draft
last_reviewed: 2026-08-08
related:
  - ../install-macos.md
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

Hearth is a local-first AI companion that runs entirely on your Mac. It gives
you a persona, Sulivan is the one you meet first, who holds a conversation,
remembers what you tell it, and speaks back in a cloned voice. Nothing is
sent anywhere: the model, the voice, and your memory all live on your own
machine.

This page covers what your Mac needs, what the install puts on your disk,
and how updates work. For the step-by-step install, see
[Installing on macOS](../install-macos.md).

## What your Mac needs

**Apple Silicon.** M1 or later. Hearth downloads an arm64 build of its
inference engine and an aarch64 build of its Python runtime, and there is no
Intel path.

**8 GB of memory or more.** 8 GB is the smallest machine Hearth supports, and
it is fully supported: an 8 GB M2 MacBook Air runs the persona and the voice
at the same time. Below 8 GB, Hearth declines to install rather than set up
something that cannot run, and tells you why.

**Free disk.** Roughly 4.5 GB on an 8 GB Mac and 8.6 GB on a 16 GB Mac. The
larger machine downloads a larger model. Hearth checks before it starts and
warns you if the space is not there.

**macOS 27.** That is what the install has been verified on. Earlier
versions are untested rather than known to fail.

## What installing gives you

The client is the installer: there is no separate backend to download.
Opening Hearth for the first time downloads the model weights, a voice, the
inference engine, and a private Python runtime together, all into one folder
you choose (`~/Hearth` by default):

```
Hearth/
  models/          the model weights, and the voice under models/voice
  runtime/         the inference engine, the Python runtime, the backend
  home/            your memory and journal live here
  config/          one generated settings file
  logs/            what everything wrote down
  hearth-install.json    the record of what was decided and installed
```

Nothing installs outside that folder: no system directories, no login items,
no background service that keeps running once you quit Hearth. Deleting the
folder is the uninstall.

While Hearth is open, it runs five local programs that talk only to each
other and to your client, all on `127.0.0.1`:

- **harness**, at port 18700, the gateway your client connects to
- **hearth-supervisor**, at 18765 for control and 18766 for assets, which
  starts, health-checks, and swaps the model
- **llama-server**, at 18080, the language model itself, running on Metal
- the **voice engine** and the voice service in front of it, at 18702; on
  macOS this is `omnivoice.cpp`, a small engine built against Apple's GPU
  rather than the CPU-only path some builds fall back to

Hearth starts this tree when it opens and stops it when it quits, so this is
usually not something you need to think about. If you do, Settings >
Connection shows whether it is running and offers Start and Stop.

## Installing

The full walkthrough, including the plan Hearth shows you before it
downloads anything, lives in
[Installing on macOS](../install-macos.md). The short version:

1. Open the disk image and drag Hearth to Applications.
2. Right-click Hearth and choose Open, then choose Open again in the dialog.
   Hearth is not yet signed by Apple, so a plain double-click on first launch
   shows a warning and refuses. macOS remembers your choice after this, and
   every launch after the first is a normal double-click.
3. Follow setup: a scan of your machine, a folder to install into, and a
   plan. On an 8 GB Air, the plan downloads Gemma 4 E2B at a 17,408-token
   context window, 3.77 GB total. A 16 GB Mac gets Gemma 4 12B at 65,536
   tokens, 7.14 GB.
4. Meet Sulivan. The last screen of setup is him speaking his first line to
   you, out loud, in his own voice. In a real conversation on the 8 GB Air,
   replies synthesize faster than real time, a measured RTF of 0.96.

## Updating

There is no in-app updater yet. Getting a new build today means downloading
the new app and reinstalling into the same folder you used the first time.
The installer only fetches and replaces what changed since your last
install, and it never touches `home/`, where your memory and journal live.

Hearth is not signed by Apple, which is also why an in-app updater is not
built yet: replacing an unsigned app automatically is a known rough edge on
macOS, and the project is deciding whether to sign before building that
piece. See [Updating an install](../updates.md) for the full design.

## Status and limitations

Hearth for macOS is pre-alpha. The install guide reflects one real,
end-to-end install on an 8 GB M2 Air, verified 2026-08-07. Some things to
know before you rely on it:

- The Windows install guide does not exist yet; only macOS is documented.
- The app is unsigned, so first launch needs the right-click-Open step
  above, and there is no automatic updater.
- Once setup finishes, Sulivan interviews you and helps you build a persona
  of your own. [First run](../first-run.md) walks through that flow.
- If something goes wrong, `install-macos.md` has a troubleshooting section
  covering connection errors, silent voice, and interrupted downloads.
