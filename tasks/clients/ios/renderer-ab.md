---
area: clients/ios
status: decided
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

### And the face was a head

With the clock fixed, the canvas flame drew -- behind a **solid cream squircle**.
`PersonaFaceView` is not an alpha-only face: it fills a head and a rim and then
puts features on it. Composited over a fire that is a persona standing in FRONT
of a flame, not a flame with a face.

The headset never hit this because its face is a TEXTURE that is mostly
transparent, with ink only where the features are -- the alpha it already had is
the mask. The SwiftUI face had no such property because nothing had ever asked
it to wear a body.

`PersonaFaceView` now takes `drawsHead:`, defaulting true so every existing
caller is unchanged. False paints the features and nothing else. The director,
the pose, the gaze and the blink are identical either way, which is the point:
a persona wearing a flame blinks exactly as it does wearing a head.

Also framed rather than scaled. `scaleEffect` shrinks stroke widths and blur
radii along with the drawing; a frame lets the face lay out at the size it is
actually shown, which is what its own geometry numbers are relative to.

## Third run: both drawing, and the embers were the tell

Side by side at last. Route B renders beautifully -- the fbm's striations are
visible and are the thing a drawn flame cannot have. Route A reads as the same
character: same silhouette, same ramp, same eyes.

**Cost, for the first time meaningfully:** B at 18.2ms / 55fps against A at
16.7ms / 60fps. That is the one case the readout CAN see -- a renderer heavy
enough to drag the main thread pulls the switch's own timeline down with it. So
the number is a real signal here even though it was meaningless when A was
frozen.

**The operator's read: the canvas has earned its keep.**

### The embers, and why they were wrong

They read as a scatter of crumbs around the mouth. Three faults, and only the
last was a number:

1. **They were born at the axis.** Their sideways drift came from
   `FlameProfile.noise`, which is damped to nothing below `domeTop` -- correct
   for a silhouette that must stay attached to its base, and wrong for a
   particle, which spends its early life exactly there. Every ember started on
   the centre line and stayed near it.
2. **They were drawn inside the body.** An opaque amber dot on a bright gold
   flame is mud. The headset never has this problem because its embers are
   ADDITIVE: inside the fire they are indistinguishable from it, outside they
   glow. The canvas now sets `plusLighter` for the same reason -- and it is the
   third time in this project that additive blending has turned out to be the
   correct answer rather than a stylistic one.
3. Too small and too few.

Now born ACROSS the upper body -- `r2` picks a birth meridian and the silhouette
gives the width there -- rising past the tip and widening as they go, shrinking
as they cool. Speaking keeps the shell, since what carries the amplitude is its
radius.

## Decision: the canvas -- 2026-08-20

**Route A wins, and route B is removed rather than kept behind a preference.**

Route B looked excellent. Its fbm striations are real structure that a drawn
flame cannot have, and nobody is pretending otherwise. It lost on the two things
that decide a phone:

- **Cost.** 18.2ms / 55fps against 16.7ms / 60fps, measured the one way that
  readout can actually measure -- a renderer heavy enough to drag the main
  thread pulls the switch's own timeline down with it.
- **Count.** A SwiftUI flame had to exist regardless, because widgets can host
  neither a RealityView nor a compute pass. Keeping B would have meant TWO
  persona renderers on the phone, which is the divergence this whole exercise
  set out to end. **One implementation beats a better-looking second one.**

So `PersonaFlameView` is deleted and `PersonaRenderer` loses its `.reality`
case. The rig stays exactly where it was -- shared, building for iOS, and the
headset's renderer. Nothing about that changed; it simply is not what the phone
draws.

### The eyes went flat black with it

`PersonaFaceView.inkColor()` mixes the persona's glow toward roast, which on a
cream head belongs to the same palette family as everything around it. On a
FLAME the background is bright saturated gold, and a brown two steps from cream
is one step from fire -- the eyes wash out exactly where the body is brightest,
which is where they sit. Flat black when `drawsHead` is false, which is also
what the headset's kernel draws, so the two renderers agree rather than diverge.

### What is left on the branch

The switch stays for now, two-way: **Shipped** against **Canvas fire**. Not as
a preference -- as a comparison, while the canvas flame is still being tuned
against the persona it replaces. It leaves when the fire becomes the
config-driven default, which is [sulivan-realityview.md](sulivan-realityview.md)
minus its original premise.

### Still to do before it ships

- The flame is only judged at IDLE. Thinking and speaking are where the states
  diverge most, and the speaking shell is untested on device.
- `PersonaOrb` must say in its own header that it survives for widgets only,
  or the next person reads two persona renderers and cannot tell which is
  current.
- How a persona's config selects the fire. Sulivan's says `procedural_face`,
  and the renderer is chosen from the config by design -- so the fire needs a
  name there rather than a hardcoded branch.
