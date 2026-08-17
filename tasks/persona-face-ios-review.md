# Persona face iOS review findings

> STATUS (2026-08-16, Windows session): findings 1 through 8 and 10 are
> FIXED on `feat/ios-qol-tier0`, unverified on device. Notes: finding 4
> (the dead Mouth slider) fell out of the Tier 2 tap-quiesce fix rather
> than needing its own change; finding 2 removed the segment-0 exception
> entirely -- all cues now park and fire from the playback tap, which
> announces segment 0 at its first rendered frame; finding 5 got both
> halves -- the bundled sulivan.json's sphere/particle blocks restored AND
> PersonaPalette deriving bead/particle from state_colors when a config
> omits them, which also heals the server-sent shape without touching the
> backend file. Finding 9 (blink starvation) is fixed on iOS; its desktop
> twin in Valinor's director.ts, and the desktop panel half of finding 10,
> are STILL OPEN upstream.

Code review of `84d54da..HEAD` on `feat/persona-face`, scoped to
`apple-client/` (2026-08-16). Eight review angles produced 42 candidates; 12
went through verification against the Hearth sources, the desktop
`director.ts` reference, and the server's `voice_loop.py`. Seven CONFIRMED,
three PLAUSIBLE survived the cap, one refuted. Ranked most severe first.

One cross-cutting root cause before the list: **`TTSStreamPlayer.stop()` has
zero call sites.** That single fact underlies findings 4 and 6 here, and it
is the same fact behind the no-barge-in and tap-runs-forever items in
`tasks/ios-qol-fixes.md`. Wiring interrupt/stop is one fix that pays off in
three places.

## 1. `composerUp` strands the face in listening (CONFIRMED, found by four angles)

`FaceFeed.shared.composerUp` (`Views/BottomInputBar.swift:89`) is a
process-global set true only by the keyboard button and false only by the mic
button. Any teardown of `BottomInputBar` leaves it true: clear and re-enter
the server address and `HearthApp` rebuilds `HearthMainView` with
`typing == false` while the global stays true, so IDLE maps to the listening
pose for the rest of the process. It also makes the Animations panel's Idle
chip render the listening playlist whenever the composer is up. The sibling
`composerFrame` got an `.onDisappear` reset in this same diff; `composerUp`
needs the same.

## 2. Segment 0's cue plays to a silent face (CONFIRMED)

`ChatViewModel.swift:379` fires segment 0's cue on `tts_chunk_start`
arrival, on the stated ground that its audio begins essentially then. But
`voice_loop.py` emits `tts_chunk_start` before synthesizing the sentence, and
OmniVoice synthesizes the whole sentence before its first yield, so the gap
is seconds. A reply opening with `[laughter]` laughs during silence, then
speaks with a flat face. The fire-when-heard path cannot cover it as written:
`handleTtsSentence` sets `captionSegment = 0` at arrival (`:853`), so
`onSegmentPlaying(0)` is dropped by the `guard segIdx > captionSegment`.
Segment 0 needs a real first-audio trigger, not arrival time.

## 3. Wall-clock dt can poison the pose forever (CONFIRMED)

`FaceDirector.swift:259` uses `let dt = min(100, now - last)` with no lower
clamp, and the port swapped desktop's monotonic `performance.now()` for
`timeline.date` wall time. A backwards clock adjustment makes alpha negative
(easing drives channels away from target); a jump of minutes overflows
`exp()` and every channel becomes NaN. Pose is the only carried state and
`DirectorBox` only rebuilds on geometry change, so the face never draws again
that session. Fix: `min(100, max(0, now - last))`, or better, a monotonic
clock. Desktop has the same min-only clamp but ticks on monotonic time where
it is harmless.

## 4. The Animations Mouth slider is dead after the first reply (CONFIRMED)

`FaceAnimationsView.swift:77` writes `FaceFeed.shared.speechLevel`, but once
the persona has spoken, the TTS amplitude tap stays installed forever
(`stop()` never called) and clobbers the slider's value with silence RMS at
~43 Hz. The panel works on a fresh launch and never again, which will make
the bug report unreproducible for whoever tests first.

## 5. Sulivan's orb palette was silently deleted (CONFIRMED)

Replacing the `visualization` block with `procedural_face` deleted the
`sphere` and `particle_system` sub-objects in the bundled copy
(`Resources/Personas/sulivan.json:7`), the backend, and the desktop configs.
`PersonaPalette.from()` (`PersonaPalette.swift:85-90`) still reads those keys
for the orb's bead and particle colors, so every orb-fallback render
(FirstRunView, pre-connect frames, widgets, face-geometry-missing) now uses
brand warmDefaults instead of the authored colors, and FirstRunView's own
comment promises the opposite. Restore the color sub-objects alongside the
face geometry, or teach the palette to read `state_colors`.

## 6. `speechLevel` is never zeroed on teardown (CONFIRMED)

`ChatViewModel.swift:224`: `closeTurn`, `handleSessionEnded`, and
`onConnectionClosed` clear `expressionsBySegment` but not `speechLevel` or
the cue; the only `onAmplitude(0)` emitter is the never-called `stop()`. An
audio-session interruption mid-reply (call, Siri, Bluetooth route change)
latches a non-zero level and the face keeps a round open mouth at idle until
the next reply's first buffer. Zero it on every turn-teardown path.

## 7. Segment marks collapse last-wins, dropping cues and captions (CONFIRMED)

`TTSStreamPlayer.swift:178`: `emitSegmentIfAdvanced` emits only the final
reached index, so a segment passed over within one amplitude buffer is never
announced. Guaranteed case: a server-side TTS error leaves two marks sharing
a startFrame and the earlier index can never fire; that sentence's reaction
and caption vanish while the harness log shows the cue was sent. Emit each
skipped index in order (or at least the parked expression for each).

## 8. Negative-age transients pre-fire and unbounded headBob (PLAUSIBLE)

`FaceDirector.swift:204`: `transientWeight` has no `age < 0` guard and
smoothstep is positive for negative w, so a cue stamped between frames can
pop in a frame early at partial weight; in the backwards-clock case the raw
weight reaches the motion layer unclamped and laughter's headBob scales to
tens of head-heights. Guard `age >= 0` and clamp the weight before
`profile.motion`.

## 9. Fast state cycling means the face never blinks (PLAUSIBLE, desktop parity)

`FaceDirector.swift:268`: every state change re-arms `nextBlinkAt` to the
full `blink.first` (2100-3200 ms), so a conversation cycling
listening/thinking/speaking faster than that never blinks; an in-flight
blink crossing a state change can also snap open mid-close. Exact parity
with desktop `director.ts`, an inherited spec wart, not a port regression.
Fix upstream in Valinor's director first, then port: carry blink phase
across state changes and only re-tier the interval.

## 10. The panel's blink chip plays the wrong blink (PLAUSIBLE, desktop parity)

`FaceAnimationsView.swift:40`: the blink chip routes through the cue path,
where TRANSIENTS has no `blink` key, so the default envelope plays a ~1.35 s
eyes-closed performance, about 5x slower than the real 240-280 ms
`blinkWeight` blink. Anyone tuning blink timing from the panel tunes the
wrong curve. Also `blink` is not a name the harness sends. Same gap exists
in the desktop panel; fix both or drop the chip.

## Refuted

The candidate claiming reduce-motion freezes the orb's speaking indication:
`paused:` only stops the TimelineView's self-invalidation; pulse and state
changes still repaint through @Published re-renders.

## Below the cap (cleanup tier, noted for later)

- `FaceAnimationsView.onDisappear` nils an in-flight live cue when the panel
  is dismissed mid-reply (narrow window).
- `FacePose` dictionary-backed storage allocates ~9 dictionaries per frame on
  the 60 fps draw path.
- A four-site duplicated turn-reset block in `ChatViewModel`.
- Three hand-rolled copies of SIMD3-to-Color/mix helpers that
  `PersonaPalette`/`HearthPalette` already own.
