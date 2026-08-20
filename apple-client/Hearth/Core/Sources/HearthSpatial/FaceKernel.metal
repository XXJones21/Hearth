//
//  FaceKernel.metal
//  HearthSpatial
//
//  The face, drawn on the GPU as signed distance fields, once per frame, into a
//  LowLevelTexture the orb wears.
//
//  This is the same ink language PersonaFaceView draws with Core Graphics paths
//  -- two vertical capsules for eyes, a glint in each, a crescent or round
//  mouth, no brows -- re-expressed as SDFs because a compute kernel has no path
//  rasteriser. Every constant below traces to that file, and where the numbers
//  look arbitrary they are: they were tuned by eye on a phone and carried here
//  unchanged, because a face that is subtly different on two devices is worse
//  than one that is the same and imperfect.
//
//  WHAT IS DELIBERATELY MISSING: the head. PersonaFaceView draws a squircle and
//  fills it, because on a flat screen the head has to be drawn. Here the BEAD is
//  the head -- this texture paints ink onto a sphere that already exists -- so
//  the kernel writes transparent everywhere it is not drawing ink, and the
//  shell it lands on blends over the body.
//
//  Coordinates: the shell is a sphere, so the kernel goes from uv to a direction
//  on that sphere, keeps only the front-facing part, and works in the tangent
//  plane there. That indirection is what makes the face land on the front of the
//  orb rather than smeared around an equirectangular wrap. `lonOffset` corrects
//  for where RealityKit's sphere generator happens to put its seam.
//

#include <metal_stdlib>
using namespace metal;

/// Must match `FaceParams` in PersonaFaceTexture.swift: same field order, same
/// types, same padding. A mismatch here is silent and draws garbage.
struct FaceParams {
    // Pose -- geometry
    float headWidth;
    float headHeight;
    float eyeSize;
    float eyeSpacing;
    float eyeHeight;
    float eyeLength;
    float eyeTilt;
    float mouthWidth;
    float mouthThickness;
    float mouthCurve;
    // Pose -- motion
    float eyelidL;
    float eyelidR;
    float eyeArc;
    float focus;
    float eyeScaleL;
    float eyeScaleR;
    float eyeTiltL;
    float eyeTiltR;
    float eyeRaiseL;
    float eyeRaiseR;
    float gazeX;
    float gazeY;
    float mouthOpen;
    float mouthRound;
    // Colours (linear sRGB 0...1)
    float3 ink;
    float3 glint;
    float3 iris;          // the eye's colour inside the ink rim
    float irisAmount;     // 0 draws no iris at all
    float eyeStyle;       // 0 = the ink capsule, 1 = the chibi oval
    // Projection
    float lonOffset;      // radians; where the front of the sphere sits in u
    float extent;         // how much of the front hemisphere the face spans
    uint  width;
    uint  height;
};

// MARK: - Distance fields

/// Rounded box. Degrades to a capsule when the radius reaches the short side,
/// which is how one primitive serves both the eyes and the round mouth.
static inline float sdRoundBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

/// A band bowed along a parabola: the happy `^` and the pensive droop.
///
/// PersonaFaceView draws this as two quadratic curves sharing endpoints. A
/// quad-curve SDF is expensive and the shape is shallow, so this evaluates the
/// parabola directly and measures vertical distance to it -- close enough at
/// this size that the difference is invisible, and cheap.
static inline float sdArcBand(float2 p, float halfW, float lift, float band) {
    float t = clamp(p.x / max(halfW, 1e-4), -1.0, 1.0);
    float curveY = -lift * (1.0 - t * t);
    float dy = abs(p.y - curveY) - band * 0.5;
    float dx = abs(p.x) - halfW;
    return max(dy, dx);
}

/// Coverage from a distance, antialiased over roughly one texel.
static inline float coverage(float d, float px) {
    return clamp(0.5 - d / max(px, 1e-5), 0.0, 1.0);
}

static inline float2 rotate(float2 p, float a) {
    float s = sin(a), c = cos(a);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

/// One eye, in its own centred space. Mirrors PersonaFaceView.eyeShape.
static inline float sdEye(float2 p, float baseHalfW, float lid, float scale,
                          float arc, float eyeLength) {
    float l = min(lid, 1.0);
    float s = max(scale, 0.2);
    float halfW = baseHalfW * s;
    float closedness = l * abs(arc);

    if (closedness > 0.35) {
        // A lid closing over an arc: joy bows up, the droop bows down.
        float sign = arc < 0.0 ? -1.0 : 1.0;
        float w = halfW * 1.45;
        float lift = halfW * 1.5 * l * sign;
        float band = max(halfW * 0.62, 0.004);
        return sdArcBand(float2(p.x, p.y - band * 0.4 * sign), w, lift, band);
    }

    // Neutral close. The capsule collapses to a stubby bar at its OWN width and
    // never a spindly hyphen -- the first cut of this thinned while it widened,
    // and mid-blink it read as a rendering fault rather than an eyelid.
    float halfH = max(halfW * 0.55, halfW * max(eyeLength, 0.2) * (1.0 - l * 0.95));
    return sdRoundBox(p, float2(halfW, halfH), min(halfW, halfH));
}

// MARK: - The chibi eye
//
// A DIFFERENT EYE, not a dressed-up version of the other one. The ink language
// draws a dark capsule and lets the persona's own surface show around it -- it
// is a mark ON a face. This is an eye IN a face: a white oval with a coloured
// iris, a dark pupil, a heavy lash line along the top and two highlights, which
// is the shape animation reaches for when a character has to read as ALIVE at a
// small size.
//
// It is a second style rather than a replacement because the first is device
// tested, shipped, and correct for the bead. Reference is RWBY Chibi.

struct EyeLayers {
    float sclera;
    float outline;
    float lash;
    float iris;
    float pupil;
    float glint;
};

/// An oval whose width varies with height: narrow at the top, WIDE at the base.
///
/// This is the shape the style actually has, and a plain ellipse is not it. The
/// reference reads as round, but its lower half carries most of the width --
/// closer to an egg standing on its wide end than to a circle. Tapering the
/// horizontal radius as a function of height gets there with one extra line,
/// where trying to reach it by squashing an ellipse only ever produced
/// something that looked squashed.
///
/// The distance is approximate: a true distance to a tapered oval is an
/// iterative solve, and the error here is a fraction of a texel at this size.
static inline float sdTaperedOval(float2 p, float2 r, float topWidth) {
    // 0 at the top of the shape, 1 at the bottom.
    //
    // MEASURED, not derived. The comment here used to say "face space has y
    // pointing down, so the bottom is +r.y" and the device drew the taper
    // upside down -- wide across the top, drawn to a point underneath. This is
    // the fourth axis convention in this file that has gone the opposite way to
    // the reasoning, so it is now written the way it renders.
    float t = clamp(0.5 - p.y / (2.0 * max(r.y, 1e-4)), 0.0, 1.0);
    float width = max(r.x * mix(topWidth, 1.0, t), 1e-4);
    return (length(float2(p.x / width, p.y / r.y)) - 1.0) * min(width, r.y);
}

static inline EyeLayers chibiEye(float2 q, float halfWidth, float lengthScale,
                                 float lid, float px, float gazeX, float gazeY) {
    EyeLayers layers = {0.0, 0.0, 0.0, 0.0, 0.0, 0.0};

    // BIGGER THAN THE INK EYE ASKS FOR, and that is the style rather than a
    // fudge. `eyeSize` comes from the persona and was chosen for a small dark
    // mark on a bead; this style puts most of the face's character in the eyes,
    // so it scales what the persona asked for rather than replacing it -- a
    // persona with small eyes still has smaller eyes than one without.
    halfWidth *= 1.42;

    // NEARLY ROUND, on the direct reference. Not the lozenge the last pass
    // made: these eyes are as tall as they are wide, or a shade taller, with
    // the width still carrying the persona's `eyeLength` so a narrow-eyed
    // persona stays narrow-eyed.
    //
    //
    // `lengthScale` is the persona's `eyeLength`, and it is 2.4 by default --
    // authored to make a tall CAPSULE tall. Multiplying the height by it here
    // produced an eye three times taller than it was wide, which is the shape
    // this style is least like. It belongs on the width instead: the same
    // number that stretched the old eye vertically stretches this one across.
    // Wider than tall now, which is the chibi proportion: the eye is a broad
    // oval, not the near-circle the last pass drew.
    float2 r = float2(halfWidth * max(lengthScale, 0.6) * 0.62, halfWidth * 1.52);
    const float topWidth = 0.74;

    // The lid comes down as a horizontal cut travelling from the top of the
    // eye toward the bottom.
    float lidY = -r.y + 2.0 * r.y * clamp(lid, 0.0, 1.0);
    float open = smoothstep(lidY - px, lidY + px, q.y);

    float d = sdTaperedOval(q, r, topWidth);
    float body = coverage(d, px) * open;
    layers.sclera = body;

    // A thin rim all the way round, so the white never bleeds into whatever is
    // behind it.
    float2 rim = max(r - float2(halfWidth * 0.10), float2(1e-3));
    layers.outline = clamp(body - coverage(sdTaperedOval(q, rim, topWidth), px) * open,
                           0.0, 1.0);

    // THE LASH FOLLOWS THE EYE'S CURVE. It was a horizontal cut across the top,
    // and a straight line through a round shape makes a D -- which is exactly
    // what the device drew: a flat-topped half-moon. It also sliced the top off
    // the iris, which pushed the pupil into the upper corner of what was left
    // and made him look shifty. One wrong shape, three wrong-looking things.
    //
    // A lash is a thickened contour, so it is the rim again -- the oval minus a
    // smaller oval -- weighted toward the top rather than cut there. The eye
    // keeps its curve and the black follows it.
    float2 lashR = max(r - float2(halfWidth * 0.26), float2(1e-3));
    float lashBand = clamp(body - coverage(sdTaperedOval(q, lashR, topWidth), px) * open,
                           0.0, 1.0);
    layers.lash = lashBand * smoothstep(0.10, -0.62, q.y / max(r.y, 1e-4));

    // THE WHITE IS A REAL AREA. At 0.86 the iris left almost no sclera and the
    // eye read as a coloured disc with a rim; the reference shows a broad white
    // around and above a circle that takes up perhaps two thirds of the height.
    // The white is what makes it an EYE rather than a lens.
    float2 centre = float2(gazeX * halfWidth * 0.26,
                           r.y * 0.12 + gazeY * halfWidth * 0.22);
    float irisR = min(r.x, r.y) * 0.66;
    layers.iris = coverage(length(q - centre) - irisR, px) * body;

    // And the pupil is SMALL against it -- a dot, not a slit. That ratio is
    // most of what separates a friendly face from an unsettling one.
    layers.pupil = coverage(length(q - centre) - irisR * 0.38, px) * body;

    // Two highlights, unequal: a large one up and to the left, a small one down
    // and to the right. One centred glint reads as a doll's eye; two unequal
    // ones read as a wet surface under a light that is somewhere in particular.
    float big = coverage(length(q - (centre + float2(-irisR * 0.38, -irisR * 0.40)))
                         - irisR * 0.34, px);
    float small = coverage(length(q - (centre + float2(irisR * 0.40, irisR * 0.38)))
                           - irisR * 0.18, px);
    layers.glint = max(big, small) * body;

    return layers;
}

// MARK: - Kernel

kernel void face_kernel(texture2d<float, access::write> out [[texture(0)]],
                        constant FaceParams &f [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) { return; }

    float2 uv = (float2(gid) + 0.5) / float2(f.width, f.height);

    // uv -> a direction on the sphere this texture is worn by.
    float lon = (uv.x - 0.5) * 2.0 * M_PI_F + f.lonOffset;
    float lat = (0.5 - uv.y) * M_PI_F;
    float cosLat = cos(lat);
    float3 dir = float3(sin(lon) * cosLat, sin(lat), cos(lon) * cosLat);

    // Only the front. Everything behind the orb stays clear, which is what
    // keeps the face a face rather than a band wrapped around the bead.
    if (dir.z <= 0.05) {
        out.write(float4(0.0), gid);
        return;
    }

    // The tangent plane at the front, in the same units PersonaFaceView uses:
    // the head's half-extent is 1, x right, y DOWN.
    float ext = max(f.extent, 1e-3);
    float2 p = float2(dir.x, -dir.y) / ext;
    p.x /= max(f.headWidth, 1e-3);
    p.y /= max(f.headHeight, 1e-3);

    // One texel, in face-space units, for antialiasing. Derived rather than
    // guessed: the tangent plane compresses toward the limb, so a fixed width
    // would alias badly at the edges of the face.
    float px = (2.0 * M_PI_F / float(f.width)) / ext;

    // Fade the ink out near the limb so the face does not end in a hard cut at
    // the horizon of the sphere.
    //
    // Narrowed from (0.15, 0.42) after the first device run. Those numbers were
    // chosen to be safe and were the reason the face looked washed out rather
    // than merely misplaced: the face was landing a quarter turn off, so the
    // eyes sat near the limb where this term had already dimmed them to a
    // smudge. The fade is a limb treatment, not a vignette over the whole face,
    // and it should only bite in the last few degrees before the horizon.
    float limb = smoothstep(0.06, 0.20, dir.z);

    // MARK: Eyes -- the whole character lives here.

    float eyeY = -1.0 + 2.0 * f.eyeHeight;
    float eyeDx = f.eyeSpacing;
    float baseHalfW = f.eyeSize;

    // Theatrical gaze travel, clamped so the eyes never cross the head's
    // outline at the height they sit at.
    float dyEye = min(0.95, abs(eyeY));
    float halfWidthAtEye = sqrt(max(0.05, 1.0 - dyEye * dyEye));
    float gxMax = max(0.0, halfWidthAtEye - eyeDx - baseHalfW * 1.6);
    float gx = clamp(f.gazeX * 0.45, -gxMax, gxMax);
    float gy = f.gazeY * 0.3;

    // Vergence: focus pulls both eyes toward a shared near point, so a focused
    // face converges slightly instead of staring through you.
    float converge = f.focus * baseHalfW * 0.55;
    float2 leftC  = float2(-eyeDx + gx + converge, eyeY + gy + f.eyeRaiseL * 2.0);
    float2 rightC = float2( eyeDx + gx - converge, eyeY + gy + f.eyeRaiseR * 2.0);

    // THE CHIBI BRANCH. It leaves the whole ink path below untouched: this
    // draws a complete eye and returns, because the two styles share the pose
    // and nothing else. Trying to make one composition serve both is how the
    // iris ended up as a blue blob with no pupil.
    if (f.eyeStyle > 0.5) {
        EyeLayers left = chibiEye(rotate(p - leftC, -(f.eyeTilt + f.eyeTiltL)),
                                  baseHalfW * f.eyeScaleL, f.eyeLength,
                                  f.eyelidL, px, f.gazeX, f.gazeY);
        EyeLayers right = chibiEye(rotate(p - rightC, -(f.eyeTilt + f.eyeTiltR)),
                                   baseHalfW * f.eyeScaleR, f.eyeLength,
                                   f.eyelidR, px, f.gazeX, f.gazeY);
        EyeLayers eye = left.sclera >= right.sclera ? left : right;

        // EYES ONLY in this style, for now. The mouth is drawn further down in
        // the ink language and is hidden at rest anyway, so wiring it through
        // here would be work in service of something nobody has seen yet. If
        // the style survives the test, the mouth follows it.
        float alphaC = eye.sclera * limb;
        if (alphaC <= 0.001) {
            out.write(float4(0.0), gid);
            return;
        }

        // Sclera, iris over it, pupil, then the strokes, then the highlights --
        // and the mouth in the same ink as the lash so a face reads as one
        // drawing rather than two.
        // Deep at the top, bright at the bottom, and a wider spread than the
        // ink eye's because the iris is doing nearly all of the work here --
        // a flat fill at this size reads as plastic.
        // Deeper at both ends than the first pass. Against a white sclera the
        // light end was washing out to nearly grey, and the reference's blue
        // holds its saturation all the way down.
        float3 irisTopC = f.iris * 0.55;
        float3 irisBottomC = mix(f.iris, float3(1.0), 0.16);
        float3 irisColourC = mix(irisTopC, irisBottomC,
                                 clamp(0.5 + (p.y - eyeY) / max(baseHalfW * 2.0, 1e-3),
                                       0.0, 1.0));

        float3 rgbC = float3(1.0, 0.99, 0.97);
        rgbC = mix(rgbC, irisColourC, min(eye.iris, 1.0));
        rgbC = mix(rgbC, f.ink, min(eye.pupil, 1.0));
        rgbC = mix(rgbC, f.ink, min(eye.outline, 1.0));
        rgbC = mix(rgbC, f.ink, min(eye.lash, 1.0));
        rgbC = mix(rgbC, f.glint, min(eye.glint, 1.0));

        out.write(float4(rgbC, alphaC), gid);
        return;
    }

    float arc = clamp(f.eyeArc, -1.0, 1.0);
    float dLeft  = sdEye(rotate(p - leftC,  -(f.eyeTilt + f.eyeTiltL)),
                         baseHalfW, f.eyelidL, f.eyeScaleL, arc, f.eyeLength);
    float dRight = sdEye(rotate(p - rightC, -(f.eyeTilt + f.eyeTiltR)),
                         baseHalfW, f.eyelidR, f.eyeScaleR, arc, f.eyeLength);
    float eyeCov = max(coverage(dLeft, px), coverage(dRight, px));

    // MARK: Iris and pupil -- the eye's colour, and the dark it surrounds.
    //
    // THREE RINGS FROM ONE SHAPE, each the eye eroded a little further. Adding
    // a positive number to a signed distance field shrinks the region it
    // describes, so the ink rim, the coloured iris and the dark pupil are the
    // SAME silhouette at three insets. They cannot disagree about where the eye
    // is, whatever the pose does to it -- and separately-drawn shapes would
    // have to track the blink, the tilt, the arc, the scale and the gaze
    // independently, drifting apart the first time any one of them moved.
    //
    // They also blink for free, because the eyelid is already inside `sdEye`.
    //
    // THE PUPIL IS THE POINT. An iris with no dark centre is a coloured blob:
    // the reference has a bright ring around a black middle, and it is the
    // black that makes it read as an eye looking at you rather than as a
    // painted dot.
    float irisCov = 0.0;
    float pupilCov = 0.0;
    float irisShade = 0.5;
    if (f.irisAmount > 0.001) {
        irisCov = max(coverage(dLeft + baseHalfW * 0.26, px),
                      coverage(dRight + baseHalfW * 0.26, px)) * f.irisAmount;
        pupilCov = max(coverage(dLeft + baseHalfW * 0.74, px),
                       coverage(dRight + baseHalfW * 0.74, px)) * f.irisAmount;

        // Where this pixel sits up the eye it belongs to, for the iris's own
        // gradient. Face space has y pointing DOWN, so larger is lower.
        float2 local = (dLeft < dRight) ? (p - leftC) : (p - rightC);
        float halfH = max(baseHalfW * max(f.eyeLength, 0.2), 1e-3);
        irisShade = clamp(0.5 + local.y / (2.0 * halfH), 0.0, 1.0);
    }

    // MARK: Glints -- the one highlight, and what stops the eyes reading flat.

    float maxLid = max(f.eyelidL, f.eyelidR);
    float glintOpacity = max(0.0, 1.0 - maxLid * 2.0);
    float glintCov = 0.0;
    if (glintOpacity > 0.0) {
        float glintR = baseHalfW * 0.3;
        float2 gOff = float2(-baseHalfW * 0.28 + f.gazeX * baseHalfW * 0.35,
                             -baseHalfW * max(f.eyeLength, 0.2) * 0.42 + f.gazeY * baseHalfW * 0.3);
        float gl = sdRoundBox(p - (leftC + gOff),  float2(glintR), glintR);
        float gr = sdRoundBox(p - (rightC + gOff), float2(glintR), glintR);
        glintCov = max(coverage(gl, px), coverage(gr, px)) * glintOpacity;
    }

    // MARK: Mouth -- hidden at rest, and the two shapes CROSSFADE.
    //
    // Morphing a crescent into an "o" path-by-path is how the first cut of this
    // ended up looking like a beak. They are separate shapes, mixed by weight.

    float mouthCov = 0.0;
    float visibility = min(1.0, f.mouthOpen * 4.0);
    if (visibility > 0.0) {
        float mouthY = 0.42;
        float mouthHalf = f.mouthWidth;
        float curve = f.mouthCurve * 0.5;
        float thickness = max(0.008, f.mouthThickness * 2.0);
        float open = f.mouthOpen * 0.42;

        float crescentW = 1.0 - f.mouthRound;
        if (crescentW > 0.0) {
            // Positive mouthCurve pushes the crescent's belly DOWN in screen
            // space: a smile's corners turn up and its centre dips below them.
            float band = thickness + open;
            float d = sdArcBand(float2(p.x, p.y - mouthY - curve - band * 0.5),
                                mouthHalf, -curve, band);
            mouthCov = max(mouthCov, coverage(d, px) * crescentW);
        }
        if (f.mouthRound > 0.0) {
            float roundH = max(0.0015, (thickness + open) * 0.55);
            float roundW = mouthHalf * 0.5;
            float d = sdRoundBox(p - float2(0.0, mouthY + roundH * 0.25),
                                 float2(roundW, roundH), min(roundW, roundH));
            mouthCov = max(mouthCov, coverage(d, px) * f.mouthRound);
        }
        mouthCov *= visibility;
    }

    // MARK: Compose
    //
    // Ink first, glint over it. Straight (non-premultiplied) alpha, because the
    // shell's material blends on the texture's own alpha channel.

    float inkCov = max(eyeCov, mouthCov);
    float alpha = max(inkCov, glintCov) * limb;
    if (alpha <= 0.001) {
        out.write(float4(0.0), gid);
        return;
    }

    // Ink, then iris over it, then the glint on top of both -- the order a
    // painter would use, and the order that keeps the glint reading as light on
    // a wet surface rather than a hole in one.
    // DEEPER AT THE TOP, brighter toward the bottom, which is what gives a flat
    // colour the look of a curved wet surface catching light from above. Both
    // ends are derived from the one iris colour rather than being two more
    // uniforms: a caller should be able to say "blue" and get an eye.
    float3 irisTop = f.iris * 0.62;
    float3 irisBottom = mix(f.iris, float3(1.0), 0.35);
    float3 irisColour = mix(irisTop, irisBottom, irisShade);

    // Ink, iris over it, pupil back to ink inside that, glint on top of all
    // three -- the order a painter would use, and the order that keeps the
    // glint reading as light on a wet surface rather than a hole in one.
    float3 rgb = mix(f.ink, irisColour, min(irisCov, 1.0));
    rgb = mix(rgb, f.ink, min(pupilCov, 1.0));
    rgb = mix(rgb, f.glint, glintCov > 0.0 ? glintCov / max(alpha, 1e-4) : 0.0);
    out.write(float4(rgb, alpha), gid);
}
