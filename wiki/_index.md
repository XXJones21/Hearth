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

## Status

Early. The component catalog is the first article and currently the only one.
It is the inventory that the packaging decision, the installer, and the
first-time user experience all depend on, so it is deliberately first.

Planned, in order:

1. **Portability ledger.** A projection of the catalog's `assumes about this
   machine` column: for each component, what is true only on the machine it was
   built on. This is the honest answer to "how far are we from someone else
   running this."
2. **Packaging decision.** Native per-platform binaries against containers,
   argued from the ledger rather than from preference. The constraint that
   frames it is already known: the two components that need the GPU cannot be
   containerised on either target platform, so containers can only ever host the
   easy half.
3. **Install guide.** What the ledger says has to happen, in the order a person
   does it.
4. **First-time user experience.** Meeting your first persona. Drafted in
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
