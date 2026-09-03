---
title: The persona face
status: draft
last_reviewed: 2026-09-03
related:
  - personas.md
  - voice.md
  - ../clients/ios.md
sources:
  - desktop-client/src/lib/face/expressions.ts
  - desktop-client/src/lib/face/director.ts
  - desktop-client/src/lib/face/geometry.ts
  - desktop-client/src/components/stage/PersonaFace.tsx
  - backend/harness/valar/gateway/voice_loop.py
  - wiki/raw/persona-face-spec.md
  - wiki/raw/persona-face-ios-plan.md
---

# The persona face

A procedural face for personas, driven by the state machine the house
already runs. Eyes-first: two vertical capsules carry the whole character,
there are no brows, and the mouth only appears while the voice is actually
producing sound. A persona authors roughly a dozen normalized numbers; one
expression library of relative deltas gives every persona (including one
created five minutes ago) the same full range of behavior.

The behavior core (the **FaceDirector**) is renderer-free: state
playlists, blink rhythms, micro-saccades, transient envelopes, and a
focal-point seam, all pure data and math. Each client only draws the pose
the director returns, which is why the same motion design ships on
Windows, macOS, and iOS without re-authoring. The full data model
(geometry schema, pose channels, the harness cue protocol) lives in the
face spec, kept as a staged source and named in this page's frontmatter.
This page is the catalogue of what the face actually **does**.

## What a persona brings

Eleven geometry numbers (head proportions, capsule eye size/spacing/
length/lean, mouth proportions), normalized to the head's own bounding
box, plus the `state_colors` block the orb glow already used. The face's
ink washes toward the active state's color. Archetypes (`warm_round`,
`narrow_precise`, `wide_open`) live in `backend/personas/_visual/
archetypes.json` as complete starting points. Sulivan wears `warm_round`.

## The animation catalogue

All timings in milliseconds. Beat targets are eased with a 140ms time
constant; a state change restarts its playlist and its blink schedule.

### Life cycle (one looping playlist per state)

| State | Character | Beats | Blink rhythm |
| --- | --- | --- | --- |
| **idle** | Soft and unhurried, never frozen: long neutral holds broken by a frank look away to one side, once with a lazy half-lid | 4 beats: neutral 4200; hard look-left (gaze -0.85, slight tilt) 3200; neutral 4200; look-right with 25% lids 2800 | calm: first 2600, every 3400-6200, 280ms lids |
| **listening** | Attention near the idle silhouette: a modest lift (eyes ~18-22% taller, ~6-8% bigger) and a lean-in tilt; the look-target does most of the telling | 3 beats x 2000, varying gaze up / aside slightly | attentive: first 3200, every 4800-7200, quick 240ms |
| **thinking** | Half-height eyes thrown up and to the sides, quick asymmetric changes, one flat-dash "processing" hold | 5 beats: up-right 1500; hard up-left with one eye raised 1500; one-eye-squint with the other grown 1400; both lids 75% (the processing dash) 1300; up-left with a lean 1500 | busy: first 2100, every 2800-5000, 260ms |
| **speaking** | The mouth does the talking; the eyes stay engaged and mobile underneath | 3 beats x 1800: slight size lift with small gaze shifts and tilts | busy (same as thinking) |

### Always-on motion

- **Micro-saccades**: the gaze darts a small random amount (up to ±0.18
  horizontal, ±0.1 vertical in gaze space) every 900-2600ms; the easing is
  what makes the jump read as a dart. The face never sits dead.
- **Breathing sway**: a continuous sinusoidal head tilt, ±0.014 rad over a
  5200ms period.
- **Blink**: closes into a thick bar (never a spindly hyphen), 42% of the
  tier's duration closing, 58% opening.
- **The speech mouth**: a round oval whose height rides the smoothed RMS of
  the PCM actually playing. It opens with the voice and closes when the
  sound stops: no timer, no state coupling, which is why it stays honest
  through buffered audio tails.

### Reactions (transients, fired by the harness)

Each reaction is a little performance with a full envelope: lerp in over
the attack, hold, lerp out over the decay (smoothstepped). The envelope
layers on top of whatever state is playing, so reactions chain naturally.
The harness resolves the voice's non-verbal tags (`[laughter]`, `[sigh]`,
...) to these names on `tts_chunk_start`; clients never parse text.

| Reaction | The face | Envelope (attack/hold/decay) | Motion layer |
| --- | --- | --- | --- |
| **laughter** | Full happy arcs (the anime `^ ^`) with a merry lean | 120 / 1600 / 650 | the chuckle: whole-face bounce, ~7.4Hz at 0.04 head-heights, plus a slower tilt wobble |
| **sigh** | The pensive-emoji droop: lids 85% closed into downward sad arcs, outer ends sinking, gaze drifting down | 400 / 900 / 1100: settles in slowly, takes its time leaving | none |
| **surprise** | Rounder eyes grown ~35% larger, slightly raised, converged on the viewer (startled **at** you) | 150 / 700 / 450: lerp wide, hold a beat, lerp back | none |
| **question** | The raised-brow emoji without brows: one eye raised, the other ~18% smaller and slightly narrowed, both leaning, head cocked | default 140 / 260 / 950 | none |
| **confirmation** | A soft contented arc-squint (60% lids, 90% happy arc) | 150 / 1250 / 500 | the yes-nod: two slow downward bobs (620ms period, 0.11 head-heights) |
| **dissatisfaction** | The unamused emoji: both eyes equally half-lidded, gaze hard to one side, dead level | default 140 / 260 / 950 | none |
| **blink** (as a cue) | One deliberate full blink | default envelope | none |

Reactions are **eyes-only by decision** (2026-08-15): the mouth is reserved
for the speech oval until it gets its own design pass, so every reaction
carries its meaning in the eyes. Asymmetry is deliberate where it appears:
matched eyes read as a machine, mismatched ones as a creature.

### The focal point

`gaze` aims the eye pair; `focus` converges it on a near point (vergence).
First caller: **listening watches the composer**. While the input is up,
the eyes settle onto it, converged, with saccades still flickering on top.
Future targets (cursor tracking, glancing at a just-rendered card) are one
caller each.

## Per-client implementation

| | Windows / macOS desktop | iOS | visionOS |
| --- | --- | --- | --- |
| Status | shipped (this branch) | implemented on this branch per the iOS face plan, kept as a staged source and named in this page's frontmatter, plus the four adjustments below; on-device verification is the plan's task 7 | future RealityKit pass |
| Renderer | SVG paths written imperatively in a rAF loop | SwiftUI `Canvas` in a `TimelineView`, the orb's own template | sphere + capsule entities, quaternion slerp (see the spec's port map) |
| Amplitude source | `ttsPlayer.level()` (smoothed RMS of played PCM) | the existing `TTSStreamPlayer` amplitude tap, via the non-published `FaceFeed` | -- |
| LookTarget | measured from the composer input's DOM position relative to the face | measured the same way: the composer publishes its frame, the face reads its own | -- |
| "Listening" trigger | input focus maps to the listening state | **listening** means the microphone is live on iOS, so the composer-being-up drives the listening **pose** at the face level without touching `hearthState`, but only over **idle**: a live turn wins, or typing a follow-up would cost the whole reply's thinking and speaking beats | -- |
| Cue timing | on `tts_chunk_start` arrival | **on the karaoke clock**: cues are parked by segment and fired from `onSegmentPlaying`, segment 0 excepted. The server pushes a whole reply in a second or two, so arrival-time cues played the sixth sentence's laugh over the first sentence's audio, the same flaw the caption already worked around. The desktop still fires on arrival |
| Reduce motion | client setting; snaps easing, stops blink/saccades/sway | `accessibilityReduceMotion` environment (wired by the face work; also fixes the orb) | -- |
| Review tooling | Personas > Animations panel plays every state and reaction | Persona > Animations on the phone: every state, every reaction, and a slider standing in for the voice; plus a per-state Xcode preview | -- |
| Unknown-type fallback | n/a (origin) | tolerant decode falls back to the orb, with a log | -- |

## Where the pieces live

- Behavior + rendering (desktop): `desktop-client/src/lib/face/` and
  `desktop-client/src/components/stage/PersonaFace.tsx`
- Behavior + rendering (iOS): `apple-client/Hearth/Core/Sources/HearthCore/Persona/Face/`
- The harness cue: `backend/harness/valar/gateway/voice_loop.py`
  (`_resolve_expression`, the `expression` field on `tts_chunk_start`)
- Persona data: `backend/personas/_visual/archetypes.json`, each persona's
  `visualization` block
