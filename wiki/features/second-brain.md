---
title: The second brain
status: draft
last_reviewed: 2026-08-08
related:
  - ../first-run.md
  - personas.md
sources:
  - backend/harness/valar/gateway/first_run.py
  - backend/harness/valar/tools/handlers/second_brain.py
  - backend/harness/valar/memory/routines.py
  - backend/harness/valar/memory/daily_review.py
  - backend/harness/valar/memory/engram.py
  - backend/harness/valar/memory/service.py
  - backend/harness/valar/config/settings.py
  - wiki/first-run.md
---

# The second brain

A persona's memory is not a database and not a cloud account. It is four
plain folders of markdown files, sitting on your own disk, that you can open
in any text editor, edit, or delete at any time. Hearth calls this the
second brain, and the pitch is ownership: nothing about it requires trusting
a server you cannot see into.

## Why it exists

Without it, a persona forgets a conversation the moment it ends. Hearth's
first-run interview makes this the persona's own argument, in their own
voice, before they explain what the brain is or ask for anything: right now
they will forget this conversation once it is over, and they would rather
not.

## The four folders

Every second brain has the same four top-level folders:

- **Projects.** Things with an end. Each project is a folder with its own
  `claude.md`, opening with the project's title, an empty `## Key Decisions`
  section, and an empty `## Notes` section.
- **Areas.** Things that never end. Standing habits and ongoing concerns
  live here, including the routines record described below.
- **Thoughts.** What you talked about, organized by day.
- **Resources.** Things worth keeping.

An installer creates all four empty as part of setup. Nothing is seeded into
them from anywhere else: a fresh second brain starts with four empty
folders, never a template or an example project.

## Where it lives

Hearth finds your second brain through one environment variable,
`HEARTH_ENGRAM`, and nothing else. There is no fallback and no guessing: if
`HEARTH_ENGRAM` is not set, memory has no root, and Hearth will not invent
one rather than risk presenting someone else's brain as yours. The
variable is written into `hearth.env`, next to the `home` folder in your
install root, so it survives a restart.

Everything else you own, including this memory tree by default, lives under
your Hearth home folder (`~/.hearth` unless you have set `HEARTH_HOME`
yourself). Updating Hearth replaces the product's own code; it never touches
this folder.

## Meeting it for the first time

The second brain is the last beat of first-run setup, and the persona you
just built hosts it, not the setup guide. They walk you through it in three
short moves: why it matters to them, what the four folders actually are, and
then one question: what are you actually working on? Whatever you answer
becomes the first project.

An empty brain is intimidating. A brain with one true thing in it is a
start, so the beat is built to end with exactly one real project rather than
an empty folder waiting for you to fill it in later.

## Starting a project

Naming something you are working on creates a folder under `Projects`,
named from what you said, with `claude.md` inside opening like this:

```markdown
# <what you said>

<a line or two, if you gave one>

## Key Decisions

## Notes

_Started 2026-08-08._
```

`Key Decisions` is not decoration. It is the exact heading the memory layer
appends to later, including from the daily review below, so a project
created this way is already one the rest of the system can write into.
Naming the same project again does not overwrite it: Hearth treats that as
you changing your mind mid-sentence, not a request to clobber what is
already there.

## Already have a second brain?

If you tell your persona you already have one, they will ask for its exact
folder path and hand it to the `import_brain` tool. Hearth never guesses at
whose memory it is opening: the path has to be absolute, from the drive
letter or root down, and the folder has to already contain at least one of
Projects, Areas, Thoughts, or Resources. Point it at anything else and
nothing changes.

Once it checks out, Hearth repoints `HEARTH_ENGRAM` at that folder, both for
the running session and in `hearth.env` for every future launch, creates
whichever of the four folders are missing, and starts reading and writing
there instead. Your persona is told, plainly, only once the tool has
actually confirmed the bridge; nothing is announced as connected before
that.

## Saying no

You can also decline, or say you are done for now. That calls
`complete_brain_setup`, which closes out the beat honestly rather than
leaving you stuck in front of a setup screen with nothing left to click.
The memory stands ready, empty, for whenever something worth keeping comes
along.

## Routines: a record you can edit

A routine is a standing habit the house keeps without being asked, and it
lives as plain text at `Areas/routines.md`, inside Areas because a routine
is a thing that never ends. There is no settings screen and no hidden
state: the record is the switch. Delete a routine's section from that file
and the house stops doing it.

The first routine is written the moment your first project is created, and
it is the daily review: each day, the persona Selene reads what was talked
about, writes a short summary, and updates any project that work actually
touched. It is assigned to Selene, triggers daily, and is described in
`routines.md` exactly as it behaves, so you can read what the house is
doing to your memory in the same file that controls it.

## What actually gets written

The daily review looks at that day's diaries under `Thoughts`, asks Selene
to summarize what happened and list which projects saw work, then writes
`Reviews/daily/<date>.md` and appends one line per project under its
`Key Decisions` heading. It runs on the house's own clock, roughly every
half hour, and does nothing on a day with no diaries to review or once that
day already has a review on file.

All of this stays on your machine. The memory layer that reads and writes
your second brain is a local filesystem client with no required network
step: if it cannot find its own package, it degrades to returning nothing
rather than failing a conversation, and no read or write here reaches
outside the folder `HEARTH_ENGRAM` points at.
