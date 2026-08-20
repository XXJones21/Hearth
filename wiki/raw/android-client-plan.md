# Hearth Android Client, the rebuild plan

Written 2026-08-19 from a full survey of the iOS client and its Xcode
project. Companion to `tasks/android-client-mirror.md` (the task) and
`wiki/raw/research-foldable-prototype.md` (the device research). The target
hardware, a Motorola Razr 40 Ultra XT2321-3, arrived 2026-08-19.

## Onboarding prompt for a fresh session

You are building the native Android client for Hearth, a local-first AI
companion. The house server (Valar) listens on port 18700; the iOS client
at `apple-client/Hearth` is the reference implementation and this plan maps
it onto Android. Phase 1 targets the Motorola Razr 40 Ultra, where the
cover screen is the product. Read this file fully, then
`tasks/android-client-mirror.md`, then the protocol notes below before
writing code. Verify every phase against the live house, not with mocks.

## What the iOS client actually is

Two layers, and the split is the whole porting strategy:

- **Core package** (~9,360 lines, 48 files, zero external dependencies):
  transport, view model, models, face logic, cards, config. Roughly two
  thirds is platform-agnostic logic.
- **App target** (~5,248 lines, 18 files): SwiftUI screens that are thin
  wrappers over Core view models and loaders.

The Widget target is untouched Xcode template, but the app-side contract
behind it is fully built: `HearthSnapshot` (persona, connection, state,
session summary, card summaries) republished on every state change. That
contract is the cover screen's data feed, designed before the phone existed.

## Stack and structure

- Kotlin + Jetpack Compose, coroutines + StateFlow. minSdk 33 (the Razr 40
  Ultra ships Android 13; nothing older matters).
- Dependencies stay minimal, matching Core's zero-dependency policy where
  Android allows: OkHttp (WebSocket + HTTP), Coil (images), Jetpack
  DataStore, EncryptedSharedPreferences. No DI framework, no Retrofit.
- Modules mirror the iOS split: `core/` (pure Kotlin + the audio and
  transport implementations) and `app/` (Compose UI). The cover-screen
  surface joins later as its own module.
- The Valinor Echo Show client is the structural reference for the service
  and kiosk patterns (foreground voice service, boot receiver, lock task);
  this app is its newer sibling, not a fork.

## The port map

### Direct ports, logic carried 1:1 into Kotlin

FaceDirector (clock-injected, has unit tests to port with it),
FaceExpressions, PersonaVisualization, UiComponentDescriptor, CardStore
(append-only transcript, cap 40, ttl expiry), EaselStore (image-job
polling), ServerConfig address parsing (host or host:port, strips schemes,
rightmost-colon split, no default host), Pairing (POST /pair code to
token), ClientPrefs, ClientProfile, every Models file (ServerMessage,
ClientInfo, HearthState, ChatMessage, SessionModels, JournalModels,
AppsSurface, SettingsSurface, PersonaSurface, TranscriptStore), and
SharedSnapshot.

### Reimplementations against Android equivalents

| iOS piece | Android piece |
| --- | --- |
| HearthWebSocketClient (URLSessionWebSocketTask) | OkHttp WebSocket; auth header on the handshake request; close code 1008 detection for the repair flow |
| ChatViewModel (Combine, @MainActor) | ViewModel + StateFlow; watchdogs, keepalive, backoff as coroutines |
| TTSStreamPlayer (AVAudioEngine) | AudioTrack MODE_STREAM ENCODING_PCM_FLOAT; playbackHeadPosition against recorded segment marks reproduces the karaoke clock; RMS computed on the write buffer |
| SpeechRecognitionManager (SFSpeechRecognizer, on-device) | Android SpeechRecognizer with offline preference; the partial-results, 1.5 s silence auto-submit, manual commit, and double-send guard logic ports directly; Vosk is the fallback if platform offline STT disappoints on the Moto |
| AudioSessionManager (AVAudioSession) | AudioManager + AudioFocusRequest + AudioDeviceCallback; playAndRecord posture, speaker default, Bluetooth routes, interruption and route-lost handling |
| PersonaFaceView (SwiftUI Canvas, 60fps TimelineView) | Compose Canvas + withFrameNanos loop; the drawing (squircle head, capsule eyes, gaze clamp, crescent mouth) is near 1:1 DrawScope work |
| PersonaOrb | Compose Canvas particle field; keep the single-static-frame render path for the widget |
| DynamicComponent card registry | Compose registry over the same type vocabulary: clock, weather_card, timer_card, brief_text, slideshow, captions, generated_view, image_card, permission_card, choice_card; unknown renders nothing |
| Screens (main stage, drawer, timeline, sessions, journal, apps, persona, settings, first run) | Compose screens over the ported loaders; same no-tab-bar shape: one stage, a drawer, full-screen surfaces |
| Keychain token vault | Keystore-backed EncryptedSharedPreferences; drop the old token when the address changes, same as iOS |
| NotificationCenter cross-screen events | one SharedFlow event bus |
| AsyncImage ?token= query | Coil with an OkHttp header interceptor; the query-token variant exists only because AsyncImage takes a bare URL, so Android drops it |

### Deferred or skipped

- PersonaModelView (RealityKit, glb_animated personas): defer. Android
  would consume the GLB directly (the USDZ step exists only for RealityKit)
  via Filament when it comes; until then the config-driven renderer
  selection falls back to the orb exactly as iOS does.
- Dead iOS paths stay dead: sendAudioChunk has no callers, play_wav_file
  has no consumer, reset_vad is never sent. Do not port them.

## Protocol notes

Identical wire contract, one change of self-description: `client_info`
sends platform `android`, stt `local`, stt_engine named for what actually
runs. Handle the same server actions the iOS client handles (ai_response,
tts_chunk_start with per-sentence text and expression, tts_chunk_end,
speaking_complete, personas_list, persona_config, ui_component,
state_update, session_ended, session_resumed, pipeline_stage, and the
rest); unknown actions log and pass, never error. Binary frames are
float32 PCM at the announced sample rate. Port default 18700, no default
host: an unconfigured app shows first run and does not dial.

Behaviors to preserve verbatim, each a paid-for iOS bug fix:

1. The karaoke clock: captions and face cues fire from playback position,
   never from packet arrival, and every newly reached segment emits.
2. The append-only card transcript: a re-emit never replaces an earlier
   card instance.
3. The persona-adopt equality guard, so the boot sequence cannot wipe a
   restored transcript.
4. Single-origin URL construction; the port literal exists in exactly one
   place.
5. The interrupted-speech flag mutes late-arriving segments of a killed
   reply.
6. Post-speak auto-listen (5 s window) except after a `say` cue or an
   interrupt; 15 s initial listen window.
7. Background teardown and foreground redial tied to lifecycle, with
   backoff reset on foreground.

## Connectivity

The standard Tailscale Android app joins the phone to the tailnet at the
VPN layer, so the client dials `vytal.tail22b3ca.ts.net:18700` like any
host; no SDK embedding in phase 1. Two carried lessons: always the full
tailnet name (short names failed on iOS), and network_security_config must
permit cleartext ws:// for the LAN and the tailnet hostname, the Echo
bring-up lesson. The app ships sideloaded, so Play policy constraints
(accessibility-purpose rules) do not bind.

## The cover screen

Two steps, matching the foldable research:

- **Step A, widget-class surface.** A Glance AppWidget consuming the
  ported HearthSnapshot from shared DataStore: static persona orb frame,
  state line, card summaries (weather, timers with client-side countdown,
  brief), and a tap target firing the `hearth://talk` deep-link analog.
  Motorola allows arbitrary apps and widgets on the cover panel, so this
  ships with no special privileges.
- **Step B, owned surface.** The CoverScreen-OS-shaped route: an
  accessibility service plus overlay window on the cover display,
  NotificationListenerService for notification content spoken in the
  persona's voice, Device Owner over ADB for Lock Task and shade
  suppression. Fragile across firmware updates by nature; sideloading
  makes the policy question moot.

Notification-reading in the persona's voice depends on the push keystone
(Valinor proactive-tools roadmap, Keystone 1) to be more than local; the
surface itself does not block on it.

## Phasing, each gate verified against the live house

- **Phase 0, skeleton and pure core.** `android-client/` in this repo;
  port the direct-port list with the FaceDirector tests. Gate: tests pass.
- **Phase 1, transport and pairing.** OkHttp socket, pairing flow, text
  turn on an emulator: text_query out, ai_response and cards in. Gate: a
  paired emulator holds a text conversation with the house.
- **Phase 2, audio.** TTS streaming playback with the karaoke clock, then
  client-side STT with the listening-window logic. Gate: a full voice turn
  with barge-in on real hardware.
- **Phase 3, the face.** Compose Canvas face driven by FaceDirector,
  expressions landing on the spoken sentence. Gate: side-by-side with iOS,
  the face reads the same.
- **Phase 4, the shell.** Timeline, drawer, sessions, journal, apps,
  persona, settings surfaces. Gate: feature walk against the iOS client.
- **Phase 5, the fold.** Snapshot publisher, Glance cover widget, quick
  talk from the closed lid on the Razr; then the Step B owned surface.
  Gate: a voice turn started and heard entirely closed.

Development ahead of the device works on any Android hardware or emulator:
`adb shell settings put global overlay_display_devices 1080x1272/400`
spawns a simulated cover display.

## Open questions

- Offline quality of platform SpeechRecognizer on Motorola firmware; the
  Vosk fallback decision belongs to phase 2 evidence.
- Whether Step B's overlay can own the cover display while the Moto
  launcher believes it is active; CoverScreen OS proves it is possible,
  not how.
- Degraded operation when the house is unreachable: what the closed lid
  shows and says with no brain. Owed a design before phase 5.
