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

- **Brows.** The reference has a separate dark arc above each eye, and it is
  doing more work than it looks: without it the face reads as an eye rather
  than an expression. This is a new mark, not a tuning of the lash.
- **A mouth in the same language.** The chibi branch draws eyes only. The ink
  mouth is still there and still correct for the bead, and the two would not sit
  together.
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

## The numbers, as they stand

In `chibiEye`: eyes scaled 1.42x over what the persona asks for, width
`eyeLength * 0.62`, height `1.52`, top of the oval 0.74 of the base, iris 0.66
of the eye's smaller radius, pupil 0.38 of the iris, lash a contour 0.26 wide
weighted to the top. In `PersonaRig`: face card 2.05 x 1.5 radii, cropped to
0.37 x 0.46 of the texture.

None of them are derived. All of them are somebody looking at a headset.
