/*
 * The expression library for procedural_face personas, shipped with the
 * harness rather than with any persona. Every entry is a set of DELTAS
 * against the persona's own geometry: `listening` lengthens whatever eyes
 * that persona has rather than setting them equal, which is the whole
 * reason a persona authors a dozen numbers instead of an animation set.
 *
 * The face is EYES-FIRST: two vertical capsules carry the character (the
 * grok-bot register -- squints, dashes, leans), there are no brows, and the
 * mouth only appears when speech amplitude or a transient opens it. So
 * expressions do their acting in the eye channels; mouth deltas exist for
 * the moments the mouth is on screen (speaking, laughter, surprise).
 *
 * Two kinds of delta, chosen per channel:
 *   scale -- multiplicative, for sizes: v * (1 + delta * weight). A big eye
 *            and a small eye change by the same PROPORTION.
 *   add   -- additive, for positions, angles, and pose channels:
 *            v + delta * weight. Normalised head units, same as geometry.
 *
 * Sign conventions:
 *   eye_tilt     radians, positive leans both capsules clockwise (italic)
 *   mouth_curve  positive = smile (the crescent's belly dips DOWN on screen)
 *   head_tilt    radians, positive = clockwise on screen
 *   gaze_x/y     head-normalised offset, positive = right/down
 *   eyelid       0 open .. 1 closed; closing collapses the capsule toward a
 *                horizontal dash rather than shrinking it to nothing
 *   mouth_open   0 closed .. 1 wide; speech amplitude drives it live
 *
 * Pure data + one pure function. No React, no DOM, no time.
 * Design: tasks/persona-avatar-system.md.
 */

import type { FaceGeometry } from '../../types/persona';

export type FacePose = FaceGeometry & {
  /** per-eye lid closure, 0 open .. 1 closed; blink drives both, an
   *  expression may drive one (the suspicious register) */
  eyelid_l: number;
  eyelid_r: number;
  /** HOW a closed eye closes: 0 = flat bar (neutral blink, boredom),
   *  +1 = upward happy arc (the anime ^ ^), -1 = downward sad arc (the
   *  pensive-emoji droop). Only visible while a lid is substantially
   *  closed. */
  eye_arc: number;
  /** Vergence: 0 = parallel gaze (focal point at infinity), 1 = fully
   *  converged on something right in front of the face. The seed of a real
   *  focal-point system -- gaze_x/y point the eyes, focus pulls them
   *  together toward the near point. */
  focus: number;
  /** Whole-face vertical bob in head units: the chuckle bounce, the nod.
   *  Driven by transient motion envelopes, never stored. */
  head_bob: number;
  /** per-eye proportional size multiplier, resting 1 (curious = one big,
   *  one small) */
  eye_scale_l: number;
  eye_scale_r: number;
  /** per-eye lean added on top of the shared eye_tilt, radians */
  eye_tilt_l: number;
  eye_tilt_r: number;
  /** per-eye vertical offset in head units, negative = raised */
  eye_raise_l: number;
  eye_raise_r: number;
  gaze_x: number;
  gaze_y: number;
  head_tilt: number;
  mouth_open: number;
  /** Mouth SHAPE while open: 0 = the smile/frown crescent, 1 = a rounded
   *  "o". Surprise is a full o; speech is mostly round (talking, not
   *  grinning); laughter stays a crescent grin. */
  mouth_round: number;
};

export type Expression = {
  /** multiplicative: v * (1 + delta * weight) */
  scale?: Partial<Record<keyof FacePose, number>>;
  /** additive: v + delta * weight */
  add?: Partial<Record<keyof FacePose, number>>;
};

export type ExpressionName =
  | 'neutral'
  | 'listening'
  | 'thinking'
  | 'speaking'
  | 'blink'
  | 'laughter'
  | 'sigh'
  | 'surprise'
  | 'question'
  | 'confirmation'
  | 'dissatisfaction';

export const EXPRESSIONS: Record<ExpressionName, Expression> = {
  /** The identity offset. Applying it at any weight returns the pose given. */
  neutral: {},

  /* ---- resting poses, one per state the house already emits ---- */

  /* Mild on purpose: focus sits in the message box for whole minutes, so
     this is a pose someone LIVES with. Slightly taller eyes, a hair of tilt. */
  listening: {
    scale: { eye_length: 0.12 },
    add: { head_tilt: 0.025 },
  },
  /* Shortened eyes glancing up and aside, with a small parallel lean --
     the capsule equivalent of narrowed eyes looking off-axis. */
  thinking: {
    scale: { eye_length: -0.35 },
    add: { eye_tilt: 0.1, gaze_x: 0.3, gaze_y: -0.2 },
  },
  /* The mouth does the talking (amplitude-driven); the eyes just brighten. */
  speaking: {
    scale: { eye_length: 0.05 },
  },

  /* ---- fired on a timer, not a state ---- */

  blink: {
    add: { eyelid_l: 1.0, eyelid_r: 1.0 },
  },

  /* ---- transients, resolved by the harness from non-verbal tags.
     EYES-ONLY by decision (2026-08-15): the mouth is reserved for the
     speech oval until it gets a proper design pass, so every reaction
     carries its whole meaning in the eyes -- overly expressive on
     purpose. Asymmetry is deliberate where it appears: matched eyes read
     as a machine, mismatched ones read as a creature. ---- */

  /* Full happy arcs with a merry lean; the chuckle bounce rides on the
     transient's motion envelope in the director. */
  laughter: {
    add: { eyelid_l: 0.9, eyelid_r: 0.9, eye_arc: 1, eye_tilt: -0.1, head_tilt: -0.06 },
  },
  /* The pensive-emoji droop: closed sad arcs, outer ends sinking. */
  sigh: {
    add: {
      eyelid_l: 0.85, eyelid_r: 0.85, eye_arc: -0.85,
      eye_tilt_l: -0.14, eye_tilt_r: 0.14, gaze_y: 0.15, head_tilt: 0.03,
    },
  },
  /* The startle: rounder eyes grown clearly larger, slightly raised and
     converged -- startled AT you. The director's envelope lerps this in,
     holds a beat, and lerps back out. */
  surprise: {
    scale: { eye_length: -0.3 },
    add: { eye_scale_l: 0.35, eye_scale_r: 0.35, eye_raise_l: -0.012, eye_raise_r: -0.012, focus: 0.3 },
  },
  /* The raised-brow emoji: one eye raised, the other narrowed smaller. */
  question: {
    scale: { eye_length: 0.15 },
    add: { eye_tilt: 0.15, eye_raise_l: -0.04, eye_scale_r: -0.18, eyelid_r: 0.2, head_tilt: 0.08, gaze_x: 0.2 },
  },
  /* A soft contented arc-squint; the yes-nod rides the motion envelope. */
  confirmation: {
    add: { eyelid_l: 0.6, eyelid_r: 0.6, eye_arc: 0.9, head_tilt: -0.03 },
  },
  /* The unamused emoji: both eyes equally half-lidded, gaze hard to one
     side, dead level. */
  dissatisfaction: {
    add: { eyelid_l: 0.55, eyelid_r: 0.55, gaze_x: 0.65 },
  },
};

/** A geometry at rest: motion channels zeroed. The two capsule channels
 *  default when absent, so a config written before the eyes-first schema
 *  (or by an older house) renders a face instead of NaN paths. */
export function neutralPose(geometry: FaceGeometry): FacePose {
  return {
    ...geometry,
    eye_length: geometry.eye_length ?? 2.2,
    eye_tilt: geometry.eye_tilt ?? 0,
    eyelid_l: 0,
    eyelid_r: 0,
    eye_arc: 0,
    focus: 0,
    head_bob: 0,
    eye_scale_l: 1,
    eye_scale_r: 1,
    eye_tilt_l: 0,
    eye_tilt_r: 0,
    eye_raise_l: 0,
    eye_raise_r: 0,
    gaze_x: 0,
    gaze_y: 0,
    head_tilt: 0,
    mouth_open: 0,
    mouth_round: 0,
  };
}

const POSE_ONLY: ReadonlyArray<keyof FacePose> = [
  'eyelid_l',
  'eyelid_r',
  'eye_arc',
  'focus',
  'head_bob',
  'eye_scale_l',
  'eye_scale_r',
  'eye_tilt_l',
  'eye_tilt_r',
  'eye_raise_l',
  'eye_raise_r',
  'gaze_x',
  'gaze_y',
  'head_tilt',
  'mouth_open',
  'mouth_round',
];

function isPose(g: FaceGeometry | FacePose): g is FacePose {
  return (g as FacePose).eyelid_l !== undefined;
}

/**
 * Resolve geometry (or an already-partly-posed face) + expression + weight
 * into a pose. Weight 0 is the input unchanged; 1 is the full expression.
 * Layering is applying again: state pose first, then a transient, then
 * blink, each with its own weight.
 */
export function apply(
  base: FaceGeometry | FacePose,
  expression: Expression,
  weight: number,
): FacePose {
  const pose = isPose(base) ? { ...base } : neutralPose(base);
  if (weight === 0) return pose;
  const w = Math.max(0, Math.min(1, weight));
  for (const [key, delta] of Object.entries(expression.scale ?? {})) {
    const k = key as keyof FacePose;
    pose[k] = pose[k] * (1 + (delta as number) * w);
  }
  for (const [key, delta] of Object.entries(expression.add ?? {})) {
    const k = key as keyof FacePose;
    pose[k] = pose[k] + (delta as number) * w;
  }
  // Channels with hard physical ranges stay in them, whatever was layered.
  pose.eyelid_l = Math.max(0, Math.min(1, pose.eyelid_l));
  pose.eyelid_r = Math.max(0, Math.min(1, pose.eyelid_r));
  pose.eye_arc = Math.max(-1, Math.min(1, pose.eye_arc));
  pose.focus = Math.max(0, Math.min(1, pose.focus));
  pose.mouth_open = Math.max(0, Math.min(1, pose.mouth_open));
  pose.mouth_round = Math.max(0, Math.min(1, pose.mouth_round));
  return pose;
}

/** Convenience for the renderer: resolve a name, unknown names are neutral
 *  (a harness ahead of this client must not break the face). */
export function applyNamed(
  base: FaceGeometry | FacePose,
  name: string,
  weight: number,
): FacePose {
  const expression = (EXPRESSIONS as Record<string, Expression>)[name] ?? EXPRESSIONS.neutral;
  return apply(base, expression, weight);
}

export { POSE_ONLY };
