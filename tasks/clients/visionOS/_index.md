---
area: clients/visionOS
updated: 2026-08-20
---

# Hearth Vision -- the backlog

Everything the visionOS client still owes, one file per area, plus the record
of the phases that are finished.

## How this folder works

`tasks/` grew to the point where finding the visionOS work meant reading
filenames, so the platform moved into `clients/visionOS/` and the `vision-`
prefix went with it -- the folder says which client, and the filename is free to
say what the work IS.

**One file per area, not per change.** An area is a thing a person would ask
for in a sentence: "the persona should follow me", "I want both of them in the
room". A file lives as long as its area does; the work inside it lands in
pieces, and each piece adds to the same file rather than spawning a new one.
That is what the phase docs already do, and it is why they are readable a month
later: the corrections sit next to the decisions they corrected.

**Every file states its status in the frontmatter.** `open` means nothing has
started. `scoped` means the shape is settled and the numbers are not. `blocked`
names what it is waiting on. `closed` keeps the file, because the reasoning
outlives the work.

**A file is allowed to say "not this".** The settled decisions below are as
much a part of the backlog as the open items, and cost more when they are lost.

## Open

| Area | What it is | Status |
| --- | --- | --- |
| [motion-room-scale.md](motion-room-scale.md) | The persona walks the room it is standing in. | scoped |
| [follower.md](follower.md) | It comes with you between rooms. | open |
| [multi-persona.md](multi-persona.md) | More than one persona in the space at once. | open |
| [room-surfaces.md](room-surfaces.md) | Persona and Apps have nowhere to live in the immersive space. | open |
| [away-from-home.md](away-from-home.md) | Reaching a house from outside its network. | blocked |
| [multiple-houses.md](multiple-houses.md) | More than one house on one headset. | open |

Ordering is a dependency, not a priority: `follower` builds on
`motion-room-scale`, and `multi-persona` is worth more once both exist.

## Settled decisions

**Cards stay rooted to the persona.** Wiki drafts listed "cards do not follow
you" as a limitation, and it is not one -- it is the design. A card is something
the persona handed you, so it belongs beside the persona; a card that trails you
around the flat is a notification, and the whole point of putting a house in a
room is that it is somewhere rather than everywhere. If a card needs to come
with you, what needs to come with you is the PERSONA, which is
[follower.md](follower.md).

## Closed -- the phase record

Read in order, they are the whole build:

- [phase-3-5.md](phase-3-5.md) -- the package split, and the surfaces coming
  out of the phone.
- [phase-4.md](phase-4.md) -- the immersive round trip: hold to enter, the room
  furnishes, hold to leave.
- [phase-4-5.md](phase-4-5.md) -- the room's light. Gestures, occlusion,
  collision, the flame, the proximity spotlight, the particle presets. Its
  section 20 has the three rules the phase produced, and they generalise past
  visionOS.
- [visual-polish.md](visual-polish.md) and [waveform-mouth.md](waveform-mouth.md)
  -- smaller open lists that predate this structure and still apply.

## Elsewhere

- [tasks/persona-chibi-face.md](../../persona-chibi-face.md) is parked and is
  NOT visionOS-only: it needs a counterpart on the phone before any persona
  could wear it, which is why it did not move here.
- The user-facing article is
  [wiki/clients/visionos.md](../../../wiki/clients/visionos.md). It says what
  the app is; these files say what it owes.
- The design authority is
  [wiki/raw/hearth-vision-design.md](../../../wiki/raw/hearth-vision-design.md).
