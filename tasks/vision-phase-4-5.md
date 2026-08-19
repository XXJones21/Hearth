# Phase 4.5 -- the room's light

An immersive quality-of-life pass, scoped 2026-08-18, to run after phase 4's
round trip works. Nothing here blocks a gate; it is the difference between a
persona standing in a room and a persona LIGHTING one.

## What this is about

Valinor's immersive scene projects an animated caustics pattern onto the real
room: a `SpotLightComponent` carrying a `ProjectiveTexture` fed by a
`LowLevelTexture` that a Metal kernel rewrites every frame, plus a
`SurroundingsLight` -- which is the piece that makes the cookie land on physical
surfaces rather than only on virtual ones. Aimed straight down from the orb, it
puts rippling water-light on the floor.

It is genuinely good and it is genuinely Valinor's. Sulivan is not that persona
any more: the palette moved to cream and the warm end of the brand, and pool
caustics under a warm bead reads as two ideas rather than one.

## 1. Caustics becomes a preset, not the mechanism

The mechanism is already parameterised and this is the smaller half of the work
than it looks. `CausticsTexture.init(size:kernelName:)` already takes a kernel
name, `Caustics.metal` already ships two -- `caustics_kernel` and
`smoke_kernel` -- and the class already exposes `scale`, `brightness` and
`speed`. Valinor drives the floor with one and the orb's internal swirl with the
other, at `scale: 2.0, speed: 0.3`.

So the work is naming rather than building:

- The type stops being called Caustics. It is a projected, animated light
  texture; caustics is one thing it can draw.
- The kernel name stops being a string at the call site and becomes a named
  preset carrying its own defaults -- kernel, scale, brightness, speed --
  because those four numbers ARE the effect, and a caller passing three of them
  correctly and one wrongly gets a subtly wrong effect with no error.
- The caustics numbers move into a `.caustics` preset, unchanged, so Valinor's
  device-tuned look survives as something selectable rather than as the default
  everything else has to argue with.

## 2. Sulivan becomes a small fire

The reference, given 2026-08-18: **Calcifer**. A hearth-fire the size of a
candle flame, sitting in its own light -- orange at the heart, going to ember
and cream at the edges, with the room lit by it rather than by a lamp pointed at
the room. The name Hearth has been asking for this since the first commit.

What that changes, mechanically:

- **A POINT light, not a spotlight.** A spotlight aims, and a fire does not aim
  -- it sits somewhere and the room falls off around it. This is what puts the
  glow on the walls AND the floor from one source instead of a cone that has to
  be pointed at each. `PointLightComponent.SurroundingsLight` exists and is what
  carries that falloff onto physical surfaces rather than only virtual ones.

  **CORRECTION, 2026-08-18, checked against the SDK.** The line above used to
  read "the other projection map visionOS supports", and that is wrong.
  `SpotLightComponent.ProjectiveTexture` has no point-light counterpart:
  `PointLightComponent` offers `SurroundingsLight`, `layers`, `color`,
  `intensity` and `attenuationRadius`, and no cookie of any kind. A point light
  is the right SHAPE for a fire and it cannot project a texture. Both halves of
  that are true and the plan has to hold them at once -- see section 2b, which
  is the whole reason this section is not just "swap Spot for Point".

  While the SDK was open it also handed over the calibration this section was
  going to guess at. Apple's own table: **a candle flame is 10-15 lumens with an
  attenuation radius of about 1 metre.** The point-light default is 26,963
  lumens at 10 metres -- three orders of magnitude out, a floodlight where a
  hearth was asked for. Start at the documented candle and let the device argue.

- **The texture generator draws fire.** The kernel writes an animated flame
  rather than caustic filaments, and that texture is what the BEAD wears. What
  the room receives is the light of it, which is section 2b.
- **The particle field goes with it.** The idle twinkles were fireflies around a
  bead; around a flame they want to be embers -- rising, brief, warmer at the
  bottom. This is `PersonaRig`'s particle choreography, not a new system, and
  it is the piece most likely to look wrong first because the current field
  orbits rather than rises.

## 2b. How a fire lights a room when it cannot project

This is the hole the correction opens, and it wants deciding before any code:
the fire has a texture and the light that suits it cannot carry one.

Three ways out, and they are not exclusive.

**a. The flame is the texture; the room gets untextured warm light.** The bead
wears the fire kernel, a point light sits inside it at candle intensity, and the
walls get a soft warm falloff with no pattern in it. This is what a real fire
does -- you see the flame's shape, and the room gets glow. It is the least code
and the most physically honest, and it gives up the thing that made the caustics
demo land: pattern on a real surface.

**b. The point light FLICKERS from the same kernel.** No cookie, but the light
is not static either: the kernel already computes a frame, so take its mean
brightness (or drive a cheap CPU-side flicker from the same clock the kernel
uses) and write `intensity` and `color` each frame. Fire's signature at a
distance is not its shape, it is that the room breathes. Cheap, and it is the
one that will read as Calcifer from across the room.

**c. Keep a spotlight for a floor pool, underneath the point light.** The
projected texture survives as light thrown DOWN onto the floor, the way a fire
in a grate throws a bright patch, while the point light does the walls. Two
lights, one persona, and it is the only option that keeps a cookie at all.

**The recommendation is b, then a, and c only if the floor looks dead.** b costs
almost nothing on top of a and is the difference between a warm lamp and a fire.
c doubles the light budget for a persona and re-introduces the aiming problem
this section started by getting rid of -- but the eight-light ceiling is not a
real constraint here (Apple6 GPUs lift it, and the headset is well past that),
so the cost is tuning time rather than a limit.

Whichever lands, `PersonaFaceTexture` proves the kernel half works on device and
the caustics rig does not -- that code was never validated on hardware. The
first thing to put in front of the headset is a plain point light at candle
intensity with nothing animated. If that does not read as warm, no kernel is
going to save it.

## 2c. The room's real geometry, so the light has somewhere to land

Added 2026-08-18 on the operator's ask, and it is a dependency of everything
above rather than a nicety. Valinor learned it the hard way and left the note in
the file: `SurroundingsLight` on its own adds flat illumination with no pattern,
because a projection needs a real mesh to fall on. The room has to be
reconstructed before it can be lit.

`SceneReconstructionProvider` on the existing `ARKitSession`, its mesh anchors
turned into `ModelEntity`s wearing **`OcclusionMaterial()`**, added and updated
and removed by `anchorUpdates` exactly as `RoomAnchors` already does for world
anchors. Invisible geometry: it shows passthrough, it occludes virtual content
behind it, and it does not paint a surface that would block the light.

**This is the deferred item from phase 4 coming due.** The design doc says the
world-sensing key that landed there "is for anchors, not surfaces", and that
justification comment in `Info.plist` has to be rewritten when this lands --
`NSWorldSensingUsageDescription` already covers both, so no new key, but the
stated reason stops being true the moment the mesh arrives.

**What occlusion changes that nobody asks for.** It is not additive. The moment
real geometry occludes, every placed thing can be EATEN by it:

- A bookcase anchored last week against a wall is now partly inside that wall,
  and the half inside it disappears rather than clipping visibly.
- The reader panel pulled close to a real table sinks into it.
- Selene standing where the mesh thinks a sofa is loses her legs.

None of these is a new bug; they are the same placements, now honestly drawn.
But they will read as regressions on the first device run, and the answer is
probably a nudge-out rather than turning occlusion off. Worth deciding whether
placement should push a `PlacedObject` clear of the mesh on spawn -- which the
mesh makes possible for the first time, because it is also the collision
geometry that lets panels REST on a real table, the other phase 4 deferral.

**The mesh is a cost.** Reconstruction runs continuously and the anchor stream
never stops. If the room's light and the room's mesh both land, the immersive
scene is carrying two Metal kernels, a particle field, a live mesh and a
character model at once, and this is the first phase where the frame budget is a
real question rather than a theoretical one.

## 2d. The rest of the light rig, ported

The pieces of Valinor's immersive scene worth taking as-is, with the reasons
they are the way they are:

- **`BloomComponent` with `scope = .unbounded`,** strength 0.9, threshold 0.5.
  Not hierarchical: Apple warns of a hard disc/box edge where the bounded region
  ends, which Valinor hit. Unbounded blooms the whole screen and the THRESHOLD
  is what keeps the passthrough room out of it. Phase 4 removed the untuned
  bloom from the room; this is it coming back with numbers.
- **`configure(for: .immersive)`,** which drops the billboard halo the volume
  uses to fake a glow, because real bloom is now doing the job. The rig already
  has this and `realBloomActive` already gates the billboard -- it just has to
  be turned on for a persona that has earned it.
- **State-driven light colour and intensity**, written every frame from the
  persona state with the speaking amplitude as a pulse. Hearth's palette is not
  Valinor's, so the mapping is re-authored in brand terms rather than copied.

**One improvement over the source, and it is the placement-root rule again.**
Valinor parents its light to a separate `causticsRoot` held alongside the orb,
which is why its drag handler writes two positions every frame and why they can
drift. Hearth's light belongs INSIDE the rig, on the scale-cancelled
`personaAnchor` -- then it travels, turns and anchors with her for free, and no
host has to remember it exists.

## 2e. What the anchor has to remember once things can be resized

Sections 4 and 5 hand the person a scale and a yaw, and section 4 already
half-notices the problem: **a `WorldAnchor` persists a UUID and a pose, and
nothing else.** Scale is not in it. A bookcase sized to the room comes back
tomorrow at whatever the code's default was, which is a worse outcome than not
being able to size it at all -- the person did the work and the room forgot.

`RoomAnchors` already keeps a UUID-to-slot map in `UserDefaults`; the scale (and
the yaw, if it is not recoverable from the pose) rides along in that same
sidecar. Small, and it has to be decided WITH the gestures rather than after,
because a gesture that silently does not persist is the kind of thing that only
shows up a day later.

## 2a. What the texture class actually becomes

Not "caustics with more presets". The right frame, and the precedent is already
in this codebase: `PersonaFaceTexture` is a `LowLevelTexture` that a Metal
kernel rewrites every frame, and it was built by reusing exactly the pattern
`CausticsTexture` established. Two consumers of one idea is a class, and this
is the third.

So it becomes a general **animated texture generator** -- a kernel name, a
handful of uniforms, a `LowLevelTexture`, a `tick` -- and caustics, smoke, and
fire are each just a kernel and a set of numbers. Which means the face texture
should eventually sit on top of the same base rather than beside it, and that
is the check on whether the abstraction is real: if the face cannot use it, it
is not a texture generator, it is caustics wearing a different name.

## 3. Who gets effects at all

Operator's rule, 2026-08-18: **non-corporeal personas get effects; humanoid ones
do not, for now.** A bead can throw light and bloom because it is a light. A
person standing in your room who casts caustics on your walls is a different and
stranger proposition.

This wants to live as a property of the visualization KIND rather than as a
check at each effect site -- the same discipline `PersonaVisualization` already
holds, where the renderer is chosen by type and never by name. `sphere_particle`
and `procedural_face` are luminous; `glb_animated` is a body. A future persona
declaring itself luminous gets the light with no client change, which is the
whole point of the type being data.

It also settles the phase 4 bloom question the same way: Selene has no emissive
shell to clear a bloom threshold, so she gets no bloom, and that is a decision
rather than an omission.

## 4. Scale what is in the room, with `MagnifyGesture`

Added 2026-08-18. A pinch-and-spread on any placed object resizes it: the
bookcase, the persona, and whatever else gets pulled off a shelf later. Rooms
differ, people differ, and every size in this client so far has been a number
someone judged once on one device -- `beadScale`, `modelPresentationScale`,
`presentationScale`. This hands that judgement to the person standing in the
room, which is the only place it can actually be made.

`MagnifyGesture().targetedToAnyEntity()`, with the initial scale captured on
first change and cleared on end, is the shape Apple's own interactive-model
sample uses.

**The structure that makes all three gestures safe**, settled 2026-08-18 and
already built: every placeable thing is an empty PLACEMENT ROOT with its
presentation hanging inside it. The persona has had this from the start --
`rootEntity` is where she is, `modelHost` and `personaAnchor` are how big she is
and what travels with her -- and the bookcase now matches: `libraryPlacement`
stands on the floor, `library.root` hangs inside it lifted by its own height,
and the close button hangs beside it unaffected by how big the bookcase is.

Gestures write the PLACEMENT and nothing else. Capture its transform on the
first change, apply the movement as a delta, clear on end -- which is what makes
a grab at the edge of a shelf move the bookcase rather than snapping its centre
onto your hand, and what makes the next gesture start from where the last one
left off. Anchoring, when it lands, anchors the placement: one transform, one
meaning.

**The trap it avoids.** Neither object is scaled by writing `entity.scale`. Both
already have a knob that other things are measured against:

- The persona has `setRigScale`, and `modelPresentationScale`, `personaAnchor`
  and `crownHeight` are all fractions or functions OF it. Writing
  `rootEntity.scale` behind them leaves a model at the wrong size and the cards,
  the caption and the shelves hanging at the wrong offsets -- which is exactly
  the bug `setRigScale` was introduced to prevent when the room and the box
  wanted different numbers.
- The bookcase has `presentationScale`, which is what keeps its geometry
  authored at life size while it is SHOWN at any size.

So the gesture drives the knob, never the transform. If a magnify ever needs to
reach something that has no knob, the answer is to give it one rather than to
reach past the ones that exist.

## 5. Turn what is in the room, with `RotateGesture`

Added 2026-08-18, and it is the other half of section 4. A bookcase you can move
and resize but not TURN can only ever face the direction it spawned in, which
for a thing you want flat against a wall is the one direction it is guaranteed
to be wrong.

Horizontal axis only -- yaw. A bookcase lying on its side is not a thing anyone
wants, and neither is a persona; the one degree of freedom that matters in a
room is which way something faces. `RotateGesture` targeted to the entity, with
the starting orientation captured on first change and cleared on end, matching
the shape sections 4 uses for scale.

Same trap as scale, in a different place. The persona's yaw is DRIVEN --
`update` writes `rootEntity.orientation` from `behavior.yaw` every frame, so a
gesture that writes the transform is overwritten before it is seen. Turning her
means giving the rig a resting yaw the director's own turn is measured against,
the way `homePosition` is what its travel is measured against. The bookcase has
no such driver and can take the rotation directly.

**Both of the open questions here are now answered.** They were: whether a
corporeal persona should be scalable at all, and whether scale should persist
with the anchor. The second is yes and is built -- see 2e.

The first is yes, and the operator's framing on 2026-08-18 turns it from a
concession into the point. The reference is **Cortana, the Halo one, not the
Microsoft assistant**: life size when the room is what she is standing in, and
small enough to stand on a desk or a counter when it is not. Sulivan is the same
idea from the other end -- the way this client actually gets used is scaled down
and close by, a desk toy within arm's reach.

So scale is not a tolerance for rooms that vary. **It is how a persona changes
what she IS in the space**: a figure you share a room with, or an object on your
desk. Which is worth carrying into motion, whenever that is picked back up --
travel authored for a life-size figure crossing a floor is the wrong motion
entirely for a palm-sized one standing on a counter, and `BehaviorDirector`
currently has one set of numbers for both. That is the shape of the deferred
motion work, and it is now a known question rather than a surprise waiting in
phase 4.5's device run.

## 6. Order of work, and the gate

The dependencies are real and mostly one-directional:

1. **Texture generator** (section 1, 2a) -- port `CausticsTexture` out of
   Valinor, rename it, give it presets. Nothing else can start until the
   mechanism has a home. The check on whether the abstraction is real is whether
   `PersonaFaceTexture` can sit on it.
2. **Scene reconstruction + occlusion** (2c) -- independent of the light and
   testable on its own: does the room mesh arrive, does it occlude, does
   anything placed vanish into a wall.
3. **A plain point light at candle intensity** (2b) -- the smallest thing that
   answers whether warm light in a real room reads at all.
4. **Fire kernel + flicker + bloom** (2, 2b, 2d) -- the look, once the two
   halves under it are known good.
5. **Embers** (2) -- the particle field last, because it is the piece most
   likely to look wrong and the easiest to judge only when the light is right.
6. **Magnify and rotate** (4, 5) -- orthogonal to all of the above and can land
   any time, but they need 2e decided the moment they do.

**Item 6 LANDED, 2026-08-18, before the fire.** Both gestures on the bookcase,
magnify on the reader, both on the persona, and 2e settled with them rather than
after: `PlacedObject.worldPose` normalises the basis so a `WorldAnchor` is handed
the pose it can actually keep, and the size travels in `RoomAnchors.scales`
beside the ids -- which had to exist anyway, because ARKit does not keep the slot
either. Three things the writing turned up that the scoping did not:

- **The persona's facing needed the same treatment as her position.** The
  director writes `rootEntity.orientation` from `behavior.yaw` every frame, so
  `restingYaw` is now what her own turning is measured FROM -- the exact
  counterpart of `homePosition`, and for the identical reason. Both can be true
  at once: she is facing the sofa, and she is glancing at you.
- **The reader gets scale and no rotation, and refuses rather than pretends.**
  `facesViewer(true)` hands orientation to RealityKit, so `turn` returns early
  for anything billboarding. A gesture that silently does nothing is worse than
  one that is not offered.
- **A facing chosen in the room does not follow her to the desk.** `restingYaw`
  resets in `adoptPersona`: which way she faces is a fact about a room, and the
  volume has one right way to be looked at.

**Gate 5, proposed.** In the room, with Sulivan: the fire lights a real wall and
a real floor, a real piece of furniture occludes something virtual behind it, a
placed object can be moved, resized and turned, and all three survive leaving
the room and coming back. With Selene: no light, no bloom, no embers, and
nothing about her placement behaves differently.

## 7. What the device said about the gestures, 2026-08-18

The first run corrected the scoping in three places, and one of them was a bug
the desk could not have found.

**One gesture per pair, because magnify and rotate overlap in the hand.** Both
are two-fingered and a twist is rarely clean of a spread, so offering both on
one object means neither is reliable. Operator's rule, and it assigns them by
what the object IS:

- **The bookcase moves and turns.** No resize -- furniture has a size, and a
  bookcase that is a different size in every room is a prop.
- **The persona moves and resizes**, and does not turn, because she billboards.
- **The reader moves.** It already billboards, and a page is at the size it is.

**The persona billboards, and the flag is in now rather than later.** Same
answer the reader gets: a thing on your desk should be facing you, and always
being right beats a gesture to make it right. `PersonaRig.facesViewer` is a
property, not a fixed component, on the operator's instruction and ahead of
need -- because motion will want it OFF. A persona crossing a room has to face
the way she is walking; a figure gliding sideways while staring at you is the
uncanny version of this feature. The volume clears it: you are already square to
a window, and a persona swivelling inside one as you lean looks nervous.

It costs the director's `behaviour.yaw`, which `update` now skips writing while
billboarding -- a value that was being computed and discarded. For a persona
always facing you it was never visible.

**THE BUG: `setRigScale` does not resize a corporeal persona at all.**
`layoutPersonaHosts` sets `modelHost.scale = modelPresentationScale / rigScale`,
deliberately, so a model keeps its own size while the bead follows the host. The
rig scale is therefore CANCELLED for a body, and a pinch routed through it moves
Selene not one millimetre. It read on device as the rotate gesture interfering,
which is what makes it worth writing down: a gesture that does nothing looks
exactly like a gesture that is being stolen.

So resizing goes through `rig.resize(to:)`, in METRES, and it asks whichever
knob actually governs the persona in front of it. Sizes are remembered in metres
too -- a scale factor means nothing without knowing which knob it belonged to
and what was on stage at the time, while "she was 40cm tall" survives a persona
switch, a host change and a re-fit. It is re-applied when `modelFramed` flips,
because a body that has not been fitted yet cannot be measured to be resized.

**The clamps are physical sizes now, not fractions.** A single 0.3 floor was
wrong twice: for a bead whose host had already set 0.5 it meant the smallest
reachable size was a grapefruit -- LARGER than the same bead in the volumetric
window -- and for a body it meant nothing, since her size does not come from
that scale. Metres are what the person in the room is judging, so metres are
what the clamp is written in: the bead down to a **tennis ball** (0.067m) and up
to 0.60m; the body from **a shade over a traditional doll** (0.34m) up to 2.0m.

## 8. Facing the viewer without the horror film

`BillboardComponent` lasted one paragraph. It has no axis constraint -- it turns
an entity to the viewer on every axis -- and the operator called the consequence
before the device did: **a persona shrunk to a desk toy and stood on the floor
tilts BACK to look up at you.** On a bead nobody would notice. On a body it is
the head-turning scene from a horror film.

So the rig turns itself, on the axes it is allowed to turn on.
`PersonaRig.FacingAxes` is an option set and `facingAxes` is a property, so the
lock is per-persona rather than a constant: `.upright` (yaw only) for anything
with feet, `.free` for a bead or a panel, which can lean harmlessly.

**Roll is absent rather than merely unused**, and that is the honest version. A
look-at can only recover roll from the viewer's own head tilt, which is not
something this app has or should ask for. Offering the option would be offering
a switch that does nothing.

**TWO MECHANISMS, chosen by what is on stage**, which is the same rule the
effects follow. **A bead keeps `BillboardComponent`**: Sulivan is not grounded
in anything, there is no wrong way up for a floating light, and the free version
is both cheaper and out of process. **A body gets the constrained turn.** The
rig picks, so a host sets one flag and a persona switch cannot leave a billboard
on something with feet.

**On the head-pose question, which was mine and was overcautious.** I wrote this
up as a real trade -- `BillboardComponent` turns an entity without the app ever
learning where the viewer is, and doing it ourselves means reading the device
anchor. The operator's correction, and he wrote Apple's introductory visionOS
samples: `WorldTrackingProvider.queryDeviceAnchor(atTimestamp:)` is the
DOCUMENTED route for exactly this, and it is what the "entity that follows a
person's view" sample is built on. It is gated behind world sensing, which the
room already holds for its anchors, on a provider it is already running.

What survives from the caution is only what is true: it is head pose, it is
named as such in both files, it reaches the rig's orientation and goes no
further, and it is never stored. The query returns a PREDICTED pose, so the
tracking state is checked rather than assumed -- an untracked anchor still
carries a transform, and it is the last good one rather than the current one.

**The whole transform, not just the point.** Facing someone only needs the
translation, and that is all the rig reads today. The forward vector is in the
same matrix and is what the next things want: spawning something in front of
you, and a persona who walks toward where you are looking.

**Her front is +Z**, which is the one assumption in the maths worth knowing.
Not arbitrary: at yaw zero she faces out of the volumetric window, and whoever
is looking into that window is on the +Z side. A persona facing away is this
sign and nothing else -- a model authored backwards is corrected by `rotationY`
from its own config, a different knob in a different place.

The reader panel keeps `BillboardComponent`. A page tilting to face you is what
a page should do.

## 9. The second device pass, 2026-08-18

**The snap-back was units, not maths.** Pinching Sulivan down worked and then he
jumped to a grapefruit the moment the gesture ended. `PersonaHold`'s own
`onDragEnded` -- which a two-handed pinch also fires -- was still storing
`rootEntity.scale.x` where everything else had moved to METRES. A tennis ball is
a rig scale of 0.14, and the restore read that back as fourteen centimetres.
Worth the note because the symptom pointed at the resize code, which was
correct; the only wrong thing was a leftover call site using the old unit. Two
units for one quantity always cost someone an afternoon, and the fix is that
`resize(to:)` now clamps as well, so a bad number from a STORE cannot produce a
persona too small to grab and correct.

**A two-handed pinch is also a drag.** She was being asked to move and resize at
once. `rig.isResizing` now holds the drag off, and `PlacedObject.isManipulating`
does the same for a book tap landing on furniture being turned.

**The rotate was inverted, and the reasoning was the tidy kind.** The first cut
argued that a clockwise twist should turn the object clockwise seen from above
and that +Y yaw is counter-clockwise, so it negated the angle. The headset
disagreed: `RotateGesture` already reports the angle in the sense the hand
means. The sign is gone.

**Nothing on the bookcase was grabbable.** Its only colliders belong to books,
and the drag surface sits deliberately BEHIND the spines, so reaching for the
furniture meant finding a gap and missing meant opening a journal. It has a grab
bar now, above the masthead -- above rather than across, because a collider over
the things people press is the fault that has bitten this project four times in
four places. Nothing is above the top shelf, so nothing is in the way.

**Both gestures ease now.** A magnification or a rotation read straight onto the
transform every frame is exactly as steady as two hands in mid-air, which is not
steady: the persona juddered as she grew. Both keep a TARGET and ease toward it,
and both are frame-rate independent -- `1 - pow(retention, dt * 60)` rather than
a fixed per-frame fraction, so the gesture feels the same at 90Hz and when the
room is busy. The target survives `endGesture`, so the ease finishes after your
fingers open: the last frame of a gesture reads as the end of a movement rather
than a stop.

`PlacedObject` got its own `ClosureComponent` to do it, which is the phase 4
lesson applying again -- a placement outlives the scene it was added to, so it
carries its own clock rather than borrowing a host's subscription.

## 10. Handles became spines, and one gesture was being read twice

**The handle is a vertical bar down the LEFT side**, standing 15cm off the
object, with a close button in line with it 25cm above its top. Operator's
call, 2026-08-18, and it retires two earlier attempts that were wrong the same
way: a horizontal bar under the reader, then one above the bookcase. A handle
that spans the thing's WIDTH has to be re-placed whenever the thing is a
different size, and on a bookcase it ended up either at your ankles or over your
head. A spine is the same shape whatever it is attached to, sits where a hand
goes, and is beside the object rather than in front of it -- so it still cannot
cover anything you might want to press, which is the constraint that keeps
coming back.

The close button reads its position off the handle (`handleAnchor`, `handleTop`)
rather than carrying its own guess at where the left-hand side is. Two numbers
meaning "the left of this thing" is two numbers to keep in step.

**Then: scaling the persona ROTATED THE BOOKCASE**, across the room, with
nothing near it -- and rotating the bookcase did not resize the persona. That
asymmetry is the whole diagnosis. It was not two gestures colliding; it was ONE
gesture being read by two recognisers. Her magnify and its rotate are both
two-handed, and the rotate recogniser read the twist out of the same pair of
hands quite happily.

**`targetedToEntity(_:)` names a target. It does not, on its own, require one.**
That is the lesson, and it is worth writing down because the API reads as though
it does. Both gestures now take `targetedToAnyEntity()` and check what they got:
a placement is grabbed only through its own handle, and the persona only through
something that hangs beneath her. The `onEnded` handlers check too -- an end
that never had a beginning was re-anchoring the bookcase for nothing.

## 11. The mechanism is proven, 2026-08-18

Confirmed on device, in hot pink so that success and failure could not be
confused with the room's own warm lighting -- which they were on the first run.

**A point light with `SurroundingsLight` lights a REAL wall.** That was the open
question under all of section 2b, and the answer is yes: a magenta wash across
real plaster and down onto a real desk. No cookie, no projective texture, no
spotlight.

**A shell wearing an animated texture as OPACITY reads as flame.** The
structure took three attempts and each failure was informative:

| where the flame went | what it looked like |
| --- | --- |
| the core's own material | a flame-shaped HOLE -- the room through Sulivan |
| a shell over a LIT core | pink smears on a cream ball |
| a shell over a DARK core | Calcifer in a grate |
| a shell with no core at all | Calcifer in the air -- and this is the one |

The lesson under all three: a flame drawn as opacity needs to know what it is
being seen against, and that is a decision about what the persona IS rather than
a material setting.

**The light flickers with it** off `AnimatedTexture.flicker()`, and the wall
moves. So "ripples in the light" does not need a projected texture -- which was
the thing section 2b could not answer from the desk.

**An accident worth keeping: it works in the VOLUMETRIC window too.** The bead
lights the real room from inside a shared-space volume, with no immersive space
open. That was not expected -- `BloomComponent` explicitly does nothing there,
which is why the volume carries a painted billboard halo instead of a real glow.
If `SurroundingsLight` works in the shared space, the volume could have real
light rather than a drawn one. That is a phase 3.5 decision arriving through a
phase 4.5 test, and it should be taken deliberately rather than absorbed.

**What is left is art, not API.** The flame currently reads as a flat DISC: one
shell, one colour, uniform opacity, with a hard circular silhouette at the
bottom where the sphere ends. A fire wants a colour ramp (white heart, orange
body, ember tips), a tapered silhouette rather than a filled hemisphere, and
some parallax between layers to be a volume rather than a decal. The fireflies
are still cream and orbiting, which now looks wrong beside a flame.

## 12. Shape, light, particles -- the three aspects

Operator's decomposition, 2026-08-18, and it is the right one because each part
fails differently and can be judged on its own.

### Shape: `LowLevelMesh`, landed

The sphere shell is retired. It proved the mechanism and it could not stop being
a sphere: a texture carves INWARD, so it can put holes in a ball and never a
tongue of flame outside one. Every frame of that test had a hard circular edge
along the bottom because that is where the geometry ended.

`FlameMesh` generates a teardrop pinched at BOTH ends -- narrow at the base
where it meets its source, swelling low, drawing to a wandering point -- as a
profile function rather than as an edit applied to a ball, which is what lets the
base taper as honestly as the tip. The texture stays, doing the job it was always
good at: structure WITHIN the flame rather than its outline.

Written on the CPU. Twelve hundred vertices is a rounding error, `LowLevelMesh`
offers GPU buffers if that changes, and keeping the profile as readable
arithmetic matters more while the shape is still being designed.

### Light: one phase, four consumers

`lanternPhase` is the lantern's clock and it is passed as an ARGUMENT to
everything that needs it -- the mesh's silhouette, the texture's structure, the
light's colour, its intensity. Four independent clock reads would be four
clocks, and the room would get four effects standing near each other instead of
one fire. Same discipline `FaceDirector` already has with `now`.

**The correction on the colour ramp.** A point light has ONE colour; it cannot
carry a spatial gradient, so a ramp cannot put a gradient on the wall. What it
can do is be SAMPLED from the ramp as the ramp travels, so the wall shifts
through the same colours in the same rhythm. That is not a compromise -- at any
distance a real fire washes a wall with a colour that keeps changing, and the
gradient is a near-field property of the flame itself.

### The proximity spotlight -- the operator's idea, 2026-08-18

For a genuine gradient ON the wall, a spotlight with a `ProjectiveTexture` is
the only route, and the operator's proposal solves the reason we rejected one:
**a spotlight that does not exist until there is a surface to aim at.** Within
some distance of a wall it wakes, turns to face that wall's normal, and projects;
away from surfaces there is nothing to aim and nothing aimed. The aiming problem
disappears because aiming only ever happens when there is exactly one right
answer.

Refinements worth building in from the start:

- **Fade, do not switch.** A light that appears at a threshold pops. Intensity
  should be a function of distance that reaches zero AT the threshold, so the
  wall warms as the flame approaches it.
- **A raycast may do the whole job**, and the room already casts one: the drag
  clamp added in section 9 fires against `RoomMesh.surfaces` every frame and its
  hit carries both a distance AND a normal. That is everything the idea needs,
  for any reconstructed surface -- furniture, a ceiling, a countertop -- rather
  than only where plane detection found a plane. Trigger volumes and plane
  anchors are the fallback if per-frame casting proves too costly, not the
  starting point.
- **Do not project the flame's own texture.** A fire does not cast a picture of
  itself on a wall; it casts a soft moving pool. The projection wants the SMOKE
  preset on the same phase clock -- low-frequency, blurred -- or the wall gets a
  flame-shaped decal, which reads as a sticker the moment you walk past it.
- **Corners.** One spot faces one way. Two walls meeting is the case to look at
  before calling it done; the dynamic-light ceiling is lifted on this hardware,
  so a second spot is affordable if it is needed.

### Particles: the emitter, and the rule that has to come with it

`ParticleEmitterComponent` with `.evolving(start:end:)`, a birth rate and a
falloff, idle only for now.

**The trap:** the rig already HAS a particle field -- `particleEntities`,
hand-animated per frame, with distinct choreography for listening, thinking,
speaking and the transition ramp. An emitter for idle means two particle systems
on one bead. Fine as a step, but the rule has to be stated now or it becomes
permanent: the emitter is authoritative for the bead's field and the states
migrate onto it. Otherwise the bead's particles change MECHANISM when it starts
listening, which will read as a glitch rather than as a state change.

**And a thing to check on device:** whether emitter output scales with entity
scale. Sulivan can be pinched from a tennis ball to 60cm, and a tennis-ball
flame throwing metre-long embers is the sort of fault that only appears at the
extremes.

## 13. The fire, built -- 2026-08-18

Landed across one evening of device runs. What follows is the shape of the
thing and the faults that produced it, because almost every number here is a
correction rather than a choice.

### The mechanism, proven

- **A point light with `SurroundingsLight` lights a real wall.** No cookie, no
  projective texture, no spotlight. This was the open question under all of
  section 2b.
- **A `LowLevelMesh` gives the silhouette**, an animated texture gives the
  structure within it, and the two answer different questions. A texture carves
  INWARD -- it can put holes in a ball and never a tongue of flame outside one.
- **One phase clock** drives the mesh, the texture and the light.
- It works in the VOLUMETRIC window too, which nobody expected. See section 11.

### Presets, not replacements

Operator's instruction, and it is the structural decision of this section.
`PersonaRig.EffectStyle` has two cases and defaults to `.fireflies`: the
emissive bead and its firefly field, which is what a brand-new house shows.
`.ember` is the hearth-fire, chosen rather than assumed, and the room opts in
explicitly while this is being built.

It matters beyond taste. The bead is device-tested, shipped and understood, and
it is the fallback whenever the flame's machinery is unavailable -- no Metal, no
compute pipeline, a metallib that missed the bundle. Deleting it to make room
for the new thing would have left nothing to fall back TO. The ember particles,
when they land, are a preset beside the fireflies for the same reason.

Whether the style APPLIES is still the rig's decision: ember belongs to a bead,
so a switch to Selene puts the fire out without any host knowing her name.

### Six faults, and what each one taught

- **The flame was a sphere.** Retired: a texture cannot fix a silhouette.
- **The profile was upside down.** The first mesh was widest near the top and
  drawn to a spike at the bottom -- a light bulb. A candle flame is fattest LOW.
  The rounded base needed the HEIGHT to curve with the width, not just the
  width; a profile that goes to zero at v=0 gives a cone point however it is
  shaped.
- **The flame came back pure white**, twice, for two different reasons. First an
  `emissiveIntensity` of 3.0, which pushes every colour in the ramp past its
  range so they all clip to the same place. Then a white base colour lit by a
  7000-lumen point light sitting INSIDE it. The fix for the second was the real
  one: fire does not receive light, it emits. `UnlitMaterial` -- which also
  makes the two-texture split unnecessary, because unlit takes one colour
  texture and uses its ALPHA, where a PBR material samples an opacity texture's
  RED channel.
- **A hard horizontal seam** marched up the body: `fract()` wrapping from 1 to 0
  in one texel. The fix was not a smoother wrap but NOISE -- heat rises in
  tongues, not in level bands, so the ramp's position is perturbed by the same
  fbm field the density uses.
- **Transparency is not transparency.** Operator's diagnosis. A blended
  transparent surface is still a SURFACE: its empty texels take part in sorting
  though they paint nothing. The face card intermittently won the sort and hid
  the fire behind its own rectangle. Three fixes: `opacityThreshold` on the card
  so empty texels are DISCARDED rather than blended, back-face culling restored
  on the flame (with `.none` every pixel was two transparent surfaces of one
  mesh with no defined order between them -- my error), and a `ModelSortGroup`
  so the order is stated rather than guessed.
- **The white flashing was gaze.** Not a rendering fault: visionOS drawing its
  hover highlight, correctly, to say the persona can be tapped. Restyled rather
  than suppressed -- a warm, weak spotlight style in the fire's own colour, so
  looking at him brightens him. Moving the collider to an invisible proxy would
  have silenced the artefact and the affordance together.

### The eyes

A sprite card, operator's design, from animation and games: features on a flat
card that always faces you rather than on the geometry. The face texture is
already exactly what that needs -- mostly transparent, opaque only where the
features are -- so the alpha it has always had IS the mask, with nothing to
author.

Two entities, because that is what makes "in front" mean anything: the pivot
billboards, the card hangs at a fixed offset along the pivot's own forward. Flat
rather than curved, because a card that always faces you is seen face-on by
definition.

The eyes came out narrow because the face texture is authored for a SPHERE: the
kernel draws in longitude and latitude, and wrapping onto a curved hemisphere
stretches it horizontally, so the eyes are drawn narrow on purpose and the
sphere widens them back. Corrected in the card's PROPORTIONS rather than in the
kernel, so the phone and the headset keep drawing the same face from the same
numbers.

### Numbers that are corrections

- Point light: 7000 -> 3500 -> 1500 lumens. Valinor's 7000 was a SPOTLIGHT's
  figure -- a cone, aimed away from the orb. A point light spends the same
  lumens in every direction from inside the thing you are looking at.
- The bead's tap collider: 0.46 against a sphere of 0.24. In a volume that cost
  nothing; in a room it held Sulivan half a metre off the floor, because what
  met the floor was the collider.
- The floor clamp: a body's floor is zero (her origin is her feet), a bead's is
  its own radius. Both halves were wrong before -- a bead held at a conversation
  height and a body held at her own CROWN.

### Still open

The proximity spotlight (section 12), the ember particles, and taking the flame
from an opt-in style to somebody's default.

## 14. A side quest: the chibi face

2026-08-19. The flame turned out well enough that the operator wanted to see
whether the persona's FACE could go with it -- the ink eyes are a mark ON a
surface, designed for a small glowing bead, and against a large bright body they
read as holes rather than as eyes.

It got far enough to be worth keeping: a tapered oval with white sclera, a
coloured iris, a small pupil, a lash contour and two unequal glints, all cut
from one distance field so they blink for free. A cool blue iris against a warm
fire is the strongest this persona has looked.

**Parked, not abandoned.** Sulivan is back on his shipped ink eyes; the whole
thing sits behind `PersonaFaceTexture.eyeStyle` and draws nothing until asked.
It still needs brows, a mouth in its own language, a counterpart on the phone,
and a home in the persona config rather than in client properties. Written up in
full, with every device correction it took, in
[tasks/persona-chibi-face.md](persona-chibi-face.md).

Next: the ember field's other three states -- see section 15.

## 15. Two presets, two mechanisms -- 2026-08-19

The particles landed, and the first thing they did was overturn section 12's
rule.

### The rule that did not survive

Section 12 said: *"the emitter is authoritative for the bead's field and the
states migrate onto it."* The worry behind it was right -- particles that change
MECHANISM when the persona starts listening read as a glitch rather than as a
state change -- but the conclusion was wrong, because it assumed one field.

There are two, and they cannot be built the same way. The fireflies'
listening, thinking and speaking states are all POSITIONAL: a swirl in the
viewer's plane, an upright ring, a waveform line whose height is the playback
amplitude. Every one of those states says where each particular dot goes, and a
simulator cannot be told to spell something out. Migrating them onto an emitter
would not have been a port; it would have been deleting them.

So the rule is amended rather than dropped, and the amendment is what makes it
survivable:

> **One preset, one mechanism.** Fireflies are choreographed for all four
> states. Embers are simulated for all four states. Nothing switches mechanism
> mid-turn, which is what section 12 was actually protecting.

### What that needed: a seam

`ParticleChoreography` in `Core/Sources/HearthSpatial/ParticleField.swift`. The
rig owns the clock, the turn, the palette and the audio level and hands all of
it over each frame in a `ParticleFrame`; a choreography owns its entities and
nothing else. It cannot read the rig and cannot decide when a turn begins --
which is the same division `FaceDirector` lives by, and for the same reason.

Three files, all in the package rather than in the Vision target, because the
phone is going to want to say `.fire` too:

- **`ParticleField.swift`** -- the preset enum, `ParticleWorld` (the geometry a
  field arranges itself against), `ParticleFrame`, the protocol, and the shared
  deterministic noise.
- **`FirefliesField.swift`** -- a MOVE, not a rewrite. Every number and every
  comment was judged on a headset across phases 1-4; what changed is that
  `spinAngle` became field state instead of rig state, because a field that
  borrows the rig's spin cannot be swapped out without leaving a number behind.
- **`EmberField.swift`** -- the new one.

`PersonaRig` lost 96 entities, eight arrays and five update methods, and gained
`particleWorld` (which reports the FLAME's radius and visible top when the
lantern is lit, and the bead's when it is not) and `swapParticles`.

### `.ember` became `.fire`

The preset names the whole look -- which core, which swarm -- so it is named
after the thing you see rather than after one part of it. `EffectStyle` is now a
typealias of `ParticlePreset`, which lives in the package.

### The ember field is a configuration, not a loop

This is the part worth remembering. `ParticleEmitterComponent` is a value type,
so changing anything means writing the whole component back. `EmberField` is
therefore EDGE-TRIGGERED: it writes a configuration when the turn changes and
early-returns on every other frame. There is no halfway house where the rig
nudges the emitter's output, because a simulated particle that something else is
also moving belongs to neither system and looks like neither.

Two decisions inside it are worth stating:

- **Born on the flame's SKIN, along its normal, then bent upward by buoyancy.**
  A `.sphere` emitter with `.surface` birth and `.normal` direction, sized to a
  fraction of the flame's waist, with `acceleration` doing the lift and
  `dampingFactor` bleeding off the initial speed. Embers leave a fire in every
  direction and the ones aimed down simply lose to the rising air a moment
  later, which is what damping-plus-buoyancy reproduces for free.
- **Additive blending, and it settles the sorting problem by construction.**
  Every transparency artefact this phase produced came from two transparent
  surfaces with no defined order between them. Adding light to light gives the
  same answer whichever comes first, so the embers can be `.unsorted` and still
  be correct. It is also simply what fire does.

The hot end of the colour ramp is the persona's own accent for the current
state, so the fire warms toward the speaking colour and cools toward the
thinking one without a single extra wire. The cold end is fixed: a dying ember
is the same deep red whatever was burning. Not black -- an ember that fades to
black fades through grey, and grey has no business in a fire.

### The scale question, answered by construction

Section 12 asked whether emitter output scales with entity scale, and named the
failure: a tennis-ball flame throwing metre-long embers. Rather than test and
then patch, the whole configuration is written for a REFERENCE flame
(`sphereRadius * 1.05`, Sulivan at full volumetric size) and every metric
quantity -- speed, size, acceleration, noise -- is multiplied by one
`sizeFactor`. Which makes the device question binary: if the embers are wrong at
every size the numbers are wrong; if they are right at one size and wrong at the
others, the factor is.

`particlesInheritTransform` is TRUE for the first pass. The alternative --
leaving embers behind in world space as Sulivan is carried across a room -- is
more physical and genuinely lovely, and it is the wrong trade first: a plume
that does not scale with him reads as broken in a way a plume that does not
trail does not.

### Status: idle is drawn

Listening, thinking and speaking are named in `EmberField.update` and currently
hold the idle configuration, deliberately and visibly, so the first device pass
judges one thing. What they want, and what the emitter can already express:

- **Listening** -- `attractionStrength` and `attractionCenter` pull the embers
  back in and hold them, so the fire looks like it is drawing breath.
- **Thinking** -- `vortexStrength` and `vortexDirection` spin the plume.
- **Speaking** -- `burst()` on the playback amplitude, which is the emitter's
  answer to the fireflies' waveform line: not the same shape, the same job.

### One thing fixed on the way past

`MainVolume.stage` went over the type-checker's budget the moment the package
changed underneath it, with the reported line moving around as small edits
shifted the blame -- the signature of a body that is too large rather than a
line that is wrong. Split at the natural seam, where the RealityView ends and
the modifier chain begins, plus the card attachment lifted into `StageCard`.
Not part of this work; it was simply in the way.
