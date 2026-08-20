---
title: Persona Flame (the fire visualization)
status: canonical
last_reviewed: 2026-08-20
related:
  - persona-face-spec.md
  - hearth-vision-design.md
sources:
  - apple-client/Hearth/Core/Sources/HearthSpatial/FlameMesh.swift
  - apple-client/Hearth/Core/Sources/HearthSpatial/AnimatedTexture.swift
  - apple-client/Hearth/Core/Sources/HearthSpatial/AnimatedTexture.metal
  - apple-client/Hearth/Core/Sources/HearthSpatial/PersonaRig.swift
  - apple-client/Hearth/Core/Sources/HearthSpatial/EmberField.swift
  - tasks/clients/visionOS/phase-4-5.md
---

# Persona Flame

How Sulivan's fire is built, in the order you would build it.

This is a **walkthrough, not an API reference**. The visionOS client is the
reference implementation and every technique below is described in terms of
what it does and why, so it can be rebuilt on desktop and Android against
whatever those platforms offer instead of RealityKit and Metal.

The companion document is [persona-face-spec.md](persona-face-spec.md), which
covers the face itself -- the geometry, the expression library, the director.
This one covers the body the face sits on.

**Read the "why" paragraphs.** Almost every number here replaced a different
number that looked correct and failed on a headset, and the reason is more
portable than the value.

---

## The shape of the whole thing

Five pieces, each answering one question. Building them in this order works
because each one can be seen before the next exists.

| Piece | Question it answers |
| --- | --- |
| 1. The mesh | What silhouette does it have? |
| 2. The texture | What is happening inside it? |
| 3. The material | How is it drawn? |
| 4. The face plane | Where do the eyes go? |
| 5. The particles | What does it throw off, and what does that say? |

Plus a light, which is small enough to fold into step 3.

Everything shares one clock. A `phase` in seconds is passed to the mesh, the
texture, the light and the embers, rather than each keeping its own. **Four
effects on four clocks are four effects near each other; four on one clock are
one fire.** Whatever the platform, thread the same elapsed time through all of
them.

---

## 1. The mesh: a teardrop that moves

### Why geometry and not a texture

The first version was an animated opacity map on a sphere. It read as fire, it
lit a real wall, and it proved the mechanism. What it could not do was **stop
being a sphere**. A texture carves inward: it can put holes in a ball and it can
never put a tongue of flame outside one. Every frame had a hard circular edge
along the bottom, because that is where the geometry ended.

So the **silhouette is the mesh's job** and the **texture keeps the internal
structure**. They answer different questions and both are wanted.

### The topology

A ring-and-segment cylinder, 28 rings by 44 segments, about 1,300 vertices --
small enough to rebuild on the CPU every frame. Vertices carry position, normal
and UV.

Two details that are easy to get wrong:

- **The seam column is duplicated.** A closed ring costs one extra column of
  vertices, and that is the right trade: sharing the seam would force `u` to be
  both 0 and 1 at the same vertex, and the texture would mirror down one side.
- **Indices are written once.** The topology never changes -- only where the
  vertices are -- so the triangle list does not belong in the per-frame path.

### The profile, which is the whole shape

For each ring, `v` runs 0 at the base to 1 at the tip. Three functions of `v`
produce the silhouette:

**`profile(v)` -- how wide.** Two pieces, because the base and the body want
different curves:

- Below `domeTop` (0.3) it is a **hemisphere**: `radius * sin(t * π/2)`,
  swelling from the pole to full width.
- Above it, `radius * pow(1 - t², 0.45)` -- a rounded shoulder, then a taper.

> **The first version was upside down.** It was widest near the top and drew to
> a point at the bottom, which is a light bulb. A candle flame is fattest LOW,
> just above whatever it is burning on, and spends the rest of its height
> tapering.
>
> **And the second version was a cone.** `pow(1 - t, n)` is very nearly a
> straight line near the base, so the device showed full width at the bottom and
> a ruler-straight edge to the point. Squaring `t` inside is what keeps the
> flame near full width through its lower third and moves all the narrowing into
> the top half, which is where a flame's narrowing is. The exponent is the top's
> width, and LOWER is wider.

**`rise(v)` -- how high.** Not linear, and that is what makes the base a dome
rather than a cone: across the bottom section the height follows the same
quarter circle the width does, so the two together describe a hemisphere. Above
it, height runs straight. **A profile that simply goes to zero at v = 0 gives a
spike; you need the height to curve with the width.**

**`lean(v)` -- how far it tips.** Zero at the base, growing with `v²` so the
lean is all in the top third. Two sines at different rates, one per horizontal
axis, so the tip wanders rather than swinging in a plane. This is what stops the
flame reading as a symmetrical vase.

### The wobble

Per-vertex radius is multiplied by `1 + turbulence * noise(angle, v, phase)`.

Three things about that noise matter:

- **It is per-meridian as well as per-height.** A body that is round from every
  angle reads as a vase, not a fire.
- **It is trigonometric, not a noise table**, because the flame closes on itself
  in `u`. Sines of INTEGER multiples of the angle agree at 0 and 2π for free. A
  hash-based noise would need the circle trick described in step 2.
- **It is damped to nothing at the base** by a smoothstep from `domeTop` to 1. A
  flame is held steady by whatever it is burning on. The first run's wobble ran
  all the way down and chewed the dome into a knot of folds.

### The body-wide breath

`1 + 0.012 * sin(phase * 1.6)`, and the number is small on purpose. It was 0.06
and it swelled the silhouette enough to swallow the face card on every cycle --
the eyes sank into the fire and came back out, which reads as a fault rather
than as breathing. **A flame does not pulse as a whole; its edges move**, and
that is the turbulence's job.

### Two values the rest of the system asks for

- **`visibleTop`** -- `rise(0.95)`, not `rise(1.0)`. The mesh runs to a point,
  but the density kernel has faded it to nothing well before that, so the tip is
  drawn and never seen. Anything hung above the persona has to clear what people
  can SEE. If the fade window in the kernel moves, this moves with it.
- **`surfaceRadius(atY:angle:phase:)`** -- where the skin is, right now, on a
  given meridian. The face card rides it. See step 4.

### Normals

Radial, biased upward: `normalize(x, 0.35, z)`. Correct enough for something
emissive, and honest about it -- **this surface is not being shaded by the room,
it IS the light.** Do not spend effort on accurate normals here.

---

## 2. The texture: what happens inside

A square texture (512², RGBA16F) rewritten every frame by a compute shader. On
platforms without compute, a fragment shader over the same UVs computes the same
function; nothing here needs to persist between frames.

### Rows, and which way is up

Row zero is the top of the texture and the flame wears it with row zero at the
tip, so the kernel flips: `v = 1 - y/height`, and `v` means **height up the
flame** everywhere after that. Get this wrong and the fire is upside down, which
is exactly what happened first.

### The noise

Standard value noise with smoothstep weights, in a 5-octave fbm, domain-warped
by more fbm:

```
q = (fbm(p, drift), fbm(p + 3.7, drift))
n = fbm(p + 1.2 * q, drift)
```

Domain warping is what makes it billow rather than fizz.

**Seamless in u, and this is the one non-obvious step.** The flame closes on
itself, so `u = 0` and `u = 1` are the same meridian. Instead of sampling noise
along a line in x, **walk a circle**:

```
angle = u * 2π
p = float2(cos(angle), sin(angle)) * scale
p.y += v * scale
```

One sin/cos, and the seam is gone entirely. Sampling along a line leaves a
visible join straight down the persona's side.

**The drift is vertical**, not sideways: `drift = (0, -time * 0.55)`. The field
RISING is what makes it read as flame at all -- the same noise drifting sideways
is smoke.

### Density (the alpha channel)

Three terms, multiplied and maxed:

```
height  = 1 - smoothstep(0.18, 1.05, v)     // solid low, tattered high
flame   = clamp(n * height * 2.1 * brightness, 0, 1)
core    = 1 - smoothstep(0.0, 0.42, v)      // an opaque heart
density = max(flame, core * 0.95)
density *= 1 - smoothstep(0.88, 0.99, v)    // feather the tip
```

Three lessons in those five lines:

- **The fade must start low.** The first cut faded from the base and put every
  lick at the very top, so the flame read as a solid body wearing a fringe. A
  real flame is dense at its heart and tattered over most of its upper half.
- **The core is opaque regardless of the noise.** A fire has a body; noise alone
  gives it holes all the way through.
- **The tip must be feathered before the geometry ends.** The mesh draws to a
  point and a point is the one shape a flame never has -- on the device it read
  as a needle on top of an egg. The window is 0.88 to 0.99; three per cent of
  the height is a cut rather than a feather.

### Colour (the RGB channels)

A five-stop ramp -- straw, gold, amber, red, ash -- indexed by a `heat` value.

**The heat value is where the hardest bug lived.** It used to be
`fract(v - time * 0.22)` to make heat travel upward. `fract` wraps: it drops
from 1 to 0 in one texel, and that discontinuity drew a hard horizontal line
across the body that marched slowly up it. It was the one thing on the device
that looked like a fault rather than a choice.

**The fix is not a smoother wrap. It is noise:**

```
heat = clamp(v * 0.92 + 0.26 * (n - 0.42), 0, 1)
```

Heat in a flame does not rise in a level band; it rises in tongues. Perturbing
the ramp's position by the same fbm field the density uses means the colour
boundaries wander exactly where the flame's structure wanders, and there is no
seam because there is no longer a horizontal anything.

**Yellow low, red high.** The near-white heart this started with claimed too
much of the height and left the body bleached. A hearth flame is yellow where it
is fed and red where it is spending itself.

Finally the whole colour is multiplied by `0.94 + 0.12 * sin(time * 2.3)` -- a
slow flare on the same clock, so colour breathes with shape rather than beside
it.

### Colour and density in one texture

They share one RGBA texture: colour in RGB, density in ALPHA.

This was originally two textures, and the reason is worth carrying to any
platform: **a physically-based material samples an opacity texture's RED
channel**, so colour and density could not share one. An **unlit** material
takes one colour texture and uses its alpha for transparency. Choosing unlit is
what collapsed two textures into one.

---

## 3. The material and the light

### Unlit, and this is not an optimisation

The flame came back **pure white** twice.

- First from `emissiveIntensity = 3.0`, which clipped every colour in the ramp.
- Then from a white base colour lit by a 7,000-lumen point light sitting inside
  it, centimetres away. A white diffuse surface that close to a light that
  bright saturates: every channel clips.

Turning the emissive down would not have helped, because the light was doing the
damage. **Fire does not receive light. It emits.** An unlit material ignores the
room, ignores its own light, and draws exactly the texture it is given.

On any platform: the flame's fragment colour is the texture, full stop. No
lighting term, no tone mapping if you can avoid it.

### Back faces culled

Setting culling to none was a real bug. With both sides drawn, **every pixel of
the flame is two transparent surfaces from one mesh**, and transparency sorts
per object -- so the far wall of the teardrop and the near wall have no defined
order. What that looks like is dark regions where the two layers disagree, and a
body that seems to have solid parts where nothing solid exists.

A closed teardrop does not need its inside drawn. One layer, one order, half the
overdraw.

### Draw order

The flame and the face card are both transparent and both belong to one object,
so state their order explicitly rather than leaving it to be derived from two
origins. Flame first, face second.

### The light

A point light at the flame's **exact centre** -- a bulb inside a shade, not a
lamp beside it. Getting this wrong is immediately visible.

Two things make it a fire rather than a warm lamp:

- **It reaches physical surfaces.** On visionOS that is `SurroundingsLight`;
  every platform has its own answer or none, and where there is none, the flame
  is still a flame.
- **It flickers.** Intensity is multiplied by `0.75 + 0.5 * flicker()`, where
  `flicker()` is three sine waves at incommensurable rates
  (`sin(2.7t)·0.5 + sin(4.3t + 1.7)·0.3 + sin(9.1t + 0.4)·0.2`), read on the
  CPU on the same clock as the texture.

> **The flicker is deliberately NOT read back from the GPU.** Pulling a texture
> back to average it every frame would cost more than drawing it. This is a
> **correlation, not a measurement** -- the same clock, a similar wobble -- and
> it is enough, because a fire's signature from across a room is not its shape,
> it is that the light on the walls is never still.

Intensity reference points, from Apple's own table: a candle is 10-15 lumens
over a metre; a theatrical spot is 500-1,000; the default point light is 26,963,
which is a car park. The hearth sits around 3,200 -- two orders above a real
candle, because a virtual light has to compete with a lit room seen through
passthrough.

---

## 4. The face plane

The face is a texture drawn by its own kernel (see
[persona-face-spec.md](persona-face-spec.md)) shown on a small card in front of
the fire.

### Why a card and not the surface

The bead's face used to be a shell at 1.02 of the sphere's radius. A flame is
narrower than that almost everywhere and a different shape everywhere else, so
the shell either poked through the fire or sat buried in it, **and no scale
fixes both at once**.

The card is the traditional animation answer: features live on a flat sprite
that faces the viewer, not on the geometry. The face texture is already exactly
what that needs -- mostly transparent, with opaque ink only where the features
are -- so the alpha it already had is the mask.

### Curved, not flat

A flat card in front of a round body is flat in front of a round body: its
centre can touch the surface or its edges can, never both. It reads as a mask
held up rather than a face ON something, and bringing it closer only trades
hovering for sinking.

Give the card **the surface's own curvature** -- bend it around a cylinder of
radius `surfaceRadius(atEyeHeight)` -- and the choice disappears. Because the
flame is very nearly a surface of revolution, the profile it presents is the
same from every angle, so a card curved once is correct wherever the billboard
turns it.

Vertical stays straight. The flame curves that way too, but eyes bending
backwards over a dome is a different and worse problem.

### It rides the moving surface

The turbulence swings the flame's skin in and out by up to a quarter of its
radius. Any fixed distance is too far for half the cycle and too near for the
other half -- on device that looked like the fire swallowing one eye and giving
it back.

So every frame the card asks the flame where its skin is, **on the meridian the
viewer happens to be looking down**:

```
forward = pivot.convert(direction: (0,0,1), to: flameSpace)
angle   = atan2(forward.x, forward.z)
skin    = flameMesh.surfaceRadius(atY: eyeHeight, angle: angle, phase: phase)
card.z  = skin + clearance
```

The eyes then keep a constant small gap from a moving surface, which is what "on
his face" means when the face is made of fire.

### The pivot carries the turning, the card carries the curve

Two entities: a pivot at eye height that billboards to the viewer, and the card
as its child. Keeping them separate is what lets the card's curvature stay fixed
while the turning happens above it.

### Opacity threshold, not blending

A blended transparent surface is still a surface: **its empty texels take part
in sorting even though they paint nothing.** A big, mostly empty card in front of
the fire intermittently won the sort and hid the flame behind its own rectangle
-- which showed as a panel flashing over the persona.

An opacity threshold (0.35) makes the renderer **discard** below-threshold texels
rather than blend them, so the empty part of the card stops existing as far as
sorting is concerned. The cost is that the ink's edges go binary instead of soft,
which is the right trade for eyes and the wrong one for the flame.

### Proportions, and the resolution trap

Two sizing facts that cost real time:

**The card is wider than tall** (2.05 × 1.5 radii). The face texture was authored
to be worn by a sphere, drawn in longitude and latitude, and wrapping that onto a
curved hemisphere stretches it horizontally -- so the eyes are drawn narrow on
purpose and the sphere widens them back. A flat card does no such widening and
shows the unwrapped drawing exactly as stored: correct height, far too thin.
Undo it in the card's proportions, never in the kernel, so every client keeps
drawing the same face from the same numbers.

**The card shows only the middle of the texture** -- about a seventh of its area.
When sizing the texture to the viewing conditions, divide by the crop. Asking for
"enough texels to cover the card" asked for seven times too few, and the face was
being magnified out of a corner of its own image. This is the single reason the
face looked soft at large sizes.

On visionOS the viewing conditions come from `AdaptiveResolutionComponent`, which
reports the pixels per metre the renderer needs right now. Apple bins that value
for privacy -- a continuous one would leak how close someone is standing -- and
the binning is a gift, because it means the value changes rarely and rebuilding
the texture on a change is cheap. On other platforms, distance and field of view
give the same number.

---

## 5. The particles

Full detail, including all six configurations, is in
[tasks/clients/visionOS/phase-4-5.md](../../tasks/clients/visionOS/phase-4-5.md)
sections 15 to 19. The portable parts:

### One preset, one mechanism

The bead's older field is **choreographed**: 96 named entities whose positions are
stated every frame, which is the only way to draw a ring or spell out a waveform.
The fire's embers are **simulated**: an emitter births them, buoyancy and
turbulence carry them, and nothing ever knows where any particular ember is.

Both are valid. What is not valid is switching between them mid-turn, which reads
as a glitch rather than as a state change. **Pick one mechanism per look and
answer all four turn states with it.**

### Configuration on edges, motion on the transform

Emitter settings are a rulebook and cost a full write; rewriting them every frame
to carry an amplitude is waste. So:

- **Rulebook on edges** -- when the turn changes, the palette changes, or the
  budget changes.
- **Continuous values on the emitter entity's transform.** Scaling that entity
  moves the whole live system for free.

This is what makes an amplitude-driven shell and a two-second collapse ramp
affordable, and it keeps the simulation authoritative: nothing repositions an
individual particle.

### Everything is local to the persona

The persona travels, is carried, is resized and crosses between scenes. **Any
quantity resolved against the room stops meaning what it meant.**

This cost a real bug: an attraction point left at the origin without stating a
simulation space resolved against the WORLD, so the embers flew at the point
where the person was standing when the space opened. Nothing in the particle code
could have explained the behaviour, because the particle code was not deciding it.

State it: forces local, particles inherit the entity transform, birth directions
local or surface-normal, never world.

### The four states, and what each is doing

| State | Behaviour |
| --- | --- |
| Idle | A rising column. Born through the VOLUME of a cylinder spanning the flame's body, all leaving along local up, buoyancy dominating birth speed. |
| Listening | The same column, narrower and faster-rising, with a gentle vertical vortex. Turbulence comes DOWN, because a held breath should look held. |
| Thinking | A fire whirl: vortex up, lift down, damping near zero, and long streaks. |
| Speaking | A shell around the persona whose radius rides the playback amplitude, like a level meter you can walk around. Everything here is about holding still, so the only thing moving is the thing carrying the signal. |

Plus a crossing flourish: the plume collapses inward over two seconds -- the
collapse IS the progress bar -- then one burst with birth rate at zero.

### Five findings that generalise

1. **A shell births on a skin, and a skin is visible as a skin.** Birth through
   volumes, not surfaces.
2. **A sphere has a bottom.** Birthing on one put a third of the embers under the
   fire. Combined with a surface-normal direction, which averages to nothing,
   that produced a ball rather than a plume.
3. **A fast thing drawn as a point reads as a point.** Streak factor mattered
   three separate times.
4. **A state that reads as "less" is not a state.** Listening as a gather-and-hang
   stopped the plume rising, and rising is what made it look like fire.
5. **An effect can be in the wrong PLACE**, and no tuning finds it. A spark jet
   above the persona was correct and invisible, because the caption card owns
   that region.

### Additive blending solves sorting by construction

Every transparency artefact in this whole build came from two transparent
surfaces with no defined order. **Adding light to light gives the same answer
whichever comes first**, so additive particles can be unsorted and still correct.
It is also simply what fire does.

---

## What a flat client can drop -- and what it cannot

Most of the machinery above exists to survive conditions a screen does not have.
Worth separating carefully, because the saving is real and it is smaller than it
first looks.

### First, ask whether the client is flat at all

**The desktop client is not.** It renders the persona through
`@react-three/fiber` in a `<Canvas>` with a perspective camera and
**`OrbitControls`** -- zoom disabled, polar angle clamped, but free in yaw. The
viewer can walk around the persona. That is a 3D scene in a window, not a
composited picture, and it keeps almost everything a headset needs.

**Android is undecided**, and this is the decision to make deliberately rather
than by default, because it changes what gets ported:

- A **3D scene in a view** costs what desktop costs and gains a persona you can
  turn.
- A **flat composite** is much cheaper and gives up rotation permanently.

### Drops on every non-headset client

These need passthrough or a room, and neither exists in a window:

- **`SurroundingsLight`.** No physical surfaces to reach.
- **The proximity spotlight** -- surface detection, the cone that widens with
  distance, the wall/floor/ceiling cookies, the corner blending. All of it.
- **Occlusion and collision against a scene mesh.**
- **The point light itself**, very nearly. The flame is unlit, so the light
  never touched it -- its only job was the room. Keep it only if a lit model
  persona might stand near the fire.
- **`AdaptiveResolutionComponent`.** A window knows its own pixel size exactly,
  which is simpler than the headset's answer rather than a substitute for it.
- **The gestures** -- move, scale, rotate, the spine handles, the anchors that
  remember where things were left.

`EffectBudget.flat` already encodes most of this: `lightScale` 0, no
surroundings, no proximity spot.

### Drops ONLY on a truly flat client

These survive anywhere the viewer can change angle, which includes desktop
today:

- **The billboard on the face pivot.** One fixed viewpoint means the card never
  needs to turn. An orbiting camera means it does.
- **The card's curvature.** It exists so the face is correct from every angle.
  One angle needs no curve.
- **Tracking the flame's moving surface in depth.** A flat composite draws the
  face over the fire and the problem does not exist.
- **`opacityThreshold` and the sort group.** Both are fixes for transparency
  sorting between two objects. Compositing in a fixed order has no sort to lose.

### The bigger saving, if the client really is flat

**The mesh becomes optional.** It exists for one reason: a texture carves
inward, so it could never put a tongue of flame outside the sphere it was worn
by. That is a constraint of texturing 3D geometry, and a flat client is not
texturing geometry -- it is drawing pixels.

So on a flat client, `profile`, `rise`, `lean` and the wobble stop describing a
ring of vertices and start describing an **outline in screen space**: a mask, or
an SDF, evaluated in the same fragment shader that already computes the fire.
One pass, no vertex buffer, no per-frame mesh upload -- **and the silhouette is
identical, because the arithmetic is the same.**

The cost is that it stops being an object. There is no path from there to
rotating it later without redoing the shape, which is precisely why this is a
decision to take on purpose.

### The one thing that is a LOSS, not a saving

The flicker on the walls. *"A fire's signature from across a room is not its
shape -- it is that the light on the walls is never still."* A window has no
walls, so the fire loses its most legible cue and gets nothing back.

The compensation is the thing the headset deliberately gave up: **a painted
glow.** The bead wears one, and the flame switches it off, because a real light
in a real room does that job better. In a window nothing does that job, so the
2D clients should keep the halo the headset dropped -- driven by the same
`flicker()` value, which is CPU-side arithmetic on the shared clock and free on
any platform.

That inversion is the general rule for this port: **the headset spent effort on
the room and none on the composite; a screen has to spend it the other way
round.**

## Porting notes

**What is RealityKit-specific and needs a local answer:**

- `LowLevelMesh` -- any dynamic vertex buffer works. The mesh is ~1,300 vertices
  rebuilt per frame on the CPU; that is a rounding error on any platform, and the
  profile stays readable as arithmetic.
- `LowLevelTexture` + compute -- a fragment shader over the same UVs computes the
  same function, since nothing persists between frames.
- `SurroundingsLight` -- has no equivalent off visionOS, and needs none. Without
  passthrough there are no physical surfaces to light.
- `AdaptiveResolutionComponent` -- replace with distance and field of view.
- `BillboardComponent` -- note that it constrains no axes. Anything with feet
  needs a yaw-only look-at instead, or a persona shrunk to a desk toy tilts back
  to look up at you.

**What is not platform-specific and should be copied exactly:**

- The profile, rise, lean and noise functions. They are the shape.
- The colour ramp and the heat perturbation.
- The density curve, including the tip feather and where it starts.
- The decision to be unlit, and the reasons.
- One clock through all five pieces.

**What to build first, if you want to see something early:** the mesh with a flat
colour. The silhouette is most of the character, and every later step is easier
to judge against a shape you can already recognise.

## Open items

- The mesh is CPU-written. `LowLevelMesh` offers GPU buffers if the vertex count
  ever grows enough to matter; it has not.
- The chibi face variant sits behind a flag and is written up in
  [tasks/persona-chibi-face.md](../../tasks/persona-chibi-face.md).
- The thinking vortex strength has no documented unit behind it and was set by
  eye on device.
