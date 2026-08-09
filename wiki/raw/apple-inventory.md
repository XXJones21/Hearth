---
title: Apple Client Inventory
status: draft
last_reviewed: 2026-08-07
related:
  - ../backend/component-catalog.md
  - ../backend/portability-ledger.md
  - ../_index.md
sources:
  - D:/Tools/Valinor/Apple Client/Valinor/
  - D:/Tools/Valinor/wiki/clients/apple-client.md
  - D:/Tools/Valinor/wiki/clients/visionos-client.md
  - D:/Tools/Valinor/tasks/hearth-prealpha-handoff.md
  - D:/Tools/Valinor/tasks/caustics-immersive-handoff.md
---

# Apple Client Inventory

Everything in Valinor's Apple client, what it is coupled to, and which parts
belong in Hearth. Compiled 2026-08-07 from a read-only pass over
`D:\Tools\Valinor\Apple Client\` on branch `hearth-journal`, plus a branch
survey of the five branches that carried Apple work.

This is the first of three documents for extracting the iOS and visionOS
surfaces into a clean Xcode project under Hearth. It answers three questions,
in the order the extraction needs them:

1. What is actually in there.
2. What does each piece assume about Joshua's house.
3. Which pieces cross into the product.

The precedent is the desktop extraction. `Valinor/hearth-client/` became
`Hearth/desktop-client`, scrubbed of the old branding, with its own bundle
identifier so the two clients cannot share a profile. The Apple side is harder
in exactly one way: an Xcode project carries signing identity, entitlements,
an App Group and a URL scheme, and every one of those is a namespaced string
that has to change together or the app will not install.

## How to read this

Every component carries a `ships in Hearth` verdict, on the same rule the
[backend catalog](../backend/component-catalog.md) uses. Valinor is the
superset and keeps everything. Hearth ships the subset, and the verdict is
decided once here rather than re-argued per file.

`undecided` means a real question is open and guessing would be worse than
saying so. Each undecided row names the question that settles it. There are
four of them, listed together at the end.

Line counts are exact and are there to size the work, not to grade it.

## The project

One Xcode project, `Apple Client/Valinor/Valinor.xcodeproj`, at object version
77. It uses file-system synchronized root groups, so folders on disk are the
group structure and new files join their target automatically. That is worth
knowing up front, because the two `membershipExceptions` sets are the only
places where the on-disk layout and the build graph disagree, and both handoff
documents in `tasks/` record time lost to exactly that.

**Two targets. No watch target, no App Intents extension, no test target.**

| Target | Product | Platforms | Deployment | Device family |
| --- | --- | --- | --- | --- |
| `Valinor` | `Valinor.app` | iphoneos, iphonesimulator, xros, xrsimulator | iOS 26.0, visionOS 27.0 | 1, 2, 7 (iPhone, iPad, Vision Pro) |
| `ValinorWidgetsExtension` | `.appex`, embedded | iphoneos, iphonesimulator | iOS 26.2 | 1, 2 |

The app target is one binary for both iOS and visionOS, split by
`#if os(visionOS)` in `ValinorApp.swift` and by a per-SDK Info.plist
(`INFOPLIST_FILE[sdk=xros*]` points at `Info-visionOS.plist`). Mac Catalyst is
off and "Designed for iPad" on Vision Pro is off, so visionOS gets the native
build and nothing else.

**The widget extension is iOS only.** Its device family is `1,2` with no `7`.
Valinor's visionOS article describes the widget as shipping to visionOS with a
`.recessed` spatial treatment; the project does not do that today. Whoever
copies the article into Hearth should not copy that claim.

**visionOS 27.0 is the floor**, not 26. The immersive caustics work uses
`SpotLightComponent.ProjectiveTexture` and `SurroundingsLight`, which are 27
APIs. That pins the visionOS surface to a version that was in beta as of
June 2026.

There is one scheme, `Valinor`. It is marked shared in the per-user scheme
management file, but `Valinor.xcodeproj/xcshareddata/` does not exist, so the
scheme is not actually in the repository and Xcode regenerates it per user.
A fresh clone gets an autocreated scheme. Fixing that is a one-file addition
and worth doing during the extraction rather than after.

### Dependencies

Two package references, three linked products.

| Package | Version | Products linked | Notes |
| --- | --- | --- | --- |
| `facebook/meta-wearables-dat-ios` | 0.4.0 | `MWDATCore`, `MWDATCamera`, `MWDATMockDevice` | `platformFilter = ios`; no visionOS slice exists |
| `ml-explore/mlx-swift-lm` | branch `main` | none | referenced, resolved, and linked into no target |

MLX is the interesting one. It appears in `packageReferences` and pulls
fourteen transitive pins into `Package.resolved` (mlx-swift, swift-transformers,
swift-huggingface, swift-jinja, yyjson, NIO, swift-crypto and the rest), but it
is absent from every target's `packageProductDependencies`. Nothing links it.
`OnDeviceInferenceEngine.swift` guards its entire body on `#if canImport(MLX)`,
which is currently false, so the on-device path compiles to a stub that reports
itself unavailable. Commit `cffc3a3` is titled "exclude MLX from build" and this
is what it did. Dropping the package reference during extraction removes
fourteen pins and costs nothing that runs today.

## Source inventory

74 source files, 15,439 lines: 73 Swift files at 15,323 lines plus one Metal
compute kernel at 116.

| Area | Files | Lines | What it is |
| --- | --- | --- | --- |
| `Valinor/` root | 8 | 1,696 | app entry, socket client, server config, audio in and out |
| `Shared/` | 8 | 989 | palette, icons, orb, persona config decode, capability table, widget snapshot |
| `Models/` | 9 | 1,258 | wire types and the four house-surface decoders |
| `ViewModels/` | 1 | 1,386 | `ChatViewModel`, the whole client state machine |
| `Views/` root | 8 | 1,649 | the stage, the shelf, the status bar, the composer, the legacy chat |
| `Views/Dynamic/` | 10 | 1,721 | the card system: store, descriptor, registry, renderers, easel |
| `Views/Journal/` | 3 | 798 | Selene's library in portrait |
| `Views/Persona/` | 2 | 789 | the persona page and its controls |
| `Views/Apps/` | 2 | 1,016 | Apps and Extensions, plus the card library sheet |
| `Views/Settings/` | 1 | 402 | `HearthSettingsView` |
| `Views/Timeline/` | 1 | 283 | the interleaved transcript feed |
| `VisionOS/` | 5 | 869 | volumetric scene, immersive caustics scene, orbit layout, transcript card, gallery |
| `Visualization/` | 6 | 1,360 | RealityKit orb, character renderer, caustics texture and kernel, motion |
| `OnDevice/` | 4 | 734 | MLX engine stub, model downloader, router, persona cache |
| `Compat/` | 1 | 118 | MWDAT no-op shim for visionOS |
| `ValinorWidgets/` | 5 | 371 | two widgets, provider, orb, bundle |

### Shared code, the parts both surfaces run

`ValinorWebSocketClient.swift` (660) is the transport: one
`URLSessionWebSocketTask`, receive loop started before `client_info`, 5s
handshake timeout, exponential backoff to a 30s ceiling, binary frames over 1MB
rejected rather than closing the socket. `ChatViewModel.swift` (1,386) is
everything else: the turn state machine, the tool activity list, the caption
scheduler, the Ray-Ban lifecycle, the widget snapshot publisher, and the
persona switch.

`Shared/` is the part that is already product-shaped. `HearthPalette.swift`
(237) writes each token once as a hex literal and decodes it into both a
SwiftUI `Color` and a `SIMD3<Float>` so the flat and RealityKit renderers
cannot drift; surfaces and ink are dynamic light and ember providers, the fire
colours are not. `HearthIcons.swift` (133) is the desktop's `icons.tsx` redrawn
as SwiftUI shapes on the same 24-unit grid. `ClientProfile.swift` (63) is the
Swift mirror of `clientProfile.ts`, and it already knows about four clients
including `desktop`. `PersonaOrb.swift` (231) is the Canvas renderer, and it is
a member of both targets.

STT is `SpeechRecognitionManager.swift` (192): `SFSpeechRecognizer` with
`requiresOnDeviceRecognition = true`, partial results, a 1.5s silence timer to
finalise what the recogniser will not, and errors 203 and 216 swallowed. No
audio leaves the phone. TTS in is `TTSStreamPlayer.swift` (255): float32 LE mono
PCM onto an `AVAudioPlayerNode` that never stops between sentences, end of
playback detected with a 50ms silent sentinel buffer, and the frame-offset marks
that make captions follow what is heard rather than what has arrived.

Two audio files are older than the live path and still wired.
`TTSAudioPlayer.swift` (139) plays whole audio blobs through `AVAudioPlayer` and
is still called from `handleAudioResponse`, so it is a live fallback for a
non-streaming server rather than dead code. `AudioInputManager.swift` (234)
contains a 48kHz to 16kHz capture and upload path that nothing calls;
`startStreaming()` has no caller anywhere. What is load-bearing in that file is
`configureForGlasses(_:)`, which owns the `AVAudioSession` category and mode and
is called from three places. The session logic has to survive the extraction;
the capture path does not.

### iOS-specific

`ValinorMainView.swift` (283) is the unified portrait stage: persona on top,
this turn's card in the middle, caption below, transcript expanding to take
55% when opened. `HouseShelf.swift` (233) is the 268pt right-hand drawer with
the four destinations. `BottomInputBar.swift` (193) is the three-button
composer.

The four house surfaces are `HearthSettingsView.swift` (402),
`AppsView.swift` (748) with `CardLibraryView.swift` (268),
`PersonaView.swift` (469) with `PersonaComponents.swift` (320), and the journal
trio `JournalView.swift` (446), `JournalBookView.swift` (179),
`JournalEntryView.swift` (173). The journal is the Selene's Library work merged
2026-08-03; all of it is on the current branch.

`ChatView.swift` (432) is the classic transcript, still reachable through
`ContentView` behind `@AppStorage("useClassicChatUI")` with nothing in the UI
to flip it. `VisualizationChatView.swift` (242) has no reference anywhere in
the tree and is genuinely dead. `MessageBubble.swift` (95) is used by both.

### Cards

Ten files, 1,721 lines, and the most reusable block in the project after the
transport. `CardStore.swift` (136) owns `upsert`, `clear` and `clear_all` plus
per-instance TTL, appending a new instance per upsert and capping at 40.
`UiComponentDescriptor.swift` (164) is the tolerant decoder: unknown keys
ignored, numbers accepted as int, double or string, only a missing `type` or an
unknown version fatal. `DynamicComponent.swift` (334) is the registry.

`CommissionedCards.swift` (235) is the exception. It holds
`choam_portfolio_dashboard` and `ticker_insight_card`, the two types the backend
catalog already ruled out of Hearth as "commissioned for the trading dashboard".
The type constants live in `UiComponentDescriptor.swift` and the registry
dispatch in `DynamicComponent.swift`, so removing them is three files, not one.

The drawing card is five files: `ImageCard.swift` (186), `EaselStore.swift`
(165), `ImageViewer.swift` (159), `ImageActions.swift` (124), and
`RemoteImage.swift` (107) which the slideshow shares. It polls
`/imagery/state`, which the backend serves from ComfyUI, and ComfyUI is a `no`
in the component catalog. That makes the drawing card the largest single block
whose fate follows a backend decision rather than a client one.

### visionOS-specific

`SulivanVolumeView.swift` (231) hosts the volumetric window;
`CausticsImmersiveView.swift` (423) is the mixed immersive space with the ARKit
`SceneReconstructionProvider` occlusion mesh and the spotlight projector;
`CardOrbitLayout.swift` (46) places cards around the orb;
`LiveTranscriptCardView.swift` (61) and `SessionGalleryView.swift` (108) are the
spatial transcript and picker.

The renderer is `RealityKitSceneManager.swift` (611), hoisted to `ValinorApp`
so the same orb entity reparents between the volume and the immersive space.
`CausticsTexture.swift` (138) drives a `LowLevelTexture` that `Caustics.metal`
(116) rewrites per frame. `PersonaModelView.swift` (335) is the `glb_animated`
character path shared with iOS. `DeviceMotionTracker.swift` (84) is used only
by the dead `VisualizationChatView` and by `VisualizationView.swift` (76), which
is itself only used by that dead view. Both are candidates to leave behind.

### Widgets

Five files, 371 lines. `SulivanWidget.swift` (183) is the persona in every size
with a card carousel at medium and large; `QuickTalkWidget.swift` (46) is the
small orb with "Tap to talk". Both are whole-widget links to `valinor://talk`.
`SharedSnapshot.swift` (78) is the Codable state published into the App Group.
`PulsingPersonaOrb.swift` (44) is the timeline-alternation approximation of
motion.

The widget chrome is hardcoded pre-Hearth violet: `Color(red: 0.47, green:
0.43, blue: 0.78)` in three places and a near-black `0.06, 0.06, 0.10`
background in the provider, none of which come from `HearthPalette`. The orb
inside renders warm because it goes through the palette fallback. The widgets
are the one surface where the old brand is still visible.

### Assets

There are none. Both asset catalogs contain only `Contents.json`. `AppIcon` has
three declared 1024px slots (universal, dark, tinted) with no image files, and
`AccentColor` is an empty colorset. No app icon exists on either target, which
matches the desktop client's state in the pre-alpha handoff.

**Selene's 3D assets are not in the Apple tree and not in the repository at
all** for the app's purposes. The canonical files live at
`Persona/Selene/Assets/selene.glb` and `Persona/Selene/Assets/usdz/selene-{idle,
listening,speaking,thinking}.usdz` and are served by Valar. The client also
looks for bundled copies with `Bundle.main.url(forResource: "selene-idle",
withExtension: "usdz")`, and the folder those come from,
`Apple Client/Valinor/Valinor/PersonaModels/`, is gitignored on purpose. So a
fresh clone builds an app that cannot show Selene offline, and nothing in the
build fails to say so. That has to be a deliberate decision in Hearth, not an
inherited accident.

## Branch reality

**All Apple work is merged.** Every branch that ever carried it is an ancestor
of `hearth-journal`, verified with `git merge-base --is-ancestor` against
`origin/hearth-ios`, `generative-ui`, `valinor-vision`, `ios-generative-ui`,
`visionos-gen-ui` and `origin/ios-portal`. The diff between `HEAD` and
`origin/hearth-ios` under `Apple Client/` is empty.

Exactly one file exists on other branches and not on `hearth-journal`:
`Views/SettingsView.swift`, the legacy settings page, deleted on purpose in
commit `917ff9d` because a Settings row inside Settings was redundant. It is
not a loss.

So the extraction reads one branch. That is the good news, and it is worth
stating plainly because the wiki still describes the visionOS surface as "being
built on the `visionos-gen-ui` branch", which stopped being true some time ago.

**What is unverified is a different question from what is unmerged.** The
immersive caustics work was pushed from a Windows session with no Vision Pro
attached, and `tasks/caustics-immersive-handoff.md` opens by telling the Mac
session that three files exist on disk but are not target members and that
`Caustics.metal` must be added to Compile Sources or the kernel silently fails
to load. Five later commits (`9452ef4` "device-build fixes", `8b985ed`,
`467bebd`, `0141e8b`, `de6400c`) read as that Mac session iterating on device,
so the feature was worked on with hardware. Nothing in the repository states it
passed. Treat the caustics mode as built and iterated but not signed off, and
treat the volumetric orb as validated, which the Valinor wiki does record.

The file-system synchronized groups make the target-membership trap much less
likely to recur, since files now join their target by living in the folder. The
two `membershipExceptions` sets are the remaining manual surface, and both are
correct today.

## Coupling audit

Ordered by how much of the extraction each one blocks.

### 1. The server address, and the port that is wrong for Hearth

**Severity: blocker. Effort: trivial.**

`ServerConfig.swift` defaults to `10.1.95.5:8700`. The host appears twice as a
literal (`serverIP` getter and `defaultHost`) and the port twice (`serverPort`
getter and `defaultPort`).

Hearth's desktop client dials `18700`, not `8700`, and `src/lib/config.ts` says
why in a comment: the development machine runs the internal Valinor stack on
8700, so a Hearth build defaulting to 8700 would silently adopt the personal
house. The iOS client has the same failure mode and worse consequences, because
a phone is the client most likely to be handed to someone else.

A phone also cannot default to `127.0.0.1` the way the desktop can, since the
server is on another machine by definition. So this is not a one-line port
change. It is a decision about what a Hearth phone shows before it has been
told an address: a blank field, a discovery step, or a pairing flow from the
desktop that already knows the host. That question is listed as undecided
below.

Two smaller address bugs sit in the same class.
`LocalModelManager.swift:150` still builds `http://<ip>:8766/...` for GGUF
downloads, a port that has not answered since Valar became the single entry
point in June. `PersonaStore.swift` had the identical bug and was fixed;
the comment there records it. The Valinor wiki already flags this one as
open.

### 2. Identity: the bundle, the group, the scheme, the team

**Severity: blocker. Effort: moderate, and it must be done as one change.**

Six namespaced strings all carry `Valinor` or Joshua's identity, and they are
coupled to each other:

| Where | Value |
| --- | --- |
| App bundle id | `com.joshuajones.Valinor` |
| Widget bundle id | `com.joshuajones.Valinor.ValinorWidgets` |
| App Group, both entitlements | `group.com.joshuajones.Valinor` |
| App Group id in code | `SharedSnapshot.swift:57`, same string as a literal |
| URL scheme | `valinor`, in both Info.plists, plus `valinor://talk` in the widgets and `valinor://` in the MWDAT block |
| Development team | `AS9PH6XDN4`, in four build configurations |

The desktop precedent gives the target shape: `com.hearth.release.app`, chosen
so the two clients do not share a WebView2 profile. The Apple equivalent has to
change the bundle id, the widget id, the App Group in three files (two
entitlements and one Swift literal, which will not fail to compile if you miss
it), and the URL scheme in five places. Miss the App Group in one and the
widgets go permanently blank with no build error.

The URL scheme is the subtlest. `valinor://` is registered for two different
purposes at once: the widget deep link, and MWDAT's OAuth callback, declared in
`Info.plist` under `MWDAT.AppLinkURLScheme`. `ValinorApp.handleOpenURL`
intercepts `valinor://talk` before forwarding everything else to the SDK.
Renaming the scheme means renaming it in the MWDAT dictionary too, and that
value is also registered on Meta's side against the Meta App ID. If the Ray-Ban
integration does not ship, this collapses to a simple rename.

Also in this class: `INFOPLIST_KEY_NSMicrophoneUsageDescription` and
`NSMotionUsageDescription` are set in build settings and again in
`Info.plist`, and every usage string in both plists plus
`Info-visionOS.plist` says "Valinor" to the user. There are eight of them
across the two plists.

### 3. Valinor-only surfaces reached from product screens

**Severity: silent. Effort: moderate.**

None of these break a build. All of them show a stranger something that belongs
to Joshua's house.

**Mentat.** `Models/MentatState.swift` (99) polls `GET /mentat/state` every
five seconds from `HouseStatusBar`, which is on the main screen. Mentat's run
registry is `no` in the backend catalog (22 absolute paths, every run personal
project work). The poller is quiet on failure, so in Hearth it would poll a
404 forever and show nothing. Harmless and pointless. Remove the file and the
one status line that consumes it.

**Wright, Liara and the trading desk.** `HouseStatusBar.swift:79-95` is a
seventeen-entry tool label table containing `consult_liara` mapped to "Ringing
the trading desk", `wright` mapped to "Bringing in Wright", `uefn_` mapped to
"Working in the editor", and `mentat_` mapped to "Talking to Mentat". Four rows
name systems the catalog says do not ship. The table is data, so this is a
four-line deletion, but it has to actually happen or Hearth users will
occasionally be told the house is ringing a trading desk.

**CHOAM.** Three code sites: the two commissioned card renderers in
`CommissionedCards.swift`, the type constant
`choam_portfolio_dashboard` in `UiComponentDescriptor.swift:41`, and the
registry dispatch in `DynamicComponent.swift`. A fourth site is a layout comment
in `ValinorMainView.swift:158` that uses the CHOAM dashboard's 550pt height to
justify the stacked stage, which is fine to keep as reasoning but should lose
the name.

**`PersonaSurface.swift`** filters internal personas by the server's `internal`
flag rather than by name, which is the right design and needs no change. Its
comments name Liara, Mentat, Wright and Sage as examples; those are comments,
not coupling.

**Seeded journal fixtures.** `ChatViewModel.swift:1184-1200` carries six
hardcoded session entries with real dates, `"project": "valinor"`, and titles
like "CHOAM market load latency". `JournalModels.swift` supplies keeper
summaries for the three living volumes with `persona: "Selene"` baked in.
These are development fixtures that render as content. A first-run Hearth phone
would show a stranger six sessions from Joshua's June.

### 4. Persona names in code rather than in config

**Severity: degraded. Effort: trivial.**

The renderer switch is properly data-driven: `PersonaVisualization` decodes
`visualization.type` and nothing anywhere says "if Selene". That part is clean
and should be preserved exactly.

What is not clean is the defaults. `"Sulivan"` is the fallback persona name in
five places (`ChatViewModel` twice, `SharedSnapshot.placeholder`,
`JournalModels`, `TimelineFeed`), and `"Valinor"` is the fallback in four more
inside `ValinorWebSocketClient` and `ChatViewModel`, so an unnamed reply is
currently attributed to "Valinor". The widget type is literally named
`SulivanWidget` with `kind: "Sulivan"`, and the visionOS scene is
`SulivanVolumeView` with scene ids `sulivan-volume` and `sulivan-caustics`.

Hearth ships Sulivan, so the name is not wrong. Whether a widget kind string
should be a persona name is a different question, and changing a widget's
`kind` after release orphans every placed widget. Decide it once, before the
first build anyone installs.

`CardLibraryView.swift:257` hardcodes two sample image paths under
`/Persona/Selene/Assets/`, which resolve only where Selene's assets exist.

### 5. Ray-Bans, MWDAT, and a whole platform's worth of plumbing

**Severity: structural. Effort: large to keep, small to drop.**

MWDAT touches more of the project than its feature footprint suggests: three
linked SPM products, a 118-line no-op shim that exists solely so the shared
view model compiles for visionOS, a `Wearables.configure()` call in the app's
`init` that runs before anything else, the URL scheme sharing described above,
four Info.plist keys (`NSBluetoothAlwaysUsageDescription`,
`UIBackgroundModes` for `bluetooth-peripheral` and `external-accessory`,
`UISupportedExternalAccessoryProtocols` for `com.meta.ar.wearable`, and
`LSApplicationQueriesSchemes` for `fb-viewapp`), and a live row on the Apps
page.

The `MWDAT.ClientToken` and `MWDAT.MetaAppID` values in `Info.plist` are empty
strings. Whatever makes registration work today is not in the repository, which
puts this in the same class as the backend's systemd drop-ins: configuration
that exists only on the machine it was configured on.

Per Valinor's wiki the camera is wired but silent, with frames decoding at 1fps
and `processFrame` stopping short of forwarding them. Audio and registration
work. This is the single largest yes-or-no in the inventory and it is listed as
undecided.

### 6. Smaller items

- **Defaults keys are namespaced to Valinor**: `valinor_server_ip`,
  `valinor_server_port`, `valinor_last_persona`, and the widget snapshot key
  `valinor.snapshot.v1`. Two others already use the new prefix
  (`hearth.transcriptShown`) or none (`useClassicChatUI`). A rename is free
  before release and a migration after.
- **`PersonaStore` writes to `Documents/valinor-personas/`.**
- **`ValinorState` is the state enum's name**, referenced across roughly a
  dozen files including both widget and app targets.
- **Debug output is `print` with `[ValinorApp]` and `[TTS]` prefixes.**
  `sendDebug` was correctly reduced to a local print after Valar answered every
  socket breadcrumb with an error the timeline then rendered as a user-facing
  row. The lesson is captured; the prefixes are cosmetic.
- **`LocalModelManager` names a "Valinor Agent Adapter"** as a user-visible
  download row.

## The boundary proposal

Verdicts follow the backend catalog's rule: Hearth ships the chat shell,
persona rendering, journal, settings and voice. Valinor-only surfaces stay
behind.

### Ships

| Component | Ships | Why |
| --- | --- | --- |
| `ValinorWebSocketClient` | yes | the protocol is the product; rename only |
| `ChatViewModel` | yes | the state machine, minus the Mentat and fixture blocks |
| `Models/`: `ClientInfo`, `ServerMessage`, `ChatMessage`, `ValinorState` | yes | the wire contract |
| `Models/SettingsSurface`, `AppsSurface`, `PersonaSurface` | yes | the house surfaces Hearth serves |
| `Models/JournalModels` | yes | strip the seeded keeper summaries |
| `ServerConfig` | yes | with a new default and port, see undecided |
| `Shared/HearthPalette`, `ColorHex`, `HearthIcons` | yes | already Hearth-branded |
| `Shared/PersonaOrb`, `PersonaPalette`, `PersonaVisualization` | yes | the persona render contract, data-driven already |
| `Shared/ClientProfile` | yes | already knows four clients by table |
| `Shared/SharedSnapshot` | yes | App Group id is the only change |
| `SpeechRecognitionManager` | yes | on-device STT is a product claim, not a convenience |
| `TTSStreamPlayer` | yes | the streaming PCM path |
| `AudioInputManager`, session config only | yes | `configureForGlasses` owns the category and mode |
| `ValinorMainView`, `HouseShelf`, `BottomInputBar`, `HouseStatusBar` | yes | the shell; status bar loses four label rows and the Mentat line |
| `Views/Timeline/TimelineFeed` | yes | transcript history is the card model |
| `Views/Dynamic/`: `CardStore`, `UiComponentDescriptor`, `DynamicComponent`, `GeneratedViewCard` | yes | the builtin v1 card vocabulary |
| `Views/Settings/HearthSettingsView` | yes | Connection is the section that matters most on a phone |
| `Views/Apps/AppsView`, `CardLibraryView` | yes | the honest answer to "what can this thing do" |
| `Views/Persona/PersonaView`, `PersonaComponents` | yes | two editable fields, both file-local |
| `Views/Journal/` three files | yes | if memory ships, and it is the reason Selene ships |
| `Visualization/RealityKitSceneManager` | yes | the visionOS renderer, if visionOS ships |
| `Visualization/PersonaModelView` | yes | the `glb_animated` path; Selene is a Hearth persona |
| `VisionOS/` five files | yes | if visionOS ships, see undecided |
| `Compat/WearablesShim` | conditionally | exists only to make MWDAT compile for visionOS; dies with MWDAT |
| `ValinorWidgets/` five files | yes | rebrand the violet chrome from the palette |

### Does not ship

| Component | Ships | Why |
| --- | --- | --- |
| `Models/MentatState` and its status line | no | Mentat's run registry is Valinor-only in the backend catalog |
| Four tool labels: `consult_liara`, `wright`, `uefn_`, `mentat_` | no | name systems that do not ship |
| `Views/Dynamic/CommissionedCards` plus its two type constants and registry rows | no | the two card types the catalog already excluded |
| Seeded journal fixtures in `ChatViewModel` and `JournalModels` | no | one person's sessions rendered as product content |
| `Views/VisualizationChatView` | no | dead, referenced nowhere |
| `Visualization/VisualizationView`, `DeviceMotionTracker` | no | used only by the dead view |
| `Views/ChatView`, `ContentView` classic path, `MessageBubble` classic use | no | superseded shell behind a toggle nothing exposes |
| `TTSAudioPlayer` | no | the pre-streaming blob player; Hearth serves one TTS engine and one format |
| `AudioInputManager` capture path (`startStreaming`, `processAudioBuffer`) | no | no caller; server-side Whisper is not the phone's path |
| `OnDevice/OnDeviceInferenceEngine`, `InferenceRouter` | no | MLX is unlinked and the engine is a stub |
| `OnDevice/LocalModelManager` | no | downloads from a port that has not answered since June |
| `mlx-swift-lm` package reference | no | fourteen pins for a path that does not compile in |
| `CardLibraryView` Selene sample image paths | no | replace with paths that resolve on any install |

### Undecided

Four rows, each with the question that settles it.

| Component | Question that decides it |
| --- | --- |
| **Ray-Bans and the whole MWDAT block** (3 SPM products, `Compat/WearablesShim`, the shared URL scheme, 4 Info.plist keys, an Apps page row) | Is a Meta wearable part of the Hearth product, or a Valinor-only peripheral? The camera never forwards a frame today, and keeping it means Hearth ships a Meta SDK, a Meta App ID, and a Bluetooth permission prompt on first launch. Dropping it also deletes the shim and simplifies the URL scheme rename. |
| **The visionOS surface at all** (5 `VisionOS/` files, `RealityKitSceneManager`, `CausticsTexture`, `Caustics.metal`, 869 + 865 lines) | Does the pre-alpha ship to Vision Pro? It is the most distinctive thing in the client and it costs a visionOS 27 floor, a second Info.plist, an unsigned-off caustics mode, and an ARKit world-sensing permission. A defensible answer is to ship iOS first and keep the visionOS code in the project unbuilt, which the per-SDK plist already supports. |
| **The drawing card** (`ImageCard`, `EaselStore`, `ImageViewer`, `ImageActions`, 634 lines; `RemoteImage` is shared and stays either way) | Does image generation ship? This is open decision 4 in the backend catalog, not a client decision. If ComfyUI is out, these four files follow it out and `PersonaModelView` keeps `RemoteImage`. |
| **What a Hearth phone dials before it is told an address** | The desktop can default to `127.0.0.1:18700`; a phone cannot. Blank field, discovery, or pairing from the desktop that already knows the host? This gates `ServerConfig` and the first-run experience on iOS, and it is the one item here that is genuinely unbuilt rather than merely undecided. |

## What the extraction has to build that does not exist

Recorded so the second and third migration documents do not rediscover it.

- **App icons.** Both catalogs are empty. Same state as the desktop client.
- **A shared scheme.** There is none in the repository.
- **Selene's bundled USDZ set.** Gitignored, so a fresh clone cannot show her
  offline and nothing says so.
- **A first-run flow.** The desktop has `SetupFlow.tsx`. iOS has a settings
  field and a build-time default IP.
- **The MWDAT client token and Meta App ID**, if Ray-Bans ship. Empty in the
  repository, present on one machine.
- **A rebranded widget chrome.** Three violet literals and a near-black
  background, none from the palette.
