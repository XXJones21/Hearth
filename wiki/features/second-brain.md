---
title: The second brain
status: draft
last_reviewed: 2026-08-19
related:
  - ../first-run.md
  - ../clients/windows.md
  - personas.md
sources:
  - backend/harness/valar/gateway/first_run.py
  - backend/harness/valar/gateway/settings_api.py
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

Say so during setup and your persona will ask for its exact folder path and
hand it to the `import_brain` tool. Hearth never guesses at whose memory it
is opening: the path has to be absolute, from the drive letter or root down,
and the folder has to already contain at least one of Projects, Areas,
Thoughts, or Resources. Point it at anything else and nothing changes.

Once it checks out, Hearth repoints `HEARTH_ENGRAM` at that folder, both for
the running session and in `hearth.env` for every future launch, creates
whichever of the four folders are missing, and starts reading and writing
there instead. Your persona is told, plainly, only once the tool has
actually confirmed the bridge; nothing is announced as connected before
that.

## Changing your mind later

Setup is not the only chance to answer. **Settings > On disk > Journal and
memory** shows where memory currently lives and gives you three things to do
about it: **Open folder**, **Change**, and **Remove**.

Both doors run the same code. `import_brain` and the Settings row call one
`link_brain`, because the rule they enforce is the product's only defence
against a house quietly adopting a stranger's notes, and a rule with two
copies is a rule that drifts. One difference is deliberate:

- A **conversation** naming a path always means the brain you already have,
  so a folder that is not brain-shaped is refused.
- **Settings** also accepts a folder that is completely empty, and starts a
  new brain there. Picking an empty folder in a file dialog is a reasonable
  way to say "put it here"; a sentence never is.

A folder with unrelated things in it is refused on both paths. Writing four
folders into your Documents is not a small mistake.

Changing the folder ends the conversation you are in. A session opened
against the old tree would file its diary and its continuity note there
after the move, which is how a conversation goes missing from the memory it
belongs to.

## Removing it

**Remove** unplugs the tree. It does not delete anything: `HEARTH_ENGRAM`
goes empty in the running house and in `hearth.env`, and every file stays
exactly where it is. That leaves Hearth in the state it is in before anyone
answers the question at all: the Journal reports no tree, recall returns
nothing, and the house keeps working. Point it somewhere again whenever you
like.

A button that could destroy years of notes would be a different kind of
control, and it is not this one.

## Shared brains

Because the folder is a plain path, two installs can point at the same tree:
a desktop and a laptop over a synced folder, or two houses on one machine.
That is a supported thing to set up rather than a trick.

What that means in practice:

- Continuity notes do not collide. Each house writes its own file.
- Diaries are per session and carry a timestamp in the name, so two houses
  filing at the same moment is the only collision case.
- The nightly review runs in every house that has one. Two houses reviewing
  the same day will write that day twice.

Sync conflicts are your sync tool's business. Hearth writes plain files and
does not lock them.

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
`Key Decisions` heading. A session too short to earn a diary still leaves a
chatlog, and a day of only chatlogs still gets its review; the review reads
the chatlogs raw. It runs on the house's own clock, roughly every half
hour, and does nothing on a day with nothing to review or once that day
already has a review on file.

Dev work reaches the same review through the harvester
(`harness/valar/memory/dev_harvest.py`). The routines record can carry a
**Dev sources** list under the Daily review section, lines of
`- <repo-path> -> <project-slug>`; before a day is reviewed, each listed
repo's commits from that day are filed as a diary at
`Thoughts/<day>-dev-<slug>/claude.md`, which Selene reads like any other.
No list means no harvesting, so an install without repos behaves exactly
as before. As with every routine, deleting a line is the switch.

The reviews shelf is also readable back. A recall that names a day, in any
form the operator would say it ("yesterday", "August 18", "2026-08-18"),
skips search ranking entirely and returns that day's review plus its
session list, so "what did we do yesterday" is answered from the record
rather than reconstructed. Searches over past sessions also cover
`Reviews/` as its own scope. When a day has no records, recall says so
plainly, and the persona is instructed to repeat that honestly instead of
inventing a plausible day.

All of this stays on your machine. The memory layer that reads and writes
your second brain is a local filesystem client with no required network
step: if it cannot find its own package, it degrades to returning nothing
rather than failing a conversation, and no read or write here reaches
outside the folder `HEARTH_ENGRAM` points at.

## A persona's own memory is not the second brain

Since 2026-09-02 each resident persona also keeps a memory of its own beside
its manifest: its notes, its read on you, its activity log and session index,
and an archive. That layer is the persona's, private by rule (another persona
may ask it, never read its files), and it reaches the second brain only through
the day report each persona files and the reviews Selene writes from those
reports. The second brain stays yours; the persona's memory stays the
persona's. The design lives in the Valinor repository as
`docs/superpowers/specs/2026-09-02-persona-private-memory-design.md`.
