/*
 * Pose -> SVG path data. Pure functions, no React, no DOM: the component
 * feeds these strings into <path d= ...> and owns everything about time.
 *
 * Coordinate space: a square viewBox, head centred, all pose values
 * normalised against the head's own bounding box. SIZE only scales the
 * numbers put into the path strings; nothing downstream may assume pixels.
 *
 * Shape choices (the eyes-first, grok-bot register):
 *   head   a squircle: four cubic segments whose handle length morphs with
 *          head_roundness (0.552 draws a circle; shorter handles go boxy).
 *   eyes   two vertical capsules; the whole character lives here. eyelid
 *          collapses the capsule's height while widening it a little, so a
 *          closed eye reads as a horizontal DASH, not a missing element.
 *          eye_tilt leans both capsules in parallel (the italic look);
 *          gaze shifts them instead of drawing pupils.
 *   brows  none. Deliberate: brows are where an abstract face starts
 *          looking like a judging human.
 *   mouth  one closed crescent that opens with mouth_open. The component
 *          hides it entirely at rest (opacity from mouth_open), so the
 *          resting face is eyes-only.
 *
 * head_tilt is returned as a transform for the whole group; each eye also
 * gets its own rotate() for eye_tilt, because a path cannot lean itself.
 * Design: tasks/persona-avatar-system.md.
 */

import type { FacePose } from './expressions';

export type FacePaths = {
  head: string;
  leftEye: string;
  rightEye: string;
  /** rotate() for each capsule's lean, applied on the eye path itself */
  leftEyeTransform: string;
  rightEyeTransform: string;
  /** specular glints -- the light dots that make an eye read as wet and
   *  alive rather than a hole. Fade out as the lids close. */
  leftGlint: string;
  rightGlint: string;
  glintOpacity: number;
  /** The smile/frown crescent. Crossfaded with mouthRound by mouth_round. */
  mouth: string;
  /** The rounded "o" -- surprise's oh, speech's talking oval. */
  mouthRound: string;
  /** SVG transform for the whole face group (head_tilt). */
  transform: string;
  viewBox: string;
};

const fmt = (n: number): string => (Math.round(n * 100) / 100).toString();

/** Rounded rect that degrades to a capsule in either orientation. */
function capsulePath(cx: number, cy: number, halfW: number, halfH: number): string {
  halfW = Math.max(0.5, halfW);
  halfH = Math.max(0.5, halfH);
  const r = Math.min(halfW, halfH);
  return (
    `M ${fmt(cx - halfW + r)} ${fmt(cy - halfH)}` +
    ` L ${fmt(cx + halfW - r)} ${fmt(cy - halfH)}` +
    ` A ${fmt(r)} ${fmt(r)} 0 0 1 ${fmt(cx + halfW)} ${fmt(cy - halfH + r)}` +
    ` L ${fmt(cx + halfW)} ${fmt(cy + halfH - r)}` +
    ` A ${fmt(r)} ${fmt(r)} 0 0 1 ${fmt(cx + halfW - r)} ${fmt(cy + halfH)}` +
    ` L ${fmt(cx - halfW + r)} ${fmt(cy + halfH)}` +
    ` A ${fmt(r)} ${fmt(r)} 0 0 1 ${fmt(cx - halfW)} ${fmt(cy + halfH - r)}` +
    ` L ${fmt(cx - halfW)} ${fmt(cy - halfH + r)}` +
    ` A ${fmt(r)} ${fmt(r)} 0 0 1 ${fmt(cx - halfW + r)} ${fmt(cy - halfH)} Z`
  );
}

/** Squircle: four cubics, handle length morphing circle -> rounded box. */
function squirclePath(cx: number, cy: number, rx: number, ry: number, roundness: number): string {
  const t = Math.max(0, Math.min(1, roundness));
  // 0.5523 is the magic circle constant; 0.30 reads as a soft rectangle.
  const k = 0.3 + (0.5523 - 0.3) * t;
  const kx = rx * (1 - k);
  const ky = ry * (1 - k);
  return (
    `M ${fmt(cx)} ${fmt(cy - ry)}` +
    ` C ${fmt(cx + rx - kx)} ${fmt(cy - ry)} ${fmt(cx + rx)} ${fmt(cy - ry + ky)} ${fmt(cx + rx)} ${fmt(cy)}` +
    ` C ${fmt(cx + rx)} ${fmt(cy + ry - ky)} ${fmt(cx + rx - kx)} ${fmt(cy + ry)} ${fmt(cx)} ${fmt(cy + ry)}` +
    ` C ${fmt(cx - rx + kx)} ${fmt(cy + ry)} ${fmt(cx - rx)} ${fmt(cy + ry - ky)} ${fmt(cx - rx)} ${fmt(cy)}` +
    ` C ${fmt(cx - rx)} ${fmt(cy - ry + ky)} ${fmt(cx - rx + kx)} ${fmt(cy - ry)} ${fmt(cx)} ${fmt(cy - ry)} Z`
  );
}

export function facePaths(pose: FacePose, size = 200): FacePaths {
  const cx = size / 2;
  const cy = size / 2;
  // The head's half-extents. 0.38 leaves air for head tilt.
  const hw = size * 0.38 * pose.head_width;
  const hh = size * 0.38 * pose.head_height;

  const head = squirclePath(cx, cy, hw, hh, pose.head_roundness);

  // Eyes: vertical capsules, each with its own lid, size, lean, and lift --
  // matched eyes read as a machine, mismatched ones as a creature.
  const eyeY = cy - hh + pose.eye_height * (2 * hh);
  const eyeDx = pose.eye_spacing * hw;
  // Theatrical gaze travel: the eyes genuinely move around the face (the
  // Pokemon register), clamped so they never cross the head's outline at
  // the height they sit at.
  const baseHalfW = pose.eye_size * hw;
  const dyEye = Math.min(0.95, Math.abs(cy - eyeY) / hh);
  const halfWidthAtEye = hw * Math.sqrt(Math.max(0.05, 1 - dyEye * dyEye));
  const gxMax = Math.max(0, halfWidthAtEye - eyeDx - baseHalfW * 1.6);
  const gx = Math.max(-gxMax, Math.min(gxMax, pose.gaze_x * hw * 0.45));
  const gy = pose.gaze_y * hh * 0.3;
  const arc = Math.max(-1, Math.min(1, pose.eye_arc));
  const eyeShape = (
    ecx: number,
    ecy: number,
    lid: number,
    scale: number,
  ): string => {
    const l = Math.min(1, lid);
    const s = Math.max(0.2, scale);
    const halfW = baseHalfW * s;
    const closedness = l * Math.abs(arc);
    if (closedness > 0.35) {
      // The arc close: a thick band bowing UP for joy (the anime ^) or
      // DOWN for the pensive droop, scaled by how closed the lid is so it
      // eases in rather than popping.
      const w = halfW * 1.45;
      const lift = halfW * 1.5 * l * Math.sign(arc);
      const band = Math.max(2, halfW * 0.62);
      const endY = ecy + band * 0.4 * Math.sign(arc);
      return (
        `M ${fmt(ecx - w)} ${fmt(endY)}` +
        ` Q ${fmt(ecx)} ${fmt(ecy - lift)} ${fmt(ecx + w)} ${fmt(endY)}` +
        ` Q ${fmt(ecx)} ${fmt(ecy - lift + band)} ${fmt(ecx - w)} ${fmt(endY)} Z`
      );
    }
    // Neutral close: the capsule collapses to a thick stubby bar at its own
    // width -- never a spindly hyphen (the first cut widened while it
    // thinned and mid-blink read as a rendering bug).
    const halfH = Math.max(
      halfW * 0.55,
      halfW * Math.max(0.2, pose.eye_length) * (1 - l * 0.95),
    );
    return capsulePath(ecx, ecy, halfW, halfH);
  };
  // Vergence: focus pulls both eyes toward a shared near point, so a
  // focused face converges slightly instead of staring in parallel past
  // you. The seed of the focal-point system; gaze aims it, focus nears it.
  const converge = pose.focus * baseHalfW * 0.55;
  const leftCx = cx - eyeDx + gx + converge;
  const rightCx = cx + eyeDx + gx - converge;
  const leftCy = eyeY + gy + pose.eye_raise_l * (2 * hh);
  const rightCy = eyeY + gy + pose.eye_raise_r * (2 * hh);
  const leftEye = eyeShape(leftCx, leftCy, pose.eyelid_l, pose.eye_scale_l);
  const rightEye = eyeShape(rightCx, rightCy, pose.eyelid_r, pose.eye_scale_r);
  // Shared lean plus each eye's own, per the reference's local rotation.
  const tiltL = ((pose.eye_tilt + pose.eye_tilt_l) * 180) / Math.PI;
  const tiltR = ((pose.eye_tilt + pose.eye_tilt_r) * 180) / Math.PI;
  const leftEyeTransform = `rotate(${fmt(tiltL)} ${fmt(leftCx)} ${fmt(leftCy)})`;
  const rightEyeTransform = `rotate(${fmt(tiltR)} ${fmt(rightCx)} ${fmt(rightCy)})`;

  // Specular glints: one light dot per eye, up-gaze-ward of centre, gone
  // once the lids are half closed (a closed eye has no wet surface).
  const maxLid = Math.max(pose.eyelid_l, pose.eyelid_r);
  const glintR = baseHalfW * 0.3;
  const glintDx = -baseHalfW * 0.28 + pose.gaze_x * baseHalfW * 0.35;
  const glintDy = -baseHalfW * Math.max(0.2, pose.eye_length) * 0.42 + pose.gaze_y * baseHalfW * 0.3;
  const leftGlint = capsulePath(leftCx + glintDx, leftCy + glintDy, glintR, glintR);
  const rightGlint = capsulePath(rightCx + glintDx, rightCy + glintDy, glintR, glintR);
  const glintOpacity = Math.max(0, 1 - maxLid * 2);

  // Mouth: one closed shape. Top lip bends with the smile; the bottom lip
  // falls away with mouth_open. Hidden at rest by the component (opacity),
  // so its geometry only matters while speech or a transient shows it.
  const mouthY = cy + hh * 0.42;
  const mouthHalf = pose.mouth_width * hw;
  // A smile's corners turn up and its centre dips below them: positive
  // mouth_curve pushes the crescent's belly DOWN in SVG's y-down space.
  const curve = pose.mouth_curve * hh * 0.5;
  const thickness = Math.max(size * 0.008, pose.mouth_thickness * 2 * hh);
  const open = pose.mouth_open * hh * 0.42;
  const mouth =
    `M ${fmt(cx - mouthHalf)} ${fmt(mouthY)}` +
    ` Q ${fmt(cx)} ${fmt(mouthY + curve)} ${fmt(cx + mouthHalf)} ${fmt(mouthY)}` +
    ` Q ${fmt(cx)} ${fmt(mouthY + curve + thickness + open)} ${fmt(cx - mouthHalf)} ${fmt(mouthY)} Z`;
  // The round "o": an ellipse-ish capsule whose height follows mouth_open.
  // The component crossfades crescent<->round by mouth_round, so the two
  // shapes never have to morph into each other path-by-path.
  const roundH = Math.max(1.5, (thickness + open) * 0.55);
  const roundW = mouthHalf * 0.5;
  const mouthRound = capsulePath(cx, mouthY + roundH * 0.25, roundW, roundH);

  const tiltDeg = (pose.head_tilt * 180) / Math.PI;
  const bobY = pose.head_bob * hh;

  return {
    head,
    leftEye,
    rightEye,
    leftEyeTransform,
    rightEyeTransform,
    leftGlint,
    rightGlint,
    glintOpacity,
    mouth,
    mouthRound,
    transform: `translate(0 ${fmt(bobY)}) rotate(${fmt(tiltDeg)} ${fmt(cx)} ${fmt(cy)})`,
    viewBox: `0 0 ${size} ${size}`,
  };
}
