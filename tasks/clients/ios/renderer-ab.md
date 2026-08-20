---
area: clients/ios
status: investigating
branch: investigate/ios-flame-renderer
depends_on: []
blocks: [sulivan-realityview.md]
updated: 2026-08-20
---

# Which renderer draws Sulivan on the phone

Sulivan is a fire on the headset and an orb on the phone: two characters wearing
one name. Two ways to close that, and this branch exists to look at both on a
device rather than argue about them from a desk.

- **A -- SwiftUI.** Draw the flame with vector primitives the way `PersonaOrb`
  already draws the bead. Recipe in
  [wiki/raw/persona-flame-spec.md](../../../wiki/raw/persona-flame-spec.md).
- **B -- RealityView.** Host the SAME rig the headset runs, lights off,
  particles kept.

## Why B was built first

Not because it is favoured. Because it was nearly free, and that is not luck --
every seam it needed was cut before there was anything to put through it:

- `HearthSpatial` builds for iOS deliberately, and the iOS target already links
  it.
- `PersonaRig.init(embedCamera:)` exists with the comment *"a flat iOS
  RealityView needs the scene to carry its own camera"*.
- `EffectBudget.flat` already states what a phone may do -- no surroundings
  light, no proximity spot, a thinner ember field.

So B is roughly ninety lines of wiring, and A is building the thing. Looking at
the cheap one first is not the same as preferring it.

## The reframe that matters

**This is not A versus B.** Widgets can host neither a `RealityView` nor a
compute pass, so if Sulivan is to appear in a widget at all, **A has to exist
regardless of what the app uses.**

The real question is therefore: *given that the SwiftUI flame will be built
anyway, does the live app use it too, or does it use the rig?*

That is a much better question, and it has a default answer -- use A everywhere,
one implementation, no divergence -- which B has to beat on evidence.

## What B has to beat it on

**Looks.** The fbm gives fine grain that broad strokes cannot. Whether that
reads at phone size, in a panel a few centimetres tall, is exactly the kind of
thing the desk gets wrong.

**Cost, and this is the one that could decide it.** A Metal kernel, a live mesh
rebuild and a particle simulator running behind a conversation is a very
different proposition to a `Canvas`, and the phone is where that shows up first
-- battery, thermals, and what happens to the audio path under load.

## A bug worth recording, found on the first device run

The switch appeared and did nothing, and the reason was the branch ORDER.

`HearthMainView` picks a renderer from the persona's own config -- face, then
model, then orb -- and the A/B was appended to the END of that chain. Sulivan's
shipped config is `procedural_face` **with** geometry, so `canRenderFace` is
true and the first branch always won. The override was unreachable for the exact
persona it existed to compare.

**An override has to override.** The toggle is now checked before the
config-driven chain, and `shipped` is the control case rather than one of the
candidates -- which also makes the picker honest, since "whatever the config
says" is a third thing and not the same as "the Canvas orb".

## What is on the branch

- `Core/Sources/HearthUI/Persona/FlameProfile.swift` -- the flame's shape as
  pure arithmetic, lifted from `FlameMesh`. Duplicated rather than shared
  because HearthUI must not depend on RealityKit; what is copied is a page of
  trigonometry with no platform in it.
- `Core/Sources/HearthUI/Persona/PersonaFlameCanvas.swift` -- route A.
- `Hearth/Views/PersonaFlameView.swift` -- route B.
- `Hearth/Views/RendererAB.swift` -- a three-way switch on the stage plus a
  rolling frame-time readout. The switch is `@AppStorage`-backed so a decision
  survives a relaunch, and it sits ON the stage rather than in Settings because
  an A/B you have to go and find is an A/B nobody runs twice.

The readout is a blunt instrument -- it measures how often SwiftUI redraws that
view -- and it is enough to tell a 60fps answer from a 40fps one, which is the
distinction that matters. Do not quote the number.

Builds clean for device (`iPhone (60)`, iOS 26.6) and simulator as of
2026-08-20.

## What to look at on device

1. **Side by side at conversation size.** Flip mid-turn, not while idle. The
   states are where the two diverge most.
2. **The face.** Same texture, same director, but B draws it on a curved card
   riding a moving surface and A would draw it flat on top. At phone size the
   curvature may buy nothing.
3. **Thermals over a long conversation**, not a thirty-second look.
4. **The glow.** B currently inherits the headset's decision to drop the painted
   halo, which was right when a real light did that job and is wrong here -- see
   the spec's note on this being the one genuine loss. If B looks flat next to
   the orb, that is the first thing to try rather than evidence against it.

## Second device run, 2026-08-20

**Route B renders incredibly well.** That is the headline and it is not in
doubt.

**Route A was not finished, and two of the three faults were mine rather than
the approach's.**

- *"Does not animate at all, stop and stutters."* A `Canvas` does not animate
  itself. `date: .now` is evaluated once when the body is built, so without a
  clock driving re-evaluation the flame only moved when something ELSE
  invalidated the view -- which is exactly "stationary, then a lurch".
  `PersonaCanvasView` wraps the shipped orb in a `TimelineView` for precisely
  this reason and route A was missing the wrapper.
- *"No eyes or anything."* Correct -- nothing drew a face. Fixed by compositing
  the SAME `PersonaFaceView` the shipped persona uses over the flame, which is
  the 2D shortcut the spec describes: one viewpoint and no depth to fight over
  means no curved card, no surface tracking, no sort group.
- *"The particles are stationary."* Same cause as the first: they are drawn
  from the clock that was not advancing.

**And the frame-time readout lied, which is worse than the bugs.** It has its
own `TimelineView`, so it reports the display's refresh whatever the persona
beside it is doing -- it said a confident 60fps for a flame that was completely
frozen. It measures itself. It can still catch a renderer heavy enough to stall
the main thread, and it cannot see a renderer that is cheap because it is not
drawing. **Judge motion by eye; use the number only for cost.**

None of this means B is the wrong answer. It means the comparison had not
happened yet.

## Decision, when it comes

Whichever wins, **the loser does not stay.** Two persona renderers behind a
preference is the divergence this whole exercise is trying to end -- with the
single exception of `PersonaOrb`, which survives for widgets and must say so in
its own header.

Record the outcome here and fold it into
[sulivan-realityview.md](sulivan-realityview.md).
