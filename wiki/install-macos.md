---
title: Installing on macOS
status: draft
last_reviewed: 2026-08-07
related:
  - first-run.md
  - backend/native-runtime.md
  - _index.md
sources:
  - wiki/raw/macos-status.md
  - wiki/raw/m1-air-runbook.md
---

# Installing on macOS

Everything here was measured on the machine it describes: an 8 GB M2 MacBook
Air running macOS 27. Where a number appears, it came off that machine rather
than an estimate.

## What you need

**An Apple Silicon Mac.** M1 or later. Hearth fetches an arm64 build of its
inference engine and an aarch64 build of its Python runtime; there is no Intel
path, and an Intel Mac will not be able to finish the install.

**8 GB of memory or more.** 8 GB is the smallest machine Hearth supports and
it is fully supported: a 8 GB Air runs the mind and the voice at the same
time, and speaks. Below that Hearth declines rather than installing something
that cannot run, and says why:

> this machine cannot run Hearth. It has 4.00 GB to work with, which leaves
> 2.25 GB after the voice, speech recognition and headroom, and the smallest
> model is 2.36 GB.

**Free disk.** Roughly 4.5 GB on an 8 GB Mac and 8.6 GB on a 16 GB Mac. The
larger machine gets a larger model, so it downloads more. Hearth checks before
it starts and warns you if the space is not there.

macOS 27 is what this has been verified on. Earlier versions are untested
rather than known-bad.

## Opening it the first time

Hearth is not yet signed by Apple, so the first launch needs one extra step.
Double-clicking will show a warning and refuse.

1. Open the disk image and drag Hearth to Applications.
2. **Right-click** Hearth and choose **Open**.
3. Choose **Open** again in the dialog.

macOS remembers the decision. Every launch after this one is a normal
double-click.

## The install itself

The client is the installer. There is no separate download for the backend,
and nothing to configure before you begin.

**Welcome, then a scan.** Hearth reads your machine: memory, graphics, free
disk. It takes a second or two.

**Choose where it lives.** The default is a folder named `Hearth` in your home
directory. Everything Hearth downloads goes inside that one folder, which is
what makes uninstalling it a matter of deleting the folder. You can put it
anywhere with room. Pick an empty location rather than a folder that already
holds something of yours.

**Read the plan.** Hearth shows exactly what it has decided and why, before it
downloads anything. On an 8 GB Air the plan reads:

| | |
| --- | --- |
| Model | Gemma 4 E2B, Q4_K_M |
| Context window | 17,408 tokens |
| Backend | Metal |
| Mind and voice | both resident |
| Download | 3.77 GB |

A 16 GB Mac gets a considerably larger model (Gemma 4 12B) and a 65,536-token
context window for 7.14 GB. The plan explains its own reasoning in plain
sentences, including anything it had to trade away.

**It downloads and provisions.** Several things happen at once: the model
weights, the voice, the inference engine, and a private Python runtime. On a
reasonable connection this is mostly download time.

**You meet Sulivan.** The last screen of setup is the point: he says the first
thing he will ever say to you, out loud, in his own voice. This is the check
no automated test can perform, so the buttons are honest ones. If you heard
him, say so. If you did not, say that instead.

After that, Hearth opens into the house and stays there. It will not walk you
through setup again.

## What ends up on your machine

One folder, wherever you chose:

```
Hearth/
  models/          the model weights, and the voice under models/voice
  runtime/         the inference engine, the Python runtime, the backend
  home/            your memory and journal live here
  config/          one generated settings file
  logs/            what everything wrote down
  hearth-install.json    the record of what was decided and installed
```

Nothing is installed outside it. No system directories, no login items, no
background service that runs when Hearth is closed.

While Hearth is open it runs five local programs: the gateway your client
talks to, a supervisor, the language model, the voice engine, and the voice
service in front of it. They listen only on `127.0.0.1` and only while Hearth
is running. Nothing is sent anywhere.

## Starting and stopping the backend

Hearth starts its backend when it opens and stops it when it quits, so this is
usually not something you need to think about.

If you do, **Settings > Connection** shows whether it is running, names
anything that failed, and offers **Start** and **Stop**. Stopping frees the
memory the model and voice are holding without closing Hearth; starting brings
them back without relaunching.

## Uninstalling

Quit Hearth, drag it to the Trash, and delete the folder you chose during
setup. That is the whole uninstall. Deleting the folder also deletes your
memory and journal, so copy anything out of `home/` first if you want to keep
it.

## When something goes wrong

Everything writes to `logs/` inside your Hearth folder, and the names say what
wrote them: `harness.log` for conversations, `llama-server.err.log` for the
model, `voice.log` and `voice-engine.log` for the voice, `supervisor.log` for
what started and stopped.

**Hearth says it is not connected.** Open Settings > Connection. If the house
is stopped, press Start. If something failed, its name and reason appear
there.

**He answers but does not speak.** Check that Settings > Voice has output
enabled. Failing that, `voice-engine.log` will show whether the voice produced
audio at all.

**The install ran out of disk partway.** Free space and run setup again.
Downloads resume rather than starting over: anything already fetched and
verified is skipped.

**Setup will not finish.** The install folder can be deleted and setup run
again from the beginning. Nothing outside that folder needs cleaning up.

## What this does not cover yet

Once the install is done, Sulivan interviews you and you build a persona of
your own together. That flow is being finished on Windows as of 2026-08-07 and
will be documented when it lands, in [`first-run.md`](first-run.md).
