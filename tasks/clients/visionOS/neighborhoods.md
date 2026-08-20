---
area: clients/visionOS
status: design
depends_on: [multi-persona.md]
blocks: []
updated: 2026-08-20
---

# Neighborhoods

Multiple users, each with their own house and their own personas, able to work
together and communicate.

**This file is a placeholder, deliberately.** The design work is in progress
elsewhere -- alongside the Android client -- and nothing should be built from
this document. It exists so that the shape of the goal is recorded where the
visionOS backlog can see it, because two nearer items are only worth building if
they do not foreclose it.

## What this is NOT

The earlier version of this file was called `multiple-houses.md` and scoped the
wrong thing: one person with a house at home and a house at work, wanting a
switcher. That is not the goal, and it is worth keeping the distinction because
the two get confused easily.

- **One house moving between machines** -- one house, two addresses over time --
  is already solved. Settings accepts a new address. Nothing to build.
- **One person switching between two of their own houses** is a real but minor
  convenience, and building a directory to serve it would be building the wrong
  thing.
- **Neighborhoods** is many PEOPLE, not many addresses. The unit is a person and
  their personas, not a machine.

## Why it is recorded here at all

Two things in this backlog have to not get in its way:

**[multi-persona.md](multi-persona.md) is the local rehearsal.** Two personas in
one room, addressed individually, each with their own configuration, is exactly
the problem neighborhoods has -- minus the network and minus the second person.
Anything learned there about addressing, attention and whose card is whose
transfers directly. That is a reason to build it in the shape that generalises:
personas identified rather than enumerated, addressing carried on the message,
nothing in the client knowing Sulivan or Selene by name.

**[away-from-home.md](away-from-home.md) is a prerequisite in disguise.** Two
people's houses cannot talk over a network neither of them has opened. Whatever
transport answers that question answers the first half of this one.

## The one thing worth writing down now

Hearth's whole claim is that there is no cloud account and no third party
between you and your house. Neighborhoods is the feature most likely to erode
that by accident, because "two people's houses talk" is the classic reason a
product grows a server in the middle.

Whatever the design lands on, that constraint is the one to hold, and it is
better stated before the design exists than argued about after.
