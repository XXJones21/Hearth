---
title: Installing Hearth
status: draft
last_reviewed: 2026-08-09
related:
  - install-macos.md
  - first-run.md
  - clients/windows.md
  - clients/macos.md
  - backend/native-runtime.md
  - updates.md
sources:
  - wiki/install-macos.md
  - wiki/first-run.md
  - wiki/clients/windows.md
  - wiki/clients/macos.md
  - wiki/backend/native-runtime.md
  - wiki/updates.md
---

# Installing Hearth

You have the Hearth installer. This page walks through what happens next: the
scan of your machine, the plan it shows you, the download, and the moment you
know it worked. It is the narrative version of the install; for the detailed
macOS steps and troubleshooting, see [Installing on macOS](install-macos.md).

## Before you start

Hearth checks your machine before it installs anything, and it declines
outright if your machine is below its floor rather than installing something
that cannot run.

### macOS

You need an Apple Silicon Mac, M1 or later. There is no Intel path: Hearth
fetches an arm64 build of its inference engine and an aarch64 build of its
Python runtime, and an Intel Mac cannot finish the install. 8 GB of memory is
the smallest machine Hearth supports, and it is fully supported: an 8 GB M2
MacBook Air runs the mind and the voice at once and speaks. Below 8 GB, Hearth
declines and tells you why. You also need free disk: roughly 4.5 GB on an
8 GB Mac and 8.6 GB on a 16 GB Mac, because the larger machine downloads a
larger model. macOS 27 is what the install has been verified on; earlier
versions are untested rather than known to fail. See
[Hearth on macOS](clients/macos.md) for the full requirements.

### Windows

The Windows desktop app installs and runs the whole backend as native Windows
processes: no separate server, no container, no Linux layer. Before
downloading anything, Hearth scans your memory, GPU, and free disk, and it
chooses a model plan sized to what it finds, the same way the Mac client does.
Most machines land on a 16 GB GPU tier, and a smaller GPU gets a smaller plan.
See [Hearth on Windows](clients/windows.md) for what the installed app looks
like once it is running.

## The scan and the plan

Once you open Hearth for the first time, it reads your machine: memory,
graphics, and free disk. This takes a second or two.

Then it shows you a plan, before it downloads a single byte. The plan names
the model, the context window, and the download size, and it explains its own
reasoning in plain sentences, including anything it had to trade away. On an
8 GB Mac, that plan reads:

| | |
| --- | --- |
| Model | Gemma 4 E2B, Q4_K_M |
| Context window | 17,408 tokens |
| Download | 3.77 GB |

A 16 GB machine gets a considerably larger model, Gemma 4 12B, at a
65,536-token context window, for a 7.14 GB download. Where a machine is
small, Hearth says so in your language rather than in specs: on an 8 GB
machine, the honest phrasing is that your persona will think and speak one at
a time, not a note about memory headroom. You approve the plan. Nothing
downloads before that.

## Choosing where it lives

Hearth asks for one folder, the install root, and everything it downloads
goes inside it: the model weights, the voice, the inference engine, and a
private Python runtime. The default is `Hearth` in your home directory on
macOS and `D:\Hearth` on Windows, and you can point it anywhere with room.
Pick an empty location rather than a folder that already holds something of
yours.

Nothing Hearth installs lands outside that folder, aside from the client
application itself and its small browser-webview profile. That is what makes
uninstalling a single action: quit Hearth and delete the folder.

## The download

Several things download and unpack at once: the model weights, the voice, the
inference engine, and the Python runtime it needs. On a reasonable connection
this is mostly download time.

Every file is verified against a published sha256 hash once it lands. A
mismatch deletes the file and fails loudly, rather than being mistaken for an
already-complete file on retry. If the download is interrupted, for a lost
connection or low disk, running setup again resumes it: anything already
fetched and verified is skipped rather than fetched again.

## Proving it works

Starting is not the same as working, so Hearth checks each capability in turn
and names it in plain terms: the mind is loaded and answering, the voice is
ready, hearing is ready, skills are available, and the second brain exists.

The last check is one no automated test can perform. The final screen of
setup is Sulivan speaking the first thing he will ever say to you, out loud,
in his own voice. If you heard him, the mind that wrote the words, the voice
that spoke them, and the machine underneath both are all working. The buttons
are honest ones: say whether you heard him or not.

After that, Hearth opens into the house and stays there. It will not walk you
through setup again.

## What comes next

Setup ends where the relationship starts. Sulivan interviews you and helps
you build a persona of your own, and that persona then sets up your second
brain with one real thing in it. See [First run](first-run.md) for the full
walkthrough of both.

## Platform notes

The step-by-step for macOS, including the unsigned-app right-click-Open step
that first launch requires, lives in
[Installing on macOS](install-macos.md). It is the deepest install page
Hearth has, measured on a real 8 GB M2 Air.

A dedicated Windows install guide does not exist yet. [Hearth on
Windows](clients/windows.md) covers what the Windows app does: the process
tree it supervises, the ports it uses, and the install root layout, and is
the best reference until that guide is written.

## Updating, briefly

Hearth does not have an in-app updater yet. Getting a new build today means
downloading the new installer and reinstalling into the same folder you used
the first time. Reinstalling only fetches and replaces what changed since
your last install, and it never touches your memory or journal. See [Updating
an install](updates.md) for the full design and what is still missing.
