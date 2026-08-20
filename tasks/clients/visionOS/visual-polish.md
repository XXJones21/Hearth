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
[the waveform mouth task](waveform-mouth.md) wants to promote it further.
Only its width and its distance from the bead are in question.

`PersonaRig.updateSpeakingParticles` owns both: `width` and the `z` offset that
pushes the line in front of the bead.

## 3. Not yet a task, but watch it

At `eyeScale` 1.2 the eyes eat gaze travel: the kernel clamps horizontal gaze to
`halfWidthAtEye - eyeSpacing - eyeSize * 1.6`, so larger eyes have less room to
drift before they would cross the head's outline. If the eyes start reading as
fixed rather than alive, that clamp is why, and the fix is `eyeSpacing` in the
persona geometry rather than anything in the Vision client.

## 4. The choreography is switched off, and wants tuning before it comes back

`BehaviorDirector.motion` is `.none` as of 2026-08-17. Cues still resolve, the
library prop still stages, the face still reacts -- only the flying stops. It is
off by choice rather than unbuilt, because the travel is good and it fights
everything else in the volume for the same space while the layout is still
being settled.

Turning it back on is one line. What wants doing first:

- **Scale the travel to the stage, not the room.** `.subtle` exists for this and
  multiplies every offset by 0.45; the right number is whatever keeps the orb
  inside the volume and below the live text card, which sits near the box's
  middle. The orb currently flies well above it.
- **Match the travel to the library.** When the persona consults a journal the
  prop appears beside it, so the flight's top and bottom should be bounded by
  where that prop actually is rather than by numbers picked in isolation.
- **The prop is too small.** `MainVolume.propScale` is 0.10, which came from a
  first guess and has never been judged on the device. It reads as a token
  rather than a bookshelf.

`orientTo` is implemented and wired into `consulting_journal`, so the orb turns
to face the shelf rather than arriving and continuing to look at the person.
That part is worth keeping when motion comes back.

## 5. Cards do not travel with the orb, and in the volume that is now deliberate

Design section 6 says cards "anchor to the rig, not the scene, so when the orb
travels its cards follow with a soft spring lag". `CardOrbitLayout.offsetFromOrb`
exists for exactly that and has no callers; the volume uses the absolute
`position(index:count:)` instead.

Operator's call 2026-08-17: parenting belongs in the IMMERSIVE space, not the
volumetric window. In a room the orb genuinely travels and its work should go
with it; in a box a metre wide the cards have nowhere to go, and prose that
slides while you are reading it is worse than prose that sits still.

So this is phase 4 work rather than a bug. `offsetFromOrb` stays unused until
then, deliberately.
