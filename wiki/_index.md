---
title: Hearth Wiki
status: draft
last_reviewed: 2026-08-09
related:
  - sitemap.md
  - developing.md
sources:
  - D:/Tools/Valinor/wiki/raw/backend-audit-2026-08-04/
---

# Hearth Wiki

Hearth is a local-first AI companion that runs on your own machine. Your
personas, your voice, your memory, your hardware. Nothing is sent anywhere.

This wiki is the knowledge base for **Hearth as a product other people can
install**. It is deliberately separate from the Valinor repository, which
remains the personal testbed and superset: the Quest 3 client, the trading
agents, the game-development harness, and the messaging surfaces all continue
to live there and are not part of this.

The split is the point. Valinor answers "what is Joshua running." Hearth
answers "what does a stranger install."

The full reading order, structured for the future public GitHub wiki, is in
the [site map](sitemap.md).

## Start here

| You want to... | Article |
| --- | --- |
| Find out what Hearth is and what you need | [`getting-started.md`](getting-started.md) |
| Install it | [`installing.md`](installing.md) |
| Change it | [`developing.md`](developing.md) |

## The apps

What Hearth is on each platform, written for someone meeting it cold.

| Platform | Article |
| --- | --- |
| Windows desktop | [`clients/windows.md`](clients/windows.md) |
| macOS | [`clients/macos.md`](clients/macos.md) |
| iOS | [`clients/ios.md`](clients/ios.md) |

## The features

The ideas the product is built around, one page each.

| Feature | Article |
| --- | --- |
| Personas, the companions you design | [`features/personas.md`](features/personas.md) |
| The second brain, memory you own | [`features/second-brain.md`](features/second-brain.md) |
| Voice, designed and spoken locally | [`features/voice.md`](features/voice.md) |
| Apps and extensions, cards and tools | [`features/apps-and-extensions.md`](features/apps-and-extensions.md) |

## Under the hood

The engineering record behind the product pages.

| Question | Article |
| --- | --- |
| What is the backend actually made of? | [`backend/component-catalog.md`](backend/component-catalog.md) |
| How far is it from running on someone else's machine? | [`backend/portability-ledger.md`](backend/portability-ledger.md) |
| How does the backend run on a user's machine? | [`backend/native-runtime.md`](backend/native-runtime.md) |
| How does it get installed, and in what form? | [`backend/packaging-options.md`](backend/packaging-options.md) |
| How do we build the thing people download? | [`backend/build-pipeline.md`](backend/build-pipeline.md) |
| How does a persona get a voice? | [`backend/voice-engine.md`](backend/voice-engine.md) |
| How does someone install it on a Mac, in full? | [`install-macos.md`](install-macos.md) |
| How does an install become a newer one? | [`updates.md`](updates.md) |
| What happens the first time someone opens it? | [`first-run.md`](first-run.md) |
| How does the card library grow? | [`card-forge.md`](card-forge.md) |

The Apple migration records, the macOS status notes, and the packaging
research are staged in `raw/` as sources, no longer canonical articles.

## Status

The consumer-facing layer landed 2026-08-08 and was restructured 2026-08-09:
getting started, the install walkthrough, three platform pages under
`clients/`, four feature pages, and the contributor guide, sitting on top of
the engineering record (six backend articles plus the install, updates,
first-run, and card-forge pages). The five Apple migration documents and the
two macOS field notes moved to `raw/` as staged sources.

The packaging question is DECIDED as of 2026-08-06: the backend runs native
on both platforms, no WSL, no container. Containers were ruled out first (no
GPU on Apple Silicon, and the Windows GPU path runs through WSL2 anyway);
the WSL image fell next, on its own steelman (the VM lifecycle conflicts
with an always-on companion, and the consumer install and support costs are
documented in `backend/packaging-options.md`). The voice engine no longer
blocks native, and the compiled `omnivoice.cpp` engine is now the default on
both Windows and macOS. See `backend/native-runtime.md` and
[`features/voice.md`](features/voice.md).

The install guide exists for macOS as of 2026-08-07, written from a real
install on an 8 GB M2 Air rather than from the plan: see
[`install-macos.md`](install-macos.md). The Windows guide is the same article
for the other platform and waits on that machine's own run.

The first-run arc is live end to end on Windows as of 2026-08-08: the voice
test, the persona interview, the handover to the persona you made, and the
second brain with its three exits (a first project, an imported brain, or a
decline). The Apple client held its first real conversation on 2026-08-08: an
iPhone against a Windows house, speech recognized on the phone, the reply
streamed back as PCM, and a weather card drawn in the timeline.

Planned, in order:

1. **Install guide, Windows.** The macOS article is the shape; the numbers,
   the Gatekeeper equivalent, and the voice engine's CUDA build are what
   differ.
2. **Pairing surfaces.** The house side of device pairing is built and
   tested; the phone's code-entry screen and the desktop's pairing panel are
   not. See [`clients/ios.md`](clients/ios.md).

## Conventions

Same rules as the Valinor wiki, because they work and because moving between
the two should not require a second set of habits.

- Markdown only. Relative links only. One H1 per article, matching the
  frontmatter `title`.
- Sentence case headings.
- Frontmatter carries `title`, `status`, `last_reviewed`, `related`, `sources`.
- Canonical articles never link to raw or unprocessed material. Where an
  article is compiled from staged sources, name them in `sources`.
- No em dashes. No emojis.
