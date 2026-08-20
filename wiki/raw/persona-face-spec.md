---
title: Persona Face (procedural_face)
status: canonical
last_reviewed: 2026-08-15
related:
  - persona-flame-spec.md
  - clients/desktop-client.md
  - architecture/harness/valar.md
  - architecture/engram-knowledge-system.md
sources:
  - tasks/persona-avatar-system.md
  - https://github.com/smontlouis/bible-strong-avatar-lab
---

# Persona Face (procedural_face)

An expressive procedural face for personas, driven by the state machine the
house already runs. Eyes-first in the grok-bot register: two vertical
capsules carry the whole character, there are no brows, and the mouth only
appears while the voice is actually producing sound. Built 2026-08-15 on the
desktop client; the data model is client-neutral so Hearth and the iOS
RealityKit renderer consume the same persona config and the same motion
design. Original design: `tasks/persona-avatar-system.md`. Timing and
register reference: the bible-strong avatar lab's grok bot and the Pokemon
Let's Go partner interactions.

## The data model

### What a persona stores (appearance only)

`visualization.type = "procedural_face"` plus a `geometry` block of eleven
normalised numbers -- no motion, ever:

```json
"visualization": {
  "type": "procedural_face",
  "archetype": "warm_round",
  "geometry": {
    "head_width": 1.0, "head_height": 1.05, "head_roundness": 0.8,
    "eye_size": 0.1, "eye_spacing": 0.38, "eye_height": 0.45,
    "eye_length": 2.4, "eye_tilt": 0.0,
    "mouth_width": 0.34, "mouth_thickness": 0.05, "mouth_curve": 0.26
  },
  "state_colors": { "idle": {"r":0.89,"g":0.604,"b":0.357}, "...": {} }
}
```

Every value is normalised against the head's own bounding box, so a face is
resolution-independent. `eye_size` is the capsule's half-width as a fraction
of the head's half-width; `eye_length` is its height as a multiple of its
width (1 is a dot, ~2.4 a tall pill); `eye_tilt` is a resting parallel lean
in radians. Colour is NOT stored in geometry: the face's ink follows the
persona accent and washes toward `state_colors` per state, the same block
the orb glow reads.

Archetypes (complete geometry blocks a new persona starts from) live in
`Persona/_visual/archetypes.json`: `warm_round` (Sulivan-adjacent),
`narrow_precise` (Selene-adjacent), `wide_open`. Orb presets snapshotted
before migration live in `Persona/_visual/presets/` (restoring Sulivan's
orb is one copy).

### The pose (geometry + motion channels)

The renderer never draws geometry directly; it draws a `FacePose` =
geometry plus the channels only motion owns. Per-eye channels are the charm
layer -- matched eyes read as a machine, mismatched as a creature:

| Channel | Meaning |
| --- | --- |
| `eyelid_l/r` | per-eye closure, 0 open .. 1 closed |
| `eye_arc` | HOW a closed eye closes: +1 happy arc `^`, 0 flat bar, -1 sad droop |
| `eye_scale_l/r` | per-eye proportional size multiplier (resting 1) |
| `eye_tilt_l/r` | per-eye lean added to the shared `eye_tilt` |
| `eye_raise_l/r` | per-eye vertical lift in head units |
| `gaze_x/y` | shared gaze direction, [-1, 1] |
| `focus` | vergence: 0 parallel, 1 converged on a near point |
| `head_tilt` | whole-face rotation, radians |
| `head_bob` | whole-face vertical bob (chuckle bounce, nod) |
| `mouth_open` | 0 closed .. 1 wide; speech amplitude drives it live |
| `mouth_round` | mouth shape when open: 0 smile crescent, 1 round "o" |

## The expression library

One library, versioned with the harness, in
`hearth-client/src/lib/face/expressions.ts`. Every entry is a set of
DELTAS against the persona's own geometry (`scale` = multiplicative for
sizes, `add` = additive for positions/angles/pose channels), so `listening`
lengthens whatever eyes a persona has instead of setting them equal.
`apply(base, expression, weight)` is pure; layering is applying again.

Eleven names. The four states (`neutral`, `listening`, `thinking`,
`speaking`) are resting poses; `blink` is timer-driven; the six transients
map 1:1 to the non-verbal performance tags: `laughter`, `sigh`, `surprise`,
`question`, `confirmation`, `dissatisfaction`.

**Reactions are eyes-only by decision (2026-08-15).** The mouth is reserved
for the speech oval until it gets a proper design pass. Current reads:
laughter = happy arcs + chuckle bounce; sigh = the pensive-emoji droop
(negative arc, outer ends sinking); surprise = rounder eyes grown larger,
converged, lerp-in/hold/lerp-out; question = the raised-brow emoji (one eye
up, one smaller); confirmation = contented arc-squint + a two-bob yes-nod;
dissatisfaction = the unamused emoji (equal half-lids, hard side gaze).

## The FaceDirector

`hearth-client/src/lib/face/director.ts` -- everything about WHEN, nothing
about HOW it is drawn. Renderer-free and time-injected (testable without a
clock); any renderer ticks it once per frame and draws the returned pose.

- **State playlists.** Each state loops beats (expression + hold ms):
  idle 4 beats at 2.8-4.2s with frank look-aways; listening 3 modest beats
  near the idle silhouette; thinking 5 fast (1.3-1.5s) asymmetric beats
  thrown up and to the sides; speaking 3 subordinate beats under the
  amplitude mouth. Beat targets ease with tau 140ms.
- **Energy-tiered blink** (from the avatar-lab reference): calm
  (idle: 3.4-6.2s interval, 280ms), attentive (listening: 4.8-7.2s, 240ms),
  busy (thinking/speaking: 2.8-5s, 260ms). Blink closes to a thick bar,
  never a spindly hyphen.
- **Micro-saccades** every 0.9-2.6s plus a slow sinusoidal head sway: the
  face never sits dead.
- **Transient envelopes.** Every reaction lerps IN over an attack, holds,
  lerps OUT over a decay (smoothstepped), so cues chain naturally. Cues may
  carry a motion layer (laughter's 7Hz chuckle bounce, confirmation's
  nod) via `head_bob`/`head_tilt`.
- **Look target.** `tick(..., lookTarget)` takes `{x, y, focus}` in gaze
  space. While listening, the face watches it (converged), with saccades
  riding on top. The DESKTOP derives it from DOM geometry (the composer
  input's position relative to the face); an iOS renderer passes its own
  ("down, at the keyboard"). This is the seed of the focal-point system --
  future callers: cursor tracking, glancing at a just-rendered card.
- **Speech mouth.** `ttsPlayer.level()` (smoothed RMS of the PCM actually
  playing) drives `mouth_open` with `mouth_round = 1`: a clean oval that
  opens with the voice and closes when the sound stops -- no timer, no
  state coupling. Reduce-motion snaps easing and suppresses blink,
  saccades, sway, and motion layers.

## Rendering (desktop SVG)

`hearth-client/src/lib/face/geometry.ts` turns a pose into SVG path data
(pure). `components/stage/PersonaFace.tsx` ticks the director in a rAF
loop and writes attributes imperatively -- a 60fps mouth must not
re-render the React tree; the loop body is try/catch-guarded because an
exception in a rAF callback would otherwise silently freeze the face.
`PersonaCanvas` mounts it for `procedural_face` instead of the three.js
canvas. Notable rendering choices:

- Squircle head; capsule eyes that collapse to thick bars; arc-close bands
  for the happy `^` and sad droop; specular glints (light dots riding the
  gaze, gone when lids close) -- the single cheapest aliveness win.
- Gaze is theatrical (0.45 x-multiplier) and clamped to the head's width
  at the eyes' height; `focus` converges the pair toward the near point.
- Two mouth paths (crescent + round "o") crossfaded by `mouth_round`, so
  shapes never morph path-by-path.
- Colours: base ink from `--persona`; state colours wash in over 600ms.

The Personas page has an **Animations** section (under Presence) that
plays every state and reaction on the stage for review.

## The harness contract

The harness resolves non-verbal performance tags to expression names at
the source: `tts_chunk_start` gains an optional `expression` field beside
the `text` it already carries (absent when the sentence has no tag). The
resolver lives in the gateway voice loop of BOTH trees (Valinor and
Hearth), collapses tag families (`[surprise-ah|oh|wa|yo]` are all
`surprise`), and runs on the ORIGINAL sentence before display
sanitisation strips the tags. Clients never parse text for tags. On the
client, the cue lands in the store (`faceCue`) and the director plays it.

## Porting notes

- **Hearth desktop client**: port the four `lib/face/` modules, the
  `PersonaFace` component, the `faceCue` store field, and the
  `tts_chunk_start` handler line verbatim (merge, don't overwrite); its
  voice loop already carries the resolver.
- **iOS / RealityKit**: keep `expressions.ts` and `director.ts` semantics
  identical (they are pure data + math; port or transpile). Render with a
  sphere + two capsule entities; `head_tilt`/`head_bob` on the head
  entity, quaternion slerp free of charge; glints as small emissive dots.
  Pass a LookTarget of "down, toward the keyboard" while the composer is
  up. Long-term option: serve the expression library + playlists as JSON
  from the house so all clients share one motion design without
  re-authoring.

## Open items

- **Speaking** needs another design pass (flagged 2026-08-15).
- **The mouth** beyond the speech oval is deferred until a cleaner design;
  the crescent/round crossfade machinery is in place for it.
- **Focus wiring**: cursor tracking and card-glancing as look-target
  sources.
- **create_persona** does not yet author faces (step 8 of the plan).
- The expression library lives in the client; serving it from the house is
  the multi-client end-state.
