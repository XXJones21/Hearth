---
title: Hearth Vision Design
status: draft
last_reviewed: 2026-08-17
related:
  - visionos-handoff.md
  - apple-migration-plan.md
  - persona-face-spec.md
sources:
  - brainstorming session 2026-08-17, Windows house
  - D:/Tools/Valinor/Apple Client/Valinor/Valinor (Visualization/, VisionOS/)
  - apple-client/Hearth/Core/Sources/HearthCore
---

# Hearth Vision Design

The approved design for the dedicated Hearth Vision app: what the visionOS
client is, how it is structured, and the order it gets built. This document is
the outcome of the 2026-08-17 brainstorm and supersedes section 4 of
`visionos-handoff.md` where the two disagree. The handoff's sections 1 to 3
and 5 to 7 (state of the target, what crosses, hazards, the scheme trap, first
moves) remain accurate and are not restated here.

---

## Onboarding a new session

If you are a fresh session picking this up, in this order:

1. Read `wiki/raw/visionos-handoff.md` for the state of the Vision target,
   the migration hazards, and the scheme trap. The target is an untouched
   Xcode template until phase 0 below lands.
2. Read this document whole. It is the design authority for the Vision app.
3. The manifest `apple-client/manifest.yaml` is the authority on what crosses
   from Valinor and what is excluded. New files authored for this design are
   `generated` entries. The caustics set stays `excluded`; the face borrows
   its pattern (section 3), never its files.
4. Source for ported files: `/Users/jones/Valinor`, branch `hearth-ios`, under
   `Apple Client/Valinor/Valinor/` (`Visualization/`, `VisionOS/`). A copy
   also exists on the Windows box at `D:/Tools/Valinor/Apple Client/` but the
   manifest names the Mac tree as source.
5. Branch from a `main` that contains the shared-scheme commits `a4930b0` and
   `43c66ee`. Confirm all four schemes list in Xcode before touching anything.
6. Find the current phase by checking which phase gates (section 8) already
   pass, and continue from the first one that does not.

The build machine is the MacBook Air, on the tailnet at `100.83.26.13`.
Section 10 covers driving it from Windows.

---

## The decisions

Settled in the brainstorm, each with its reasoning in the numbered sections:

| Decision | Choice |
| --- | --- |
| Topology | Compact volume as the resting state, immersive space as the expansion, toggled by pinch-and-hold on the orb in both directions |
| Construction | Everything is an entity or a RealityKit attachment; scene hosts are dumb stages |
| Face | Live texture on the orb's front hemisphere, `CausticsTexture` pattern, `FaceDirector` reused untouched |
| Choreography | Harness-named behavior cues over the wire, client behavior library, `state_update` fallback |
| Cards | The shared SwiftUI card library as attachments, billboard toward the user, anchored to the orb |
| Journals | Books as entities on a shelf, pages are the existing SwiftUI journal views mounted inside |
| Surfaces | Settings, Apps, Transcript as 2D windows reusing iOS views; Persona as a volumetric window |
| Reuse direction | Spatial code targets iOS 18 as well; the iOS client adopts the RealityKit orb later |

---

## 1. Scenes

Five scenes. Three are RealityKit hosts for one shared entity world.

- **Pairing window**, a plain 2D `WindowGroup`. Shown when unpaired; address
  then code, reusing `FirstRunView`'s flow reshaped for a floating pane.
- **Main volume**, a volumetric `WindowGroup` and the launch scene. The
  persona rig sits low in the box (the `CardOrbitLayout.orbY = -0.22`
  reasoning carries over: low means it can be set on a real table), cards
  billboard beside it, a compact journal shelf, the composer as a bottom
  ornament, house status as a top ornament. Launch opens this scene alone.
- **Library volume**, a volumetric `WindowGroup` opened on demand. The
  journal shelf at full size, same book entities the main volume shows
  compactly. Opens from the shelf; closes freely.
- **Immersive house**, an `ImmersiveSpace` with `.mixed` passthrough. The
  shelf and books settle into the room, the orb roams, and the real
  `BloomComponent` replaces the billboard halo through the `realBloomActive`
  switch the ported scene manager already carries. While immersive is open
  the main volume dismisses; it returns on exit. This mirrors the iOS
  collapsed and expanded discipline at room scale.
- **Transcript window**, a 2D `WindowGroup` hosting `TimelineFeed`. History
  is a thing in the room, not a mode of the stage.

**The one-scene rule.** An entity lives in exactly one scene at a time. The
world (persona rig, shelf, card cluster) is owned by an app-level world
model, and each RealityKit host attaches or releases the shared root on
appear and dismiss. The scene manager stays hoisted at app level; hosts hold
no state worth keeping.

**The toggle.** Pinch-and-hold the orb (the 2-second hold from Valinor's
`SulivanVolumeView`, reinstated now that its destination exists) enters the
immersive house from the volume, and the same gesture inside the immersive
house closes it and reopens the volume. A plain pinch on the orb starts a
voice turn, unchanged.

## 2. Where the code lives

- **`HearthCore`** keeps the logic: models, transport, audio, config, view
  models, and the brand palette. The palette stays here rather than moving up
  with the views because it writes each token once as both a SwiftUI `Color`
  and a `SIMD3<Float>` scene value, and `PersonaPalette` in this layer reads
  the latter; splitting it would break its own no-drift premise.

  This section expected phase 0 to burn down `#if os(iOS)` fallout "first in
  `Audio/`, `Cards/`, `Config/`". There was none to burn: HearthCore had no
  platform guards at all. The whole of the xrOS fallout was three lines --
  `UIImpactFeedbackGenerator` and `UINotificationFeedbackGenerator` are
  unavailable on visionOS, so `Haptics` is silent there and its call sites
  stay unguarded.
- **`HearthUI`**, a second new library, and the one this section originally
  missed. Section 7 promises the Vision app reuses `HearthSettingsView`,
  `AppsView`, `CardLibraryView`, `TimelineFeed` and the journal views, and
  section 5 mounts the journal views inside book entities -- but all of them
  lived in the iOS app target, where a second target cannot see them. A
  directory cannot fix that; only a library can. So `HearthUI` holds the
  SwiftUI both platforms render: the card library, the persona chrome, and the
  six surfaces. Its one platform shim is `hearthNavigationTitleInline()`,
  wrapping the iOS-only `navigationBarTitleDisplayMode`; a second shim is the
  signal that whatever asked for it is iOS-shaped and belongs back in the app
  target.
- **`HearthSpatial`**, a new library target in the same Core package: the
  persona rig (orb, face texture, look-at), the behavior system,
  `CardOrbitLayout`, book and shelf entities, and the ported
  `RealityKitSceneManager`. Platform floor iOS 26 and visionOS 27 -- the
  package's floors, stated once in `Package.swift` and `Shared.xcconfig`.
  (This section first said iOS 18 and visionOS 2, which were pre-renumbering
  numbers carried over by hand; the build has never used them.) No
  `#if os(visionOS)` guards except where an API genuinely diverges. This is
  what makes the later iOS adoption of the RealityKit orb a target change
  rather than a rewrite, and it is enforced by a build gate: `HearthSpatial`
  compiles for iOS before iOS uses it, which is why the iOS target links it
  from phase 0.
- **The Vision target** holds only scenes, hosts, `Info.plist`, and
  entitlements. Thin by design, like the iOS target already is.

## 3. The persona rig and the face

`PersonaRig`, an entity in `HearthSpatial` composed of the orb body (ported
from `RealityKitSceneManager` minus its immersive-only branches, which move
behind the mode switch), the glow billboard for volume mode, and the face.

**The face texture.** `PersonaFaceTexture` is structurally a sibling of
Valinor's `CausticsTexture`: a `LowLevelTexture` (rgba16Float, 512) rewritten
every frame by a `face_kernel` Metal compute pass, exposed as a
`TextureResource`, ticked from the host's per-frame closure. `FaceDirector`
and `FaceExpressions` are reused with zero changes. Per frame the director's
`FacePose` serializes into a params struct (eye centers and half-sizes, blink
phase, pupil offset, mouth shape, palette colors) exactly as `CausticsParams`
does, and the kernel draws the established capsule-and-squircle ink language
as signed distance fields. The texture binds to the orb's front hemisphere as
an emissive-weighted material layer, so the face glows with the body and
participates in bloom in immersive mode.

**Fallback.** `CausticsTexture` construction can return nil on a device
without a usable compute pipeline, and `PersonaFaceTexture` keeps that
contract. The fallback is the existing `PersonaFaceView` mounted as an
attachment billboard: degraded, never faceless.

**Look-at, two layers.** The body layer rotates the rig toward a target with
a smoothed slerp: the user's head anchor when listening or speaking (looking
forward while listening is this layer's default), or an object target during
choreography. The gaze layer is the existing `LookTarget` pupil math, fed by
projecting the 3D target into face space, so the eyes lead the head turn the
way composer-tracking already works on iOS. Both layers feed the one
director; there is no second state machine.

**A caveat to respect.** The caustics set was never validated on a device, so
the `LowLevelTexture` pattern gets its first on-device proof through the
face. Treat the pattern as unproven until headset gate 2 passes. *(Resolved
2026-08-17: the pattern works. The face renders on the headset, and the kernel
compiles and links for iOS as well.)*

**An open change to the mouth.** The speaking particle waveform is, in the
operator's judgement, the best speaking treatment across every client -- and
the face draws an unrelated oval beside it. Two answers to one question, with
the weaker one on the face. The mouth should become the waveform. Scoped, with
the two readings of that separated and the phase-channel question laid out, in
`tasks/vision-waveform-mouth.md`; deliberately not folded together with the
separate complaint that the particle wave is too wide at volume scale.

## 4. Choreography

**The wire.** Valar emits a `behavior_cue` message at tool boundaries:
`{name, phase: start | end}`, with `name` mapped from the tool being invoked
(`consulting_journal`, `searching_files`, `remembering`, `working`). Same
seam and philosophy as `tts_chunk_start` naming face expressions: the harness
names the performance, the client stages it. The Valar change lands in
Valinor first and merges into the Hearth backend after, per the standing
rule. The client treats the cue vocabulary as open: an unknown name resolves
to the generic working behavior.

**The client.** `BehaviorDirector` in `HearthSpatial` receives cues,
forwarded from `ChatViewModel` through a small feed mirroring `FaceFeed`, and
resolves them against a behavior library: a table from cue name to a sequence
of primitives such as `flyTo(target)`, `orientTo`, `openBook`, `hoverAt`,
`returnHome`. Primitives are entity animations with completions, so behaviors
compose and a new cue is a table entry, not new code.

**Interruption rules, explicit.** A `start` cue preempts idle. TTS beginning
recalls the orb toward the user unless the running behavior marks itself
speak-in-place. An `end` cue, a new turn, or any error resolves to
`returnHome`. In the compact volume the same cues play at desk scale: targets
are entities, and the entities are simply closer.

**The fallback producer.** Until the Valar cue lands, or on any turn that
arrives without one, coarse cues derive from `state_update` (thinking maps to
an attentive idle, tool stages to a generic working hover). The director
cannot tell the producers apart, so headset work never blocks on the backend.

## 5. Journals as books

**The book.** `JournalBook`, a simple procedural cover-and-pages mesh, cover
colored from the persona palette and carrying the journal's title, opening on
a hinge animation. No modeled assets in v1; the object language stays in the
orb's clean geometric family. Opened, the pages are a SwiftUI attachment
reusing `JournalBookView` and `JournalEntryView`, so the reading experience
is the proven iOS one mounted inside the object. Closing the book folds the
attachment away with it.

**The shelf.** `JournalShelf` lays out books from the same server-fed
`JournalModels` the iOS client renders, and it is the dynamic-growth point:
a new journal arriving is a new book appearing. Compact in the main volume,
full size in the library volume, settled near a real surface in the immersive
house. Same entities in all three.

**Two open paths.** Gaze-and-pinch a book directly, or the orb opens it: the
`consulting_journal` choreography is `flyTo(shelf)`, the book slides out and
opens, the orb hovers while the harness reads, `returnHome` on the `end`
cue. The book left open at the found entry is the payoff: the spatial version
of a card, except it is the actual object of the search.

## 6. Cards

Cards stay the shared SwiftUI library, mounted as RealityView attachments.
`CardOrbitLayout` ports as the anchor logic: cards spawn from the orb's
position, take their slot in the column, and billboard toward the user
continuously. They anchor to the rig, not the scene, so when the orb travels
its cards follow with a soft spring lag: the orb reads as carrying its work.

**Amended 2026-08-17: that anchoring is the IMMERSIVE house's, not the
volume's.** In a room the orb genuinely travels and its work should go with it.
In a box a metre wide the cards have nowhere to go, and prose that slides while
you are reading it is worse than prose that sits still. The volume uses the
absolute `position(index:count:)`; `offsetFromOrb` stays unused until phase 4,
deliberately rather than by omission.
Lifecycle, types, and rendering are `CardStore` unchanged. Nothing forks from
iOS, which is deliberate: the card library stays universal across Apple
devices.

## 7. The surfaces

- **Settings**: a 2D window, near carbon copy of `HearthSettingsView`, plus a
  visionOS section for immersive preferences as they accrue.
- **Persona**: a volumetric window: the active persona rendered through the
  already-shared `PersonaModelView` (Selene works today on iOS and carries),
  with the existing SwiftUI persona menu mounted as an attachment panel.
- **Apps**: a 2D window reusing `AppsView` and `CardLibraryView` as they are.
- **Transcript**: the 2D window from section 1, hosting `TimelineFeed`.

All four open from the shelf ornament on the main volume.

## 8. Phasing

Ordered so each failure is cheap and the headset is needed as late as
possible.

**Phase 0, groundwork.** LANDED 2026-08-17 on `client/visionOS`, and this is
now a record rather than a forecast. Branch from a `main` containing `a4930b0`
and `43c66ee`. Split the Core package into three libraries and link all three
into both app targets; the surfaces come out of the iOS target on the way.
Fix both plists: microphone, speech, local networking and ATS into the Vision
plist; `NSWorldSensingUsageDescription` out of the iOS one, parked until
phase 4. Delete the Xcode template entirely; write the scene skeleton
(pairing window plus an empty main volume). No headset, no house.

Two things the plan did not anticipate, both found by running the skeleton on
the simulator rather than by reading:

- The Vision plist's immersion style was the template's `Full`. It is `Mixed`
  now, because passthrough is not a detail of the immersive house -- section 1
  stages the shelf, the books and the roaming orb against the real room.
- **Every surface renders in ember mode on visionOS, permanently.**
  `HearthPalette.isEmber` asks `UITraitCollection` for
  `userInterfaceStyle == .dark`, and visionOS answers dark always; it has no
  light appearance. So `cream` resolves to `0x241B14` and `roast` to the light
  ink on this platform. It is self-consistent and readable, and it may be the
  right look for a headset -- but the palette calls light-first
  non-negotiable, and nothing decided this: it fell out of a trait query
  written for a phone. **Phase 5 owns the call**: accept ember as the
  headset's mode and say so in the palette, or give visionOS its own
  resolution path.

**Phase 1, the compact house core.** LANDED 2026-08-17. **Gate 1 PASSED**
2026-08-17 on the device: paired, connected, a full voice turn with reply
playback. Parity with what the Valinor client reached.
Port `RealityKitSceneManager` (volume path only) into `PersonaRig`. Pairing
window live against the house. Cards as attachments through the ported
`CardOrbitLayout`. Composer and status ornaments.
*Headset gate 1: a full voice turn in the volume.* Pinch the orb, speech
recognized, reply spoken, a card beside the orb.

On the device, Build-and-Run hung at "Configuring Debugger Actions" with LLDB
reading device memory to resolve symbols; killing the app and launching it from
the Home View cleared it every time, and the turn then ran end to end.

**Disabling the two checkers was not enough.** That was the first fix and it
left the hang in place, because removing the injected dylibs does not remove the
dyld-to-LLDB notify path they wedge in. The Vision scheme now runs with no
debugger at all -- "Debug executable" unchecked -- which is what the Valinor log
concluded in the first place. The checkers stay disabled underneath so that
ticking the debugger back on to chase something does not immediately re-arm the
trap, and GPU validation and frame capture are off as well, since frame capture
auto-enables for a Metal binary under the debugger and this target links Metal
as of phase 2.

The cost is the console: `print` writes to stdout, stdout is not the unified
log, and with no debugger Xcode shows neither. Anything worth reading on the
headset goes through `os.Logger` and is read with `xcrun devicectl device
console` or Console.app.

Two decisions taken during the port, both departures from what this document
first said:

- **The pairing window is Vision-native, not a reshaped `FirstRunView`.** What
  is genuinely shared is the contract, and that IS reused unchanged --
  `ServerConfig`, `Pairing.pair`, `.hearthServerConfigured`. What does not
  carry is the chrome: the phone's view is a full-screen column sized against
  a keyboard sliding up under it, and the headset's is a 396pt pane floating
  in front of a room. Two layouts, one flow. (Standing reason to revisit:
  reaching a house over Tailscale from the headset is unresolved, and the
  address step is where that surfaces.)
- **The ornaments are Vision-native too.** `HouseStatusBar` and
  `BottomInputBar` are shaped for a 390pt column with a keyboard under them;
  an ornament is a short horizontal strip with no keyboard of its own.
  Parameterising the phone's for both would serve neither. They stay in the
  iOS target until something actually wants them twice.

**Phase 2, the face.** LANDED 2026-08-17. **Gate 2 PASSED** on the device: the
face alive on the orb through a full turn, blinking, with the mouth riding real
TTS amplitude. The `LowLevelTexture` pattern is proven, on hardware, for the
first time. `PersonaFaceTexture` and `face_kernel`, the `FacePose` params
bridge, the material binding, the attachment fallback. Look-at moved out; see
below.

Four adjustments came out of the device runs and none were predictable from the
simulator: the face landed a quarter turn off (RealityKit's sphere UV seam is
undocumented, so the shell's rotation is measured rather than derived); the
limb fade was vignetting the whole face rather than its last few degrees; the
ink was being written sRGB into a linear float texture, which is most of a stop
too bright and was the whole of the "washed out" complaint; and the geometry
carried from a flat 130pt phone view is simply small on a bead the size of a
palm. The face now runs flat black at `eyeScale` 1.2, both marked as test
settings in the code. Colour polish is
[tasks/vision-visual-polish.md](../../tasks/vision-visual-polish.md).
*Headset gate 2: the face alive on the orb, expressions firing on
`tts_chunk_start`.* This is also the first on-device proof of the
`LowLevelTexture` pattern.

Three things this section assumed that turned out otherwise:

- **Neither look-at layer belongs in the volume, and both move to phase 4.**
  The body layer was specified as a smoothed slerp toward the user's head
  anchor; a head anchor needs a world-tracking ARKit session, and the Shared
  Space does not grant one to a volumetric window. The first fix was a
  `BillboardComponent`, and it was the wrong instinct -- a volume is a box you
  look into from the front, so the face simply faces forward and stays there.
  That is not an approximation of the intended behaviour at this scale; it is
  the whole of it. Looking-at earns its keep in the immersive house, where the
  orb roams a room and the person moves around it, and it lands there against
  the real anchor rather than a stand-in for one. (Operator's call,
  2026-08-17.)
- **The kernel draws no head.** Section 3 says the kernel draws "the
  established capsule-and-squircle ink language", but the squircle is the
  phone's head, and on the orb the bead already is one. The kernel writes
  transparent everywhere it is not laying ink and the shell blends over the
  body.
- **The metallib does not live where Valinor's did.** Valinor's kernel sat in
  the app target, where `makeDefaultLibrary()` finds it. This one ships in a
  package target: the build compiles it and copies a `default.metallib` into
  `HearthCore_HearthSpatial.bundle`, nested inside the app rather than at its
  root. `PersonaFaceTexture` searches for it rather than assuming, and still
  returns nil -- into the fallback -- if it is genuinely absent.

So section 3's "look-at, two layers" is phase 4 work in full. Nothing of it
ships here, deliberately: the director's own playlist and saccades keep the
eyes alive without anything to track, and machinery that cannot be judged in
the scene it lives in is machinery nobody can tell is broken.

**Phase 3, choreography and journals.** LANDED 2026-08-17. **Gate 3 PASSED in
part** on the device: the library opens on the Journal button, its shelves
scroll, a spine can be pinched and the entry read in the phone's own journal
view, and the persona's investigation prop stages and clears with the cue. The
half NOT demonstrated is the orb flying to the shelf, because `motion` is
`.none` by decision -- the travel fought the volume's layout and was switched
off rather than tuned under pressure. See
[tasks/vision-visual-polish.md](../../tasks/vision-visual-polish.md) item 4. `BehaviorDirector`, primitives, the fallback producer. `JournalBook`,
`JournalShelf`, both open paths. In parallel on the backend: `behavior_cue`
lands in Valar in Valinor, then merges to the Hearth backend; the client swaps
producers with no change.
*Gate 3: a journal-search turn makes the orb fly to the shelf, and the found
entry is readable in the opened book.*

Three departures worth knowing:

- **The fallback producer reads the TOOL LIST, not `state_update`.** This
  section says `state_update`, but that message carries a coarse stage
  (transcribing, deciding, acting) that cannot tell a journal search from a
  file read -- so every turn would produce the same generic hover. The
  `pipeline_stage` message already carries actual tool names, so the derived
  cues are matched loosely against those. Both producers post through one
  funnel and the director cannot tell them apart, which is what the design
  actually asked for; the moment a real `behavior_cue` arrives the derived one
  goes quiet for the session, because two producers running at once would
  fight and the harness is always better informed.
- **Which book to open is a guess, and it should not stay one.** The cue names
  a performance, not a journal, so the client matches a quoted title out of the
  house's own reply against the shelf. It works and it is embarrassing. The
  harness KNOWS which journal it read, so `behavior_cue` should grow a payload
  -- `{name, phase, subject}` -- and that guess should be deleted rather than
  improved. Worth landing with the Valar change.
- **The library volume is not built.** The shelf is one set of entities scaled
  by its host, so the compact shelf in the main volume is the whole mechanism;
  the library volume is that same shelf in a bigger box, and it is a scene
  declaration rather than new machinery. Deferred so gate 3 can be judged on
  the thing it is actually about.

**Phase 3.5, finishing the volume. LANDED 2026-08-18.** Added 2026-08-17, after
gate 3, for two things: the shared surfaces were unusable in the box, and the
desktop's third slot had no equivalent here. Both are done.

The surfaces were not blank -- they rendered, behind a glass slab that visionOS
draws for a navigation container and that ate every pinch. The cause was the
suspected one, the phone's navigation chrome inside an attachment, and the fix
is the split rather than the fork: `HearthSurfaceChrome` in the environment
picks `.navigation` or `.bare`, `HearthSurfaceShell` draws or omits the stack
accordingly, and `hearthSurfaceClose` gives an unpresented surface a real way
out. One implementation of what each screen SAYS; only the shell differs.

The rail is the desktop's `AppFrame` third column, made collapsible for a
smaller box: a VERTICAL button shelf on the right face mirroring the bottom
one, opening a docked panel with the desktop's three tabs. Sessions moved off
the bottom shelf into it, where the desktop keeps it; Memory reads
`/journal/facts`; Routines says it has nothing rather than porting the
desktop's fabricated rows. Opening it squeezes the centre slot instead of
covering it, which is what the desktop's grid does. Scoped and recorded in
[tasks/vision-phase-3-5.md](../../tasks/vision-phase-3-5.md).

Phase 4 DISMISSES this volume and returns to it, which is why these were worth
fixing first: anything broken in the box is broken in both places and harder to
see in one of them.

**Phase 4, the immersive house.** The `ImmersiveSpace(.mixed)` host, entity
re-hosting between volume and room, the `realBloomActive` switch,
pinch-and-hold in both directions, `NSWorldSensingUsageDescription` into the
Vision plist when surface placement lands. Room-scale choreography falls out
of the same behavior library.
*Gate 4: the immersive round trip.* Hold to enter, the room furnishes, hold
to leave, the volume returns.

**Phase 5, surfaces and polish.** Settings, Persona, Apps, Transcript
windows; the shelf ornament that opens them.

## 9. Definition of done

Extends `visionos-handoff.md` section 8, which still applies in full.

- The Vision target links HearthCore and HearthSpatial and builds for xrOS
  device and simulator. No file from the Xcode template remains.
- `HearthSpatial` compiles for iOS 26. A build gate only; iOS adoption of the
  RealityKit orb is its own later workstream.
- `tools/apple-gates.sh` clean; `apple-scrub.py --check` reports no drift;
  new files are `generated` entries in the manifest; the caustics set is
  still `excluded` and the manifest still says why.
- Both `Info.plist` files justify every key they carry.
- Headset gates 1 through 4 pass as written in section 8.

## 10. Building from Windows, and the Mac seam

The MacBook Air is on the tailnet at `100.83.26.13`. As of 2026-08-17 the
route works but SSH is refused: Remote Login is off. Enable it on the Air
(System Settings, General, Sharing, Remote Login) and a Windows session can
drive builds directly:

```
ssh jones@100.83.26.13 "cd ~/Hearth/apple-client/Hearth && \
  xcodebuild -scheme 'Hearth Vision' -destination 'generic/platform=visionOS' build"
```

What that seam covers: builds, gate scripts, git operations, log retrieval.
What it does not: headset deploys, signing dialogs, simulator interaction,
and anything Xcode presents as UI. Those remain hands-on-Mac work, which is
why the onboarding block at the top of this document exists either way.

Two standing hazards from the handoff apply to every Mac session: the SDK
must match the headset OS (a mismatch crashes before `main()` and looks like
the app), and a device hang at launch is a debugger question before it is an
app question.
