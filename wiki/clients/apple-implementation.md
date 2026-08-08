---
title: Apple Implementation Plan
status: draft
last_reviewed: 2026-08-08
related:
  - apple-inventory.md
  - apple-project-architecture.md
  - apple-migration-plan.md
  - ../backend/component-catalog.md
  - ../first-run.md
branch: apple-client-migration
sources:
  - /Users/jones/Valinor/Apple Client/Valinor/  (branch hearth-ios, 9235cd0)
  - /Users/jones/Hearth/apple-client/Hearth/    (scaffold, created 2026-08-08)
  - /Users/jones/Hearth/backend/manifest.yaml
  - /Users/jones/Hearth/tools/sync-report.py
  - Xcode 27.0 (27A5194q) and Xcode 26.5 (17F42), both installed
---

# Apple Implementation Plan

The fourth document, and the one that gets executed. The
[inventory](apple-inventory.md) says what is there, the
[architecture](apple-project-architecture.md) says what to build, the
[migration plan](apple-migration-plan.md) says how to move it. This one
reconciles the three against the machine they are actually being run on,
settles the places where they disagree, and turns the result into an ordered
list of steps with commands attached.

It was written on 2026-08-08 from a read-only pass over both working trees on
this Mac. Five things are true now that were not true when the other three were
written, and each one changes the plan rather than decorating it.

---

## 0. Where this stands

Updated 2026-08-08. Branch `apple-client-migration`; rollback points are
`pre-apple` here and `rc-pre-apple-move` in Valinor.

| Phase | State | Proved by |
| --- | --- | --- |
| 0, rollback and toolchain | done | ignore fix verified against 11 paths; `xcode-select` now Xcode 27 |
| 1, manifest and scrub | done | 79 files reconciled against the source tree, none unaccounted, none phantom |
| 2, the project | done | three targets build; both apps install as **Hearth** |
| 3 area 1, foundation | done | orb drawn from bundled JSON with nothing listening |
| 3 area 2, transport and voice | done | live handshake on 18700 against the local stack |
| 3 area 3, the turn and the cards | **next** | — |
| 3 areas 4–6 | not started | — |
| 4, capabilities and signing | not started | App Group is the check that needs a device |
| 5, first run on a real network | not started | the one check that cannot be faked locally |

### Resuming

Three things about this machine, none of which survive a fresh shell:

- **`export DEVELOPER_DIR=/Users/jones/Downloads/Xcode-beta.app/Contents/Developer`**
  for any command-line build. `xcode-select` is pointed at 27 now, but the
  scripts should not depend on machine state.
- **Open the project in Xcode 27 before starting a session.** The MCP bridge
  advertises no tools when Xcode is closed, which looks exactly like a broken
  configuration (§1.6).
- The Hearth stack answers on 18700; **nothing may be listening on 8700** while
  testing, or a passing first-run check proves nothing.

Two commands say whether the tree is still good:

```
tools/apple-gates.sh                                        # F1 over the tree
python3 tools/sync-report.py --manifest apple-client/manifest.yaml
```

As of this commit: 41 source files checked, all gates clean, 65 files tracked
under `apple-client/`, no drift from Valinor since `9235cd0`.

### What area 3 has to do by hand

The scrub cannot make these, and the manifest prints them after every run:

- `ChatViewModel`, four named subtractions: the Mentat poll; the six seeded
  journal fixtures at 1184–1200, which carry real dates, `"project": "valinor"`
  and titles like "CHOAM market load latency"; the `TTSAudioPlayer` blob-player
  fallback at 127 and 403; and the MWDAT lifecycle.
- The commissioned cards, out of **four** sites rather than the three the
  inventory records — the fourth is `CardLibraryView.swift:242`.
- The `public` pass, compiler-driven, for whatever area 4's shell needs.

### Standing corrections to this document's own plan

Found by executing it, and each one is written up where it belongs:

- `swift build` is the wrong gate for `HearthCore` — it targets macOS, which
  the package does not support. Use `xcodebuild` with an iOS destination.
- Swift 6 for the package does not survive the boundary this migration drew;
  see `Core/Package.swift`, which carries the argument.
- `verbatim` is almost never right for a Swift file: 65 of 73 carry a header
  line naming the old project.
- The MCP bridge cannot create targets, add packages, assign base
  configurations, create schemes, or edit project-level settings (§1.6).

---

## 1. What changed under the plan

### 1.1 Both repositories are on one machine, and it is the Mac

The three documents were written from Windows and are organised around that
fact. Their source paths are `D:/Tools/Valinor` and `D:/Tools/Hearth`; the
migration plan's section E is a Windows-versus-Mac split table; section C2
prices a source freeze against the cost of Mac round trips; section E4's phase-3
rhythm is *Windows scrubs and stages, Mac pulls, builds and reports in one
line*.

None of that applies. The trees are `/Users/jones/Valinor` (branch
`hearth-ios`, `9235cd0`) and `/Users/jones/Hearth`, on the same disk, in the
same session, with Xcode installed.

This is the largest single simplification available and it should be taken
deliberately rather than absorbed:

- **The handoff document disappears.** Scrub and build are the same loop, so
  an area that does not compile is fixed and re-scrubbed in seconds instead of
  in a round trip. The "Mac reports the first error verbatim" protocol exists to
  compress a channel that no longer has latency in it.
- **The freeze mostly disappears.** C2's freeze is expensive because building
  the project by hand is a long pause during which Valinor keeps moving. Here
  the pause is minutes and the operator is the same person, so the correct
  freeze is *do not commit to `Apple Client/` while phase 3 is running*, and
  nothing stronger.
- **`sync-report.py` drops from load-bearing to a receipt.** Its purpose was to
  catch drift across a multi-day window between two machines. It still earns its
  place as a gate — F1 item 9 — but it is no longer the mechanism that makes the
  migration safe. Teaching it `--manifest` is still the right one-line change;
  it is just no longer the *first* thing to do.
- **Section E3's hazards stay.** SDK-versus-device mismatch and the
  launch-without-debugger trick are properties of Apple's tooling, not of the
  Windows split.

What does **not** change is C4's prohibition list, and it gets sharper rather
than softer: with both trees on one disk, the accident of editing Valinor
instead of Hearth is now one wrong `cd` away. **Never `git checkout`, `switch`,
`restore`, `stash`, or commit inside `/Users/jones/Valinor`.** Every command in
this document that touches Valinor is a read.

### 1.2 The branch is `hearth-ios`, and `hearth-journal` is behind it

Both the inventory and migration plan section D name `hearth-journal` as the
consolidated tip. The working tree is on `hearth-ios` at `9235cd0`, and the
ancestry is the other way around.

Checked on 2026-08-08, counting commits ahead of `hearth-ios` over the
`Apple Client/` path:

```
origin/hearth-journal   0
generative-ui           0
visionos-gen-ui         0
valinor-vision          0
ios-generative-ui       0
ios-portal              0
main                    0
```

Every candidate is behind, `hearth-journal` included. The diff from `hearth-ios`
to `hearth-journal` deletes four files — `EaselStore.swift`,
`ImageActions.swift`, `ImageCard.swift`, `ImageViewer.swift` — which is the
drawing card, landed in `9235cd0` after the inventory's survey.

**The inventory's file-level content is correct; only its branch name is
wrong.** Its area table reproduces exactly against the working tree today:

| Area | Inventory | Verified 2026-08-08 |
| --- | --- | --- |
| Swift files, total | 73 / 15,323 | 73 / 15,323 |
| `Valinor/` root | 8 / 1,696 | 8 / 1,696 |
| `Shared/` | 8 / 989 | 8 / 989 |
| `Models/` | 9 / 1,258 | 9 / 1,258 |
| `ViewModels/` | 1 / 1,386 | 1 / 1,386 |
| `Views/` root | 8 / 1,649 | 8 / 1,649 |
| `Views/Dynamic/` | 10 / 1,721 | 10 / 1,721 |
| `VisionOS/` | 5 / 869 | 5 / 869 |
| `Visualization/` | 6 / 1,360 | 5 Swift / 1,244 + `Caustics.metal` 116 |
| `OnDevice/` | 4 / 734 | 4 / 734 |
| `ValinorWidgets/` | 5 / 371 | 5 / 371 |

So the migration reads one branch, and it is `hearth-ios`. The correction is
owed to three places: the inventory's opening paragraph, migration plan D1 and
D2, and the `source.branch` key of the manifest this plan is about to write.

The one substantive consequence: **the drawing card is on the tip and was
device-tested**, which moves it out of the inventory's undecided list on the
client side. It still follows the ComfyUI decision on the backend side. See §2.3.

### 1.3 The scaffold exists, it is kept, and it is where the project grows

`apple-client/Hearth/` is untracked in git and was created on 2026-08-08 from
Xcode's App template, deliberately: a clean slate already associated with the
Apple developer account, so signing works before any source arrives. **It is
kept.** The migration plan's phase 2 is therefore not "create a project" but
"finish this one", and the layout mirrors `desktop-client/` — one
platform-client directory under the repository root, self-contained.

What is in it today, and what each row still needs:

| | Scaffold today | Target state | Note |
| --- | --- | --- | --- |
| Targets | one app target, `Hearth` | + visionOS app, + widget extension | §2.1 |
| `objectVersion` | 110 | unchanged | synchronized root groups confirmed present |
| Bundle id | `com.joshuajones.Hearth` | unchanged | §2.4 |
| `DEVELOPMENT_TEAM` | `AS9PH6XDN4`, four configurations | `Local.xcconfig`, gitignored | the value stays the same, it just leaves source control |
| `SUPPORTED_PLATFORMS` | includes `macosx` | drop `macosx` | nothing targets the Mac at pre-alpha |
| Deployment targets | 27.0 for iOS, macOS, visionOS | iOS 26.0, visionOS 27.0 | §1.4 |
| Sources | `HearthApp.swift` with a SwiftData `ModelContainer`, `ContentView.swift`, `Item.swift` | replaced in area 1 | see below |
| Scheme | `Hearth`, per-user | shared, committed | Valinor never had one either |

Two things to delete rather than carry:

**The SwiftData container.** `HearthApp.swift` builds a `ModelContainer` around
a template `Item` model. Nothing in the client persists through SwiftData — the
state that survives a launch is `UserDefaults` and the App Group snapshot — so
carrying it means a store file appearing in the app container for no reason and
a schema nobody owns. `Item.swift` goes with it.

The bundle identifier is settled in §2.4 and the scaffold's is kept, which
removes what would otherwise have been the one phase-2 step with a cost outside
the repository.

One open question, small and worth answering before targets multiply: the
project currently sits at `apple-client/Hearth/Hearth.xcodeproj` with sources at
`apple-client/Hearth/Hearth/`. `desktop-client/` puts its contents directly
under the client directory, so the closer analogue is
`apple-client/Hearth.xcodeproj`. Moving it up one level is free today and
touches the synchronized root group paths, the entitlements and the widget
membership list once the second and third targets exist.

### 1.4 The toolchain is Xcode 27, but `xcode-select` points at 26.5

Corrected 2026-08-08 after checking the whole disk rather than the active
developer directory. Both are installed:

| | Path | SDKs |
| --- | --- | --- |
| **Xcode 27.0** (27A5194q) | `/Users/jones/Downloads/Xcode-beta.app` | iOS 27.0, visionOS 27.0 |
| Xcode 26.5 (17F42) | `/Applications/Xcode.app` | iOS 26.5, visionOS 26.5 |

```
$ xcode-select -p
/Applications/Xcode.app/Contents/Developer      # 26.5
```

**This is a live hazard, not a footnote.** Every `xcodebuild` in this plan, and
every command a script runs, resolves through `xcode-select` and therefore gets
26.5 — which cannot build against the visionOS 27 SDK the floor requires. The
symptom is an SDK-mismatch error that names a deployment target rather than a
toolchain, which is the most misread error in the whole Apple toolchain.

Two fixes, and the second is the one to rely on:

- `sudo xcode-select -s /Users/jones/Downloads/Xcode-beta.app/Contents/Developer`
- Set `DEVELOPER_DIR` explicitly in the scrub script, the build gates and the
  runbook, so a build never depends on machine state:
  `export DEVELOPER_DIR=/Users/jones/Downloads/Xcode-beta.app/Contents/Developer`

Also worth moving `Xcode-beta.app` out of `~/Downloads`, which is a directory
things get cleaned out of.

**Verified against the scaffold, 2026-08-08**, with `DEVELOPER_DIR` set to 27:

```
xcodebuild -scheme Hearth -destination 'generic/platform=iOS Simulator'      build   ** BUILD SUCCEEDED **
xcodebuild -scheme Hearth -destination 'generic/platform=visionOS Simulator' build   ** BUILD SUCCEEDED **
```

Device destinations (`generic/platform=iOS`) fail on provisioning —
`No profiles for 'com.joshuajones.Hearth' were found` — because automatic
signing needs `-allowProvisioningUpdates` from the command line. That is
expected and is not a project defect; the simulator gates are the ones the
per-area loop should run, and device signing is phase 4's business.

**Floors, decided:** `IPHONEOS_DEPLOYMENT_TARGET = 26.0` for the app and the
widget extension, `XROS_DEPLOYMENT_TARGET = 27.0`. The inventory and the
architecture article disagreed about the visionOS floor and the answer is the
inventory's: 27 is where the caustics rig's `SpotLightComponent.ProjectiveTexture`
and `SurroundingsLight` live, the SDK is installed, and the one Vision Pro this
surface has to run on is Joshua's. iOS goes to 26.0 for reach, since nothing in
the iOS source needs 27 — there is no Liquid Glass adoption on iOS at all, and
the five `glassBackgroundEffect()` calls are visionOS and predate visionOS 2.

The consequence for phasing: **the immersive caustics mode is no longer blocked
by the toolchain.** Architecture §7 gates it on "a Mac session builds and runs
it, and visionOS 27 is generally available"; the first half is now available
and the second is a distribution question that does not apply to an audience of
one. It stays out of *this migration* because it is unverified code and the
migration's value is a clean starting point — but it returns as a feature branch
that can actually be built, rather than as something waiting on Apple. See §2.3.

One thing to check early rather than discover: Valinor's own Apple project also
sets `XROS_DEPLOYMENT_TARGET = 27.0`, so F4 item 19 — Valinor still builds —
needs the same `DEVELOPER_DIR`. Run that check under 27, not under whatever
`xcode-select` happens to point at.

### 1.5 `.gitignore` already swallows `Models/`, and it is verified

Migration plan B4 warns that broad ignore patterns eat sibling-stack source and
notes it went undetected for a week last time. It is not a hypothetical here.

```
$ git config core.ignorecase
true
$ git check-ignore -v apple-client/Hearth/Hearth/Models/Foo.swift
.gitignore:16:models/	apple-client/Hearth/Hearth/Models/Foo.swift
```

`models/` on line 16 is there for downloaded weights. macOS sets
`core.ignorecase = true`, which makes ignore matching case-insensitive, so it
matches `Models/` as well — and `Models/` is nine files and 1,258 lines of wire
types, the layer everything else depends on. Committed as-is, the build passes
on this machine and every clone fails to compile at area 1.

This is a phase-0 fix, before anything is copied, and it needs three changes:

- Anchor the weights rule to where weights live rather than to a bare name.
- Add the Xcode rules the repository has never needed: `xcuserdata/`,
  `DerivedData/`, `*.xcuserstate`, `Local.xcconfig`, `.swiftpm/`.
- Do **not** ignore `Package.resolved` — migration plan B5 is explicit that the
  pinned revisions are the ones that build, and for a zero-dependency project
  it is a two-line file that documents the absence.

**And do not solve it with `.gitkeep`.** Tried, 2026-08-08, and it fails
loudly: a synchronized root group treats every file in the folder as a resource,
including dotfiles, and flattens them into `Resources/`. Four folders each
holding a `.gitkeep` produced four commands writing one output path and the
build stopped with `Multiple commands produce .../Resources/.gitkeep`. Empty
organization folders therefore cannot be kept in git by the usual trick; they
arrive when their first real file does.

The general form of the check, which is F1 item 8 and which should run after
every area rather than once at the end:

```
git ls-files apple-client | wc -l          # against the manifest's count
git status --porcelain --ignored apple-client | grep '^!!'   # nothing surprising
```

### 1.6 The Xcode MCP bridge is live tooling, and it is empty when Xcode is closed

`xcrun mcpbridge` — Apple's own bridge, `xcode-tools` 25227.8 — was registered
against the Valinor project scope only. It is now registered for Hearth, pinned
to the Xcode 27 binary rather than invoked through `xcrun`, since both Xcodes
ship one and a bare `xcrun` resolves through `xcode-select` (§1.4).

**It advertises no tools unless Xcode.app is running.** Probed directly: with
Xcode closed, `initialize` succeeds, reports `tools: {listChanged: true}`, and
`tools/list` never answers. With the project open in Xcode 27, the same probe
returns **47 tools**. A session that starts before Xcode does gets a connected
server with nothing in it, which looks exactly like a broken configuration.

The operational rule: **open the project in Xcode 27 first, then start the
session.**

What it changes about phases 2 and 3, which were written assuming `xcodebuild`
and the Xcode UI were the only two instruments:

| Tool | Replaces |
| --- | --- |
| `UpdateTargetBuildSetting`, `GetTargetBuildSettings` | hand-editing floors, `SUPPORTED_PLATFORMS` and identifiers in the project file |
| `AddEntitlement` | the App Groups capability step in phase 4 |
| `AddInfoPlist` | per-target plist keys, including the world-sensing key |
| `XcodeMakeDir`, `XcodeWrite`, `XcodeMV`, `XcodeRM` | filesystem operations that keep the project navigator in step |
| `BuildProject`, `GetBuildLog`, `XcodeRefreshCodeIssuesInFile` | the per-area gate, with diagnostics per file rather than a log tail |
| `XcodeListSchemes`, `XcodeListRunDestinations`, `XcodeSwitchRunDestination` | guessing at `-destination` strings |

This does not change what the phases *do*. It changes how much of phase 2 and
phase 4 has to happen through the UI, which was the part of this plan least able
to be checked by anyone but the person doing it. The `xcodebuild` gates stay as
written, because they are what a fresh clone runs and the bridge is not.

**What the bridge cannot do**, established by working through phase 2 with it
rather than by reading the tool list. The 47 tools operate on things that
already exist; they do not create project structure. There is no tool that:

- creates a target
- adds a local package to a project
- assigns a base configuration file (`.xcconfig`) to a build configuration
- creates or shares a scheme
- edits a **project**-level build setting — `UpdateTargetBuildSetting` is
  target-level only, and that gap has a sharp edge, see below

So phase 2's topology is a UI session, and everything after it is drivable.
Plan accordingly: make the targets, the package and the xcconfig assignments in
one sitting, then hand the settings, entitlements, plists and build gates to the
bridge.

**The project-level gap is not cosmetic.** `DEVELOPMENT_TEAM` can be deleted
from all three targets through the bridge and still sit in the project's own
build configurations, where nothing but Xcode or a pbxproj edit can reach it.
A clone then builds using the committed team rather than failing over to
`Local.xcconfig`, which is precisely the failure `Local.xcconfig` exists to
produce loudly. Clear it at the project level by hand, and check with
`git grep AS9PH6XDN4 -- apple-client/` rather than by reading the target editor.

---

## 2. Decisions to settle before phase 2

Four, and three of them are places where two of the existing documents give
different answers. Recommendations attached; each is reversible only at the
stated cost.

### 2.1 Project shape: the two documents disagree

| | Migration plan A0 / E2 | Architecture §1 |
| --- | --- | --- |
| Container | one `.xcodeproj` | `.xcworkspace` |
| Targets | 2: app (iOS + visionOS in one), widgets | 4: iOS app, visionOS app, iOS widgets, visionOS widgets |
| Shared code | `Shared/` folder, widget sees five files by `membershipExceptions` | local package `HearthKit`, product dependency |
| Config | settings in the project file | `*.xcconfig` at the project root, `Local.xcconfig` gitignored |
| Created by | hand, in Xcode, committed alone | hand or generated; explicitly left open |

They cannot both be executed. The migration plan's area order, its section B4
trap list and F2 item 12 are all written against the two-target shape; the
architecture article's dependency policy, its identifier table and its phase 0
are written against the package shape.

**Recommendation: the architecture article's shape, minus the fourth target.**
One `.xcodeproj`, no workspace, three targets, one local package:

```
apple-client/
  manifest.yaml
  Hearth.xcodeproj
    Hearth iOS         (app)     the portrait stage, the house surfaces
    Hearth visionOS    (app)     skeleton: a volumetric window hosting the orb
    Hearth Widgets     (appex)   embedded by Hearth iOS
  HearthKit/                     local Swift package, platform-neutral core
    Package.swift
    Sources/HearthKit/
    Resources/Personas/sulivan.json
  Hearth iOS/                    host scenes, iOS-shaped layout
  Hearth visionOS/               host scenes, RealityKit
  Hearth Widgets/
  Shared.xcconfig  Dev.xcconfig  Release.xcconfig  Local.xcconfig   (project root)
  docs/runbook.md
```

Four reasons, in order of weight:

1. **It deletes the membership-exception mechanism entirely.** The five-path
   `membershipExceptions` list is the only place in Valinor's project file where
   disk layout and build graph disagree, it is the thing migration plan A5
   orders area 5 around, and it is F2 item 12. A widget target that depends on
   the `HearthKit` product has no such list. Sharing a sixth type becomes a
   `public` keyword in a Swift diff.
2. **It deletes `Compat/WearablesShim.swift` by construction.** The shim exists
   only because one target builds for both platforms and MWDAT is iOS-only. Two
   app targets means the file is never ported and never written again. With
   MWDAT out (§2.3) this is a smaller win today and a large one when it returns.
3. **It makes `NSWorldSensingUsageDescription` structurally impossible to
   miss.** Two targets, two ordinary `Info.plist` files, no per-SDK
   `INFOPLIST_FILE` override — which is migration plan B4's second trap and
   F5's sixth row, retired rather than documented.
4. **`swift build` typechecks the core without a simulator.** Area gates get
   faster and the model layer becomes reviewable independently.

The costs, stated: access control has to be written on the shared surface;
previews across a package boundary are fussier; and the split has to be drawn
deliberately, which architecture §1 already does in its "what goes in HearthKit"
table. Drawing it against one and a half consumers is the real risk, which is
what the visionOS skeleton target exists to mitigate.

**Grow the existing scaffold by hand in Xcode; do not generate it.** Both
documents raise XcodeGen or Tuist. Against: the scaffold is
`objectVersion = 110`, newer than the format either generator reliably emits;
the generators' selling point — a project file reviewable as text — is largely
bought instead by the xcconfigs, where the settings that matter live; and
regenerating would discard the signing association the scaffold was created to
establish. Revisit if the target count grows past four.

**Cost of reversing:** high after phase 3 begins. This decision must land before
the second and third targets exist, because it decides whether shared code
reaches the widgets through a package product or through a membership list.

### 2.2 The floors and the phasing

Settled by §1.4. `XROS_DEPLOYMENT_TARGET = 27.0`, keeping the caustics APIs in
reach on the one headset this surface runs on.
`IPHONEOS_DEPLOYMENT_TARGET = 26.0` for both the app and the widget extension —
the widget's 26.2 in Valinor is an artifact of the tool version that created it,
and an extension with a higher floor than its host is a divergence nobody chose.
`MACOSX_DEPLOYMENT_TARGET` and `macosx` come out of `SUPPORTED_PLATFORMS`
entirely.

A consequence of the split floor worth stating, because it is the argument
§2.1's target topology rests on: iOS at 26.0 and visionOS at 27.0 cannot be one
target. A single target expresses two floors as two settings fighting inside one
configuration.

That is not hypothetical, and it is worth reading off Valinor's project file
directly, because the two-target shape is a **departure** from Valinor rather
than a copy of it. Verified 2026-08-08:

```
2 native targets:  Valinor (application), ValinorWidgetsExtension (app-extension)

  SUPPORTED_PLATFORMS         = "iphoneos iphonesimulator xros xrsimulator"
  TARGETED_DEVICE_FAMILY      = "1,2,7"        # iPhone, iPad, Vision Pro
  IPHONEOS_DEPLOYMENT_TARGET  = 26.0           # both floors,
  XROS_DEPLOYMENT_TARGET      = 27.0           # one configuration
  INFOPLIST_FILE[sdk=xros*]        = Info-visionOS.plist
  INFOPLIST_FILE[sdk=xrsimulator*] = Info-visionOS.plist
```

There is no visionOS target. One app target carries both platforms, and every
mechanism the other articles complain about follows from that single fact: the
per-SDK `INFOPLIST_FILE` override exists because one target cannot own two
plists, `Compat/WearablesShim.swift` exists because one target cannot link an
iOS-only framework conditionally, and eight Swift files carry `#if os(visionOS)`
because one target compiles everything for both. What can look like two targets
in the Xcode UI is two *schemes* — `Valinor.xcscheme` and
`ValinorWidgetsExtension.xcscheme` — which are per target, not per platform.

Two app targets state each floor once, in the place it applies, and retire all
three mechanisms.

The visionOS target is present from the first commit and holds a volumetric
window with the orb in it. The volumetric surface's own contents — orbiting card
attachments, gaze and tap, the session gallery — are architecture §7 phase 2 and
are not part of this migration.

### 2.3 The inventory's four undecided rows

| Row | Recommendation | Why now |
| --- | --- | --- |
| **MWDAT / Ray-Bans** | out | Architecture §5 argues it at length and nothing has changed: the camera path never forwards a frame, `ClientToken` and `MetaAppID` are empty strings in the repository, and it costs a Bluetooth prompt and two background modes before a tester receives any value. Out also removes the shim, the three SPM products with their `platformFilter`, four Info.plist keys, and the awkward half of the URL-scheme rename. |
| **visionOS surface** | skeleton in, features phased | §2.2. The immersive caustics mode is out of *this* migration because it is unverified code and a clean starting point is the whole point — but §1.4 removes the toolchain blocker, so it returns as a buildable feature branch rather than as something waiting on Apple. First step when it does: build it under Xcode 27 and confirm `Caustics` appears in the product's `default.metallib`. |
| **Drawing card** | in | It is on the tip, device-tested, and its five files are already ordered inside area 3. It reaches ComfyUI through the gateway origin like everything else, so if the backend decision goes the other way the card renders nothing, which is the tolerant-descriptor behaviour and is correct. Excluding it now would be a client answer to a backend question. |
| **What a phone dials before it is told an address** | no host default; port defaults to 18700 | Both the migration plan (B2) and the architecture article (§4) reach this independently, and it is the only one of the four that is genuinely unbuilt. Empty host is a distinct state, and in that state the app does not dial: it renders the bundled Sulivan and shows the connection field. Bonjour discovery is the later refinement and does not gate this. |

A fifth, which the inventory raises in §6 and the migration plan leaves as a
manifest note: **rename the `UserDefaults` keys.** `valinor_server_ip`,
`valinor_server_port`, `valinor_inference_mode` and `valinor_last_persona`
become `hearth.` -prefixed, and the widget snapshot key `valinor.snapshot.v1`
becomes `hearth.snapshot.v1`. Nothing has shipped, so nothing is stranded, and
this is free today and a migration path forever after.

Sixth, and it needs an answer in the same breath because it has the same
one-way property: **the widget's `kind` string.** `SulivanWidget` declares
`kind: "Sulivan"`, and changing a widget's kind after release orphans every
placed widget. Recommendation: make it `hearth.persona` and `hearth.quicktalk`,
identifiers rather than persona names, since the widget renders whichever
persona the snapshot names.

### 2.4 The identifier family — decided, and it is the product name

**Decision, 2026-08-08: the identifier carries the product name in the position
Valinor's does, and the scaffold's `com.joshuajones.Hearth` is kept.** The
migration plan (B3) proposed `com.hearth.release.ios` and the architecture
article (§2) proposed a four-way release/development split; neither survives,
and the reasoning for dropping them is worth recording because both documents
argue at length for what they proposed.

| | Value |
| --- | --- |
| iOS app | `com.joshuajones.Hearth` |
| iOS widget extension | `com.joshuajones.Hearth.Widgets` |
| visionOS app | `com.joshuajones.HearthVision` |
| App Group | `group.com.joshuajones.Hearth` |
| URL scheme | `hearth` |

Three things this gets right that the alternatives did not:

**It satisfies the constraint that actually breaks things.** The load-bearing
requirement behind both documents' proposals is that Hearth and Valinor must not
share an operating-system store — container, `UserDefaults` suite, App Group,
keychain, widget timeline, or TCC grant — because all seven key off the
identifier, and a developer build installed over a tester build inherits every
one. `com.joshuajones.Hearth` against `com.joshuajones.Valinor` collides on
none of them. The architecture article's objection to the `com.joshuajones.*`
namespace is that it encodes a person into a product, which is true and is a
branding cost rather than a functional one: the string is visible in
provisioning and App Store Connect, and not to a user.

**It matches the convention already in use.** Valinor's identifier is
`com.joshuajones.Valinor` — namespace, then product. Hearth taking the same
shape means one rule for both Apple clients, and the desktop's
`com.hearth.release.app` stays what it is: a name chosen to solve a
WebView2-profile collision that has no analogue here.

**It costs nothing.** The scaffold already holds this identifier and is already
associated with the developer account, so phase 2 registers the App Group and
the two additional App IDs and nothing has to be re-provisioned.

Two notes on the derived rows. The widget extension's identifier **must** be
prefixed by its host app's — that is an Apple requirement, not a style choice,
and it is why one widget target cannot be embedded by both apps. It is also why
`apple-client/Hearth/Hearth/widgets/` cannot become a widget by being a folder:
an `.appex` needs its own target, bundle identifier, entitlements and
`Info.plist`, none of which a directory can supply. The folder is the right home
for the source and phase 2 points a target at it. The visionOS
app is deliberately `HearthVision` rather than `Hearth.vision`: a separate app
whose identifier looks like an extension of another app is legal and reads as a
mistake every time anyone opens the provisioning portal.

**One App Group, not one per platform.** Architecture §2 proposed splitting it
by platform. The two platforms never share a device, so the split buys nothing
and adds a third string that has to agree with itself. `SharedSnapshot`'s
`appGroupID` is still generated into the build from `$(HEARTH_APP_GROUP)` rather
than typed, which is the part of that section worth keeping: a mismatch between
the entitlements and the Swift constant compiles, signs, installs, runs, and
draws a fallback orb forever.

**The release/development split is dropped.** It existed on the desktop because
a daily-driver client and a release client run on the same machine. Nothing here
does: Valinor's Apple client is a different identifier already, and one person
with one phone does not need two installs of Hearth. If a TestFlight build ever
needs separating from a local one, `Dev.xcconfig` already exists as the place to
add a suffix, and it is one variable.

### 2.5 Selene's assets

The inventory records that `PersonaModels/` is gitignored in Valinor on purpose,
so a fresh clone builds an app that cannot show Selene offline and nothing says
so. The clean project should not inherit an accident.

Recommendation for pre-alpha: **do not bundle the USDZ set, and make the absence
explicit.** The `glb_animated` renderer path comes across intact — it is
data-driven from the persona config and falls back to the orb when no model
arrives — and the fallback is the honest behaviour for a client whose house
serves the assets. What changes is that the fallback becomes a stated design
rather than a silent one: `PersonaModelView` should log once, at debug level,
that no bundled model was found for the named persona.

---

## 3. The plan

Seven phases. Each has a gate that is a command, and no phase starts before the
previous one's gate passes.

### Phase 0 — The branch, the rollback points, the toolchain, the ignore fix

Half an hour, no code moves.

1. **Branch.** All of this lands on `apple-client-migration` in Hearth, not on
   `main`, because desktop-client work continues on the Windows machine and the
   two should not interleave on one branch. Created 2026-08-08 off `main` at
   `bc477f5`.
2. Tag Valinor at the freeze commit — **a tag is a write, so it is the one
   exception to §1.1's read-only rule, and it is the only one**:
   `git -C /Users/jones/Valinor tag rc-pre-apple-move hearth-ios`
3. Tag Hearth: `git tag pre-apple`
4. **Pin the toolchain**, per §1.4. Either `sudo xcode-select -s` to the 27
   developer directory, or export `DEVELOPER_DIR` — and do it in the runbook and
   the scrub script either way, so no gate depends on machine state. Confirm:
   `xcodebuild -version` reports 27.0 in the same shell the gates run in.
5. **Commit the scaffold as-is, on its own**, before changing a setting in it.
   It is four template files and a project file, and committing it first makes
   the phase-2 diff read as *what we changed about the template* rather than as
   twenty thousand unreviewable lines mixed with intent.
6. Fix `.gitignore` per §1.5, and prove it:
   `git check-ignore -v apple-client/Hearth/Models/Foo.swift` must exit 1.
7. Record `9235cd0` as the source commit for the manifest.

**Gate:** `git check-ignore` returns nothing for a path under every directory
name the manifest will create. Generate that list from the manifest in phase 1
and re-run it; do not eyeball it.

**Executed 2026-08-08.** Branch `apple-client-migration`; Valinor tagged
`rc-pre-apple-move` at `9235cd0`; Hearth tagged `pre-apple` at `bc477f5`, with
`4111e54` (the plan), `5a1d778` (the ignore fix) and `0e7574a` (the scaffold)
after it. The ignore fix was verified against eleven paths spanning every
directory the manifest will create, including a lowercase `Core/models/`, with
the three rules it protects — `/backend/models/`, `*.gguf`, `xcuserdata/` —
re-confirmed to still bite. Step 4 is outstanding and needs a password:
`sudo xcode-select -s /Users/jones/Downloads/Xcode-beta.app/Contents/Developer`.

Two findings from the tag step, neither of them blocking.

**Valinor's working tree is not clean, and was not made unclean by this
migration.** Two `xcuserdata` files are modified and two `xcuserdata`
directories are untracked; `UserInterfaceState.xcuserstate` was last written at
10:18 on 2026-08-08, before this session opened anything. The consequence is for
F4 item 18, which asks that `git status` in Valinor be clean: read it as **clean
under `Apple Client/` excluding `xcuserdata/`**, because Valinor tracks user
state and merely opening the project dirties it. The tag is unaffected — it
names a commit, and none of this is committed.

**Valinor does have shared schemes, contrary to the inventory.**
`Valinor.xcodeproj/xcshareddata/xcschemes/` holds `Valinor.xcscheme` and
`ValinorWidgetsExtension.xcscheme`, created 2026-06-08. They are untracked, so
the inventory's conclusion still holds for a fresh clone — the schemes are not
in the repository and Xcode regenerates them per user — but the reason is that
they were never added, not that they do not exist.

### Phase 1 — The manifest, and the scrub

This is the migration plan's "first thing to do" and it survives intact. The
manifest is the boundary in machine-readable form: it is what the scrub
iterates, what `sync-report.py` watches, what the `git ls-files` count is
checked against, and what forces the deferred set to carry a written disposition
before anything crosses.

`apple-client/manifest.yaml`, in the shape `backend/manifest.yaml` already uses,
with the same four dispositions (`verbatim`, `edits`, `generated`, `excluded`)
and these additions:

```yaml
version: 1
source:
  repo: Valinor
  path: /Users/jones/Valinor
  branch: hearth-ios          # NOT hearth-journal; see apple-implementation §1.2
  commit: 9235cd0
  tag: rc-pre-apple-move
identity:                     # the strings that must agree with themselves
  bundle_id_ios:      com.joshuajones.Hearth          # §2.4
  bundle_id_widgets:  com.joshuajones.Hearth.Widgets  # must be prefixed by the host
  bundle_id_visionos: com.joshuajones.HearthVision
  app_group:          group.com.joshuajones.Hearth    # one group, both platforms
  url_scheme:         hearth
  default_port:       18700
  default_host:       ""      # deliberately empty; see §2.3
components:
  - name: ...
    source: Apple Client/Valinor/Valinor/Models/
    destination: apple-client/HearthKit/Sources/HearthKit/Models/
    area: 1
    target: hearthkit         # hearthkit | ios | visionos | widgets
    disposition: edits
```

`target` is new against the backend manifest and it is what makes the package
split reviewable as data rather than as an argument. Every file in the
architecture article's "what goes in HearthKit" table gets `target: hearthkit`;
everything whose *layout* is platform-shaped gets an app target.

`tools/apple-scrub.py`, alongside it, does exactly what migration plan B
specifies: read the manifest, copy each source to its destination, apply the
rename table, the port and host table and the identifier table, and support
`--area N` and `--check`. Two properties matter more than the rest:

- **It reads its substitutions from the manifest's `identity` block**, never
  from constants in the script. The app group appears in three files and the URL
  scheme in three places, and every disagreement between copies is silent.
- **It refuses to write over anything the manifest marks `generated`.** The
  project file, the two entitlements files and the xcconfigs are hand-made and
  must survive a re-scrub. This is migration plan C2's boundary and it is the
  reason `disposition` exists as a column.

The rename table needs one addition the migration plan does not list, because it
follows from §2.1: files moving into `HearthKit` need `public` on their shared
surface. That is not a substitution a script can make correctly. Do it as a
compiler-driven pass during each area — build, add `public` where the app target
cannot see a symbol — and record in the manifest note that the file was edited
beyond substitution.

Also in this phase, and it is one line: teach `sync-report.py` `--manifest`.

**Gate:** `tools/apple-scrub.py --check` runs clean against the whole manifest
and reports a file count. Nothing has been copied.

### Phase 2 — Finishing the project

Xcode, by hand, on top of the committed scaffold, per §2.1 and §2.2. In order,
because each step is cheaper before the next one exists:

1. Delete `Item.swift` and the SwiftData `ModelContainer` from `HearthApp.swift`.
2. Fix the floors and platforms: iOS 26.0, visionOS 27.0, `macosx` out.
3. Move identity into the project-root xcconfigs — `HEARTH_ID_PREFIX`,
   `HEARTH_APP_GROUP` — and `DEVELOPMENT_TEAM` into a gitignored
   `Local.xcconfig`. The iOS App ID already exists; register
   `group.com.joshuajones.Hearth` and, in step 5, the two additional App IDs
   against the developer account in the same sitting (§2.4).
4. Add `HearthKit` as a local package with one `public` symbol, and make the app
   target depend on it.
5. Add the visionOS app target and the widget extension target, both depending
   on `HearthKit`. Each app target gets its own ordinary `Info.plist`.
6. Share the scheme and commit it — Valinor never had one, and a fresh clone
   currently gets whatever Xcode autocreates.

Then, before any source moves, the check migration plan A1 asks for: **drop one
file on disk inside a synchronized folder, build, and confirm it compiled
without opening the file inspector.** Synchronized root groups are confirmed
present in the scaffold, so this should pass; run it anyway, because the whole
per-area rhythm rests on it and file one is a cheaper place to learn than file
forty.

Put into `docs/runbook.md` the five settings a reader should be able to verify
without diffing the project file: bundle identifiers, app group,
`SUPPORTED_PLATFORMS`, deployment targets per target, and
`CODE_SIGN_ENTITLEMENTS` — plus the `DEVELOPER_DIR` line from §1.4.

**Gate**, with `DEVELOPER_DIR` pointing at Xcode 27:

```
xcodebuild -scheme "Hearth iOS"      -destination 'generic/platform=iOS Simulator'      build
xcodebuild -scheme "Hearth visionOS" -destination 'generic/platform=visionOS Simulator' build
swift build --package-path apple-client/HearthKit
```

All three succeed, and `git status` shows `Local.xcconfig` ignored. Simulator
destinations, not `generic/platform=iOS` — device builds need
`-allowProvisioningUpdates` and belong to phase 4, and the two failure modes
should not be able to mask each other in a routine gate.

### Phase 3 — The six areas

The migration plan's area order holds, because its constraint is the Swift
compiler and that has not moved. What changes is that each area now names a
target as well as a set of files, and that the loop has no handoff in it.

| # | Area | Lands in | Notes |
| --- | --- | --- | --- |
| 1 | Foundation and first run | `HearthKit` + iOS app entry | `ServerConfig`, `Models/`, `Shared/`, and the **new** `Resources/Personas/sulivan.json` |
| 2 | Transport and voice | `HearthKit` | the socket client, `SpeechRecognitionManager`, `TTSStreamPlayer`; `AudioInputManager` session config only |
| 3 | The turn and the cards | `HearthKit` | `ChatViewModel` and `Views/Dynamic/` entire, including the drawing card |
| 4 | The iOS shell and house surfaces | iOS app | the stage, the shelf, the status bar, the composer, and the four surfaces |
| 5 | Widgets | widgets target | now a package dependency, not a membership list |
| 6 | Visualization and the visionOS skeleton | visionOS app | `RealityKitSceneManager`, `PersonaModelView`, the volumetric window |

Per area, exactly this, and it is now four steps rather than five:

```
tools/apple-scrub.py --area N          # copy and substitute
git diff --stat                        # review what the script did
xcodebuild -scheme "Hearth iOS" -destination 'generic/platform=iOS' build
git ls-files apple-client | wc -l      # the ignore check, every area
git commit
```

The rule that makes it work is unchanged from migration plan E4: **fixes go into
the scrub script, never into the copied file**, right up until the `public` pass
that the package boundary requires. When an area needs a hand edit that the
script cannot express, the manifest note for that file says so, which is what
keeps `--check` honest afterwards.

Three area-specific notes:

**Area 1 is not a copy.** The bundled persona does not exist in the Apple client
today — it asks the server with `get_persona_config` and falls back to constants
in `PersonaPalette`. `backend/personas/Sulivan/sulivan.json` and
`desktop-client/src/personas/sulivan.json` both exist in this repository; the
Apple client should decode one of them with the same `PersonaVisualization`
decoder that handles the wire payload, so the fallback reads from the file
rather than restating its numbers in Swift. This is the item most likely to be
quietly deferred and it is the whole of the first-run claim.

**Area 3 is the one to watch.** `ChatViewModel` is 1,386 lines, it is the hub
every later area attaches to, and it is also where three of the scrub's
subtractions land: the Mentat poll, the seeded journal fixtures at lines
1184–1200, and the `"Valinor"` reply-attribution fallback. Expect this area to
take longer than the other five together.

**Area 5's gate changed.** F2 item 12 asks that five specific files resolve
inside the widget target, which was the membership-list check. Under the package
shape the equivalent check is that the widget target builds against
`HearthKit`'s public surface — same failure, louder, and at compile time in both
shapes.

### Phase 4 — Capabilities and signing

App Groups on both app targets and the widget extension, entitlements files
reading `$(HEARTH_APP_GROUP)`, `DEVELOPMENT_TEAM` present only in
`Local.xcconfig`. The Swift-side app group constant is generated into the build
rather than typed, per architecture §2, so the count of hand-maintained copies
of that string is one instead of three.

**Gate:** a device install of the iOS app whose widget renders live state after a
turn. That is the only check that proves all copies of the group identifier
agree, because a mismatch installs, runs, and draws the fallback orb.

### Phase 5 — First run

The check that matters most, and the one every other check on the list will pass
whether or not it does.

1. **Airplane mode, or a network that cannot reach this machine.** Launch. The
   app draws Sulivan from the bundled JSON, shows the connection field, and does
   not dial. No spinner, no error dialog, no palette-fallback orb.
2. Enter this machine's address, port 18700, against a running Hearth backend.
   Complete a spoken turn: connect, `client_transcription`, PCM out, a card on
   screen.
3. Confirm the widget updates from the App Group after that turn.

Step 1 is non-negotiable and it cannot be performed on this network with the
Valinor stack running, because a surviving `10.1.95.5` default produces a
flawless-looking first run against someone else's house. That is the failure the
pre-alpha handoff already recorded once.

### Phase 6 — The grep gates

Migration plan F1, run as a script so it can gate a commit. All of them apply
unchanged except that `apple-client/` is now the only path argument:

```
git grep -i valinor  -- apple-client/ ':!*.pbxproj' ':!*.xcconfig'   # nothing
git grep -E '\b10\.[0-9]+\.[0-9]+\.[0-9]+\b|\b192\.168\.' -- apple-client/
git grep -E ':(8700|8765|8766|8080|8702)\b'         -- apple-client/
git grep -E 'D:/Tools|/Users/jones/Valinor'         -- apple-client/
git grep 'valinor://'          -- apple-client/
git grep -n 'SwiftData'        -- apple-client/     # the template's, nothing else
git ls-files apple-client | wc -l                   # matches the manifest
tools/sync-report.py --manifest apple-client/manifest.yaml
```

Three changes against migration plan F1, and the first two are consequences of
§2.4 rather than relaxations:

**`git grep -i joshuajones` is dropped.** It was F1 item 2 and it would now fail
by design, because the identifier family deliberately keeps that namespace. The
check it was standing in for — that no *Valinor* identity crosses — is covered
by the `valinor` grep, which is the one that matters.

**`git grep AS9PH6XDN4` is dropped as a source grep and becomes a project-file
check.** The team ID is legitimately present on this machine; what must be true
is that it lives only in the gitignored `Local.xcconfig`. The check is
`git grep AS9PH6XDN4 -- apple-client/ ':!*/Local.xcconfig'` returning
nothing, which is a different assertion from "the string does not appear".

**The `valinor` grep gains two path exclusions.** `SUPPORTED_PLATFORMS` and
`DEVELOPMENT_TEAM` do not name Valinor, but the project file and the xcconfigs
may legitimately reference the Valinor tree in a comment recording where a
setting came from. Excluding them keeps the gate about source, which is what it
is for. If that turns out never to happen, drop the exclusions and tighten it.

One addition this machine earns: the path grep gains `/Users/jones/Valinor`
alongside `D:/Tools`, because a copy on one disk can carry an absolute path that
a copy across machines could not.

### Phase 7 — Retire nothing

Valinor's Apple project stays where it is and stays buildable. F4 items 18 and
20 are the check: `git status` clean in `/Users/jones/Valinor`, on `hearth-ios`,
with nothing changed under `Apple Client/`; and both apps installed side by side
on one device without either replacing the other.

---

## 4. What this plan says is unbuilt

Recorded here so it is estimated rather than discovered. None of it is a port.

| Item | Where it lands | Why it does not exist yet |
| --- | --- | --- |
| `Resources/Personas/sulivan.json` and the decoder path that reads it | area 1 | the Apple client has never bundled a persona |
| The no-host first-run state and its connection prompt | area 1 | today an empty field restores the build-time default |
| `HearthKit`'s public surface | areas 1–3, compiler-driven | there is no package today |
| The xcconfig set and `Local.xcconfig` | phase 2 | settings live in the project file today |
| A shared scheme, committed | phase 2 | Valinor's `xcshareddata/` does not exist; `xcuserdata/` is checked in |
| App icons | not gated | both catalogs hold only `Contents.json`; same state as the desktop client |
| Widget chrome from the palette | area 5 | three hardcoded violet literals and a near-black background |
| `tools/apple-scrub.py` | phase 1 | new |
| `sync-report.py --manifest` | phase 1 | one line |

## 5. Corrections owed to the other three documents

Made here rather than silently, because an executor will read all four.

- **The branch is `hearth-ios` at `9235cd0`**, not `hearth-journal`. Affects the
  inventory's opening and "Branch reality" section, and migration plan D1/D2.
- **The visionOS floor is 27.0 and the iOS floor is 26.0.** The inventory reads
  27.0 as the visionOS floor and it is right; the architecture article argues for
  26.0 from the availability guards, which is sound in the abstract and loses to
  the fact that the SDK is installed and the headset is a known quantity. Both
  documents' single-floor framing goes with it — the two platforms take
  different floors, which is a reason the two app targets are not optional.
- **`Visualization/` is 5 Swift files and one `.metal`**, which the inventory's
  6/1,360 row aggregates. Not an error, worth stating for the manifest count.
- **Migration plan section E is void** and section C2's freeze economics with it.
- **The drawing card is decided, on the client side**, by having landed and been
  device-tested.
- **`.gitignore:16` currently swallows `Models/`.** B4 predicted the class; this
  is the instance.
- **The identifier family is `com.joshuajones.Hearth`, not `com.hearth.release.*`,
  and there is no release/development split.** Migration plan B3 and architecture
  §2 both proposed otherwise and both should be read as superseded by §2.4. The
  grep gate F1 item 2 goes with them.
- **Two Xcodes are installed and `xcode-select` points at the wrong one.**
  Neither document could have known; it is the first thing to fix on this
  machine and the reason an SDK error will name a deployment target instead.
- **The immersive caustics mode is no longer blocked on tooling.** Architecture
  §7's gate has half retired itself. It stays out of the migration on
  verification grounds, which is a different and weaker reason than the one that
  was written.

These are edits to this repository's wiki, which this plan may make. Valinor's
`wiki/clients/visionos-client.md` also carries a stale branch and status line;
that is a Valinor edit and this migration does not make it.
