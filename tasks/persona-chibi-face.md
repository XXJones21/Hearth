# Persona chibi face

A side quest off phase 4.5, 2026-08-19. The flame turned out well enough that
the operator wanted to see whether the persona's FACE could go with it, and the
answer is yes -- far enough that it is worth keeping and finishing rather than
throwing away.

Parked here deliberately. Sulivan is back on his shipped ink eyes; everything
below is behind `PersonaFaceTexture.eyeStyle` and draws nothing until something
asks for it. Revisit after the phase 4.5 particles.

## Why it came up at all

The ink face is a MARK ON a surface: a dark capsule with a single glint,
letting the bead show through around it. That is exactly right for a small
glowing sphere, and it was designed for one.

A flame is a different object -- big, bright, with a body -- and against it the
two dark marks read as holes rather than as eyes. What the flame wanted was an
eye IN a face: white sclera, a coloured iris, a dark pupil, a lash. The
reference the operator supplied is RWBY Chibi, by way of Charmander for the
colour.

Two observations drove the whole thing:

- **A cool iris against a warm fire is a real composition.** Blue eyes on an
  orange flame is the strongest the persona has looked. It is not decoration;
  it is the only cool thing on the object.
- **A face makes it a character.** The moment the eyes read, people call it "he"
  and "him". That happened in this conversation without anybody deciding to.

## What was built

All of it in `FaceKernel.metal` and `PersonaFaceTexture`, as a SECOND style
rather than a replacement.

- **`PersonaFaceTexture.EyeStyle`** -- `.ink` (shipped, default) and `.chibi`.
  The kernel branches on it and returns early; the two share the pose and
  nothing else. Trying to make one composition serve both is what produced a
  blue ring around a black slit that the operator accurately called terrifying.
- **`sdTaperedOval`** -- an oval whose width varies with height, narrow at the
  top and wide at the base. A plain ellipse cannot make this shape, and
  squashing one only ever looks squashed.
- **Layers, all from one distance field**: sclera, a thin rim, a lash contour,
  the iris, the pupil, two glints. Each is the SAME silhouette at a different
  inset or a circle clipped to it, so they cannot disagree about where the eye
  is -- and they all blink for free, because the eyelid is already inside the
  shape function.
- **An iris gradient from one colour.** Deeper at the top, brighter at the
  bottom, derived rather than taken as two more uniforms, so a caller says
  "blue" and gets an eye.
- **Two unequal glints**, large upper-left and small lower-right. One centred
  glint reads as a doll's eye; two unequal ones read as a wet surface under a
  light that is somewhere in particular.

## What each device pass corrected

Every one of these was wrong on the desk and obvious on the headset.

- **The iris with no pupil** was a coloured blob. The dark centre is what makes
  it read as an eye LOOKING at you.
- **The pupil as a slit** was unsettling. A small round pupil against a large
  iris is most of what separates friendly from uncanny.
- **The taper ran the wrong way** -- wide at the top, drawn to a point below,
  a teardrop hanging rather than an egg standing. The fourth axis convention in
  this file to go opposite to the reasoning.
- **`eyeLength` on the height** made an eye three times taller than wide. That
  number is 2.4 by default and was authored to make a CAPSULE tall; on this
  shape it belongs on the width.
- **The iris at 0.86 left no sclera.** The white is not the ground the iris sits
  on, it is a real area, and it is what makes an eye rather than a lens.
- **The lash as a horizontal cut made a D**, and that one shape caused three
  separate faults: a flat top, an iris visibly sliced, and a pupil that looked
  shifty because the centre of what remained was not the centre of the circle.
  A lash is a thickened CONTOUR that follows the curve.
- **The face was soft**, and the cause was arithmetic rather than resolution:
  the card shows about a seventh of the texture's AREA, so asking for "enough
  texels to cover the card" asked for seven times too few. The adaptive
  resolution now divides by the crop, and the floor moved 512 -> 1024.

## What is missing before this could ship

- **Brows and a mouth**, each on its OWN plane -- see the section below, which
  is the shape of the remaining work. The eyes are a third of the picture.
- **The expressive channels are untested.** `eyeArc`, `eyeTilt`, the squash and
  the raise were all authored against a capsule. Blinks work, because the lid
  is inside the shape function. The extremes almost certainly do not.
- **The phone.** `PersonaFaceView` draws the ink language in Core Graphics and
  knows nothing about this. A persona that chose the chibi style would look like
  two different characters on two devices, which is the one outcome the shared
  `FaceDirector` exists to prevent.
- **It belongs in the persona config.** `eyeStyle`, `irisColor` and `irisAmount`
  are client properties today; they should sit beside `eye_size` and the rest of
  `FaceGeometry` so a persona can have blue eyes without a client build.

## The architecture it actually needs: three planes

Operator's call, 2026-08-19, after seeing the eyes land: **the eyes are a third
of the picture.** Brows and a mouth are not polish on top of this, they are the
other two thirds, and they should not share the eyes' plane.

### Why three, and not one texture with everything on it

The current face is one card wearing one texture, cropped to the middle where
the drawing is. That works for eyes and stops working the moment anything else
joins them:

- **They move over different distances.** Brows travel a long way -- surprise
  puts them most of the way to the hairline, anger drives them down into the
  eyes. A mouth opens wider than an eye is tall. One shared texture has to be
  large enough for the union of every extreme, and every feature then pays for
  the space the others might need.
- **Texels are the currency, and we already learned the exchange rate.** The
  softness bug earlier in this file was the face getting a seventh of its
  texture's area because of the crop. Three dedicated textures, each fully used
  by the one thing it draws, is strictly more resolution than one texture with
  three drawings sharing it -- at LESS total memory, because each can be sized
  to what it actually needs.
- **They redraw at different rates.** Eyes blink and saccade constantly. Brows
  hold a position for whole sentences. A mouth follows speech amplitude. On one
  texture, the mouth's frame rate is imposed on everything.
- **They need to sort against each other**, and against the flame. Separate
  planes make that a `ModelSortGroup` and a depth offset -- the machinery
  already in the file for the flame and the face card -- rather than a
  compositing problem inside a kernel.

### What each plane is

Same structure the eye card already has: a billboarding pivot, a curved card
riding the flame's surface, its own `AnimatedTexture`-style kernel and its own
adaptive resolution. Three of them, at three heights.

- **Eyes** -- built. See above.
- **Brows** -- a stroke with a position, an angle and an arc. Small texture, and
  the cheapest of the three to draw, but the one that carries the most
  expression per pixel: the same eyes under different brows are a different
  character.
- **Mouth** -- the real work. RWBY Chibi is the guide again, and what it does is
  a small vocabulary of distinct SHAPES rather than a continuously deformed
  curve: a smile, an open round, a flat line, a wide grin, a small "o". That is
  effectively a sprite sheet, and the operator's framing is to build it
  DYNAMICALLY -- draw each shape procedurally in the kernel and select or blend
  between them, rather than shipping an atlas.

### What a dynamic sprite sheet buys

A drawn atlas would be simpler and is the wrong trade here for the same reason
the face is a kernel and not a PNG: the shapes have to recolour with the
persona, resize with the flame, and stay sharp when somebody pinches him to
life size. A procedural shape does all three for free. It also means a new mouth
shape is a function rather than an art request, which matters for a client where
personas are meant to differ.

The crossfade the ink mouth already does between two shapes is the seed of
this -- it is a two-entry sprite sheet with a blend, and the work is to make it
a vocabulary.

### What this does not change

`FaceDirector` still owns every decision about WHEN. It already produces a pose
covering all three features, and it is shared with the phone. Three planes is a
statement about how the headset DRAWS a face, not about what a face does -- and
if that distinction ever blurs, the phone and the headset will start disagreeing
about who this persona is.

## The numbers, as they stand

In `chibiEye`: eyes scaled 1.42x over what the persona asks for, width
`eyeLength * 0.62`, height `1.52`, top of the oval 0.74 of the base, iris 0.66
of the eye's smaller radius, pupil 0.38 of the iris, lash a contour 0.26 wide
weighted to the top. In `PersonaRig`: face card 2.05 x 1.5 radii, cropped to
0.37 x 0.46 of the texture.

None of them are derived. All of them are somebody looking at a headset.
