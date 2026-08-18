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

## 2. A warm effect for the house Sulivan actually is

The new one. Brief, in the brand's own terms rather than in shader terms:
`cream` and `fennec` and `ember`, firelight rather than poolside -- something
that reads as a hearth throwing light on the walls of a room. Slow, low
contrast, no hard caustic filaments.

Two things to decide on the device rather than at the desk:

- **Where it is aimed.** Valinor aims straight down (-90 degrees about X) and
  gets a pool on the floor. Firelight on the WALLS is a different rig -- likely
  a wider cone or more than one -- and the operator's ask is the walls.
- **Whether it is one light or the room's ambient.** `SurroundingsLight` alone
  adds flat illumination with no pattern; the pattern needs geometry to land on,
  which is what the reconstructed mesh is for. A warm wash may want less pattern
  and more light than caustics did.

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
