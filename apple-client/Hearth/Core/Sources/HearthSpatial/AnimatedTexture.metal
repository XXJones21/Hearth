//
//  AnimatedTexture.metal
//  HearthSpatial
//
//  Kernels that rewrite a LowLevelTexture every frame. One entry point per
//  LOOK; the numbers that go with each live in AnimatedTexture.Preset, because
//  a kernel and its four uniforms are one effect and passing three of them
//  right and one wrong gives you a subtly wrong effect with no error.
//
//  Ported from Valinor's Caustics.metal, which drew two of these and named the
//  file after the first. The technique notes are its author's and are kept:
//  they are the reason each kernel looks the way it does rather than the more
//  obvious way that does not work.
//
//  Luminance out, colour applied by whoever is wearing the texture. A kernel
//  that also decided the palette would have to be rewritten every time the
//  brand moved.
//

#include <metal_stdlib>
using namespace metal;

struct TextureParams {
    float time;        // seconds, drives the animation
    float scale;       // feature density across the texture
    float brightness;  // output gain
    uint  width;       // texture width  in texels
    uint  height;      // texture height in texels
};

// MARK: - Caustics

// One layer of the classic iterated sin/cos water caustic. Continuous
// coordinate + large offset (the Shadertoy "caustic" trick) so it forms flowing
// filaments rather than geometric cells. A per-cell fract() coordinate, or a
// Voronoi web, reads as flat and tiled instead -- not watery.
static inline float causticLayer(float2 uv, float time, float scale) {
    float2 p = uv * scale * 6.28318530718 - 250.0;
    float2 i = p;
    float c = 1.0;
    const float inten = 0.005;

    for (int n = 0; n < 5; n++) {
        float t = time * (1.0 - (3.5 / float(n + 1)));
        i = p + float2(cos(t - i.x) + sin(t + i.y),
                       sin(t - i.y) + cos(t + i.x));
        c += 1.0 / length(float2(p.x / (sin(i.x + t) / inten),
                                 p.y / (cos(i.y + t) / inten)));
    }
    c /= 5.0;
    c = 1.17 - pow(abs(c), 1.4);
    // Exponent sets filament thickness: higher = thinner, sparser, sharper.
    return clamp(pow(abs(c), 4.0), 0.0, 1.0);
}

kernel void caustics_kernel(texture2d<float, access::write> out [[texture(0)]],
                            constant TextureParams &params [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) { return; }
    float2 uv = float2(float(gid.x) / float(params.width),
                       float(gid.y) / float(params.height));
    float v = clamp(causticLayer(uv, params.time, params.scale) * params.brightness, 0.0, 1.0);
    out.write(float4(v, v, v, v), gid);
}

// MARK: - Noise, shared by everything below

static inline float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

static inline float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);                  // smoothstep weights
    float a = hash21(i + float2(0.0, 0.0));
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

static inline float fbm(float2 p, float2 drift) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 5; i++) {
        v += amp * valueNoise(p + drift);
        p = p * 2.0 + drift;
        amp *= 0.5;
    }
    return v;
}

// MARK: - Smoke

kernel void smoke_kernel(texture2d<float, access::write> out [[texture(0)]],
                         constant TextureParams &params [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) { return; }

    float2 uv = float2(float(gid.x) / float(params.width),
                       float(gid.y) / float(params.height));
    float2 p = uv * params.scale;
    float2 drift = float2(params.time * 0.10, -params.time * 0.08);

    // Domain-warp the noise by more noise -> billowing, swirling smoke.
    float2 q = float2(fbm(p, drift), fbm(p + 5.2, drift));
    float n = fbm(p + 1.5 * q, drift);
    float v = clamp(n * params.brightness, 0.0, 1.0);
    v = smoothstep(0.25, 0.85, v);               // soft, cloudy -- not crisp

    out.write(float4(v, v, v, v), gid);
}

// MARK: - Fire

// A hearth flame rather than a bonfire: dense and bright at the base, thinning
// and breaking up toward the top, with the noise field RISING rather than
// drifting sideways. The vertical gradient is what makes it read as flame at
// all -- the same noise without it is just smoke.
//
// Wrapped horizontally on purpose. This is worn by a sphere, so u = 0 and u = 1
// are the same meridian, and a field that did not meet itself there would show
// a seam straight down the persona's side. Sampling the noise on a circle in x
// costs one sin/cos and removes the seam entirely.
kernel void fire_kernel(texture2d<float, access::write> out [[texture(0)]],
                        constant TextureParams &params [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) { return; }

    float u = float(gid.x) / float(params.width);
    // Row zero is the TOP of the texture, and a flame wears it with row zero at
    // the tip -- so `v` is flipped and means HEIGHT UP THE FLAME everywhere
    // below, which is what the rest of the kernel reads it as.
    float v = 1.0 - float(gid.y) / float(params.height);

    // Seamless in u: walk a circle instead of a line, because the flame closes
    // on itself and a field that did not meet itself would show a seam.
    float angle = u * 6.28318530718;
    float2 p = float2(cos(angle), sin(angle)) * params.scale;
    p.y += v * params.scale;

    // Rising, and faster than smoke drifts.
    float2 drift = float2(0.0, -params.time * 0.55);
    float2 q = float2(fbm(p, drift), fbm(p + 3.7, drift));
    float n = fbm(p + 1.2 * q, drift);

    // SOLID LOW, BREAKING UP HIGH. The first cut faded from the base and put
    // every lick at the very top, so the flame read as a solid body wearing a
    // fringe. A real flame is dense at its heart and tattered over most of its
    // upper half, so the fade starts sooner and runs further.
    float height = 1.0 - smoothstep(0.18, 1.05, v);
    float flame = clamp(n * height * 2.1 * params.brightness, 0.0, 1.0);

    // The core is opaque regardless of the noise: a fire has a body, and noise
    // alone gives it holes all the way through.
    float core = 1.0 - smoothstep(0.0, 0.42, v);
    float density = clamp(max(flame, core * 0.95), 0.0, 1.0);

    // FEATHER THE TIP OUT. The mesh draws to a point, and a point is the one
    // shape a flame never has -- on the device it read as a needle on top of an
    // egg. Fading the density before the geometry runs out means the visible
    // top ends where the body is still a third of its width, and ends softly.
    // The window is wider than the 0.95-0.98 first asked for, because three per
    // cent of the height is a cut rather than a feather.
    density *= 1.0 - smoothstep(0.88, 0.99, v);

    // COLOUR IN RGB, DENSITY IN ALPHA, in one texture.
    //
    // The earlier split into two textures existed because a PhysicallyBasedMaterial
    // samples an opacity texture's RED channel, so colour and density could not
    // share one. An UnlitMaterial does not work that way -- it takes ONE colour
    // texture and uses its alpha for transparency -- and unlit is what a flame
    // wanted all along: fire emits light, it does not receive it.
    //
    // THE SEAM. This used to read `fract(v - time * 0.22)` to make the heat
    // travel upward, and `fract` wraps: it drops from 1 to 0 in one texel, and
    // that discontinuity drew a hard horizontal line straight across the body
    // that marched slowly up it. It was the one thing on the device that looked
    // like a fault rather than a choice.
    //
    // The fix is not a smoother wrap, it is NOISE. Heat in a flame does not
    // rise in a level band; it rises in tongues. So the ramp's position is
    // perturbed by the same fbm field the density uses, on the same drift --
    // which means the colour boundaries wander exactly where the flame's own
    // structure wanders, and there is no seam anywhere because there is no
    // longer a horizontal anything.
    float heat = clamp(v * 0.92 + 0.26 * (n - 0.42), 0.0, 1.0);

    // WARM YELLOW LOW, RED HIGH. The near-white heart this started with claimed
    // too much of the height and left the body looking bleached -- pale cream
    // with colour only in the last third. A hearth flame is yellow where it is
    // fed and red where it is spending itself, and those two colours are the
    // whole gradient.
    const float3 straw = float3(1.00, 0.88, 0.42);
    const float3 gold  = float3(1.00, 0.66, 0.18);
    const float3 amber = float3(1.00, 0.38, 0.07);
    const float3 red   = float3(0.86, 0.13, 0.04);
    const float3 ash   = float3(0.45, 0.06, 0.03);

    float3 colour;
    if (heat < 0.28)      { colour = mix(straw, gold,  smoothstep(0.00, 0.28, heat)); }
    else if (heat < 0.58) { colour = mix(gold,  amber, smoothstep(0.28, 0.58, heat)); }
    else if (heat < 0.85) { colour = mix(amber, red,   smoothstep(0.58, 0.85, heat)); }
    else                  { colour = mix(red,   ash,   smoothstep(0.85, 1.00, heat)); }

    // A slow flare across the whole flame, on the same clock, so the colour
    // breathes with the shape rather than beside it.
    colour *= 0.94 + 0.12 * sin(params.time * 2.3);

    out.write(float4(colour, density), gid);
}

// ---------------------------------------------------------------------------
// Fire, the COLOUR half -- KEPT FOR THE WALL, not for the flame.
//
// The flame itself now carries its colour in the same texture as its density
// (above). This one stays because the proximity spotlight will want to PROJECT
// a ramp onto a real wall, and a projective texture is sampled by a light
// rather than worn by a surface -- a different job with a different channel
// layout.
// ---------------------------------------------------------------------------
// Fire, the COLOUR half -- KEPT FOR THE WALL, not for the flame.
//
// The flame itself now carries its colour in the same texture as its density
// (above). This one stays because the proximity spotlight will want to PROJECT
// a ramp onto a real wall, and a projective texture is sampled by a light
// rather than worn by a surface -- a different job with a different channel
// layout.
//
// A SECOND TEXTURE, and the reason is a channel. RealityKit samples an opacity
// texture's RED channel -- Apple's own shader listing for the equivalent custom
// material reads `tex.opacity().sample(...).r`. So density has to live in red,
// which means a single texture cannot carry both "how solid is the flame here"
// and "what colour is it", since every fire colour has red near the top of its
// range and the mask would come out nearly uniform.
//
// So density is one texture and colour is another, both driven from the same
// phase. This one carries no noise at all -- the ramp is a function of height
// and time -- so it is generated small and costs almost nothing.
// ---------------------------------------------------------------------------

kernel void fire_color_kernel(texture2d<float, access::write> out [[texture(0)]],
                              constant TextureParams &params [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) { return; }

    float v = 1.0 - float(gid.y) / float(params.height);

    // The ramp TRAVELS: heat rises through the flame rather than sitting in
    // bands, so the whole gradient is pushed up over time and wrapped. This is
    // the thing that makes a still image of a flame look alive in motion.
    float travel = fract(v - params.time * 0.22);
    // Mostly height, a little travel -- pure travel would be stripes marching
    // up a candle, which is a barber's pole rather than a fire.
    float h = clamp(v * 0.78 + travel * 0.22, 0.0, 1.0);

    // White heart -> gold -> orange -> ember red -> dark smoke at the very tip.
    const float3 heart = float3(1.00, 0.96, 0.86);
    const float3 gold  = float3(1.00, 0.78, 0.30);
    const float3 amber = float3(1.00, 0.46, 0.10);
    const float3 ember = float3(0.85, 0.16, 0.06);
    const float3 ash   = float3(0.42, 0.09, 0.05);

    float3 colour;
    if (h < 0.22)      { colour = mix(heart, gold,  smoothstep(0.00, 0.22, h)); }
    else if (h < 0.48) { colour = mix(gold,  amber, smoothstep(0.22, 0.48, h)); }
    else if (h < 0.76) { colour = mix(amber, ember, smoothstep(0.48, 0.76, h)); }
    else               { colour = mix(ember, ash,   smoothstep(0.76, 1.00, h)); }

    // A slow flare across the whole flame, on the same clock, so the colour
    // breathes with the shape rather than beside it.
    colour *= 0.92 + 0.14 * sin(params.time * 2.3);

    out.write(float4(colour, 1.0), gid);
}
