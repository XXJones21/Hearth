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

    float arc = clamp(f.eyeArc, -1.0, 1.0);
    float dLeft  = sdEye(rotate(p - leftC,  -(f.eyeTilt + f.eyeTiltL)),
                         baseHalfW, f.eyelidL, f.eyeScaleL, arc, f.eyeLength);
    float dRight = sdEye(rotate(p - rightC, -(f.eyeTilt + f.eyeTiltR)),
                         baseHalfW, f.eyelidR, f.eyeScaleR, arc, f.eyeLength);
    float eyeCov = max(coverage(dLeft, px), coverage(dRight, px));

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

    float3 rgb = mix(f.ink, f.glint, glintCov > 0.0 ? glintCov / max(alpha, 1e-4) : 0.0);
    out.write(float4(rgb, alpha), gid);
}
