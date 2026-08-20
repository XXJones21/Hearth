---
title: Persona Flame (the fire visualization)
status: canonical
last_reviewed: 2026-08-20
related:
  - persona-face-spec.md
  - hearth-vision-design.md
sources:
  - android-client/core/src/main/java/com/hearth/core/persona/FlameProfile.kt
  - android-client/app/src/main/java/com/hearth/app/ui/persona/PersonaFlame.kt
  - apple-client/Hearth/Core/Sources/HearthUI/Persona/FlameProfile.swift
  - apple-client/Hearth/Core/Sources/HearthUI/Persona/PersonaFlameCanvas.swift
  - apple-client/Hearth/Core/Sources/HearthSpatial/FlameMesh.swift
  - apple-client/Hearth/Core/Sources/HearthSpatial/AnimatedTexture.swift
  - apple-client/Hearth/Core/Sources/HearthSpatial/AnimatedTexture.metal
  - apple-client/Hearth/Core/Sources/HearthSpatial/PersonaRig.swift
  - apple-client/Hearth/Core/Sources/HearthSpatial/EmberField.swift
  - tasks/clients/visionOS/phase-4-5.md
  - tasks/clients/ios/renderer-ab.md
---

# Persona Flame

How Sulivan's fire is built, in the order you would build it.

This is a **walkthrough, not an API reference**. Every technique is described in
terms of what it does and why, so it can be rebuilt against whatever a platform
offers.

**There are two implementations and this document covers both**, because the
right one depends on what the client is:

| If the client is | Build | Section |
| --- | --- | --- |
| A screen -- Android, the desktop's card surfaces, widgets | **The canvas flame.** Vector primitives, no shader, no 3D. | [For 2D canvas renderers](#for-2d-canvas-renderers) |
| A spatial stage -- a headset, or a scene with a movable camera | **The mesh flame.** Real geometry, a compute kernel, a light in the room. | [For 3D spatial platforms](#for-3d-spatial-platforms) |

They are not a first draft and a real version. They are the same character drawn
two ways, and **both are shipping**: the headset runs the mesh, and both phones
run the canvas -- iOS since 2026-08-20 and Android the same day. The iOS client
built both and chose the canvas on device -- it cost
less and, more importantly, a canvas flame had to exist anyway for widgets,
which can host neither a 3D view nor a compute pass. One implementation beats a
better-looking second one. The full comparison is in
`tasks/clients/ios/renderer-ab.md`.

**Read the 2D section first even if you are building the 3D one.** The
silhouette arithmetic is shared, and it is most of the character.

The companion document is [persona-face-spec.md](persona-face-spec.md), which
covers the face itself -- the geometry, the expression library, the director.
This one covers the body the face sits on.

**Read the "why" paragraphs.** Almost every number here replaced a different
number that looked correct and failed on a device, and the reason is more
portable than the value.

---

## For 2D canvas renderers

Reference implementation: `PersonaFlameCanvas` and `FlameProfile` in
`apple-client/Hearth/Core/Sources/HearthUI/Persona/`. Roughly three hundred
lines of arithmetic and fills, no shader, running at 60fps on a phone.

Everything below needs only: a path you can build from points and fill with a
gradient, a way to clip one drawing to another, and an additive blend mode.
Compose's `Canvas`, HTML5 `<canvas>`, SVG and SwiftUI's `Canvas` all qualify.

### The shape of it

| Layer | What it is |
| --- | --- |
| 1. The profile | The arithmetic. Shared with the 3D version, and exact. |
| 2. The body | One closed path, one linear gradient. |
| 3. The tip | A feather, because the path ends in a point and a flame never does. |
| 4. The licks | A few narrower flames inside the body, standing in for the noise field. |
| 5. The face | The persona's own face, drawn on top. Features only. |
| 6. The embers | Additive dots, born across the body and rising past the tip. |
| 7. The halo | A radial glow. The 3D version deliberately has none. |

One clock through all of them. **Seven effects on seven clocks are seven effects
near each other; seven on one clock are one fire.**

### 1. The profile, and why it is not an approximation

Three functions of `v`, where `v` runs 0 at the base to 1 at the tip. They are
the same functions the mesh uses, and the reason a 2D client can have the exact
same silhouette is worth stating carefully:

**The flame is a surface of revolution.** Seen from the front, its outline is
the profile evaluated at the two meridians where the horizontal coordinate is
extremal -- angle 0 and angle pi. So the canvas evaluates exactly what the mesh
evaluates, at two angles instead of forty-four.

```
width(v)  = v < 0.3 ? radius * sin((v/0.3) * pi/2)
                    : radius * pow(max(1 - t*t, 0), 0.45)      where t = (v-0.3)/0.7
rise(v)   = base + (v < 0.3 ? radius*0.95 * (1 - cos((v/0.3) * pi/2))
                            : radius*0.95 + (height - radius*0.95) * t)
            where base = -radius * 0.95
lean(v)   = sway * radius * v*v * sin(phase * 1.7)
```

Three things those lines cost to learn:

- **A flame is fattest LOW.** The first version was widest near the top and drew
  to a point at the bottom, which is a light bulb.
- **`pow(1-t, n)` gives a cone.** It is very nearly a straight line near the
  base. Squaring `t` inside is what keeps the flame near full width through its
  lower third and moves all the narrowing into the top half, which is where a
  flame's narrowing is. The exponent is the top's width, and LOWER is wider.
- **`rise` must curve with `width` across the dome.** A profile that simply goes
  to zero at v = 0 gives a spike. The bottom 30% is a hemisphere: the height
  follows the same quarter circle the width does.

The lean grows with `v` squared so it is all in the top third. A flame's base is
held by whatever it is burning on.

### 2. The wobble

Multiply the width by `1 + turbulence * noise(angle, v, phase)`:

```
noise(a, v, p) = (sin(3a + p*2.1 + v*5.0)
                + sin(5a - p*1.6 + v*8.0) * 0.55
                + sin(8a + p*2.9 - v*3.0) * 0.3) / 1.85
                * smoothstep(0.3, 1.0, v)
```

Trigonometric rather than a noise table, because the flame closes on itself and
sines of INTEGER multiples of the angle agree at 0 and 2pi for free.

**The smoothstep damping is not optional.** A flame is held steady at its base;
the first version's wobble ran all the way down and chewed the dome into a knot
of folds.

Evaluate at angle 0 for the right edge and angle pi for the left. They wobble
independently, which is what stops the flame reading as a symmetrical vase.

Add a body-wide breath of `1 + 0.012 * sin(phase * 1.6)` and **keep it that
small**. At 0.06 it swelled the silhouette enough to swallow the face on every
cycle. A flame does not pulse as a whole; its edges move.

### 3. The body: one path, one gradient

Walk `v` from 0 to 1 up the right meridian, then back down the left, and close.
Forty points a side is plenty.

Fill it with a linear gradient from the base to the tip, using the same five
stops the shader ramp uses, at the same positions:

| Stop | Colour | At |
| --- | --- | --- |
| straw | `1.00, 0.88, 0.42` | 0.00 |
| gold | `1.00, 0.66, 0.18` | 0.28 |
| amber | `1.00, 0.38, 0.07` | 0.58 |
| red | `0.86, 0.13, 0.04` | 0.85 |
| ash | `0.45, 0.06, 0.03` | 1.00 |

**Yellow where the flame is fed, red where it is spending itself.** A near-white
heart claimed too much of the height and left the body looking bleached.

What a gradient cannot do is the shader's trick of perturbing the ramp position
by the noise field, so a drawn flame's colour boundaries are level where a
computed one's wander. That is the largest single visual difference between the
two implementations and it is acceptable.

### 4. The tip feather

The path ends in a point and a point is the one shape a flame never has. Fade
the body out between `v = 0.88` and `v = 0.99` -- the same window the shader
uses.

A canvas cannot subtract alpha from a fill it has already made, so clip to the
body path and paint a background-to-transparent gradient over the top of it. If
your canvas has a destination-out blend, that is cleaner.

### 5. The licks

The shader gets its internal structure from a five-octave domain-warped fbm
evaluated per pixel. A canvas cannot, and does not need to.

Draw **three narrower flames inside the body** -- the same profile at 30-55% of
the width and 70-90% of the height, each offset sideways by the noise function
at its own seed, each filled with a pale gradient at low alpha, all clipped to
the body.

Three reads as structure. More turns the body back into a wash.

### 6. The face: features only, drawn on top

This is the whole 2D shortcut, and it is a big one. The 3D version needs a card
curved to the flame's own radius, tracking the surface as turbulence moves it,
in a stated sort group. **A screen has one viewpoint and no depth to fight over,
so the face is simply drawn over the fire.**

**But it must be features only.** The persona's normal face draws a filled head
and a rim and then puts eyes on it -- composited over a fire that is a persona
standing IN FRONT OF a flame, not a flame with a face. The headset never hits
this because its face is a texture that is mostly transparent, with ink only
where the features are. Give the face renderer a flag that suppresses the head
fill and keeps everything else.

**And the ink goes flat black.** On a cream head, a warm brown belongs to the
same palette family as everything around it. On a flame the background is bright
saturated gold, and a brown two steps from cream is one step from fire -- the
eyes wash out exactly where the body is brightest, which is where they sit.

Everything else about the face is unchanged: same director, same pose, same
gaze, same blink. A persona wearing a flame blinks exactly as it does wearing a
head.

### 7. The embers

Additive dots. Three things to get right, all of which were got wrong first:

**Born across the body, not on the axis.** Pick a birth height in the upper
half, pick a meridian, and use the silhouette to get the width there. The first
version derived its sideways drift from the wobble noise -- which is damped to
nothing near the base, correct for a silhouette and wrong for a particle, which
spends its early life exactly there. Every ember started on the centre line and
stayed near it, reading as crumbs around the mouth.

**Additive, always.** An opaque dot on a bright gold flame is mud. Adding light
to light means embers inside the fire are indistinguishable from it and embers
outside it glow -- which is both what fire does and, in the 3D version, what
removes the need to sort them at all.

**Rising and widening, shrinking as they cool.** Climb past the tip; spread with
`t` squared so the plume opens; shrink to a quarter. Fading alone leaves ghosts
of the original size hanging in the air.

Per-turn behaviour, matching what the 3D emitter does:

| State | The plume |
| --- | --- |
| Idle | Slow, wide, rising. |
| Listening | Narrower and faster. |
| Thinking | Turning -- a slow whirl. |
| Speaking | A ring around the flame whose RADIUS carries the playback amplitude. |

### 8. The halo

A radial gradient behind everything, its opacity driven by a flicker value.

**Keep it, and note that the 3D version deliberately does not have one.** The
headset switches its painted glow off when the flame lights, because a real
light doing real work on real walls does that job better. A screen has no walls,
so nothing does that job -- and without the halo the fire reads flatter than the
orb it replaces.

The flicker is three sines at incommensurable rates:

```
0.5 + 0.5 * clamp(sin(t*2.7)*0.5 + sin(t*4.3 + 1.7)*0.3 + sin(t*9.1 + 0.4)*0.2, -1, 1)
```

A correlation, not a measurement. A fire's signature is that its light is never
still.

### The one bug every canvas port will hit

**A canvas does not animate itself.** If the clock is read where the drawing is
constructed rather than supplied by a per-frame timer, the flame moves only when
something else happens to invalidate the view: stationary, then a lurch. On iOS
that is a `TimelineView`; elsewhere it is a render loop or an animation frame.

Related, and worth knowing before you measure anything: **a frame-rate readout
that has its own clock will report the display refresh whatever the drawing
beside it is doing.** Ours confidently said 60fps for a completely frozen flame.
Judge motion by eye.

### What 2D gives up

- **Fine grain.** The fbm's tattered small-scale licks. This is the one that
  makes fire look *hot* up close.
- **Level colour bands** instead of wandering ones, per step 3.
- **Depth.** No parallax between the near and far walls, because there are no
  walls.
- **Any path to rotating it.** If the client ever grows a movable camera, the
  shape has to be rebuilt as geometry.

None of those is what makes it Sulivan. The shape, the palette and the motion
are, and all three port exactly.

---

## For 3D spatial platforms

Everything from here down is the mesh implementation: real geometry, a compute
kernel writing a texture every frame, an unlit material, a curved face card, and
a particle emitter. It is what the visionOS client runs.

**Build this instead of the canvas flame only if the viewer can change angle** --
a headset, or a scene with an orbit control. The desktop client is in that
category today and the phone is not.

---

---

### The shape of the whole thing

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

### 1. The mesh: a teardrop that moves

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

### 2. The texture: what happens inside

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

### 3. The material and the light

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

### 4. The face plane

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

### 5. The particles

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

## Choosing between them

The 2D recipe above used to live here as speculation, written before either
implementation existed. It is a shipped implementation now, so what is left in
this section is only the decision.

### Ask whether the client is flat at all

**The desktop client is not.** It renders the persona through
`@react-three/fiber` in a `<Canvas>` with a perspective camera and
**`OrbitControls`** -- zoom disabled, polar angle clamped, free in yaw. The
viewer can walk around the persona. That is a 3D scene in a window, and it keeps
almost everything a headset needs: the billboard, the card's curvature, the
surface tracking and the sort group all still earn their keep.

It also already pays for a WebGL context, which makes a third option available
there and probably the best one: **port the Metal kernel to GLSL as a
`ShaderMaterial` and keep the mesh.** That is a closer match than either
alternative.

**Android took the flat composite**, on 2026-08-20, and it is a shipped
implementation: `PersonaFlame.kt` plus `FlameProfile.kt` in
`android-client/`, a literal port of the iOS canvas. The reasoning was the
iOS reasoning -- a phone has one viewpoint, and a flat flame will be wanted
for the cover screen and the home-screen widget, neither of which can host a
3D scene. The alternative, a 3D scene in a view, would have cost what desktop
costs and bought a persona you can turn on a device nobody turns.

Two places Compose does better than SwiftUI, both worth carrying to the next
canvas port:

- **The tip feather is a real erase.** `BlendMode.DstOut` subtracts alpha, so
  the tip goes to nothing and the halo shows through it. SwiftUI cannot take
  alpha back out of a fill it has already made, so the iOS version washes the
  tip toward ash instead. It needs the body, the licks and the feather to share
  one `saveLayer`: an erase has to be bounded, or it takes the halo with it.
- **The frame clock is `withFrameMillis`**, which the face already ran on, so
  the flame did not need a second clock mechanism beside it.

**How a config selects it:** `visualization.type` names the renderer, and the
fire's name is **`flame`** -- one name for both implementations, because the
type says what a persona IS rather than how a platform draws it. `canvas_flame`
would have baked one client's drawing into a cross-client contract.

Two things a client adding the name has to get right, both of which bit during
the Android wiring:

- **Both face-wearing forms need the geometry.** Gating the geometry decode on
  `procedural_face` alone draws the fire blind.
- **An unknown type must fall back to the ORB, not to the model branch.** The
  desktop client's renderer chain ended in a GLB `else`, so `flame` asked for an
  asset no persona carries and tripped its error boundary -- a visible failure
  where the contract is a graceful fallback. It now draws the face, which is
  what it drew before the name existed.

### What drops on every non-spatial client

These need passthrough or a room, and neither exists in a window:

- **Surroundings lighting.** No physical surfaces to reach.
- **The proximity spotlight** -- surface detection, the widening cone, the
  wall/floor/ceiling cookies, the corner blending.
- **Occlusion and collision against a scene mesh.**
- **The point light itself**, very nearly. The flame is unlit, so the light
  never touched it -- its only job was the room.
- **Adaptive resolution.** A window knows its own pixel size exactly, which is
  simpler than the headset's answer rather than a substitute for it.
- **The gestures** -- move, scale, rotate, and the anchors that remember where
  things were left.

### What drops only on a TRULY flat client

These survive anywhere the viewer can change angle, which includes desktop:

- The billboard on the face pivot.
- The card's curvature.
- Tracking the flame's moving surface in depth.
- The opacity threshold and the sort group -- both are fixes for sorting between
  two objects, and compositing in a fixed order has no sort to lose.

### The one thing that is a LOSS, not a saving

The flicker on the walls. *"A fire's signature from across a room is not its
shape -- it is that the light on the walls is never still."* A window has no
walls, so the fire loses its most legible cue and gets nothing back.

The compensation is the halo -- see step 8 of the 2D recipe. The general rule
for this port: **the spatial version spent its effort on the room and none on
the composite; a screen has to spend it the other way round.**

## Porting notes

**What is platform-specific in the 3D version and needs a local answer:**

- `LowLevelMesh` -- any dynamic vertex buffer works. ~1,300 vertices rebuilt per
  frame on the CPU is a rounding error anywhere, and it keeps the profile
  readable as arithmetic.
- `LowLevelTexture` + compute -- a fragment shader over the same UVs computes
  the same function, since nothing persists between frames.
- `SurroundingsLight` -- no equivalent off visionOS, and none needed.
- `AdaptiveResolutionComponent` -- replace with distance and field of view.
- `BillboardComponent` -- note that it constrains no axes. Anything with feet
  needs a yaw-only look-at, or a persona shrunk to a desk toy tilts back to look
  up at you.

**What the 2D version needs from its platform**, and it is a short list: a path
built from points, a linear and a radial gradient, a clip, and an additive blend
mode. Compose `Canvas`, HTML5 `<canvas>`, SVG and SwiftUI `Canvas` all qualify.

**What is not platform-specific at all and should be copied exactly:**

- `width`, `rise`, `lean` and the trig `noise`. They ARE the shape, and they are
  identical in both implementations.
- The five colour stops and their positions.
- Where the tip feather starts and ends.
- The flicker's three sine rates.
- One clock through every layer.

**What to build first, if you want to see something early:** the outline, filled
with a flat colour. The silhouette is most of the character, and every later
step is easier to judge against a shape you already recognise.

**How to know it is right:** put it beside the headset's and ask whether it is
the same character, not whether it is the same picture. That is the bar
`PersonaOrb` cleared for the bead, and it is the bar here.

## Open items

**Shared:**

- The chibi face variant sits behind a flag and is written up in
  [tasks/persona-chibi-face.md](../../tasks/persona-chibi-face.md).
- The canvas flame has only been judged at idle on device. Thinking and speaking
  are where the states diverge most, and the speaking ring is untested.

**3D only:**

- The mesh is CPU-written. `LowLevelMesh` offers GPU buffers if the vertex count
  ever grows enough to matter; it has not.
- The thinking vortex strength has no documented unit behind it and was set by
  eye on device.
- The cylinder's `emitterShapeSize` axis convention is undocumented; it is
  passed as (diameter, height, diameter) by analogy with the sphere.

**2D only:**

- Colour bands are level where the shader's wander. Perturbing the gradient
  stops per-frame by the same noise would close some of that gap and has not
  been tried.
- Thinking has no whirl on either canvas. The state table above gives it one,
  and both flat clients draw it as idle. Adding it to one only would make the
  two flames different characters, so it is a shared item or nothing.
