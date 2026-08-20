---
area: clients/visionOS
status: open
depends_on: [motion-room-scale.md]
blocks: []
updated: 2026-08-20
---

# It comes with you

The persona keeps a set distance from you and follows as you move around a
space or between rooms.

This is the reason cards stay rooted to the persona rather than trailing you
themselves. If something should come with you, the thing that should come with
you is the persona -- and then everything it is holding comes too, without any
of it needing its own opinion about where you are.

## Why it belongs to motion, not to placement

A followed persona is not anchored. Everything else in the room is: the library
remembers its shelf, the persona remembers where it was set down, and both come
back to the same place next launch. A follower gives that up on purpose, and the
two modes have to be a CHOICE rather than a race -- a persona that is both
anchored and following will fight itself the first time you walk away.

So this is a mode on top of [motion-room-scale.md](motion-room-scale.md), using
the same travel machinery and the same clamp against the scene mesh, with the
target being you instead of a named place.

## The input already exists

`RoomAnchors.viewerTransform()` queries `WorldTrackingProvider` for the device
anchor and checks `isTracked`. It is what the persona already uses to face you.
The follower needs the same value and one more thing from it: the change in it
over time, which is what tells the difference between you turning your head and
you walking away.

That distinction is the whole feature. Following head ROTATION is what makes a
follower nauseating -- the thing orbits you every time you look around. It has
to follow translation and ignore rotation, which is the same lesson the persona
already learned about billboarding: a `look(at:)` with the wrong axes free is
what made a tiny Selene on the floor look like an exorcism.

## The shape of it

- **A dead zone.** Nothing happens until you have moved far enough that the
  persona is no longer at the distance it wants. Without one, it creeps
  continuously and never settles.
- **A lag, not a leash.** It should start after you, not with you. A companion
  that matches your velocity exactly reads as attached to your face.
- **A speed cap**, so it never outruns a walk. If you get far enough ahead, it
  should fall behind and catch up rather than teleport -- and if you go through
  a door it cannot path through, it has to give up gracefully rather than
  press against the wall.
- **A resting side.** Beside and slightly behind is where a companion walks. In
  front is where an obstacle stands.

## Open questions

- **Does it follow between rooms, or only within one?** The scene mesh is
  continuous, so "between rooms" is not a different problem to the app -- but
  passing through a doorway is a real pathing problem, and the honest first
  version may be that it stops at the door and rejoins you when you come back
  into view.
- **Does it turn itself off?** A persona that follows you into a conversation
  with another person is a persona that should have stayed put. There may need
  to be a gesture that plants it, which is arguably just "drag it somewhere",
  and that already exists.
- **What happens to the proximity spotlight** when the persona is constantly
  near new surfaces. It was tuned against a persona that stays where it is put.
