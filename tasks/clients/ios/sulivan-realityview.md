---
area: clients/ios
status: open
depends_on: []
blocks: []
updated: 2026-08-20
---

# Sulivan becomes the fire on the phone

The headset draws Sulivan as a real flame: geometry, a computed texture, a face
on a curved card, and an ember field that changes with the turn. The phone still
draws the orb -- `PersonaOrb`, a SwiftUI `Canvas`, a painterly glow with a
particle field and a speaking waveform.

They are now two different characters wearing one name, and the phone's is the
older one.

## Why the phone chose Canvas, and which reasons survive

`PersonaCanvasView` states them, and they were good at the time:

1. **It matches the painterly glow.** "RealityKit has no bloom/additive blend."
2. **The speaking waveform is trivial in a Canvas.**
3. **It is reusable in WidgetKit widgets**, which render static SwiftUI and
   cannot host a live `RealityView`.

Phase 4.5 answered the first two:

- **Additive blending is what the ember field runs on.** It was chosen there for
  correctness rather than looks -- adding light to light is order-independent, so
  the embers sort correctly without sorting at all -- but it is the same tool the
  glow wanted. And the flame's material is `UnlitMaterial`, which draws exactly
  the texture it is given and ignores every light in the scene, which is closer
  to painterly than PBR ever was.
- **The waveform is gone on the headset**, replaced by a shell that pulses with
  the playback amplitude. That was not a port; it was a better idea that arrived
  because the medium was three-dimensional.

**The third reason is untouched and permanent.** Widgets cannot host a
`RealityView`. So this is NOT a deletion of the Canvas path -- `PersonaOrb` has
to survive as the widget renderer regardless, and probably as the fallback for
any device or state where the compute path cannot start.

## The groundwork is already laid

`HearthSpatial` builds for iOS deliberately. The package comment says why: *"that
build gate is what keeps the later iOS adoption of the RealityKit orb a target
change rather than a rewrite."* This task is that adoption.

Concretely, already true:

- **`PersonaRig` compiles for iOS today.** It takes `embedCamera:` precisely
  because iOS needs a `PerspectiveCamera` and visionOS crashes if you touch one.
- **`EffectBudget.flat` already exists** -- `lightScale` 0, no surroundings
  light, no proximity spotlight, `particleDensity` 0.55. The phone's answer to
  every effect is already written down; nothing has to be invented.
- **`PresentationMode.flat`** is the mode to configure for, and `PersonaRig`
  already routes every effect through it.
- **The face is the same face.** `PersonaFaceTexture` and `FaceDirector` are
  shared, and the phone's `PersonaFaceView` is the fallback the headset uses
  when the compute path fails -- so both drawings of the face already exist on
  both platforms.

## What actually has to be built

- **A `RealityView` host on iOS**, replacing `PersonaCanvasView` where it is
  used live -- `HearthMainView` and `FirstRunView` -- while leaving `PersonaOrb`
  in place for widgets.
- **A tap gesture** instead of the headset's pinch. The rig exposes `tapTarget`;
  `enableInteraction()` is `#if os(visionOS)` because hover and input-target
  components do not exist on the phone, so the phone wires an ordinary
  `TapGesture` to the same target.
- **A decision about the flame at phone scale.** The headset's flame is judged
  in a room at 25cm across. On a phone it is a few centimetres of a 2D panel,
  seen flat and small, and the numbers that make a plume read at arm's length
  may make a smear at that size. `particleDensity` is the knob that exists; it
  may not be the only one needed.
- **A fallback that is chosen, not stumbled into.** `hasComputeFace` already
  tells the rig whether the Metal path started. The phone needs the same
  branch: no compute, no flame, fall back to the Canvas orb -- which is exactly
  what a widget will always do anyway.

## What must not happen

**The Canvas orb must not become dead code that still ships.** If it survives
only for widgets, that has to be stated in its own header, or the next person
reads two persona renderers and cannot tell which one is current. The headset
already made this mistake once with the chibi eyes and fixed it by leaving a
comment pointing at the task file.

**The phone must not grow its own persona look.** The point of doing this is
that Sulivan is ONE character. If the phone's fire diverges from the headset's
because it was tuned separately, this task has made things worse rather than
better -- two characters wearing one name is the problem being solved, not a
thing to reproduce at a smaller size.

## Open questions

- Whether Selene follows. She is a `.glb` model persona and the phone has never
  rendered one; a `RealityView` on iOS is what would make it possible, and this
  task is the natural place for it to become cheap.
- Whether the phone's persona should be interactive beyond a tap -- the headset
  can be moved, resized and turned, and a phone can do none of that meaningfully.
- Battery and thermals. A Metal kernel and a particle simulator running behind
  a live conversation is a very different cost to a `Canvas`, and the phone is
  the platform where that shows up first.
