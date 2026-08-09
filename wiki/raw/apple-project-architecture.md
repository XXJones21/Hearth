---
title: Apple Project Architecture
status: draft
last_reviewed: 2026-08-07
related:
  - apple-inventory.md
  - apple-migration-plan.md
  - ../backend/native-runtime.md
  - ../backend/component-catalog.md
  - ../first-run.md
  - ../card-forge.md
sources:
  - D:/Tools/Valinor/Apple Client/Valinor/Valinor.xcodeproj/project.pbxproj
  - D:/Tools/Valinor/wiki/clients/apple-client.md
  - D:/Tools/Valinor/wiki/clients/visionos-client.md
  - D:/Tools/Valinor/tasks/caustics-immersive-handoff.md
  - D:/Tools/Valinor/tasks/hearth-prealpha-handoff.md
  - D:/Tools/Hearth/desktop-client/src/lib/config.ts
  - D:/Tools/Hearth/desktop-client/src/lib/settings.ts
  - D:/Tools/Hearth/desktop-client/src-tauri/tauri.conf.json
---

# Apple Project Architecture

The target shape for a clean Xcode project housing Hearth's Apple clients. It
is the counterpart of the desktop extraction: `Hearth/desktop-client` was not
copied out of Valinor's `hearth-client/` and patched, it was rebuilt with the
product's own identity, its own port block, and its own first-run behaviour,
and the parts that only made sense inside Valinor were left behind. This
article says what that means for iOS, visionOS and the widgets.

Everything here is a design decision with its reasoning attached. Nothing here
has been built.

## Why a new project rather than a rename

The existing project is `D:\Tools\Valinor\Apple Client\Valinor\Valinor.xcodeproj`.
It is a good project that grew sideways. The things that would have to change in
place are exactly the things Xcode makes expensive to change in place: the bundle
identifier family, the App Group, the deployment floors, the target topology, and
the dependency graph. Renaming a bundle identifier on a project that has already
installed on devices leaves stale containers, stale permission grants, and a
provisioning profile that no longer matches. Doing it once on an empty project
costs nothing.

The second reason is subtraction. Roughly a third of the current source serves
something Hearth does not ship: a dormant on-device inference tree, a wearables
SDK that needs a Meta developer registration, a Mentat run surface that the
component catalog already ruled out of the product, and two card types
commissioned for a trading dashboard. A new project makes each of those a
decision to include rather than a decision to delete, which is the difference
between a boundary that holds and one that erodes.

## What the current project actually is

Naming this precisely matters, because the recommendation below is a departure
from it and the departure needs a baseline.

**One `.xcodeproj`, two targets, no workspace, no local packages.**

| Target | Product | Platforms | Identifier |
| --- | --- | --- | --- |
| `Valinor` | app | `iphoneos iphonesimulator xros xrsimulator` | `com.joshuajones.Valinor` |
| `ValinorWidgetsExtension` | appex | iPhone, iPad (device family `1,2`) | `com.joshuajones.Valinor.ValinorWidgets` |

Source is organised by **file system synchronized folder groups**
(`PBXFileSystemSynchronizedRootGroup`, project object version 77, the Xcode 16
feature). The folder is the target: a new `.swift` file dropped into `Valinor/`
is compiled without touching the project file. This is a genuinely good property
and it should survive into the new project, because the alternative is the
failure mode the caustics handoff opens with, three new files sitting on disk
and absent from the build.

Sharing happens two ways, and they are different mechanisms:

1. **iOS and visionOS share by being the same target.** One app target builds
   for four SDKs, with per-SDK build setting overrides
   (`INFOPLIST_FILE[sdk=xros*] = Info-visionOS.plist`) and `#if os(visionOS)`
   guards in source.
2. **The widgets share by per-file membership exception.** A
   `PBXFileSystemSynchronizedBuildFileExceptionSet` lists five paths that the
   widget target also compiles: `Models/ValinorState.swift`,
   `Shared/HearthPalette.swift`, `Shared/PersonaOrb.swift`,
   `Shared/PersonaPalette.swift`, `Shared/SharedSnapshot.swift`.

Three costs follow from mechanism 1, and they are the argument for changing it.

- **`Compat/WearablesShim.swift` exists only because of it.** MWDAT ships
  iOS-only xcframeworks, so one target that also builds for visionOS cannot link
  it unconditionally. The answer was a hand-written no-op mirror of the SDK's API
  surface behind `#if !canImport(MWDATCore)`, with a comment instructing the next
  developer to stub any new MWDAT symbol they touch on a shared path. That is a
  maintenance obligation created entirely by the target topology.
- **Per-SDK Info.plist overrides are a trap that has already fired.**
  `NSWorldSensingUsageDescription` had to be added to `Info-visionOS.plist`
  specifically, because `INFOPLIST_FILE` is per-SDK and the key in the iOS plist
  never reaches the visionOS app. ARKit hard-crashes on the authorisation request
  when it is missing.
- **The reuse boundary is a folder name.** `Shared/` is a convention. Nothing
  fails a build when platform-specific code lands in it, and the visionOS
  article's own rule, that anything duplicated between the two surfaces should be
  lifted into `Shared/`, has no mechanical enforcement at all.

## 1. Project shape

**Recommendation: a workspace containing one `.xcodeproj` with four targets and
one local Swift package, `HearthKit`, that every target depends on.**

```
Hearth/apple-client/
  Hearth.xcworkspace
  HearthKit/                       local Swift package, the platform-neutral core
    Package.swift
    Sources/HearthKit/
    Resources/Personas/sulivan.json
  Hearth.xcodeproj
    Hearth iOS          (app)      iOS host scenes, portrait layout, MWDAT seam
    Hearth visionOS     (app)      volumetric window, immersive space, RealityKit orb
    Hearth Widgets      (appex)    embedded by Hearth iOS
    Hearth Widgets vOS  (appex)    phase 2, embedded by Hearth visionOS
  Config/
    Shared.xcconfig  Dev.xcconfig  Release.xcconfig  Local.xcconfig (gitignored)
```

### Why a package rather than a shared folder

A package target has an **explicit dependency list**, and that single property
solves the three costs above at compile time rather than by convention.

- `HearthKit` does not depend on MWDAT, so MWDAT cannot appear in it. The shim
  is deleted rather than ported. MWDAT, if it ever returns, is linked by the iOS
  app target alone and reaches shared code through a protocol that `HearthKit`
  declares and the iOS app conforms to.
- The widgets depend on `HearthKit` as a product. Sharing a sixth type becomes a
  `public` keyword instead of a sixth path in the project file, and it shows up
  in review as a Swift diff rather than a pbxproj diff.
- A package declares `platforms:` once, so the floor for shared code is stated in
  one place instead of being restated across build configurations.
- `swift build` typechecks the protocol and model layer without a simulator,
  which is the only part of this codebase that can be reasoned about from a
  Windows session at all. Today the whole thing requires Xcode on a Mac, and
  every verification is a handoff document.

The honest cost: access control has to be written (`public` on the shared
surface), SwiftUI previews across a package boundary are slightly fussier, and
the split has to be drawn deliberately rather than discovered. The mitigation is
to draw it once, at extraction, using the shared/not-shared table in Valinor's
`visionos-client.md` as the specification, since that table was written from the
working code and is already right.

### Why two app targets rather than one multiplatform target

The same argument, one level up. Per-target linkage is what deletes the shim.
Two targets also mean two ordinary `Info.plist` files owned by two targets, which
makes the world-sensing class of mistake structurally impossible instead of
merely documented. And the deployment floors genuinely differ (below), which the
single target currently expresses as two settings fighting inside one
configuration.

The cost is real and should be stated: **two bundle identifiers means two App
Store records**, not one listing that says "also available on Apple Vision Pro."
That cost is not live at pre-alpha, because nothing here goes to the App Store
yet and macOS signing is already deferred until after the M1 Air round. If a
single listing is later wanted, folding the visionOS target back into the iOS
one is possible, but it brings the shim back, so the decision should be made
before that and not during it.

### What goes in HearthKit

Drawn from the current file tree, and deliberately generous: if two clients could
plausibly want it, it is shared.

| Layer | Files, by their current names |
| --- | --- |
| Transport and protocol | `ValinorWebSocketClient`, `Models/ServerMessage`, `ClientInfo`, `ValinorState` |
| Address and origin | `ServerConfig` (the parser especially) |
| Persona | `PersonaVisualization`, `PersonaPalette`, `PersonaStore`, the bundled `sulivan.json` |
| Brand | `HearthPalette`, `ColorHex`, `HearthIcons`, `PersonaOrb` |
| Cards | `UiComponentDescriptor`, `CardStore`, `EaselStore`, `DynamicComponent` and its card views, `RemoteImage` |
| Capability table | `ClientProfile` |
| Audio | `TTSStreamPlayer`, `TTSAudioPlayer`, `AudioInputManager`, `SpeechRecognitionManager` |
| House surface clients | the HTTP clients behind Journal, Apps, Settings and Persona |
| Widget bridge | `SharedSnapshot` |

What stays in an app target is the host scene and anything whose *layout* is
platform-shaped: `ValinorMainView`, `HouseShelf`, `HouseStatusBar` and
`BottomInputBar` on iOS; `RealityKitSceneManager`, `SulivanVolumeView`,
`CardOrbitLayout`, `CausticsImmersiveView`, `CausticsTexture` and
`Caustics.metal` on visionOS. The rule of thumb that produced that list: a card
*view* is shared, the surface that arranges cards is not.

One package target to start, not three. Splitting inside a package later is
cheap; splitting across packages is not.

## 2. Targets and identifiers

The desktop precedent is explicit. Valinor's daily-driver client is
`com.hearth.app`; the extracted product is `com.hearth.release.app`, and the
pre-alpha handoff states the reason directly: the two must not share a WebView2
profile. Generalised, the rule is that **release identity lives in a different
namespace from development identity, so no operating-system store keyed by
identifier is ever shared between them.**

On Apple that store is not one thing, it is seven: the app container, the
`UserDefaults` suite, the App Group container, keychain items, the widget
timeline store, and the TCC grants for microphone, speech recognition and
photo-add. All of them key off identifier. A developer build installed over a
tester build silently inherits every one.

The current family is `com.joshuajones.Valinor`, widget
`com.joshuajones.Valinor.ValinorWidgets`, App Group
`group.com.joshuajones.Valinor`. It encodes a person and a codename, and neither
belongs in a product.

### Proposed family

| | Release | Development |
| --- | --- | --- |
| iOS app | `com.hearth.release.ios` | `com.hearth.dev.ios` |
| iOS widgets | `com.hearth.release.ios.widgets` | `com.hearth.dev.ios.widgets` |
| visionOS app | `com.hearth.release.vision` | `com.hearth.dev.vision` |
| visionOS widgets | `com.hearth.release.vision.widgets` | `com.hearth.dev.vision.widgets` |
| App Group, iOS | `group.com.hearth.release.ios` | `group.com.hearth.dev.ios` |
| App Group, visionOS | `group.com.hearth.release.vision` | `group.com.hearth.dev.vision` |
| Keychain access group | `$(AppIdentifierPrefix)com.hearth.release` | `$(AppIdentifierPrefix)com.hearth.dev` |

An app extension's identifier must be prefixed by its host app's, which is why
the widget extension cannot be one target embedded by both apps. Two apps means
two widget extensions. They can and should share all their code through
`HearthKit`; only the target and its `Info.plist` are duplicated.

The App Group strings match
[`apple-migration-plan.md`](apple-migration-plan.md) exactly, because an
executor will follow that checklist literally and two spellings of the same
group is the failure it warns about. The split that carries the weight is
release against development, not iOS against visionOS: the two platforms never
share a device, whereas a developer build and a tester build share one
constantly.

The keychain access group is declared for shape, not for use: nothing in the
client stores a secret today, because the server address lives in `UserDefaults`
and the WebSocket protocol has no authentication. The first thing to land there
will be whatever away-from-home access turns out to need, which is an open
question the transport milestone answers.

### How identity is selected

Not by typing it into four targets. `Config/Shared.xcconfig` defines everything
derived, and `Dev.xcconfig` / `Release.xcconfig` define one variable each:

```
HEARTH_ID_PREFIX  = com.hearth.release
HEARTH_APP_GROUP  = group.com.hearth.release
```

with `PRODUCT_BUNDLE_IDENTIFIER = $(HEARTH_ID_PREFIX).ios` and the entitlements
files reading `$(HEARTH_APP_GROUP)`. `DEVELOPMENT_TEAM` moves into a gitignored
`Local.xcconfig`, so the signing identity leaves source control and a second
developer can build without editing the project. It is `AS9PH6XDN4` today, hard
coded in the pbxproj.

The App Group is the string this buys the most on. It appears in both
entitlements files and again in Swift as `SharedSnapshot.appGroupID`, and a
mismatch between any two of the three compiles, signs, installs and runs: the
widget reads an empty container and draws its fallback orb, which looks exactly
like a widget that is working and waiting. Two of the three can read
`$(HEARTH_APP_GROUP)` directly; the Swift constant should be generated into the
build rather than typed, through an `INFOPLIST_KEY` the app reads back or a
generated source file, so the count of hand-maintained copies is one.

### A note on who creates the project file

`.xcodeproj` creation is Mac-only work, and a four-target project is more of it
than a two-target one. That makes a generated project worth considering:
XcodeGen or Tuist produces the `.xcodeproj` from a YAML or Swift spec, which
means the target topology, the identifiers, the deployment floors and the
package dependency edges all become reviewable text that a Windows session can
edit, and the project file becomes a build artifact rather than a merge hazard.
It also makes the four-target shape cost roughly what the two-target shape
costs, which removes the main practical objection to it.

The tradeoff is a tool in the loop that a fresh Mac session has to install
before it can open anything, and Xcode's own capability editor writes to the
project file rather than the spec, so entitlements changes have to be made in
the spec and regenerated. Decide it with the migration plan rather than
separately, since that document currently assumes a hand-created project with
one app target.

## 3. Minimum OS versions

The current settings, and what actually justifies them, do not match.

| Setting | Now | Recommended |
| --- | --- | --- |
| `IPHONEOS_DEPLOYMENT_TARGET`, app | 26.0 | 26.0, chosen deliberately |
| `IPHONEOS_DEPLOYMENT_TARGET`, widgets | **26.2** | 26.0, matching the app |
| `XROS_DEPLOYMENT_TARGET` | **27.0** | 26.0, with the caustics rig gated |

**The widget's 26.2 is an accident.** The target was created with Xcode 26.2
(`CreatedOnToolsVersion = 26.2`) and inherited the tool's default. Nothing in
five files of SwiftUI snapshot rendering needs a point release, and an embedded
extension with a higher floor than its host is a divergence nobody chose.

**Nothing in the iOS source requires iOS 26.** This is worth stating plainly
because it is easy to assume otherwise. A search of the whole client finds no
`glassEffect`, no `GlassEffectContainer`, no `.buttonStyle(.glass)`, no
`scrollEdgeEffect`: **Liquid Glass has not been adopted on iOS at all.** The five
`glassBackgroundEffect()` calls are in visionOS files and that API predates
visionOS 2. Speech is classic `SFSpeechRecognizer` with
`requiresOnDeviceRecognition`, not the newer analyser API. `Canvas`, `RealityKit`,
`AVAudioEngine` and `URLSessionWebSocketTask` are all long-standing.

The recommendation is still 26.0, but as a decision rather than a default. The
client is a fully custom design system, drawn icons and hand-authored palette
tokens, so Liquid Glass adoption is a visual choice that will be made or not
made on its merits; keeping the floor at 26.0 leaves it available without a
later floor change, and a pre-alpha tester pool cannot use the reach a lower
floor would buy. Revisit at public alpha against a device-share number rather
than a guess.

**The visionOS floor at 27.0 is wrong for shipping and should come down to
26.0.** [`apple-inventory.md`](apple-inventory.md) reads it the other way, that
27 is the floor because the caustics rig calls
`SpotLightComponent.ProjectiveTexture` and `SurroundingsLight`, which are
visionOS 27 APIs. Both halves of that are true and the conclusion still does not
follow: gated use of a newer API does not raise a deployment target. The
caustics handoff is explicit that the rig is written behind
`if #available(visionOS 27.0, *)` and that "deployment target stays 26.0, so it
must still compile and run on 26", and the source honours it with two
availability guards in `CausticsImmersiveView` at lines 259 and 289. Those are
the only availability checks in the entire client. The floor was raised anyway
at some point, and since visionOS 27 went to beta on 2026-06-08, a 27.0 floor
means the app installs on no generally available Vision Pro. What genuinely
needs 26 is the volumetric surface itself: RealityView attachments carry the
orbiting cards, and entity-targeted SwiftUI gestures carry gaze and tap. That is
the floor.

Swift language mode is 5.0 across the board today. The clean project is the
cheapest place to adopt Swift 6 in `HearthKit` only, where the code is protocol,
models and decoding and the concurrency story is simple. The app targets stay in
Swift 5 mode until the audio path, which spans an `AVAudioEngine` tap, a player
node and a recogniser callback, has been audited properly. Adopting strict
concurrency across that path as part of a migration is how a migration becomes a
rewrite.

## 4. Server contract

The client speaks to **Hearth's port block, never Valinor's**. The desktop's
`config.ts` states the reason and it applies with more force to a phone: a build
that defaults to 8700 will find the development machine's running Valinor house
and adopt its memory, journal and personas as the new user's. That produces
something that looks like a working first run and is not.

### One address, and it is not compiled in

The desktop defaults to `ws://127.0.0.1:18700` because it supervises its own
backend and the house is genuinely on that machine. **The Apple clients supervise
nothing**, so neither available default is honest: `127.0.0.1` on a phone is the
phone, and the current `ServerConfig.defaultHost = "10.1.95.5"` is a personal LAN
address compiled into a product. Worse, the current behaviour on clearing the
field is to restore that build-time default, so a stranger's install cannot get
away from it.

Recommendation: **no host default at all.** Port 18700 is the default; the host
is empty until someone enters it, and the app opens to a "where is your house?"
step rather than dialling anything. That is the Apple analogue of the desktop's
`setupComplete` flag, whose comment says exactly this: a fresh install "must not
quietly connect to anything already running on this machine and adopt its data as
though it were the user's own."

Everything else about the address field carries across unchanged, because it is
already well reasoned and was paid for in bugs. From `ServerConfig.address`:
strip a pasted scheme, split on the rightmost colon only when what follows is a
real port so an IPv6 literal survives, and let a bare hostname imply the default
port so a tailnet name pastes in cleanly. From the settings surface: **Apply
means redial**, because the socket only reads the address when it dials, and
**Test probes what is typed and then rolls back**, so a bad address cannot take
the live connection down before Apply commits it.

### One origin, and exactly one place that builds it

18766 is the supervisor's asset port. In the native runtime it lives inside the
install root's process tree alongside 18765 and 18080, and the client gateway on
18700 is the single client entry point, exactly as Valar is in Valinor. A client
that dials 18766 works on the developer's machine and fails on everyone else's,
and asking a user to type two addresses into Settings is not a product.

This is not hypothetical. `PersonaStore` hardcoded `:8766` for persona JSON, so
every sync fired one request per persona at a port nothing answered on and hung
until a 60 second timeout. It was dead for two months, hidden behind a second bug
in the `personas_list` decode. `LocalModelManager` still carries the same
hardcoded `:8766` today.

The rule for the clean project, stated so it can be checked by grep: **exactly
one type constructs an origin, and no port literal appears anywhere else in the
source.** Anything the server hands over as a relative path resolves against that
origin. If some asset class is not reachable through 18700, that is a server bug
to file, not a second port for the client to learn.

### Persona bundling, so first run renders with nothing listening

The desktop ships `src/personas/sulivan.json` inside the bundle and
`SetupFlow.tsx` imports it directly. That is what makes first run standalone:
the orb draws before any backend exists.

**The Apple client has no bundled persona at all.** `PersonaPalette.fallback` is
a set of warm constants written in Swift, a second copy of the numbers in
`Persona/Sulivan/sulivan.json` in a different language, free to drift. Ship
`Resources/Personas/sulivan.json` in `HearthKit`, decode it with the same
`PersonaVisualization` decoder that handles the wire payload, and make the
fallback read from it instead of restating it. Two things follow: first launch
renders the real Sulivan with nothing listening on any port, and the widgets,
which have no live connection by construction, stop being a third copy of the
palette.

### What does not change

The wire vocabulary is a protocol, not a brand. `client_info` keeps
`platform: "ios"` and `platform: "visionos"`, `stt: "local"` with
`stt_engine: "apple_speech"`, `ui_render: true`, and the `device_context` block.
A rename sweep would happily change those strings and break the server's
handling; they are constants.

The URL scheme is a brand and does change: `valinor://talk` becomes
`hearth://talk`. Note that the current `handleOpenURL` intercepts it before
forwarding to MWDAT, which owns `valinor://` for OAuth callbacks. With MWDAT out
(below), that interception disappears with it.

## 5. Dependency policy

`Package.resolved` pins fifteen packages. Two are referenced by the project:

- **`meta-wearables-dat-ios` 0.4.0**, providing `MWDATCore`, `MWDATCamera` and
  `MWDATMockDevice`. Linked into the app target.
- **`mlx-swift-lm`, tracked on `main` with no version pin.** It appears in the
  project's `packageReferences` and in **no target's**
  `packageProductDependencies`. It is resolved on every clean checkout and linked
  into nothing.

The remaining thirteen pins are the MLX chain and its transitive graph:
`mlx-swift`, `swift-transformers`, `swift-huggingface`, `swift-jinja`,
`swift-nio`, `swift-crypto`, `swift-asn1`, `swift-numerics`, `swift-collections`,
`swift-atomics`, `swift-system`, `yyjson`, `EventSource`. Thirteen checkouts on
every clean build, serving a dormant feature whose downloader points at a dead
port.

### MWDAT: out for pre-alpha

Four reasons, in descending weight.

1. It is the only dependency that forces a platform shim, and that shim is a
   standing obligation on every future developer who touches a shared path.
2. The delivered value is smaller than it sounds. The Ray-Ban camera path is
   wired and decodes frames at 1fps, but `processFrame` stops short of forwarding
   them; what works is registration and HFP audio, which is a Bluetooth headset
   story the operating system already tells.
3. It needs a Meta developer registration. `ClientToken` and `MetaAppID` are
   **empty strings** in the current `Info.plist`, so the integration is not even
   configured today. Asking a pre-alpha tester to register a Meta app in order to
   use a local-first companion inverts the product's premise.
4. It is expensive at the permission layer. It claims `UIBackgroundModes` of
   `bluetooth-peripheral` and `external-accessory`, plus
   `NSBluetoothAlwaysUsageDescription` and an external accessory protocol list.
   Those are prompts and review-visible entitlements a tester meets before
   receiving any value.

When it returns, it returns as an **iOS-app-only target dependency behind a
protocol declared in `HearthKit`** (a `WearableAudioSource` seam or similar), on
a feature branch, with the camera path either finished or removed. Because
`ChatViewModel` currently references MWDAT directly, that seam is work; because
MWDAT is out at pre-alpha, the work is free to do at extraction time.

### MLX and on-device inference: out

Not linked, dormant, downloader broken, and conceptually redundant: the product's
thesis is that inference runs on the user's own machine, which for an Apple
client means the house, not the phone. Removing it removes thirteen of the
fifteen pins.

### What the clean project keeps

**Nothing.** Zero third-party packages at pre-alpha, which is both correct and
achievable: `URLSessionWebSocketTask`, `AVAudioEngine`, `SFSpeechRecognizer`,
`Canvas`, `WidgetKit` and `RealityKit` are all first party.

The standing policy, which the MLX reference is the argument for:
**dependencies attach to targets, never to the project.** A project-level
reference costs every build and can link nothing at all, silently, for as long as
nobody looks.

## 6. What deliberately does not come across

The desktop extraction is the precedent for how this list is drawn, and it is
instructive: `ImageCard` and the imagery pipeline came across, the journal came
across, the Mentat run surface did not, and the two commissioned trading cards
did not. The line is the `ships in Hearth` column in
[`../backend/component-catalog.md`](../backend/component-catalog.md), decided
once during the audit, not relitigated per file.

### Out because the component catalog put it out

- **`Models/MentatState.swift` and the `/mentat/state` poll in
  `HouseStatusBar`.** The catalog lists the Mentat runs registry as 22 absolute
  paths of personal project work. The desktop client has no Runs surface.
- **`choam_portfolio_dashboard` and `ticker_insight_card`** in
  `Views/Dynamic/CommissionedCards.swift`. Two of nine card types, commissioned
  for the trading dashboard, absent from the desktop extraction. The card
  descriptor is deliberately tolerant of unknown types and renders nothing, so
  their absence is silent and correct.
- **The RealityKit character path** (`PersonaModelView`, the USDZ conversion,
  `PersonaAssetCache`) is **conditional**, not out. It exists for Selene, and the
  catalog ships Selene only if the memory and journal features ship with her. The
  renderer switch itself stays either way, since it is data-driven from the
  persona config and falls back to the orb when no model has arrived.

### Out because it is dead

- **`OnDevice/`**: `InferenceRouter`, `LocalModelManager`, `OnDeviceInferenceEngine`.
  Dormant, and `LocalModelManager` still fetches from `:8766`.
- **`Compat/WearablesShim.swift`**, deleted by construction rather than ported.
- **`Views/ChatView.swift` and `MessageBubble.swift`** behind
  `@AppStorage("useClassicChatUI")`. Nothing in the UI toggles it; the switch
  went with the old Settings page.
- **`MWDATMockDevice`**, a mock device product currently linked into the shipping
  app.

### Out because it is personal or scratch

`ServerConfig.defaultHost = "10.1.95.5"`; `DEVELOPMENT_TEAM = AS9PH6XDN4` in the
project file; the `com.joshuajones.*` namespace; the `MWDAT` dictionary in
`Info.plist` carrying a `TeamID` and an app-link scheme; `NEW_SETTING = ""` in
the widget build configuration; and `xcuserdata/`, which is checked in while
`xcshareddata/xcschemes` is not. The new project inverts that: shared schemes are
committed, user data is ignored.

### Unverified branch experiments

The Apple work is now linear. `generative-ui` and `visionos-gen-ui` are both
ancestors of `hearth-journal`, so there is no branch to merge; what exists is
**unverified code sitting on the current tip**, and the boundary runs through the
middle of the visionOS surface rather than around it.

- **Verified and comes across: the volumetric orb and orbiting cards.** Built and
  tested on device, merged, and the basis for the visionOS phase below.
- **Unverified and does not come across yet: the immersive caustics mode.**
  `CausticsImmersiveView.swift`, `CausticsTexture.swift`, `Caustics.metal` and
  the bloom and mode-switch changes to `RealityKitSceneManager`, all pushed on
  2026-06-14 across seven commits. `tasks/caustics-immersive-handoff.md` hands
  the build to a Mac session and opens with a step that has never been performed:
  adding those three files to the target, with the Metal file in Compile Sources
  or the kernel silently resolves to nil and the caustics are absent. It requires
  Xcode 27 beta and visionOS 27 beta on device. Valinor's `visionos-client.md` is
  still `status: draft, last_reviewed: 2026-06-14`.

### How anything on this list returns

**A feature branch against the clean project, with a stated verification gate**,
never a bulk re-import. The gate is the point, and each one is different:

| Excluded | Returns when |
| --- | --- |
| Immersive caustics | a Mac session has built and run it on a device, and visionOS 27 is generally available |
| MWDAT | the camera path forwards frames, and a Meta app registration is something the product can reasonably ask a user for |
| On-device inference | there is a reason for a phone to infer locally that "the house is unreachable" does not already answer better |
| Commissioned trading cards | the component catalog moves the trading surface into Hearth, which it will not |
| Mentat surface | same |

## 7. Phasing

**Recommendation: iOS only for pre-alpha, with the visionOS target present as a
compiling skeleton. visionOS ships in a later phase; the immersive work later
still.**

The reasoning, in the order it decided the answer:

**The tester story is desktop-first, and it is not close.** The pre-alpha trio is
M14, M13 and M7, and all three are about a stranger installing a Hearth house on
their own machine. The Apple client is not what a tester installs, it is what
they reach an installed house with. Its earliest useful moment is after first-run
setup works, and away-from-home is the milestone that makes carrying a phone
worth anything at all.

**A Vision Pro tester does not exist.** There is one device and it belongs to
Joshua. An iOS build reaches testers through TestFlight; a visionOS build reaches
an audience of one. Mac build sessions are the scarce resource here, since each
one is a different machine and a handoff document, and spending them on the
surface with no audience is the wrong trade.

**The most distinctive visionOS work is the least verified.** Carrying the
caustics mode into the clean project means carrying a configuration that has
never compiled into the thing whose entire purpose is being clean.

**iOS is closest to being a product.** The unified portrait stage, the four house
surfaces, the drawing card, Selene's Library and the widgets are all built and
mostly device-tested. That migration is largely deletion, which is the cheapest
kind.

The counter-argument, stated honestly: extracting `HearthKit` is harder to get
right with only one consumer, and a boundary drawn against a hypothetical second
client tends to be drawn wrong. That is why the visionOS target is in the project
from day one as a **build-only skeleton**, a volumetric window hosting the orb
and nothing else. Two consumers exercise the package boundary, the boundary does
not rot, and the skeleton costs one scheme in CI.

| Phase | Contents | Gate |
| --- | --- | --- |
| 0, skeleton | workspace, `HearthKit` with protocol, models, config and the bundled persona; iOS app that connects, speaks, and renders the orb; visionOS target that builds; identity, App Group and entitlements correct from the first commit | the orb renders on a phone with nothing listening, and a real house connects when an address is entered |
| 1, iOS parity | cards, the four house surfaces, the widgets, Selene's Library | feature-for-feature against the current client, on device |
| 2, visionOS volume | volumetric window, live orb, orbiting card attachments, gaze and tap | on device; all of it is already device-validated once |
| 3, visionOS immersive | caustics, bloom, the orb transplant and mode switch | a Mac session builds and runs it, and visionOS 27 has shipped |
| never phased | MWDAT, on-device inference | see the returns table above |

Phase 0 is small in code and large in consequence. Identity, the App Group, the
entitlements and the deployment floors are the four things that are painful to
change after a build has installed on a device, so they are the four things that
must be right in the first commit rather than the tenth.
