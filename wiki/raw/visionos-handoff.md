# visionOS handoff

Written 2026-08-09, at the end of the branch that migrated the iOS client.
Area 6 is the last area, and it is the only one that needs a headset to
verify. This page exists so a session that has never seen the Apple client can
start work without reading the other four articles first.

Read alongside `apple-migration-plan.md` (areas, hazards E1–E4) and
`apple-client/manifest.yaml`, which is the authority on what crosses and what
does not. Where this page and the manifest disagree, the manifest is right and
this page is stale.

---

## 1. Where things stand

PR #1 merged the iOS client and device pairing into `main`. Areas 1–4 are done
and proved on a physical iPhone against the Windows house on 2026-08-08 —
speech recognised on the phone, the reply streamed back as PCM, a weather card
drawn in the timeline.

| Area | State |
| --- | --- |
| 1, foundation | done |
| 2, transport and voice | done |
| 3, the turn and the cards | done |
| 4, the iOS shell | done |
| 5, widgets | not started; needs `CODE_SIGN_ENTITLEMENTS` wired and a device to prove the App Group |
| **6, visualization and visionOS** | **this document** |

Two commits sit on `apple-client-migration` ahead of `main` (`a4930b0`,
`43c66ee`) — the shared scheme files, described in section 6. They merged
after PR #1 and still need to reach `main`. **Branch visionOS work from a main
that contains them**, or the first thing the new session hits is the bug those
commits fixed.

### The source tree is on this Mac

The migration plan was written assuming Valinor lived on the Windows box. It
does not any more, or not only:

```
/Users/jones/Valinor/Apple Client/Valinor/Valinor/
    VisionOS/          the five visionOS views
    Visualization/     the renderer, caustics, motion
```

on branch `hearth-ios`. This is a material change from E1's Windows/Mac split —
the scrub, the review and the build can all happen in one place now. Confirm
the branch before copying anything; `hearth-ios` was the active branch as of
this writing, and the visionOS work landed across several others historically.

---

## 2. What the Vision target actually is today

**An untouched Xcode template.** Not a partial migration, not a stub with the
shape of the real thing — the literal "Window + Volume + ImmersiveSpace" sample
Xcode emits.

```
Hearth Vision/
    Hearth_VisionApp.swift          template
    AppModel.swift                  template
    ContentView.swift               template, "Enlarge RealityView Content"
    ImmersiveView.swift             template, loads Immersive.usda
    ToggleImmersiveSpaceButton.swift template
    Resources/{Scene,Immersive}.usda, Materials/GridMaterial.usda
    Assets.xcassets/                AppIcon.solidimagestack, unstyled
    Info.plist                      see below
```

Three facts about it that decide the first hour of work:

**It does not link HearthCore.** The target's `packageProductDependencies` is
empty. The iOS target has `HearthCore`; Vision has nothing. Every model, the
transport, `ChatViewModel`, `CardStore`, pairing — none of it is reachable from
this target yet. Adding the dependency is step one and it is not merely
mechanical: HearthCore has to *compile* for xrOS, and nothing has ever asked it
to. Expect `#if os(iOS)` fallout in `Audio/` and `Cards/` first.

**Its `Info.plist` is missing everything the app needs.** It carries the scene
manifest and nothing else — no microphone, no speech recognition, no local
networking, no ATS. All of those are on the iOS side. A voice turn on the
headset will hit an authorization prompt that cannot be presented and the
system will terminate the app.

**And the iOS `Info.plist` carries a visionOS-only key.** It has
`NSWorldSensingUsageDescription`, whose string talks about caustics playing
across your real walls in immersive mode. On iOS it is inert. This is the same
per-SDK plist confusion the manifest warns about, arrived at from the other
direction: the key survived the migration into the plist that cannot use it,
and is absent from the one that will. Move it when the immersive work starts;
it belongs in neither plist until then, because area 6 excludes caustics.

The manifest's `visionos-plist` entry says to diff the two plists deliberately.
That is the reason.

---

## 3. What crosses, from the manifest

The manifest is authoritative. Reproduced here so a new session can size the
work without opening it.

| From Valinor | To | Lines | Disposition |
| --- | --- | --- | --- |
| `ValinorApp.swift` visionOS scenes | `Hearth Vision/HearthVisionApp.swift` | — | generated |
| `Visualization/RealityKitSceneManager.swift` | `Hearth Vision/RealityKitSceneManager.swift` | 611 | edits |
| `VisionOS/SulivanVolumeView.swift` | `Views/PersonaVolumeView.swift` | 231 | edits |
| `VisionOS/CardOrbitLayout.swift` | `Views/CardOrbitLayout.swift` | 46 | edits |
| `VisionOS/LiveTranscriptCardView.swift` | `Views/LiveTranscriptCardView.swift` | 61 | edits |
| `VisionOS/SessionGalleryView.swift` | `Views/SessionGalleryView.swift` | 108 | edits |
| `Info-visionOS.plist` | `Hearth Vision/Info.plist` | 62 | edits |
| — | `Hearth Vision/HearthVision.entitlements` | — | generated |

Roughly 1,050 lines of Swift, plus an entry point and an entitlements file that
are written rather than copied.

`PersonaModelView.swift` **already crossed** in an earlier area — it is
`Core/Sources/HearthCore/Persona/PersonaModelView.swift` (343 lines) and is
shared with iOS. Do not migrate it again. `PersonaOrb`, `PersonaPalette` and
`PersonaVisualization` are likewise already in HearthCore.

### Excluded, deliberately

- `CausticsImmersiveView.swift` (423), `CausticsTexture.swift` (138),
  `Caustics.metal` (116) — the immersive caustics mode. **Never validated on
  device.** Area 6 crosses what has been proved, and this is the whole of the
  excluded set. It also carries the `.metal` target-membership trap: a Metal
  file silently absent from the target produces a build that links and a shader
  that is not in `default.metallib`.
- `VisualizationChatView.swift`, `VisualizationView.swift` (76),
  `DeviceMotionTracker.swift` (84) — a dead chain. `VisualizationChatView` is
  referenced nowhere; `VisualizationView` is used only by it; `DeviceMotionTracker`
  only by `VisualizationView`.

`RealityKitSceneManager` crosses **minus** its immersive mode switch and bloom
changes, which belong to the caustics work. The volumetric path is what was
device-validated, on 2026-06-12.

---

## 4. Spatializing the home

This is the part with no prior art in Valinor to copy. Valinor's volumetric
surface was an orb with cards beside it — a good demo of the renderer, not a
home. Hearth's iOS shell is a *house* with rooms, and the question area 6 has
to answer is what a house looks like when it is not confined to a rectangle.

### What the iOS home is, so the mapping is legible

`HearthMainView` (284 lines) is one continuous portrait layout in two states,
toggled from the shelf:

- **Collapsed** (resting): the stage owns everything above the composer —
  persona on top, this turn's card in the middle, the spoken caption below.
  The conversation *is* the orb, its cards and its voice.
- **Expanded**: the stage takes the upper 45% and yields the rest to
  `TimelineFeed`, the attributed history.

Around it: `HouseStatusBar` (the house's state), `HouseShelf` (a right-hand
drawer), `BottomInputBar` (the composer), and four surfaces presented full
screen — Journal, Persona, Apps, Settings.

The stage's discipline is the thing worth preserving: **the persona is never
covered**, and the card is bounded to a share of the stage rather than allowed
to grow over it.

### The proposal: one volume, surfaces as satellites

Not an immersive space. A volume.

**The volume holds the stage and nothing else.** Persona low in the box at
roughly palm size — `CardOrbitLayout.orbY = -0.22` already encodes this, and
the reasoning in its comments is sound: low in the volume means it can be set
down on a real table, and it leaves the space above for long-form cards. Cards
stack in a column to its left (`leftX = -0.28`, `verticalSpacing = 0.22`),
which is what `CardOrbitLayout` already does and what was proved on device.

The two-state collapse has no analogue and should not be ported. On iOS the
timeline competes with the stage for a fixed rectangle. In a volume it does
not compete — it is simply somewhere else. **Collapse is a solution to a
constraint that does not exist here**, and porting it would be the mechanical
kind of migration this project keeps refusing.

**The transcript becomes a second window**, not a state of the first. A plain
2D `WindowGroup` hosting `TimelineFeed`, which already exists and is
platform-agnostic enough to try unchanged. Open it from the ornament; leave it
open or close it. That is the collapse toggle, expressed as a thing in the room
rather than a mode of a view.

**The four surfaces become windows too.** Journal, Persona, Apps and Settings
are full-screen presentations on iOS because a phone has one screen. They are
each a `WindowGroup` here. This is the cheapest large win in the whole area:
they are ordinary SwiftUI, they do not touch RealityKit, and a person can have
the Journal open beside the orb instead of *instead of* the orb.

**The status bar and composer become ornaments** on the volume. `.ornament` at
`.bottom` for the composer, `.top` for house state. Ornaments are the visionOS
idiom for exactly this — chrome that belongs to a scene without occupying it.

**Gaze-and-pinch on the persona starts a turn.** Valinor's `SulivanVolumeView`
already does this, including a 2-second pinch-and-hold to switch to the
immersive scene. Keep the tap; **drop the hold**, because the mode it switches
to is the excluded caustics scene. A hold gesture that leads nowhere is worse
than no gesture.

### What to decide before writing code

Three questions this document cannot answer from the repo:

1. **Does the volume survive the app being backgrounded**, and does the
   persona keep its transform when the user walks to another room? Affects
   whether `RealityKitSceneManager` can stay a singleton hoisted at the app
   level, which is how the manifest describes it.
2. **Does pairing happen in the volume or in a window?** `FirstRunView` is a
   two-step flow (address, then code) and is iOS-shaped. A volume showing a
   text field is awkward; a plain window before the volume opens is not. Lean
   window.
3. **One scene or two on launch?** Opening the volume *and* the transcript on
   first run explains the app; opening only the volume respects the resting
   state the iOS shell fought for. Lean volume alone.

None of these blocks the first three steps in section 7.

---

## 5. Hazards that have already cost a session each

From E3 of the migration plan, both confirmed the expensive way.

**The SDK must match the device OS.** A visionOS 26.5 SDK binary on a
visionOS 27.0 Vision Pro crashes at launch *before `main()`* — and it crashed a
fully stripped plain-`Text` app too. It looks exactly like the app is broken
and it is not. Confirm the Xcode SDK against the headset before concluding
anything about area 6.

**A device hang at launch is a debugger question first.** The same
investigation ended at dyld wedging while notifying LLDB, with Main Thread
Checker injected. Detached from the debugger, the app launched in about a
second.

**`NSWorldSensingUsageDescription` missing** makes ARKit hard-crash on the
authorization request — on a device, in immersive mode only. Not reachable
while caustics stay excluded, but the reason the key exists.

**`.metal` target membership** is silent on the way in and loud much later:
the build links, and the shader is simply not in `default.metallib`. Only
relevant if caustics are un-excluded.

---

## 6. The scheme trap, because it will happen again

The iOS device build failed with "mismatched platform" on 2026-08-08. The cause
was not the project — the `Hearth` target correctly declares
`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"`. The cause was that the
`Hearth` scheme had **disappeared**, and Xcode left the nearest survivor
active, which was `Hearth Vision` (`SDKROOT = xros`), pointed at an iPhone.

Autocreated schemes are derived state and derived state is allowed to vanish.
All three are now real files under `Hearth.xcodeproj/xcshareddata/xcschemes/`
and tracked.

Two things follow for this work:

- **Both app targets produce a product named `Hearth.app`.** A scheme with the
  wrong `BlueprintIdentifier` builds successfully and installs the *other*
  platform's app. Read identifiers out of `project.pbxproj`; do not copy a
  scheme and edit the name.
- **The configurations are `Debug` and `Release`.** `Dev.xcconfig` is the file
  that feeds Debug, not a configuration. A scheme naming `Dev` references a
  configuration that does not exist.

If a scheme stops appearing in Xcode's list, it did not fail loudly — an
unparseable `.xcscheme` simply stops being in the list.

---

## 7. First moves

In this order, because each one's failure is cheap and informative, and the
expensive verification is last.

1. **Branch from a `main` containing `a4930b0` and `43c66ee`.** Confirm all
   four schemes list in Xcode before touching anything.
2. **Add `HearthCore` to the Vision target and build.** Change nothing else.
   This is the real scope discovery: whatever `#if os(iOS)` fallout exists in
   `Audio/`, `Cards/` and `Config/` surfaces here, against a target with no
   other moving parts. Do not proceed until it compiles for xrOS.
3. **Fix the two `Info.plist` files.** Microphone, speech, local networking and
   ATS into the Vision plist; `NSWorldSensingUsageDescription` out of the iOS
   one. Diff them side by side and justify every difference.
4. **Write `HearthVisionApp.swift` and delete the template.** `AppModel`,
   `ContentView`, `ImmersiveView`, `ToggleImmersiveSpaceButton` and the three
   `.usda` files all go. Getting the template out early stops it being mistaken
   for scaffolding later.
5. **Pairing in a window, then a live transport.** The house must answer before
   any of the spatial work can be judged, and pairing is the gate. Loopback is
   exempt but the headset is not on loopback.
6. **`RealityKitSceneManager` + `PersonaVolumeView` + `CardOrbitLayout`.** The
   orb in the volume with cards beside it. This is the device-validated core.
7. **Surfaces as windows**, then ornaments, then the transcript window.
8. **Verify on the headset.** Section 5 first — SDK against OS — before
   believing any crash.

Steps 1–4 need no headset and no house. Step 5 needs the house. Only step 8
needs the Vision Pro.

---

## 8. Definition of done

- The Vision target links HearthCore and builds for xrOS device and simulator.
- No file from the Xcode template remains.
- `tools/apple-gates.sh` clean; `apple-scrub.py --check` reports no drift
  against the manifest.
- Both `Info.plist` files justify every key they carry.
- All four schemes present and shared; each resolves its own platform.
- A voice turn completes on the headset: gaze-and-pinch the persona, speech
  recognised, reply spoken, a card appears beside the orb.
- The caustics set is still excluded, and the manifest still says why.
