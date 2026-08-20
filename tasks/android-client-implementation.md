# Android client, the implementation plan

Written 2026-08-20 after the first run on real hardware failed. Phases 0
through 4 built and passed on an emulator; the Motorola Razr froze on first
launch. This document walks the iOS app as it actually is, states honestly
what the Android client has today, names the defects with their evidence,
and lays out the work in sections that can be taken one at a time.

Companions: `wiki/raw/android-client-plan.md` (the design and the port map),
`wiki/raw/android-appliance-plan.md` (the OS overhaul that comes after),
`tasks/android-client-mirror.md` (the task and the hardware notes).

## The evidence that stopped us

From the Razr over adb, first launch after pairing:

```
ANR in com.hearth (com.hearth/.app.MainActivity)
Reason: Input dispatching timed out. Waited 5001ms for KeyEvent
Choreographer: Skipped 1318 frames!
OpenGLRenderer: Davey! duration=14628ms
CPU usage: 22% TOTAL (11% user + 9.3% kernel)
```

A single frame took 14.6 seconds while the CPU sat at 22 percent. That is
the signature of a BLOCKED main thread, not a slow one. The screen captured
black: nothing rendered at all.

Second observation, from the operator: the layout is wrong on the device.
The emulator is 1080x2400; the Razr's inner display is 1080x2640, and the
cover screen is 1056x1066. Nothing in the current layout was written against
a real device, and the stage uses fixed weights that assume a shape.

## Part 1: How the iOS app is actually built

### The project on disk

```
apple-client/Hearth/
  Hearth.xcodeproj          three targets
  Core/                     a local Swift package, three libraries
    Package.swift
    Sources/HearthCore/     models, transport, audio, config, view models, brand
    Sources/HearthUI/       the SwiftUI both platforms render
    Sources/HearthSpatial/  RealityKit, empty until the Vision phases
    Tests/HearthCoreTests/  the face director suite
  Hearth/                   the iOS app target
  Hearth Vision/            the visionOS app target
  Hearth Widget/            the widget target, still Xcode template
```

Targets are thin. Nearly everything lives in the package, which is why the
Vision app can exist at all: it links the same three libraries and supplies
only its own scenes. The split is the reason a second platform is cheap, and
it is the split `android-client/` copies as `core/` and `app/`.

`Core/Package.swift` declares ZERO external dependencies. That is a standing
policy, not an accident: the client's whole job is to talk to one house over
one socket, and every dependency is a thing that can break a build for a
reason unrelated to Hearth.

### How it launches, in order

1. `HearthApp` is the `@main` App. One `WindowGroup`, no tab bar, no
   navigation stack at the root.
2. It reads `ServerConfig.shared.isConfigured && isPaired` and branches:
   unconfigured or unpaired shows `FirstRunView`, everything else shows
   `HearthMainView`. An unconfigured client NEVER dials.
3. `ChatViewModel` is constructed once and held by the app. It builds the
   socket, the TTS player, and the speech manager.
4. `scenePhase` drives the connection: `.background` tears down (mic off,
   TTS off, reconnect cancelled, socket closed); `.active` resets the
   backoff and dials immediately.
5. On connect, the client sends `client_info`; the house answers
   `client_info_ack`; the view model then asks for the persona list, which
   leads to `persona_config`, which is where the face's geometry and the
   palette arrive.
6. `onOpenURL` handles `hearth://talk`, the widget's quick-talk deep link.
7. `NotificationCenter` carries cross-screen actions
   (`.hearthServerConfigured`, `.hearthResumeSession`, `.hearthTopicSession`,
   `.hearthChoicePicked`) so screens that own no view model can still act.

### The screens, and what each one is

| Screen | File | Lines | What it is |
| --- | --- | --- | --- |
| First run | `FirstRunView` | 169 | Two steps: address, then a six-digit code. Draws the bundled persona so the app is never blank. Primes mic and speech permission after pairing succeeds, in one deliberate moment. |
| Main stage | `HearthMainView` | 359 | Collapsed (stage is the screen) vs expanded (stage 45 percent, timeline below). Card ceiling 46/34 percent. Karaoke caption band. Idle clock overlay. Tapping the stage interrupts, discards, or starts a turn. |
| Composer | `BottomInputBar` | 241 | One "Tap to talk" button, keyboard as the secondary path. Publishes composer position so the face can look at it. Mic glow rides the level. |
| Status strip | `HouseStatusBar` | 124 | The house's own language for what it is doing ("Setting up the easel"), from `pipeline_stage`. Renders NOTHING when idle. |
| Drawer | `HouseShelf` | 239 | Personas with live switch, the four surfaces, chat-log toggle, settings. |
| Timeline | `TimelineFeed` | 286 | Messages and cards interleaved by timestamp, a rail at x=21, 44px nodes. |
| Conversations | `SessionsView` | 256 | Merged live and journal rows grouped by day. Expand, then Resume: two taps, because resuming replaces what is on screen. |
| Journal | `JournalView` + 2 | 881 | Rooms (Heart, Alcove, Forge, Conservatory, Sanctum), horizontal spine rails, searchable. Book to keeper page to entry. |
| Apps | `AppsView` + `CardLibraryView` | 999 | House apps grouped active/setup/available, an on-device section, and a sheet that renders a LIVE sample of every card type. |
| Persona | `PersonaView` + 2 | 964 | Six sections. Only the prompt and state colours are editable, batched behind Save. Includes a face test bench. |
| Settings | `HearthSettingsView` | 593 | Connection (address, Test that probes and rolls back, Apply that commits and redials, Forget), persona pin, voice, history, then the house's own read-only memory and connections. |

### The rules that are load-bearing

Seven behaviours in the iOS client are paid-for bug fixes rather than
choices. They were listed in the design plan and they still bind:

1. Captions and face cues fire from PLAYBACK position, never arrival.
2. The card transcript is append-only; a re-emit never replaces an instance.
3. The persona-adopt equality guard, so boot cannot wipe a restored
   transcript.
4. Single-origin URL construction; the port literal exists in one place.
5. The interrupted-speech flag mutes late segments of a killed reply.
6. Post-speak auto-listen, 5 s, except after a `say` cue or an interrupt.
7. Background teardown and foreground redial, with backoff reset on
   foreground.

## Part 2: What Android has today, honestly

Built and green on the emulator:

- `core/`: the face director and expressions (ported value for value, 8
  tests), face geometry, the transport and its event vocabulary, ServerConfig
  with the address parser (8 tests), pairing, the view model, the TTS player,
  the speech manager, the five surface loaders, the palette.
- `app/`: first run, the main stage, the Compose face, the drawer, five
  surface screens, the Hearth theme.

Verified against the live house from the emulator: pairing, a text turn, TTS
streaming at 24 kHz, the persona's own face and colours, the drawer, and all
five surfaces with real data.

NOT verified anywhere: audible playback, real speech recognition, barge-in,
the karaoke clock against a multi-sentence reply, and any layout on real
hardware. The device run froze before the first turn.

Not built at all: cards (the whole generative-UI surface), the timeline rail,
the status strip, the idle clock, the persona editor, settings controls
(Test, Apply, voice, history), the journal's rooms and entries, and the
widget or cover surface.

## Part 3: The defects, with what to check

### D1: the main thread is blocked (the ANR)

Three suspects, in the order they should be checked, because the first is
both the most likely and the cheapest to prove:

1. **Keystore on the main thread.** `ServerConfig.deviceToken` reads
   `EncryptedSharedPreferences`, which builds a `MasterKey` through the
   Android Keystore on first touch. That is slow, and it is touched during
   composition (`config.isPaired`, `config.address` in Settings and in the
   root branch) and in `onStart`. Keystore work on a cold start on a
   three-year-old device is exactly the shape of a multi-second stall.
2. **Per-frame allocation in the face.** `FaceDirector.tick` builds a new
   `FacePose` map every layer, and `applyExpression` copies the 27-entry map
   again on each of roughly six calls per tick. That is on the order of two
   hundred map allocations per frame at 60 fps. The emulator hid it; a real
   device will not.
3. **`produceState` restarting.** The face's frame loop is keyed on
   `speechLevel` and `cue`, both of which change constantly while speaking,
   so the coroutine is cancelled and restarted continuously instead of
   running once.

Also worth removing regardless: `AudioTrack.write` with `WRITE_BLOCKING` runs
on the OkHttp reader thread, so a slow speaker stalls the socket.

### D2: the layout was never written for a device

The stage divides the screen by fixed weights (0.38 and 0.62) with the shelf
button bolted above it, and it was only ever seen at 1080x2400. The Razr's
inner display is 1080x2640 and its cover screen is 1056x1066. There is no
collapsed-versus-expanded behaviour, no proper top bar, and the composer is a
text field with a text button rather than the iOS "Tap to talk" affordance.

### D3: the surfaces are mirrors, not the iOS screens

They render correct data in a plain list. iOS groups, searches, and lets two
things be edited. This is a known and deliberate gap, not a bug, but it is
the difference between "the data is reachable" and "the client matches iOS".

### D4: no cards

`ui_component` is parsed into an event and then dropped. The card store, the
ten card renderers, the append-only transcript, and the stage's card ceiling
are all absent. This is the largest single piece of missing surface.

## Part 4: The plan

Each section ends with a gate that must pass ON THE RAZR before the next
begins. No section is "done" on an emulator.

### Section 1: make it run on the device

Nothing else can be judged until the app is responsive.

1. Move every Keystore and preference read off the main thread. `ServerConfig`
   becomes async at the edges: the token and address load once into memory on
   a background dispatcher, and the UI reads the in-memory copy. First run
   writes through the same seam.
2. Make the pose allocation-free per frame: give `FacePose` a fixed-size
   `DoubleArray` indexed by channel ordinal instead of a `Map`, and mutate a
   scratch pose in place inside the director rather than rebuilding it.
   The director's public behaviour and its 8 tests must not change.
3. Rewrite the face's frame loop so the coroutine starts once: hold the
   inputs in a mutable holder the loop reads, rather than keying the loop on
   values that change every frame.
4. Move `AudioTrack.write` onto its own writer thread fed by a queue, so the
   socket reader never blocks on the speaker.

**Gate:** the app launches on the Razr, pairs, and holds a text conversation
with no ANR and no frame over 100 ms in `Choreographer` output.

### Section 2: the stage, laid out properly

1. Replace the ad-hoc shelf button with a real top bar carrying the house
   affordance, matching the iOS chrome.
2. Implement collapsed versus expanded: the stage owns the screen when the
   transcript is empty, and yields to the timeline once there is one.
3. Size the persona against the smaller screen dimension rather than a fixed
   dp, so the inner display, the cover screen, and a tablet all work.
4. Port `BottomInputBar` properly: one primary "Tap to talk" affordance with
   the keyboard secondary, and the mic glow riding the level.
5. Port `HouseStatusBar`: the house's own language from `pipeline_stage`,
   rendering nothing when idle.

**Gate:** side by side with the iOS client on the same house, the stage reads
as the same app in both states, on the inner display.

### Section 3: the voice loop on real hardware

This is the phase 2 gate that the emulator could not close.

1. Confirm audible playback and that the karaoke caption tracks the voice
   across a multi-sentence reply rather than racing it.
2. Confirm on-device recognition: partials appear while speaking, the 1.5 s
   silence commits, the mic button commits early.
3. Confirm barge-in cuts audio immediately and opens the mic.
4. Confirm the post-speak window opens and closes silently.
5. Fix whatever the above surfaces, in particular any language-pack path the
   emulator's error 13 was standing in for.

**Gate:** a full spoken exchange, including one interruption, on the Razr.

### Section 4: cards

1. Port `CardStore`: the append-only transcript, the op vocabulary
   (`upsert`, `clear`, `clear_all`), the `ttl_s` expiry, the cap of 40.
2. Port the renderers, in the order the house actually emits them: clock,
   weather, timer, brief text, captions, generated view, image, permission,
   choice, slideshow. Unknown types render nothing.
3. Wire the stage's card ceiling and the timeline's interleave by timestamp.
4. Port `EaselStore` polling for image cards.

**Gate:** ask the house for the weather and for a timer on the Razr, and both
cards appear on the stage and in the timeline.

### Section 5: the surfaces, raised to the iOS bar

1. Conversations: expand-then-resume, not a single tap.
2. Journal: rooms, spines, search, and the entry view.
3. Apps: grouping and the live card-sample sheet.
4. Persona: the six sections, with prompt and state colours editable behind
   Save.
5. Settings: Test that probes a typed address and rolls back, Apply that
   commits and redials, voice controls, history clear.

**Gate:** every surface does what its iOS counterpart does, judged screen by
screen.

### Section 6: the cover screen

Only after the client is right on the inner display.

1. The snapshot publisher: port `HearthSnapshot` and write it to shared
   storage on every state change.
2. A Glance widget rendering persona, state, and card summaries, with the
   quick-talk deep link.
3. Then the owned surface: accessibility service plus overlay, per the
   appliance plan.

**Gate:** a voice turn started and heard with the phone closed.

## Working rules for this plan

- Every section is verified on the Razr over adb, with logs pulled, before it
  is called done.
- `./gradlew :core:test` stays green throughout; the face suite is the
  contract that the optimisation in section 1 does not change behaviour.
- The seven load-bearing iOS behaviours are not renegotiated.
- When the device disagrees with the emulator, the device is right.
