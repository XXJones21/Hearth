---
title: Site map
status: draft
last_reviewed: 2026-08-09
related:
  - _index.md
  - getting-started.md
  - developing.md
sources: []
---

# Site map

The wiki in reading order, written for the day this repository goes public
and these pages become the GitHub wiki. Three doors in: get started, install,
or develop. Everything else hangs off one of those.

## Getting started

The doorway. What Hearth is, what your machine needs, and the three steps to
a running house.

- [Getting started](getting-started.md)

## Installing

The guided walkthrough of the install: the scan, the plan, the download, and
Sulivan's first spoken line. Platform detail sits underneath it.

- [Installing Hearth](installing.md), the walkthrough for both platforms
- [Installing on macOS](install-macos.md), the full macOS step-by-step with
  troubleshooting
- Installing on Windows: planned; [Hearth on Windows](clients/windows.md)
  covers what the app does until the guide is written
- [Updating an install](updates.md)

## The apps

One page per platform, for someone meeting Hearth cold.

- [Hearth on Windows](clients/windows.md)
- [Hearth on macOS](clients/macos.md)
- [Hearth on iOS](clients/ios.md)

## Using Hearth

The ideas the product is built around, and the first hour with it.

- [First run](first-run.md), the voice test, the persona interview, the
  handover, and the second brain
- [Personas](features/personas.md)
- [The persona face](features/persona-face.md)
- [The second brain](features/second-brain.md)
- [Voice](features/voice.md)
- [Apps and extensions](features/apps-and-extensions.md)

## Developing

For people who want to change Hearth rather than just run it.

- [Developing on Hearth](developing.md), the repository map and the two
  build loops
- [The card forge](card-forge.md), how the card library grows

## Under the hood

The engineering record. These stay in the repo wiki; whether they join the
public GitHub wiki or remain repo-only is decided when the repo opens.

- [Component catalog](backend/component-catalog.md)
- [Native runtime](backend/native-runtime.md)
- [Build pipeline](backend/build-pipeline.md)
- [Packaging options](backend/packaging-options.md)
- [Portability ledger](backend/portability-ledger.md)
- [Voice engine](backend/voice-engine.md)

## Not part of the public wiki

`raw/` holds staged sources and decommissioned documents: the research
that fed the packaging decision, the Apple migration records, and the
macOS status notes. Canonical articles name them in `sources` frontmatter
but never link to them, and they do not ship to the GitHub wiki.

## Planned pages

1. **Installing on Windows.** The macOS article is the shape; the numbers
   and the CUDA voice build are what differ.
2. **Pairing.** A short page on connecting a phone to a house, once the
   phone's code-entry screen and the desktop's pairing panel both exist.
