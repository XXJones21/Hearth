---
title: Hearth Wiki
status: draft
last_reviewed: 2026-08-04
related:
  - backend/component-catalog.md
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

## Start here

| Question | Article |
| --- | --- |
| What is the backend actually made of? | [`backend/component-catalog.md`](backend/component-catalog.md) |
| How far is it from running on someone else's machine? | [`backend/portability-ledger.md`](backend/portability-ledger.md) |
| How does it get installed, and in what form? | [`backend/packaging-options.md`](backend/packaging-options.md) |

## Status

Early. Three articles, all about the backend, because packaging is the gate
everything else waits behind.

The packaging question is answered as far as research can answer it. Containers
are out: no runtime on Apple Silicon can reach the GPU, and on Windows the
container GPU path runs through WSL2 anyway, so it adds a layer rather than
removing one. The category ships native installers. The component blocking a
native package is the voice engine, because it is the only reason torch is in
the product at all.

Planned, in order:

1. **Install guide.** What the ledger says has to happen, in the order a person
   does it. Waits on the packaging route being chosen.
2. **First-time user experience.** Meeting your first persona. Drafted in
   `D:\Tools\Valinor\tasks\first-time-user.md`.

## Conventions

Same rules as the Valinor wiki, because they work and because moving between
the two should not require a second set of habits.

- Markdown only. Relative links only. One H1 per article, matching the
  frontmatter `title`.
- Frontmatter carries `title`, `status`, `last_reviewed`, `related`, `sources`.
- Canonical articles never link to raw or unprocessed material. Where an
  article is compiled from staged sources, name them in `sources`.
- No emojis.
