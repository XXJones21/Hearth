---
area: clients/visionOS
status: scoped
depends_on: []
blocks: [follower.md]
updated: 2026-08-20
---

# The persona walks the room

`BehaviorDirector.motion` is `.none`, and has been since phase 4. The travel is
BUILT -- cues resolve, behaviours run, the library prop stages itself, the face
responds -- and only the flying is switched off.

## Why it is off

Not because it does not work. Because it was tuned against a volumetric box,
where every offset in the behaviour library is a fraction of a stage roughly
40cm across, and the room is not that. Turned on in an immersive space with the
same numbers, the persona twitches; multiplied up to room proportions by hand,
it walks through the wall behind it.

`MotionStyle` already anticipates this. `.subtle` at 0.45 travel and `.full` at
1.0 exist precisely so the same library can mean two different distances, and
the honest reading is that `.subtle` is the VOLUME's setting and `.full` is the
room's -- rather than both being settings of the same stage.

## What it needs

**A travel budget that comes from the room, not from a constant.** Phase 4.5
established the discipline: derive from the geometry, never restate it. The
same applies here. The persona already knows where the floor is, already has a
raycast into the scene mesh, and already refuses to be pushed through a wall.
Travel should be clamped by the same mesh rather than by a number somebody
picked -- which also makes the behaviour library room-size-independent, so a
studio flat and a hall both get a persona that uses what it has.

**Targets that mean something in a room.** `setTarget(_:at:)` is already how the
shelf, the workspace and the recall positions are named, and the immersive host
already sets them. What is missing is that a room's targets should be
DISCOVERED -- the shelf is wherever the library was left, the workspace is
wherever you are sitting -- rather than placed at fixed offsets from the spawn
point.

**A rule for where it may not go.** Behind you is the obvious one. A persona
that walks out of your field of view to consult a journal has not gone to the
shelf; it has vanished. The proximity spotlight's raycast is the machinery that
can answer this, and the head pose is already available -- see
[follower.md](follower.md), which needs the same input.

## What it must not break

- **The floor.** `floorClearance` differs by persona kind -- zero for a body,
  half the presented size for a bead -- and travel has to respect it at every
  point along a path, not only at the ends.
- **The anchor.** The persona's placement is remembered in a `WorldAnchor`.
  Travel is a performance and must return home; what gets REMEMBERED is home,
  never where a behaviour left it mid-flight.
- **The gesture.** A persona that is walking must still be grabbable, and a
  grab must interrupt the walk rather than fight it.

## Open questions

- Whether `.full` in a room means the design's choreography at room scale, or
  whether room scale wants a third style with its own library.
- What a persona does when the room is too small for a behaviour. Scaling the
  offset down is the easy answer and probably the wrong one -- a fire that
  shuffles six inches to "go to the shelf" reads worse than one that does not
  move at all.
