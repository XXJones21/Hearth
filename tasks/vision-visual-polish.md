# Vision client visual polish

Quality-of-life adjustments to the orb's look, collected from device runs during
phases 1 and 2 (2026-08-17). None of these block a phase gate; they are the
difference between "it works" and "it looks like it was designed". Land them
whenever, and before the phase 5 polish pass settles the register.

## 1. The state colours go too yellow

The body's per-state accents run to a bright, saturated yellow -- `honey`
(0xFFB84D) is the listening accent and the particle field's own tint -- and on a
bead the size of a palm, lit against a real room, it reads as a highlighter
rather than as firelight. The brand's own word for this palette is warm, and the
warm end of it is `cream` and `fennec`, not `honey` at full strength.

Wanted: the states stay distinguishable but sit in the cream range, so the orb
reads as a warm bead that shifts rather than a lamp that changes colour.

Where it lives, and the constraint that matters: the accents are data, not
constants. `PersonaPalette` decodes `state_colors` from the persona's own config
(`sulivan.json`, and the server's `public_config()`), and every client reads the
same block -- desktop, phone, Quest, headset. So this is a change to the
PERSONA, not to the Vision client, and doing it locally would be the headset
quietly drawing a different Sulivan. The fallback constants in
`PersonaPalette.fallback` want the same treatment so an unconfigured house
matches.

Check the desktop and phone before committing to numbers: a colour that reads as
a highlighter on a glowing 3D bead may be exactly right as a flat 2D accent, and
the point of the shared block is that one set of numbers has to serve both. If
they genuinely cannot, that is a finding worth writing down rather than
papering over with a per-client override.

## 2. The speaking waveform is too wide at volume scale

The speaking choreography throws the particle field into a travelling wave
spanning `particleMaxDistance * 1.8`, which was tuned against a differently
scaled orb. At the volume's 0.22 rig scale it reads as a wave cutting across the
room rather than as the orb's own voice.

The waveform itself is not the problem and must not be "fixed" -- it is, in the
operator's judgement, the best speaking treatment across every client, and
[the waveform mouth task](vision-waveform-mouth.md) wants to promote it further.
Only its width and its distance from the bead are in question.

`PersonaRig.updateSpeakingParticles` owns both: `width` and the `z` offset that
pushes the line in front of the bead.

## 3. Not yet a task, but watch it

At `eyeScale` 1.2 the eyes eat gaze travel: the kernel clamps horizontal gaze to
`halfWidthAtEye - eyeSpacing - eyeSize * 1.6`, so larger eyes have less room to
drift before they would cross the head's outline. If the eyes start reading as
fixed rather than alive, that clamp is why, and the fix is `eyeSpacing` in the
persona geometry rather than anything in the Vision client.
