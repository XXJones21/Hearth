/*
 * The FaceDirector: everything about WHEN, nothing about HOW it is drawn.
 *
 * The avatar-lab reference treats an animation as a looping playlist of
 * expression presets with per-beat hold times, an energy-tiered blink
 * schedule, and perpetual micro-motion on the gaze. This module is that
 * model, mapped onto the four states the house already emits.
 *
 * It is deliberately renderer-free: the SVG component ticks it once per
 * frame and draws the pose it returns; a future three.js or RealityKit
 * face consumes the identical output. Time comes in as an argument so the
 * director is testable without a clock.
 *
 * Composition order per tick, each layer recomputed from scratch so
 * nothing accumulates: eased playlist pose -> saccade drift -> transient
 * cue -> blink -> speech mouth.
 * Design: tasks/persona-avatar-system.md; timing from the grok-bot lab.
 */

import {
  EXPRESSIONS,
  apply,
  neutralPose,
  type Expression,
  type ExpressionName,
  type FacePose,
} from './expressions';
import type { FaceGeometry } from '../../types/persona';

export type DirectorState = 'idle' | 'listening' | 'thinking' | 'speaking';

type Beat = { expr: Expression; ms: number };

type BlinkTier = {
  /** ms until the first blink after entering the state */
  first: number;
  /** randomized interval bounds, ms */
  min: number;
  max: number;
  /** full close-and-open time, ms */
  duration: number;
};

type FaceAnimation = { beats: Beat[]; blink: BlinkTier };

const E = EXPRESSIONS;
/** A state pose with extra deltas layered on, as one beat's target. */
const variant = (base: ExpressionName, extra: Expression): Expression => ({
  scale: { ...(E[base].scale ?? {}), ...(extra.scale ?? {}) },
  add: { ...(E[base].add ?? {}), ...(extra.add ?? {}) },
});

/* Timing lifted from the reference: calm states hold long beats and blink
   slowly; busy states change often and blink quickly. */
const CALM: BlinkTier = { first: 2600, min: 3400, max: 6200, duration: 280 };
const ATTENTIVE: BlinkTier = { first: 3200, min: 4800, max: 7200, duration: 240 };
const BUSY: BlinkTier = { first: 2100, min: 2800, max: 5000, duration: 260 };

/* Theatrical register (operator's choice 2026-08-15): each state has a
   silhouette you can name from across the room, full-cartoon gaze travel,
   and thinking changes fast. Gaze values here are in the renderer's
   clamped head-normalised space; +-1 is a hard look to one side. */
const ANIMATIONS: Record<DirectorState, FaceAnimation> = {
  /* Soft and unhurried, but never frozen: long holds, then a frank look
     away somewhere, once with a lazy half-lid. */
  idle: {
    beats: [
      { expr: E.neutral, ms: 4200 },
      { expr: variant('neutral', { add: { gaze_x: -0.85, gaze_y: 0.1, eye_tilt: -0.04, head_tilt: -0.02 } }), ms: 3200 },
      { expr: E.neutral, ms: 4200 },
      { expr: variant('neutral', { add: { gaze_x: 0.7, eyelid_l: 0.25, eyelid_r: 0.25, head_tilt: 0.02 } }), ms: 2800 },
    ],
    blink: CALM,
  },
  /* Attention, near the idle silhouette: a modest lift and a lean-in
     tilt; the look-target (the input box) does most of the telling. */
  listening: {
    beats: [
      { expr: variant('listening', { scale: { eye_length: 0.18, eye_size: 0.06 }, add: { head_tilt: 0.05 } }), ms: 2000 },
      { expr: variant('listening', { scale: { eye_length: 0.22, eye_size: 0.08 }, add: { gaze_y: -0.1, head_tilt: 0.04 } }), ms: 2000 },
      { expr: variant('listening', { scale: { eye_length: 0.15, eye_size: 0.05 }, add: { gaze_x: 0.15, eye_raise_l: -0.015, head_tilt: 0.06 } }), ms: 2000 },
    ],
    blink: ATTENTIVE,
  },
  /* Half-height eyes thrown up and to the sides, quick asymmetric beats,
     one flat-dash "processing" hold. */
  thinking: {
    beats: [
      { expr: variant('thinking', { scale: { eye_length: -0.15 }, add: { gaze_x: 0.9, gaze_y: -0.55 } }), ms: 1500 },
      { expr: variant('thinking', { add: { gaze_x: -0.95, gaze_y: -0.5, eye_raise_r: -0.03, head_tilt: -0.04 } }), ms: 1500 },
      { expr: variant('thinking', { add: { eyelid_l: 0.6, eye_scale_r: 0.25, gaze_x: 0.5, gaze_y: -0.4 } }), ms: 1400 },
      { expr: variant('thinking', { add: { eyelid_l: 0.75, eyelid_r: 0.75, gaze_x: 0, gaze_y: 0 } }), ms: 1300 },
      { expr: variant('thinking', { add: { gaze_x: -0.6, gaze_y: -0.6, eye_tilt_l: 0.08, head_tilt: 0.04 } }), ms: 1500 },
    ],
    blink: BUSY,
  },
  /* The mouth does the talking; the eyes stay engaged and mobile. */
  speaking: {
    beats: [
      { expr: variant('speaking', { scale: { eye_size: 0.1 } }), ms: 1800 },
      { expr: variant('speaking', { scale: { eye_size: 0.12 }, add: { gaze_x: 0.3, eye_tilt: -0.03, head_tilt: 0.02 } }), ms: 1800 },
      { expr: variant('speaking', { scale: { eye_size: 0.08 }, add: { gaze_x: -0.25, eye_raise_l: -0.015, head_tilt: -0.02 } }), ms: 1800 },
    ],
    blink: BUSY,
  },
};

/** ms of eased approach toward the current beat's pose. */
const EASE_TAU = 140;

/* A transient is a little performance, not just a pose: each cue carries a
   full envelope -- lerp IN over `attack`, hold, lerp OUT over `decay` --
   so reactions ease into the face and chain together naturally instead of
   popping. Ramps are smoothstepped. An optional motion layer (bounce, nod)
   rides on top; t is ms since the cue fired, w the current weight. */
type TransientProfile = {
  attack: number;
  hold: number;
  decay: number;
  motion?: (t: number, w: number) => Expression;
};
const DEFAULT_TRANSIENT: TransientProfile = { attack: 140, hold: 260, decay: 950 };
const TRANSIENTS: Record<string, TransientProfile> = {
  /* A physical chuckle: the whole face bounces fast and small while the
     happy arcs hold, like laughter shaking through the body. */
  laughter: {
    attack: 120,
    hold: 1600,
    decay: 650,
    motion: (t, w) => ({
      add: {
        head_bob: Math.sin((t / 135) * Math.PI * 2) * 0.04 * w,
        head_tilt: Math.sin((t / 270) * Math.PI * 2) * 0.018 * w,
      },
    }),
  },
  /* The yes-nod: two slow downward bobs under the contented arc-squint. */
  confirmation: {
    attack: 150,
    hold: 1250,
    decay: 500,
    motion: (t, w) => ({
      add: { head_bob: ((1 - Math.cos((t / 620) * Math.PI * 2)) / 2) * 0.11 * w },
    }),
  },
  /* A sigh settles in slowly and takes its time leaving. */
  sigh: { attack: 400, hold: 900, decay: 1100 },
  /* The startle: eyes lerp wide, hold a beat, lerp back. */
  surprise: { attack: 150, hold: 700, decay: 450 },
};

/** Smoothstepped 0..1 envelope for a transient's age. */
function transientWeight(age: number, p: TransientProfile): number {
  let w: number;
  if (age <= p.attack) w = p.attack > 0 ? age / p.attack : 1;
  else if (age <= p.attack + p.hold) w = 1;
  else w = Math.max(0, 1 - (age - p.attack - p.hold) / p.decay);
  return w * w * (3 - 2 * w);
}
/** Micro-saccades: small, quick, irregular. The gaze never sits dead. */
const SACCADE_MIN_MS = 900;
const SACCADE_MAX_MS = 2600;
const SACCADE_AMP_X = 0.18;
const SACCADE_AMP_Y = 0.1;
/** A slow breathing sway on the whole head -- the lab's "subtle living
 *  presence". Radians of head_tilt, sinusoidal. */
const SWAY_AMP = 0.014;
const SWAY_PERIOD_MS = 5200;

export type TransientCue = { name: string; at: number } | null;

/** A focal point in gaze space: x/y in [-1, 1] (right/down positive),
 *  focus 0..1 nearness. The renderer's host decides where it is -- the
 *  desktop points it at the composer input, a phone points it down at its
 *  own keyboard -- and the director looks there while listening. */
export type LookTarget = { x: number; y: number; focus: number } | null;

export class FaceDirector {
  private geometry: FaceGeometry;
  private pose: FacePose;
  private state: DirectorState = 'idle';
  private beatIndex = 0;
  private beatStartedAt = 0;
  private blinkStartedAt = -1;
  private nextBlinkAt: number;
  private saccade = { x: 0, y: 0 };
  private nextSaccadeAt: number;
  private last: number;

  constructor(geometry: FaceGeometry, now: number) {
    this.geometry = geometry;
    this.pose = neutralPose(geometry);
    this.beatStartedAt = now;
    this.nextBlinkAt = now + ANIMATIONS.idle.blink.first;
    this.nextSaccadeAt = now + SACCADE_MIN_MS;
    this.last = now;
  }

  /** One frame. Layers are recomputed every tick; only the eased base pose
   *  carries over between frames. */
  tick(
    now: number,
    state: DirectorState,
    cue: TransientCue,
    speechLevel: number,
    reduceMotion: boolean,
    lookTarget: LookTarget = null,
  ): FacePose {
    const dt = Math.min(100, now - this.last);
    this.last = now;

    const anim = ANIMATIONS[state];
    if (state !== this.state) {
      // Entering a state restarts its playlist and its blink schedule.
      this.state = state;
      this.beatIndex = 0;
      this.beatStartedAt = now;
      this.nextBlinkAt = now + anim.blink.first;
    }

    // Advance the playlist.
    const beat = anim.beats[this.beatIndex % anim.beats.length];
    if (now - this.beatStartedAt >= beat.ms) {
      this.beatIndex = (this.beatIndex + 1) % anim.beats.length;
      this.beatStartedAt = now;
    }
    const target = apply(this.geometry, anim.beats[this.beatIndex].expr, 1);

    // Ease every channel toward the beat's pose. Reduce motion snaps.
    const alpha = reduceMotion ? 1 : 1 - Math.exp(-dt / EASE_TAU);
    for (const key of Object.keys(this.pose) as (keyof FacePose)[]) {
      this.pose[key] += (target[key] - this.pose[key]) * alpha;
    }

    let frame: FacePose = { ...this.pose };

    // While listening, the face watches where the words are coming from:
    // the host's look target (the composer input on desktop, the keyboard
    // area on a phone) mostly overrides the beat's gaze, converged near.
    // Saccades still ride on top, so the watch stays alive.
    if (state === 'listening' && lookTarget) {
      frame = apply(
        frame,
        {
          add: {
            gaze_x: (lookTarget.x - frame.gaze_x) * 0.85,
            gaze_y: (lookTarget.y - frame.gaze_y) * 0.85,
            focus: (lookTarget.focus - frame.focus) * 0.85,
          },
        },
        1,
      );
    }

    // Micro-saccades: the gaze jumps a little at irregular intervals and
    // the easing above is what makes the jump read as a dart, not a snap.
    if (!reduceMotion) {
      if (now >= this.nextSaccadeAt) {
        this.saccade = {
          x: (Math.random() * 2 - 1) * SACCADE_AMP_X,
          y: (Math.random() * 2 - 1) * SACCADE_AMP_Y,
        };
        this.nextSaccadeAt =
          now + SACCADE_MIN_MS + Math.random() * (SACCADE_MAX_MS - SACCADE_MIN_MS);
      }
      frame = apply(frame, { add: { gaze_x: this.saccade.x, gaze_y: this.saccade.y } }, 1);
      // Breathing sway: continuous, slow, never still.
      frame = apply(
        frame,
        { add: { head_tilt: Math.sin((now * 2 * Math.PI) / SWAY_PERIOD_MS) * SWAY_AMP } },
        1,
      );
    }

    // The harness's transient cue: full weight through its hold, then a
    // decay -- with the cue's own motion envelope (chuckle bounce, nod)
    // riding on top while it plays.
    if (cue) {
      const age = now - cue.at;
      const profile = TRANSIENTS[cue.name] ?? DEFAULT_TRANSIENT;
      const weight = transientWeight(age, profile);
      if (weight > 0) {
        const expr = (EXPRESSIONS as Record<string, Expression>)[cue.name];
        if (expr) frame = apply(frame, expr, weight);
        if (profile.motion && !reduceMotion) {
          frame = apply(frame, profile.motion(age, weight), 1);
        }
      }
    }

    // Blink, on the state's energy tier. Suppressed under reduce motion;
    // lids still move with expressions that close them.
    if (!reduceMotion) {
      if (this.blinkStartedAt < 0 && now >= this.nextBlinkAt) this.blinkStartedAt = now;
      if (this.blinkStartedAt >= 0) {
        const w = blinkWeight(now - this.blinkStartedAt, anim.blink.duration);
        if (w === null) {
          this.blinkStartedAt = -1;
          this.nextBlinkAt =
            now + anim.blink.min + Math.random() * (anim.blink.max - anim.blink.min);
        } else {
          frame = apply(frame, EXPRESSIONS.blink, w);
        }
      }
    }

    // The mouth follows the sound itself, not the state -- and a talking
    // mouth is a clean round oval whose height rides the amplitude. A
    // partial crescent underlay looked like a beak; pure oval reads as
    // talking.
    if (speechLevel > 0.01) {
      frame = apply(frame, { add: { mouth_open: speechLevel, mouth_round: 1 } }, 1);
    }

    return frame;
  }
}

/** Quick close, slower open; null when the blink is over. */
function blinkWeight(sinceStart: number, duration: number): number | null {
  if (sinceStart < 0) return null;
  const close = duration * 0.42;
  if (sinceStart < close) return sinceStart / close;
  if (sinceStart < duration) return 1 - (sinceStart - close) / (duration - close);
  return null;
}
