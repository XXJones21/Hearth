---
title: Hearth on Windows
status: draft
last_reviewed: 2026-08-08
related:
  - ../backend/native-runtime.md
  - ../first-run.md
  - ../updates.md
  - ../install-macos.md
sources:
  - wiki/backend/native-runtime.md
  - wiki/first-run.md
  - wiki/install-macos.md
  - desktop-client/src-tauri/src/probe.rs
  - crates/hearth-probe/dictionary.yaml
  - wiki/updates.md
  - wiki/_index.md
---

# Hearth on Windows

Hearth is a local-first AI companion: your personas, your voice, and your
memory run on your own machine, and nothing is sent anywhere. On Windows,
Hearth ships as one desktop app that installs and runs the whole thing
itself.

## What the desktop app is

The Windows desktop app is a Tauri v2 and React client, and it is the whole
product on this platform. There is no separate server to stand up and no
container or Linux layer involved: the backend runs as native Windows
processes, and the client is the root of that process tree.

The client supervises everything beneath it:

- Ordered startup, so each piece comes up only after the one before it is
  healthy.
- Automatic restart with backoff if a process crashes.
- Logs for every supervised process, written to `logs\` under your install
  folder.
- A single kill path (a Windows Job Object) that takes the whole tree down
  together, so nothing is left running as an orphan process.

Closing the client window does not stop Hearth. It minimizes to the tray, and
the backend keeps running, because an always-on companion cannot depend on a
window staying open. Quit is the explicit stop.

## What the installer gives you

The client is the installer. You download one app, and the first run
provisions everything else to match your hardware.

Everything Hearth installs lands under one folder you choose, called the
install root (`D:\Hearth` by default). Inside it:

```
<root>\
  hearth-install.json     the record: your machine, the plan, what landed
  models\                 model weights, sha256-verified
  runtime\                vendored Python, llama-server, the supervisor, the backend
  envs\voice\              the voice engine's own environment, installed at first run
  config\                 generated configuration
  logs\                   one file per supervised process
```

Nothing of the product lands outside that folder, aside from the client
itself and its small WebView2 profile. Uninstalling is deleting the folder:
no distro to unregister, no virtual disk, and nothing else in the Windows
registry beyond the installer's own entry.

Once running, the supervised tree looks like this:

```
Hearth client (Tauri)
  hearth-supervisor (Rust)          18765 WS control, 18766 assets
    llama-server                    18080, CUDA (or Vulkan on non-NVIDIA GPUs)
  harness (vendored Python)         18700, the client gateway, holds Whisper
  voice worker (OmniVoice env)      18702, its own environment
```

The supervisor's job is model residency: it starts and health-checks
llama-server, and handles persona switching. Everything listens on
`127.0.0.1` only, unless you opt in to a firewall rule that lets another
device on your network reach `18700`.

The voice engine has its own environment, separate from the rest of the
backend, installed the first time you run Hearth rather than bundled with the
app. The app works without it while it installs: text works immediately, and
voice arrives once that step finishes.

## The hardware probe picks your model

Before anything downloads, Hearth scans your machine (memory, GPU, free
disk) and chooses a model plan sized to what you have. The plan names the
model, the quantization, the context window, and the download size, and it
explains its own reasoning before fetching anything.

The dictionary that drives this defines four tiers, from a small model that
fits an 8 GB GPU up to a mixture-of-experts model for the largest cards. The
tier most machines land on is a 12B model (Gemma 4 12B, quantization-aware
training build) on a 16 GB GPU, with a 65,536-token context window and both
the model and the voice resident in memory at once. On a smaller GPU, Hearth
says so plainly, for example that the model and the voice cannot both stay
loaded at the same time, so you know what to expect before you commit to the
download.

Every download is verified against a published sha256 after it lands. A
mismatch deletes the file and fails loudly rather than being mistaken for an
already-complete download on retry, and a failed or partial download resumes
rather than starting over.

## First launch

The first time you open Hearth, it walks you through three things in order:
installing (the scan, the plan, the download, and a verification pass that
proves each piece works, ending with Sulivan speaking a first line out loud
so you can confirm you heard him), a conversation where Sulivan helps you
build your own persona, and a first look at the second brain that persona
keeps for you. See [First run](../first-run.md) for the full walkthrough.

## Updates

Hearth is designed so that updating means replacing a small app bundle, not
re-downloading multi-gigabyte model weights: re-running the install
provisioning against an existing install root already skips files that are
present at the correct size and hash, and never touches your memory or
journal. The in-app update flow that surfaces this automatically is not
built yet. See [Updating an install](../updates.md) for the current state of
that design.

## Status

Hearth is pre-alpha. The Windows desktop app runs the native backend
described above, and the native-runtime decision that replaced an earlier
WSL-based plan is final as of 2026-08-06. A dedicated Windows install guide,
mirroring [Installing on macOS](../install-macos.md), does not exist yet;
this page covers what the app is and does until that guide is written.
