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

- **A POINT light, not a spotlight.** The other projection map visionOS
  supports. A spotlight aims, and a fire does not aim -- it sits somewhere and
  the room falls off around it. This is what puts the glow on the walls AND the
  floor from one source instead of a cone that has to be pointed at each.
- **The texture generator draws fire.** The kernel writes an animated flame
  rather than caustic filaments, and the SAME texture is both what the bead
  looks like and what the room is lit by: the fire is the light, so its glow on
  the walls is its own texture projected.
- **The particle field goes with it.** The idle twinkles were fireflies around a
  bead; around a flame they want to be embers -- rising, brief, warmer at the
  bottom. This is `PersonaRig`'s particle choreography, not a new system, and
  it is the piece most likely to look wrong first because the current field
  orbits rather than rises.

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

**Two open questions for the device.** Whether a corporeal persona should be
scalable at all -- Selene at life size is the point of her, and a half-height
Selene is a doll -- and whether scale should persist with the anchor when a
placed object is anchored, which it almost certainly should: a bookcase you sized
to your room should be that size tomorrow.
