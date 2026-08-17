# The waveform becomes the mouth

Source: operator's read of the first full working turn on the Vision Pro
(2026-08-17, phase 2 landed). Not scheduled; land it when the face is otherwise
settled and before the phase 5 polish pass fixes the register in place.

## The idea

The speaking particle waveform is the best thing in the persona's whole visual
vocabulary. The operator's judgement, and it holds across clients: of every
speaking treatment tried on Echo, Quest, the desktop and the phone, the
travelling sine line is the one that nailed it.

Right now it is a body behaviour and the mouth is a separate, unrelated shape:
`PersonaRig.updateSpeakingParticles` throws all 96 particles into a horizontal
wave in front of the bead, while `face_kernel` draws a round oval on the face
whose height rides the same amplitude. Two answers to one question, and the
weaker one is the one on the face.

**So the waveform should BE the mouth.** The orb speaks in the wave rather than
mouthing along beside it.

## What has to be decided first

Two readings, and they are not the same feature:

1. **The face's mouth becomes a wave.** `face_kernel` stops drawing the oval
   and draws a travelling sine band at the mouth position, amplitude from
   `mouthOpen` exactly as now. The particle field keeps its own wave. Cheap,
   contained, and it makes the FACE speak in the same language the body does.
2. **The particle wave moves onto the face.** The field's waveform is scaled
   down and positioned at the mouth, so the actual particles form the mouth.
   Much stronger idea, and much harder: the particles are entities in the rig's
   space, the face is a texture on a shell, and the mouth's position is a
   pose channel that moves. It also costs the body its speaking behaviour,
   which is the thing being praised.

The operator's phrasing -- "making that become the mouth instead of the current
one" -- reads as (1) with (2) as the ambition. Confirm before building.

## If it is (1)

- The band is already written: `sdArcBand` in `FaceKernel.metal` draws the
  crescent, and a travelling wave is the same primitive with a `sin` term
  instead of a parabola. The kernel already has `animationTime`'s equivalent
  available through the pose if a phase channel is added.
- `FacePose` has no phase channel. Either add one to `PoseChannel` in
  HearthCore -- which is a shared-layer change the phone inherits, and it
  should, since the phone's mouth has the same weakness -- or drive the phase
  from the rig's own clock and pass it in `FaceParams`, which keeps it
  visionOS-only and is the smaller first step.
- The crossfade stays: `mouthRound` blends oval and crescent today, and a third
  shape wants the same treatment rather than a hard switch. The reason is in
  PersonaFaceView's own comment -- morphing these path-by-path is how the first
  cut ended up looking like a beak.
- Keep the amplitude source. The mouth already rides real TTS amplitude through
  `FaceFeed.speechLevel`; nothing about that changes.

## Not in scope

The particle waveform's SIZE, which is
[vision-visual-polish.md](vision-visual-polish.md) item 2. The wave being too
wide and the mouth being the wrong shape are different complaints, and fixing
them together would make it impossible to tell which change did what.
