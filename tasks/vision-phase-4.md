# Phase 4 -- the immersive house

Scoped 2026-08-18, after phase 3.5 closed. This supersedes the phase 4 sketch in
[the design doc](../wiki/raw/hearth-vision-design.md) section 8, which is now a
summary pointing here.

The sketch was written on 2026-08-17, before the volume had been built. Two of
its assumptions are now false, and both change the work rather than merely
adding to it.

## What changed under it

**The persona may have a body.** Phase 3.5 taught `PersonaRig` to dispatch on
`visualization.type`, so Selene renders as a `glb_animated` model where Sulivan
renders as a bead with a compute face. Everything the sketch assumed about the
orb -- that it is small, that it hovers at a comfortable height, that a halo
blooms around it -- is true of one of them and false of the other.

**The volume grew a full client interface, and all of it is ornaments.** House
status (and, since 3.5, persona switching), the composer and its mic, the
four-icon house shelf, and the right rail are every one of them ornaments on a
window. An `ImmersiveSpace` has no ornaments. Design section 1 says the volume
DISMISSES when the room opens -- which, as things stand, would leave a persona
in a room with no way to reach anything at all.

**Three things were built for this phase already, and should not be rebuilt.**
`modelPresentationScale` (1.0) and `modelVerticalOffset` (0) both default to the
room's own answer, so the immersive host is correct by saying nothing -- it must
simply not copy the volume's 0.4 and 0.16. And `personaAnchor` is how work
travels with the persona; `CardOrbitLayout.offsetFromOrb` has its caller.

## 1. The scene and the handover

Declare the `ImmersiveSpace(.mixed)` on `SceneID.immersiveHouse`, which is
already named in `HearthVisionApp`. The rig and the view model are already
hoisted to app level for exactly this, so the handover is a re-parent rather
than a rebuild.

**The hazard that will cost an afternoon if it is not read first.**
`rig.updateSubscription` holds a `content.subscribe(to: SceneEvents.Update.self)`
taken from the VOLUME's scene. A subscription is bound to the scene that issued
it. When the volume dismisses, the rig stops ticking -- no face, no travel, no
particles -- and nothing reports an error; the persona simply freezes in the
room. The immersive host must take its own subscription, and whichever host is
leaving must release the old one, or a brief overlap ticks the rig twice per
frame and everything runs at double speed.

Second, smaller: `MainVolume` holds `stageRoot`, `libraryEntity` and
`propLibrary` as `@State`. Those do NOT survive the volume dismissing, so
returning from the room rebuilds the library and re-fetches it. Acceptable, but
it means the return trip is not free and the journal's scroll position is lost.

## 2. Where the persona stands, and how big

In the volume this is settled and wrong for a room: the rig sits at
`CardOrbitLayout.orbY` (-0.22, low in the box so it can be set on a table),
scaled to 0.22, with a model at 0.4 of life size lifted 16cm to clear the
ornaments.

In a room, every one of those numbers is a different question:

- **The bead.** At the volume's 0.22 rig scale it is about 10cm across. In a
  room that is a marble on the floor. It has to grow, and how much is a
  judgement nobody has made yet.
- **The figure.** `modelPresentationScale` 1.0 makes Selene 1.34m, which is
  right -- and means she needs a FLOOR to stand on rather than a height above
  the box's centre.
- **Home.** `rig.homePosition` is currently a point in a box. In a room it wants
  to be floor-relative and in front of the person at a conversational distance,
  which is what world sensing (section 6) is for.

## 3. Controls without ornaments

The phase's largest open question, and a design decision rather than a port. As
things stand, entering the room costs the person: house status, persona
switching, typing, the mic button, Journal, Persona, Apps, Settings, Sessions,
Memory and Routines.

Three ways out, and they are not exclusive:

1. **The volume does not dismiss.** It stays open as a control panel while the
   room is furnished around it. Cheapest by far -- everything keeps working
   untouched -- and it contradicts design section 1, which is worth re-reading
   rather than merely overruling. The section's argument is the iOS collapsed/
   expanded discipline; whether that argument survives a client whose controls
   all live on the collapsed state is exactly the question.
2. **The controls become entities.** A panel that floats near the persona and
   travels with her -- `personaAnchor` already exists and already carries work
   that must stay with her. Most in keeping with "everything is an entity", and
   the most new work: four surfaces and a rail would need spatial hosts.
3. **The surfaces become their own windows.** Phase 5 already plans "Settings,
   Persona, Apps, Transcript windows", and a `.mixed` immersive space coexists
   with plain windows. This pulls phase 5 forward rather than inventing
   anything, and leaves only status/persona/mic homeless.

**Recommendation: 1 for the gate, then 3.** Keep the volume open for the first
device run so the round trip can be judged on its own terms without a control
rewrite confounding it; then move the surfaces to windows and revisit whether
the volume still earns its place. Decide before writing the toggle, because
whether the volume dismisses is the first line of it.

## 4. The toggle

Pinch-and-hold for two seconds on the persona, both directions. The rig carries
the machinery already, dormant since the port: `transitionProgress` ramps the
switch flourish and `configure(for:)` swaps presentation mode.

Watch:

- The hold must target `rig.tapTarget`, which is now a computed property that
  changes with the persona. It is only correct if the gesture is rebuilt when
  `modelActive` changes -- which is why that flag is `@Published`.
- A plain pinch still starts a voice turn. Two gestures on one target, told
  apart by duration, is the same arbitration the library's scroll-versus-open
  needed and got wrong twice.
- `realBloomActive` swaps the billboard halo for a real bloom. That is a fact
  about a BEAD; a model persona has no halo and `configure(for:)` must not
  assume one. Verify what the switch actually does under a model before
  trusting it.

## 5. Choreography at room scale

`BehaviorDirector.motion` has been `.none` since 2026-08-17 by the operator's
call, and this is the phase to turn it on: the travel was always a room-scale
idea being tried in a box.

- Re-register the director's targets in the room's own metres. `shelf`, `cards`
  and home are all currently points in a 0.8m box.
- `.subtle` multiplies every offset by 0.45 and exists for the volume; the room
  is what `.full` was written for.
- **A figure that travels is not a bead that travels.** The director moves and
  yaws `rootEntity`; a bead has no wrong way up, and a walking clip is not what
  it plays. Whether a model should travel at all in v1, or stand and turn, is
  worth deciding before tuning numbers.
- **The spring lag.** Section 6 asks for cards that follow "with a soft spring
  lag"; `personaAnchor` is rigid parenting, which was invisible in a box where
  the orb never moved. With motion on, at room scale, it will not be. This is
  the remaining half of section 6.

## 6. World sensing

`NSWorldSensingUsageDescription` into the Vision plist, and the plist rule
stands: every key justifies itself. Wanted for the floor the persona stands on
and the wall the bookcase leans against. Scope it to what is actually used --
a key carried for a feature that never landed is the kind of thing the gates
script exists to catch.

## 7. The library in a room

`JournalLibraryEntity` was built for this and mostly already does it: the
geometry is authored at life size and `presentationScale` shows it smaller. In
a room the scale is 1.0 and it is a real bookcase.

What comes OFF rather than on: `clipBelowInParent` exists because a volume has
a composer along its bottom edge, and the drag-to-scroll exists because a
bookcase taller than the box cannot be seen otherwise. A bookcase standing on a
real floor needs neither -- you walk to it.

## Gate 4

The immersive round trip: hold to enter, the room furnishes, hold to leave, the
volume returns.

Extended, because phase 3.5 changed what is being re-hosted: **the round trip
must pass with BOTH persona kinds.** A bead and a figure travel through the same
handover code and fail differently -- the bead is small and hovers, the figure
is large and stands, and only one of them has a model whose loader holds tasks
that a scene teardown does not cancel.

## What not to do

- **Do not fork `MainVolume`.** The immersive host is a different stage for the
  same world, not a copy of the volume with the box taken out. Everything in
  `MainVolume` that is not placement is either the rig's or the app's.
- **Do not let the immersive host own the rig.** It is `@StateObject` on the app
  for the exact reason that phase 4 exists; a host that owns it destroys it at
  the moment the design asks it to travel.
- **Do not copy the volume's presentation numbers.** `modelPresentationScale`
  0.4, `modelVerticalOffset` 0.16, `presentationScale` 0.765 and `clipFloorY`
  are all facts about a box with ornaments along its bottom edge. The rig's and
  the library's defaults are the room's answer.
