---
title: What is not here
status: draft
last_reviewed: 2026-09-03
related:
  - _index.md
  - developing.md
sources: []
---

# What is not here

Find out which pages are still to be written and which material never reaches this wiki.

Two things are missing from these pages, and they are missing for different reasons. Some
articles have not been written yet, and they are named below so you know the gap is known rather
than overlooked. Other material exists but never publishes, because it is source rather than
documentation.

## Pages that are not written yet

1. **Installing on Windows.** [Installing on macOS](install-macos.md) is the shape it will take.
   What differs is the numbers and the CUDA voice build. Until it exists,
   [Hearth on Windows](clients/windows.md) covers what the app does.
2. **Pairing.** A short article on connecting a phone to a house, once the phone's code-entry
   screen and the desktop's pairing panel both exist. [Hearth on iOS](clients/ios.md) describes
   how pairing works today.

## Material that never publishes

The `raw/` directory holds staged sources and decommissioned documents: the research behind the
packaging decision, the Apple migration records, and the macOS status notes.

Those files are sources, not articles. An article compiled from one names it in the `sources`
field of its frontmatter and never links to it, because the publish step strips `raw/` before
these pages become the GitHub wiki. A link into it would be a dead end for every reader.

`scripts/lint_wiki.py` fails on any article that links to `raw/` or names a `raw/` path in its
prose. [Developing on Hearth](developing.md) covers the conventions it enforces.
