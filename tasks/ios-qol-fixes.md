# iOS client quality-of-life fixes

Source: full read-only audit of `apple-client/` on branch `feat/persona-face`
(2026-08-16), with `desktop-client/src` as the parity reference. Ranked by
what a daily user hits first. Each task is independently shippable; land them
in order within a tier.

## Tier 0. Broken or blocking

> STATUS (2026-08-16, Windows session): all four Tier 0 tasks are BUILT on
> branch `feat/ios-qol-tier0`, unverified on device. Task 3 shipped
> permission_card and choice_card; terminal_card stays unsupported by
> decision. Verification owner: the Mac session (build, then the live
> checks listed per task). Wiki parity lands with verification.

### 1. Sessions: new, resume, topic (the seed complaint)

The client cannot start a new session or resume a previous one. Worse, the
scaffolding that exists is wrong in three independent ways:

- `HearthWebSocketClient.sendSessionResume` (`Transport/HearthWebSocketClient.swift:621`)
  sends `{"action":"session_resume"}`. The server dispatcher
  (`backend/harness/valar/gateway/server.py:868`) only accepts
  `resume_session` (with `session_id` or `slug`), so it errors as an unknown
  command.
- The only caller path is a `session_gallery` card that `DynamicComponent`
  has no case for, so it renders `EmptyView` and `selectSession` is
  unreachable.
- `handleTextMessage` has no `session_resumed` or `topic_session` cases; the
  rehydration payload would be dropped at the `default:` log line.

Fix, mirroring desktop exactly (`desktop-client/src/hooks/useHearthWebSocket.ts:481-520`):

1. Add three sends to `HearthWebSocketClient`: `new_session`,
   `resume_session` (`session_id` for a record, `slug` for a journal entry),
   `start_topic_session`. Guard each on connected and not waiting on a turn.
2. Add inbound `session_resumed` and `topic_session` handling. `turns` are
   `{user, assistant}` pairs, not flat messages; flatten in order and replace
   `messages`. `session_ended` always arrives first, so handle
   wipe-then-repaint.
3. On `session_ended`, wipe `messages` like desktop does. Today
   `handleSessionEnded` (`ViewModels/ChatViewModel.swift:871`) keeps the feed
   on screen after the house has closed the session, so the phone shows a
   conversation the house no longer remembers.
4. UI: a Sessions row in `HouseShelf` (beside Journal/Persona/Apps) opening a
   list backed by `GET /sessions` plus `GET /journal/sessions`, deduped by
   thought slug the way desktop's `mergeRows` does; a New session button in
   that view and in the shelf footer.
5. Delete the dead vocabulary: `sendSessionResume`, `selectSession`,
   `debugShowSampleGallery`, the `session_gallery` constant and its
   `CardStore.singletonTypes` entry.

### 2. Auth failure recovery (1008) and unpair

A revoked or wrong token today produces a silent infinite reconnect loop.
The close delegate (`HearthWebSocketClient.swift:693`) discards `closeCode`
and `reason`, so a policy close is indistinguishable from a network drop, and
there is no unpair UI to recover with short of deleting the app.

1. Inspect `closeCode` in `didCloseWith`; on `.policyViolation` stop the
   backoff loop, enter a distinct `needsPairing` state, and present a re-pair
   sheet instead of retrying.
2. Clear `hearth.deviceToken` when the server host actually changes
   (`Config/ServerConfig.swift:111` setter never touches it, so house A's
   token gets presented to house B).
3. Move the token from UserDefaults to the Keychain. The comment at
   `ServerConfig.swift:72` already calls the current storage a pre-alpha
   shortcut.
4. Add "Forget this house" to Settings > Connection: two-step confirm, calls
   `Pairing.forget()` (exists at `Config/Pairing.swift:101`, zero callers),
   clears the address, posts `.hearthServerConfigured` to return to
   `FirstRunView`.

### 3. permission_card and choice_card renderers

A `permission_card` is a file-access approval the house is waiting on. On
iOS it arrives, occupies a transcript slot, and renders as nothing; the house
blocks and the screen shows an empty gap. `choice_card` is the same shape of
problem. `DynamicComponent.swift:25-48` covers eight types; these two (and
`terminal_card`) are missing.

Port `permission_card` first (it can hard-block the house), then
`choice_card`. Both need their answer path: the files decide POST, and the
choice reply as a `text_query`. `terminal_card` can stay unsupported but the
Apps card library already marks it so; keep that honest.

### 4. The speaking wedge and the two crash-on-input unwraps

- No barge-in and no cancel: the talk button, stage tap, and text field are
  all disabled during SPEAKING, and `TTSStreamPlayer.stop()`
  (`Audio/TTSStreamPlayer.swift:221`) has zero callers. A phone call
  mid-reply stops both engines, the completion sentinel never plays, there is
  no SPEAKING watchdog, and the app wedges in SPEAKING permanently.
  Fix together: allow tap-to-interrupt during SPEAKING (call `stop()`, return
  to IDLE), add a SPEAKING watchdog, and handle
  `AVAudioSession.interruptionNotification` and
  `routeChangeNotification` (currently zero matches in the tree).
- `TTSStreamPlayer.swift:72` force-unwraps `AVAudioFormat` built from the
  wire's `sample_rate`; a bad value crashes the app. Guard and fall back.
- `SpeechRecognitionManager.swift:38` force-unwraps
  `SFSpeechRecognizer(locale:)` at ChatViewModel construction; an
  unsupported-locale device crashes on launch. Make it optional and surface
  a disabled-mic state.
- `TTSStreamPlayer.swift:73` assigns `audioFormat` before `engine.start()`;
  on start failure every later guard passes against a dead engine and the app
  sits in SPEAKING forever. Nil it in the failure branch.

## Tier 1. Daily quality of life

> STATUS (2026-08-16, Windows session): tasks 5 through 8 are BUILT on
> `feat/ios-qol-tier0`, unverified on device. Notes against the plan:
> tap-to-send replaced tap-to-discard (discard moved to the stage tap); the
> countdown shipped as an explicit "sends when you pause" hint rather than a
> timer bar; mic level drives the talk button's glow; keepalive is 20 s and
> the pong transcript row is gone; speak-replies off is volume zero so the
> karaoke caption still reveals in playback time; permission priming runs
> right after pairing succeeds in first run.

### 5. Transcript persistence, per persona

Nothing is persisted; relaunch loses everything, and switching personas keeps
the previous persona's turns in the feed. Mirror desktop: persist per-persona
transcripts (JSON file in Application Support, not UserDefaults; transcripts
are unbounded), restore on persona change, write on append, and copy
desktop's boot-sequence guard (`appStore.ts:219-232`): `personas_list` then
`persona_config` both name the current persona, and without the equality
check the second wipes what the first restored. `ChatMessage` needs
`Codable`. Add Settings > clear history (all and per persona) alongside.

### 6. Voice UX honesty

1. Tapping "Listening" currently discards your speech; the only submit path
   is the 1.5 s silence timer with no on-screen indication. Make the tap
   commit the partial transcription instead, and show the auto-submit
   countdown.
2. Permission denial is written to a transcript pane that is collapsed by
   default, so denying the mic makes the button look dead. Surface denial as
   an alert with a Settings deep link (`UIApplication.openSettingsURLString`),
   and prime permissions once during first run instead of two stacked system
   alerts on first tap. Also check authorization before `isAvailable`
   (`SpeechRecognitionManager.swift:58-80` does it backwards, which can throw
   recognizerUnavailable before the permission dialog ever shows).
3. STT runtime errors are bound to `_` (`ChatViewModel.swift:187`); surface
   them.
4. Add haptics for listen-start, commit, and error; zero exist today and this
   is a voice-first app used without looking at the screen.
5. Feed the mic level into the listening pulse; the buffer is already in hand
   at `SpeechRecognitionManager.swift:93` and the pulse is currently a fixed
   timer regardless of whether the mic works.
6. Add an application-level keepalive ping (15 to 30 s). Desktop pings every
   5 s; iOS `sendPing()` has no caller, so half-open sockets surface only
   when the next turn fails.

### 7. Lifecycle: scenePhase

Zero scenePhase handling exists. On background: stop listening, tear down
the socket intentionally. On foreground: reset `reconnectAttempt` and dial
immediately, so the user does not return to a backoff loop already at the
30 s cap with a disabled talk button.

### 8. Settings parity

- Start-with persona pin, enforced with desktop's rule: on `personas_list`,
  send `switch_persona` only when the pin is set, differs case-insensitively
  from `current_persona`, and exists in the served list. Today
  `onPersonasListReceived` (`ChatViewModel.swift:308`) unconditionally adopts
  the house's persona, so the "remembered" persona is cosmetic.
- Auto-reconnect toggle.
- Voice section: speak-replies toggle and volume.
- The Apps view is deliberately read-only; add one line under its header
  saying changes are made on the machine running the house, so the inert rows
  read as intended rather than broken.

## Tier 2. Polish

### 9. Journal to sessions bridge

The Journal is the only place past conversations appear on iOS and none can
be reopened. Once task 1 lands: `JournalEntry` decodes only `t/d/s`; add
`slug` and `has_transcript`, put Resume on the entry detail, and let shelf
books start a topic session by title. Add the search box desktop has.

### 10. Platform basics

- Dynamic Type: 166 fixed `.font(.system(size:))` call sites and zero
  `relativeTo:`; `ClientProfile` explicitly promises "iOS follows the OS."
  Convert the main surfaces (timeline, settings, shelf) first.
- Accessibility labels on Journal books, shelf rows, Apps rows (seven labels
  exist in the whole app).
- Keyboard avoidance: the GeometryReader-driven stage resizes as you type;
  test small devices and pin a minimum.
- Journal hardcodes light-mode browns (`JournalView.swift:254`, `:276`,
  `:354`, `:416`) while the rest of the app has genuinely good dark-mode
  token support; route them through `HearthPalette`.
- iPad and landscape are stretched-phone today; defer real adaptation, but
  note it.

### 11. Small cleanups

- `onPongReceived` writes "Server ping successful" into the transcript
  (`ChatViewModel.swift:427`); drop it.
- `replaceLastAiMessage` (`ChatViewModel.swift:1027`) targets by type, so
  interleaved cards make finalization overwrite the wrong row; hold the
  streaming message id instead.
- `handleTtsSentence` appends unconditionally on `segIdx == 0` (`:834`);
  guard against duplicate segment 0.
- `SpeechRecognitionManager`'s silence `Timer` is scheduled from the
  recognition callback thread; if that queue has no run loop the only
  auto-submit path in the app never fires. Hop to main for all timer and
  state mutation.
- `Info.plist` mic string claims the app streams voice off-device; STT is
  on-device now. Fix the copy before it meets App Review.
- `AppsView.swift:356` opens the private `App-prefs:` scheme; replace or
  remove.
- Delete the orphaned `AudioSessionManager.shared`,
  `requestMicrophonePermission()`, `isDebugMode`/`setDebugMode`, and the
  unused `audioInputManager` reference, or wire them.
- `sessionSummary` is stored and shown only in the widget; surface it in-app
  when a session ends (pairs naturally with task 1's wipe).
- Per-turn `AVAudioEngine` allocation in `SpeechRecognitionManager`; reuse
  the engine, and validate `inputNode` format sample rate before
  `installTap` (a mid-handoff Bluetooth route throws an uncatchable ObjC
  exception today).
- The TTS amplitude tap runs for the process lifetime once installed, with a
  linear `segmentMarks` scan under a lock on the realtime audio thread; stop
  the tap when playback stops and index the marks.
