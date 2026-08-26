import { useEffect, useRef } from 'react';
import { FaceDirector } from '../lib/face/director';
import { facePaths } from '../lib/face/geometry';
import { ttsPlayer } from '../lib/audioPlayer';
import { loadSettings, SETTINGS_EVENT } from '../lib/settings';
import { useAppStore, type VisualizerState } from '../store/appStore';
import type { FaceGeometry } from '../types/persona';

/*
 * The canvas flame -- the desktop build of wiki/raw/persona-flame-spec.md's
 * 2D recipe, the same character the phones draw: one body path with one
 * gradient, a bounded destination-out tip feather (the Compose lesson: an
 * erase has to be bounded, or it takes the halo with it -- so the body, the
 * licks and the feather share one offscreen layer), three licks standing in
 * for the noise field, the persona's own face drawn on top in features-only
 * flat black, additive embers, and the halo.
 *
 * The profile arithmetic is copied exactly from the spec and matches every
 * other client: it IS the shape. One clock through every layer, supplied by
 * the rAF timestamp -- a canvas does not animate itself.
 */

const DOME_TOP = 0.3;
const TURBULENCE = 0.22;
const SWAY = 0.18;
const EYE_V = 0.45;
const EMBER_COUNT = 46;
const EDGE_STEPS = 40;

/**
 * The fire, in CSS pixels, and FIXED.
 *
 * It used to be sized off the canvas box, which meant a wider window drew a
 * bigger Sulivan. That is right for the headset, where he stands in a room at
 * his own scale, and wrong here: on a desktop he is a character on a shelf, so
 * a wider window should give him more room around him, not more of him.
 *
 * Three numbers, each judged on a screen rather than derived. HEIGHT is the
 * drawn height of the body; RADIUS is the base radius everything else keys off
 * (the licks, the ember spread, and the face at R * 2.5); HALO_RADIUS is the
 * glow, deliberately kept at the footprint the fire had before it was cut down,
 * because the light was already the right size and only the thing casting it
 * was wrong.
 */
// Proportion measured off the iOS client, which is the look to match: the
// body there is ~1.55 tall for every 1 wide, a squat egg rather than a taper.
// H / R therefore wants to sit near 3.1; at 3.7 it reads as a candle flame.
const FIRE_HEIGHT_CSS = 130;
const FIRE_RADIUS_CSS = 42;
const HALO_RADIUS_CSS = 68;

const smoothstep = (a: number, b: number, x: number): number => {
  const t = Math.max(0, Math.min(1, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};

/** width(v) in units of the base radius. Fattest LOW. */
function profileWidth(v: number): number {
  if (v < DOME_TOP) return Math.sin((v / DOME_TOP) * (Math.PI / 2));
  const t = (v - DOME_TOP) / (1 - DOME_TOP);
  return Math.pow(Math.max(1 - t * t, 0), 0.45);
}

/** rise(v) in px: the height curves with the width across the dome. */
function profileRise(v: number, radius: number, height: number): number {
  const base = -radius * 0.95;
  if (v < DOME_TOP) return base + radius * 0.95 * (1 - Math.cos((v / DOME_TOP) * (Math.PI / 2)));
  const t = (v - DOME_TOP) / (1 - DOME_TOP);
  return base + radius * 0.95 + (height - radius * 0.95) * t;
}

/** Trig noise, seamless in angle, damped to nothing at the base. */
function wobble(a: number, v: number, p: number): number {
  return (
    ((Math.sin(3 * a + p * 2.1 + v * 5.0) +
      Math.sin(5 * a - p * 1.6 + v * 8.0) * 0.55 +
      Math.sin(8 * a + p * 2.9 - v * 3.0) * 0.3) /
      1.85) *
    smoothstep(0.3, 1.0, v)
  );
}

const breath = (p: number): number => 1 + 0.012 * Math.sin(p * 1.6);
const lean = (v: number, radius: number, p: number): number =>
  SWAY * radius * v * v * Math.sin(p * 1.7);

/** Three sines at incommensurable rates. A correlation, not a measurement. */
function flicker(t: number): number {
  const s = Math.sin(t * 2.7) * 0.5 + Math.sin(t * 4.3 + 1.7) * 0.3 + Math.sin(t * 9.1 + 0.4) * 0.2;
  return 0.5 + 0.5 * Math.max(-1, Math.min(1, s));
}

/** The five stops the shader ramp uses, at the same positions. */
const STOPS: Array<[number, string]> = [
  [0.0, 'rgb(255, 224, 107)'], // straw
  [0.28, 'rgb(255, 168, 46)'], // gold
  [0.58, 'rgb(255, 97, 18)'], // amber
  [0.85, 'rgb(219, 33, 10)'], // red
  [1.0, 'rgb(115, 15, 8)'], // ash
];

/** The two SVG transform shapes facePaths emits, replayed onto the context. */
const nums = (s: string): number[] => (s.match(/-?\d+\.?\d*/g) || []).map(Number);

function applySvgTransform(ctx: CanvasRenderingContext2D, transform: string): void {
  const t = /translate\(([^)]+)\)/.exec(transform);
  if (t) {
    const [tx, ty] = nums(t[1]);
    ctx.translate(tx || 0, ty || 0);
  }
  const r = /rotate\(([^)]+)\)/.exec(transform);
  if (r) {
    const [deg, cx, cy] = nums(r[1]);
    ctx.translate(cx || 0, cy || 0);
    ctx.rotate(((deg || 0) * Math.PI) / 180);
    ctx.translate(-(cx || 0), -(cy || 0));
  }
}

type Ember = { born: number; life: number; angle: number; v0: number; spin: number };

const seedEmber = (now: number, i: number): Ember => ({
  born: now - Math.random() * 2.5,
  life: 1.8 + Math.random() * 1.6,
  angle: Math.random() * Math.PI * 2,
  v0: 0.5 + Math.random() * 0.4,
  spin: (i % 2 === 0 ? 1 : -1) * (0.4 + Math.random() * 0.5),
});

type Props = {
  geometry: FaceGeometry;
  visualState: VisualizerState;
};

export function PersonaFlame({ geometry, visualState }: Props) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const stateRef = useRef<VisualizerState>(visualState);
  stateRef.current = visualState;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const layer = document.createElement('canvas');
    const layerCtx = layer.getContext('2d');
    if (!layerCtx) return;

    const director = new FaceDirector(geometry, performance.now());
    let reduceMotion = loadSettings().reduceMotion;
    const syncSettings = () => {
      reduceMotion = loadSettings().reduceMotion;
    };
    window.addEventListener(SETTINGS_EVENT, syncSettings);

    const embers = Array.from({ length: EMBER_COUNT }, (_, i) => seedEmber(0, i));

    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const resize = () => {
      const w = canvas.clientWidth || 1;
      const h = canvas.clientHeight || 1;
      canvas.width = Math.round(w * dpr);
      canvas.height = Math.round(h * dpr);
      layer.width = canvas.width;
      layer.height = canvas.height;
    };
    resize();
    const observer = new ResizeObserver(resize);
    observer.observe(canvas);

    let raf = 0;
    const start = performance.now();

    /** One meridian of the silhouette, in px, at this instant. */
    const edgeX = (side: 1 | -1, v: number, R: number, phase: number): number => {
      const a = side === 1 ? 0 : Math.PI;
      const w = R * profileWidth(v) * breath(phase) * (1 + TURBULENCE * wobble(a, v, phase));
      return side * w + lean(v, R, phase);
    };

    const bodyPath = (
      cx: number,
      yBase: number,
      R: number,
      H: number,
      phase: number,
      widthScale: number,
      heightScale: number,
      seed: number,
    ): Path2D => {
      const p = new Path2D();
      for (let i = 0; i <= EDGE_STEPS; i++) {
        const v = i / EDGE_STEPS;
        const x = cx + edgeX(1, v, R * widthScale, phase + seed) + (seed ? wobble(seed, 0.5, phase) * R * 0.3 : 0);
        const y = yBase - profileRise(v, R, H * heightScale);
        if (i === 0) p.moveTo(x, y);
        else p.lineTo(x, y);
      }
      for (let i = EDGE_STEPS; i >= 0; i--) {
        const v = i / EDGE_STEPS;
        const x = cx + edgeX(-1, v, R * widthScale, phase + seed) + (seed ? wobble(seed, 0.5, phase) * R * 0.3 : 0);
        const y = yBase - profileRise(v, R, H * heightScale);
        p.lineTo(x, y);
      }
      p.closePath();
      return p;
    };

    const frameBody = (now: number) => {
      const phase = (now - start) / 1000;
      const state = stateRef.current;
      const level = ttsPlayer.level();
      const W = canvas.width;
      const Hpx = canvas.height;
      if (W === 0 || Hpx === 0) return;

      // Layout: rise spans [-0.95R, H - 0.95R], so the drawn flame is H tall
      // with the dome's bottom 0.95R BELOW the base line. Sized like the
      // phones: the fire holds the middle of the box with air around it for
      // the halo and the ember plume, not a fill.
      //
      // Fixed size in CSS px, lifted to device px. The box still decides WHERE
      // the fire sits (cx, yBase below), never how big it is.
      const H = FIRE_HEIGHT_CSS * dpr;
      const R = FIRE_RADIUS_CSS * dpr;
      const R0 = HALO_RADIUS_CSS * dpr;
      const cx = W / 2;
      const yBase = Hpx * 0.72 - R * 0.95;
      const yAt = (v: number) => yBase - profileRise(v, R, H);
      const yTip = yAt(1);

      ctx.clearRect(0, 0, W, Hpx);

      // 8. The halo, behind everything. A screen has no walls, so the glow
      // is where the fire's never-still light lives.
      const glowA = 0.28 + 0.3 * flicker(phase);
      const halo = ctx.createRadialGradient(cx, yAt(0.35), R0 * 0.2, cx, yAt(0.35), R0 * 2.6);
      halo.addColorStop(0, `rgba(255, 180, 80, ${glowA})`);
      halo.addColorStop(1, 'rgba(255, 140, 40, 0)');
      ctx.fillStyle = halo;
      ctx.fillRect(0, 0, W, Hpx);

      // Body + licks + feather share one layer, so the erase is bounded.
      layerCtx.clearRect(0, 0, W, Hpx);
      const body = bodyPath(cx, yBase, R, H, phase, 1, 1, 0);
      const grad = layerCtx.createLinearGradient(0, yBase, 0, yTip);
      for (const [at, color] of STOPS) grad.addColorStop(at, color);
      layerCtx.fillStyle = grad;
      layerCtx.fill(body);

      // 5. The licks: three narrower flames inside, standing in for the
      // noise field. Three reads as structure; more is a wash.
      layerCtx.save();
      layerCtx.clip(body);
      for (let li = 0; li < 3; li++) {
        const seed = 2.3 + li * 1.7;
        const lick = bodyPath(cx, yBase, R, H, phase * 1.15, 0.3 + li * 0.12, 0.7 + li * 0.1, seed);
        const lg = layerCtx.createLinearGradient(0, yBase, 0, yBase - H * 0.9);
        lg.addColorStop(0, 'rgba(255, 236, 150, 0.34)');
        lg.addColorStop(1, 'rgba(255, 236, 150, 0)');
        layerCtx.fillStyle = lg;
        layerCtx.fill(lick);
      }
      layerCtx.restore();

      // 4. The tip feather: a real erase, bounded to this layer. The path
      // ends in a point and a point is the one shape a flame never has.
      layerCtx.save();
      layerCtx.globalCompositeOperation = 'destination-out';
      const feather = layerCtx.createLinearGradient(0, yAt(0.88), 0, yAt(0.99));
      feather.addColorStop(0, 'rgba(0, 0, 0, 0)');
      feather.addColorStop(1, 'rgba(0, 0, 0, 1)');
      layerCtx.fillStyle = feather;
      layerCtx.fillRect(0, 0, W, Math.max(0, yAt(0.88)));
      layerCtx.restore();

      ctx.drawImage(layer, 0, 0);

      // 7. The embers: additive dots, born ACROSS the body via the
      // silhouette, rising past the tip, spreading with t squared,
      // shrinking as they cool.
      ctx.save();
      ctx.globalCompositeOperation = 'lighter';
      const speaking = state === 'speaking';
      const speedMul = state === 'listening' ? 1.5 : 1.0;
      const whirl = state === 'thinking' ? 1.6 : 0;
      for (let i = 0; i < EMBER_COUNT; i++) {
        const e = embers[i];
        let t = (phase - e.born) / (e.life / speedMul);
        if (t >= 1) {
          embers[i] = seedEmber(phase, i);
          t = 0;
        }
        let x: number;
        let y: number;
        if (speaking) {
          // The ring: a level meter you can walk around; only the signal moves.
          const a = e.angle + phase * 0.25 * e.spin;
          x = cx + Math.cos(a) * R * (1.15 + level * 0.9);
          y = yAt(EYE_V) + Math.sin(phase * 1.3 + i) * R * 0.05;
        } else {
          const a = e.angle + phase * whirl * e.spin;
          const born = R * profileWidth(e.v0) * (state === 'listening' ? 0.5 : 0.8);
          const spread = born + t * t * R * 0.9;
          x = cx + Math.cos(a) * spread + lean(e.v0, R, phase);
          y = yAt(e.v0) - t * (yAt(e.v0) - yTip + R * 0.7);
        }
        const cool = Math.max(0, 1 - t);
        const size = R * 0.045 * (1 - t * 0.75);
        ctx.fillStyle = `rgba(255, 170, 60, ${0.75 * cool * (speaking ? 0.5 + level : 1)})`;
        ctx.beginPath();
        ctx.arc(x, y, Math.max(0.5, size), 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.restore();

      // 6. The face: features only, flat black, drawn on top. A filled head
      // over a fire is a persona standing IN FRONT OF a flame; warm brown
      // ink washes out exactly where the body is brightest.
      const pose = director.tick(
        now,
        state,
        useAppStore.getState().faceCue,
        level,
        reduceMotion,
        null,
      );
      const S = R * 2.5;
      const p = facePaths(pose, S);
      ctx.save();
      ctx.translate(cx - S / 2 + lean(EYE_V, R, phase) * 0.6, yAt(EYE_V) - S * 0.42);
      applySvgTransform(ctx, p.transform);
      ctx.fillStyle = '#000000';
      for (const [d, tr] of [
        [p.leftEye, p.leftEyeTransform],
        [p.rightEye, p.rightEyeTransform],
      ] as const) {
        ctx.save();
        applySvgTransform(ctx, tr);
        ctx.fill(new Path2D(d));
        ctx.restore();
      }
      // The glints ride the same eye transforms and fade as the lids close,
      // exactly as on the SVG face -- a wet eye reads as alive, and on flat
      // black ink the warm-white dot survives the bright gold behind it.
      if (p.glintOpacity > 0.01) {
        ctx.fillStyle = '#FDF8F1';
        ctx.globalAlpha = p.glintOpacity;
        for (const [d, tr] of [
          [p.leftGlint, p.leftEyeTransform],
          [p.rightGlint, p.rightEyeTransform],
        ] as const) {
          ctx.save();
          applySvgTransform(ctx, tr);
          ctx.fill(new Path2D(d));
          ctx.restore();
        }
        ctx.globalAlpha = 1;
      }
      const mouthVis = Math.min(1, pose.mouth_open * 4);
      if (mouthVis > 0.01) {
        ctx.globalAlpha = mouthVis * (1 - pose.mouth_round);
        ctx.fill(new Path2D(p.mouth));
        ctx.globalAlpha = mouthVis * pose.mouth_round;
        ctx.fill(new Path2D(p.mouthRound));
        ctx.globalAlpha = 1;
      }
      ctx.restore();
    };

    const step = (now: number) => {
      // A rAF exception ends the chain silently and freezes the fire in its
      // last pose; skip the frame instead and keep the loop alive.
      try {
        frameBody(now);
      } catch {
        /* keep the loop alive */
      }
      raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);

    return () => {
      cancelAnimationFrame(raf);
      observer.disconnect();
      window.removeEventListener(SETTINGS_EVENT, syncSettings);
    };
  }, [geometry]);

  return <canvas ref={canvasRef} className="h-full w-full" role="img" aria-label="Persona flame" />;
}
