---
title: Installing Hearth
status: scoped
type: how-to
last_reviewed: 2026-09-04
related:
  - getting-started.md
  - meeting-your-persona.md
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

Install Hearth on a Mac or a Windows PC, from the scan that sizes your model
plan to the moment Sulivan speaks his first line out loud.

Download the installer for your platform first.
[Getting started](getting-started.md) says where builds land and what each
release carries. Setup then runs through five screens: a welcome, a scan of
your machine, the plan it decides on, the download, and a spoken line that
proves the whole thing works.

## Before you start

Hearth checks your machine before it downloads anything, and it declines
outright rather than installing something that cannot run.

The refusal comes after the scan, not before setup starts. It names how much
memory the machine has to work with, and how much of that is left once the
voice, speech recognition, and headroom are held back, measured against the
smallest model Hearth could use.

The reason is memory rather than disk space, so freeing up space does not
change it.

### macOS

You need an Apple Silicon Mac, M1 or later. There is no Intel path: Hearth
fetches an arm64 build of its inference engine and an aarch64 build of its
Python runtime, and an Intel Mac cannot finish the install.

8 GB of memory is the smallest machine Hearth supports, and it is fully
supported: an 8 GB M2 MacBook Air runs the model and the voice at once and
speaks. Below 8 GB, Hearth declines and tells you why.

You also need free disk: roughly 4.5 GB on an 8 GB Mac and 8.6 GB on a 16 GB
Mac, because the larger machine downloads a larger model. Each figure is the
download plus about a fifth again to unpack into, so it is larger than the
download size the plan shows you.

Hearth compares that figure against your free disk before it starts and warns
you when the space is not there.

macOS 27 is what the install has been verified on; earlier versions are
untested rather than known to fail. See
[Hearth on macOS](clients/macos.md) for the full requirements.

### Windows

The Windows desktop app installs and runs the whole backend as native Windows
processes: no separate server, no container, no Linux layer.

Video memory decides the answer on Windows, and there are three bands:

- Below roughly 4.5 GB, Hearth declines and tells you why.
- Between roughly 4.5 GB and 5.4 GB, Hearth installs, and your persona thinks
  and speaks one at a time.
- Above roughly 5.4 GB, the model and the voice both stay resident, and neither
  waits for the other.

Most machines land on a 16 GB GPU tier, and a smaller GPU gets a smaller plan.

You also need free disk for the download plus about a fifth again to unpack
into, so the space you need is larger than the download size. The plan names
the download size before you approve it.

See [Hearth on Windows](clients/windows.md) for what the installed app looks
like once it is running.

## Open Hearth for the first time on macOS

Hearth is not yet signed by Apple, so the first launch needs one extra step.
Double-clicking shows a warning and refuses.

1. Open the disk image and drag Hearth to Applications.
2. Right-click Hearth and choose **Open**.
3. Choose **Open** again in the dialog.

macOS remembers the decision, so every launch after this one is a normal
double-click.

![The macOS dialog offering to open an unsigned app](images/pending/installing-macos-first-open.png "CAPTURE: macOS 27, the second Open dialog raised by right-click Open on Hearth.app, the Open button visible and not yet pressed, 1280x800")

## Read the plan and start the download

Hearth puts the plan and the install folder on one screen, with the plan above
the folder, and one button approves both.

1. Open Hearth. It reads your memory, graphics, and free disk, which takes a
   second or two.
2. Read the plan. It names the model, the context window, the backend, whether
   the model and the voice both stay resident, and the download size, and it
   explains its own reasoning in plain sentences, including anything it had to
   trade away.
3. Check the install root under **Where Hearth installs**, and point it at
   anywhere with room. Pick an empty location rather than a folder that
   already holds something of yours.
4. Press **Download** to approve the plan. Nothing is fetched before you press
   it.

![The plan Hearth shows before it downloads anything](images/pending/installing-plan-screen.png "CAPTURE: setup on an 8 GB Apple Silicon Mac, the plan screen at the point of approval, showing the model, context window, backend, mind-and-voice and download rows, the Where Hearth installs field, and the Download button, unpressed, 1280x800")

### What the plan says

On an 8 GB Apple Silicon Mac, the plan reads:

| Plan row | Value |
| --- | --- |
| Model | Gemma 4 E2B, Q4_K_M |
| Context window | 17,408 tokens |
| Backend | `metal` |
| Mind and voice | both resident |
| Download | 3.77 GB |

A 16 GB machine gets a considerably larger model, Gemma 4 12B, at a
65,536-token context window, for a 7.14 GB download. Where a machine is small,
Hearth says so in your language rather than in specs.

The model dictionary behind those rows defines four tiers, from a small
on-device model up to a mixture-of-experts model for the largest cards. The
tier most machines land on is Gemma 4 12B, the quantization-aware training
build, on a 16 GB GPU, with a 65,536-token context window.

The `Mind and voice` row is where the plan says whether the model and the
voice can both stay in memory at once.

### Where Hearth installs by default

Hearth asks for one folder, the install root, and everything it downloads goes
inside it: the model weights, the voice, the inference engine, and a private
Python runtime.

On macOS the default is `Hearth` in your home directory. On Windows it is
`Hearth` on the roomiest fixed drive that is neither removable nor the drive
Windows itself runs from, and `Hearth` in your user profile on a machine with
only one drive.

Nothing Hearth installs lands outside that folder, aside from the client
application itself and its small browser-webview profile. That is what makes
uninstalling a single action.

## Let the download finish

Several things download and unpack at once: the model weights, the voice, the
inference engine, and the Python runtime it needs. The download figure in the
plan covers two of them, the model and the voice. The inference engine and the
Python runtime are fetched alongside them and are not counted in that number.

On a reasonable connection this is mostly download time. Every file that
carries a published sha256 hash is verified against it once it lands. A
mismatch deletes the file and fails loudly, rather than being mistaken for an
already-complete file on retry.

If the download is interrupted, by a lost connection or by low disk:

1. Clear whatever stopped it, such as freeing disk space.
2. Run setup again. Anything already fetched and verified is skipped rather
   than fetched again, so the download resumes instead of starting over.

## Confirm Hearth works

Starting is not the same as working, so Hearth checks each capability in turn
and names it in plain terms:

- **The model.** Loaded and answering.
- **The voice.** Ready.
- **Hearing.** Ready.
- **Skills.** Available.
- **The second brain.** Exists.

1. Wait for the five checks to finish.
2. Listen to Sulivan. The last screen of setup is the first thing he will ever
   say to you, out loud, in his own voice.
3. Answer the two buttons honestly: say whether you heard him or not.

The last check is one no automated test can perform. If you heard him, the
model that wrote the words, the voice that spoke them, and the machine
underneath both are all working. If you did not, the voice entries in Work out
what went wrong, at the end of this page, are where to start.

![The final screen of setup, after Sulivan has spoken](images/pending/installing-voice-check.png "CAPTURE: the last setup screen just after the spoken line, both answer buttons visible and neither pressed, 1280x800")

After that, Hearth opens into the house and stays there. It will not walk you
through setup again.

## Check what Hearth installed

Everything the product installs sits under the install root you chose, so
opening that folder is the fastest way to see what landed.

### macOS

The macOS install root has a layout of its own. See
[Hearth on macOS](clients/macos.md), which lists it folder by folder.

### Windows

Inside the install root:

```
<root>\
  hearth-install.json     the record: your machine, the plan, what landed
  models\                 model weights, sha256-verified
  runtime\                vendored Python, llama-server, the supervisor, the backend
  home\                   your memory and journal live here
  envs\voice\             the voice engine's own environment, installed at first run
  config\                 generated configuration
  logs\                   one file per supervised process
```

Nothing of the product lands outside that folder, aside from the client itself
and its small WebView2 profile. There is no distro to unregister, no virtual
disk, and nothing else in the Windows registry beyond the installer's own
entry.

[Hearth on Windows](clients/windows.md) covers what is running once the
install is done: the process tree Hearth supervises and the ports it uses.

## What comes next

Setup ends where the relationship starts. Sulivan interviews you and helps you
build a persona of your own, and that persona then sets up your second brain
with one real thing in it. See
[Meeting your persona](meeting-your-persona.md) for the walkthrough of both.

## Update an install

Hearth does not have an in-app updater yet, so getting a new build today is
something you do by hand.

1. Download the new installer from the releases page named in
   [Getting started](getting-started.md).
2. Reinstall into the same folder you used the first time.

Reinstalling only fetches and replaces what changed since your last install,
and it never touches your memory or journal. See
[Updating an install](updates.md) for the full design and what is still
missing.

## Uninstall Hearth

> **Important:** Deleting the install root deletes your memory and journal
> along with everything else. Copy anything you want to keep out of `home/`
> first.

1. Copy anything you want to keep out of `home/` inside the install root.
2. Quit Hearth.
3. Delete the install root you chose during setup.
4. On macOS, drag Hearth itself to the Trash.

That is the whole uninstall.

## Work out what went wrong

Everything writes to `logs/` inside the install root, and the names say what
wrote them.

- `harness.log`. Conversations.
- `llama-server.err.log`. The model.
- `voice.log` and `voice-engine.log`. The voice.
- `supervisor.log`. What started and stopped.

Four failures come up often enough to name.

- **Hearth says it is not connected.** Open **Settings > Connection**. If the
  house is stopped, press **Start**. If something failed, its name and reason
  appear there.
- **He answers but does not speak.** Check that **Settings > Voice** has
  output enabled. Failing that, `voice-engine.log` shows whether the voice
  produced audio at all.
- **The install ran out of disk partway.** Free space and run setup again.
  Downloads resume rather than starting over.
- **Setup will not finish.** Delete the install folder and run setup again
  from the beginning. Nothing outside that folder needs cleaning up.
