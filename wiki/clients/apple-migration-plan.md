---
title: Apple Migration Plan
status: draft
last_reviewed: 2026-08-07
related:
  - _index.md
  - first-run.md
  - backend/component-catalog.md
  - backend/native-runtime.md
sources:
  - D:/Tools/Valinor/tasks/m14-migration-plan.md
  - D:/Tools/Valinor/tasks/hearth-prealpha-handoff.md
  - D:/Tools/Valinor/tasks/lessons.md
  - D:/Tools/Valinor/wiki/clients/apple-client.md
  - D:/Tools/Valinor/wiki/clients/visionos-client.md
  - D:/Tools/Valinor/Apple Client/Valinor/Valinor.xcodeproj/project.pbxproj
  - D:/Tools/Hearth/backend/manifest.yaml
---

# Apple Migration Plan

How Valinor's Apple clients become a clean Xcode project in this repository.
This is the process document: the order, the per-file scrub, what keeps Valinor
buildable while it happens, and the checks that say it is finished. The
inventory and the target architecture are covered by their own articles; this
one assumes both and does not restate them.

The method is M14's, the backend migration that already executed successfully.
Three things carry over unchanged: write the manifest before copying anything,
never modify the source repository during the window, and define done as
commands someone runs rather than an impression someone forms.

Three things do not carry over, and they are what makes this document
necessary.

**The destination cannot be created from Windows.** M14's destination was a
directory tree. This one is an Xcode project, and `.xcodeproj` creation, target
setup, capabilities, signing and every build live on the Mac. The plan is
therefore split by machine, not only by phase.

**The source is under active development.** M14's shipping set was ten files
that had not moved in weeks. `Apple Client/` took 52 commits in the 60 days to
2026-08-03, the most recent four days before this was written. A freeze that
would have been free in M14 is expensive here, so the drift mechanism has to be
better than "report and hand-port".

**The scrub is mechanical where M14's de-literaling was judgment.** M14 said
never re-sync, because an automatic copy would clobber edits that took thought.
Here the edits are a name swap, a port number and an identifier: a script can
make them, deterministically, as many times as needed. That difference is worth
paying for deliberately, and section C is built on it.

---

# A. Sequencing

## A0. Where it lands

`apple-client/`, a sibling of `desktop-client/`, matching the convention the
repository already set.

```
Hearth/
  apple-client/
    manifest.yaml                 the machine-readable boundary
    Hearth.xcodeproj/             created on the Mac, phase 2
    Hearth/                       synchronized root group, the app target
      HearthApp.swift
      ServerConfig.swift
      Models/  Shared/  ViewModels/  Views/  Visualization/  VisionOS/
      Resources/personas/sulivan.json
      Info.plist
      Hearth.entitlements
    HearthWidgets/                synchronized root group, the widget target
      Info.plist
    HearthWidgetsExtension.entitlements
    Info-visionOS.plist
    docs/mac-runbook.md
  tools/apple-scrub.py            new, the deterministic rewrite
  tools/sync-report.py            existing, gains --manifest
```

The folder name is `Hearth`, not `Valinor`, at every level including the two
synchronized root group paths. Renaming later means touching the project file,
the entitlements, the app group and the widget membership list at once, which
is a second migration for no gain.

## A1. Why the folder structure is the whole migration

The current project is `objectVersion = 77` and uses
`PBXFileSystemSynchronizedRootGroup` for both targets. Files on disk inside a
synchronized folder are target members automatically. Only five Swift filenames
appear anywhere in the 2,400-line project file, and all five are there because
the widget extension needs them from the app's folder:

```
Exceptions for "Valinor" folder in "ValinorWidgetsExtension" target
  membershipExceptions = (
      Models/ValinorState.swift,
      Shared/HearthPalette.swift,
      Shared/PersonaOrb.swift,
      Shared/PersonaPalette.swift,
      Shared/SharedSnapshot.swift,
  );
```

This is the fact the plan is built on. If the new project uses synchronized
folders too, then landing an area is a file copy and a commit, with no project
file edit and no per-file checkbox. The Mac's job per area collapses to pull,
build, report. Seventy three files move without anyone opening the file
inspector once.

It also means the old target-membership lesson (`.metal` files need adding to
Compile Sources by hand) applies to the old format and not to this one.
`Caustics.metal` compiles today because it sits inside the synchronized folder.
The lesson keeps its force in exactly one place, section B4.

**Verify this before phase 3 starts.** Create the project, drop one file in on
disk, build, and confirm it compiled without touching Xcode's UI. If the
template produced classic groups instead, the whole area-by-area rhythm needs
rethinking and it is better to know at file one than at file forty.

## A2. The phases

**Phase 0. Tag both repositories.** Valinor has `rc-pre-hearth-move` and gains
`rc-pre-apple-move` at the freeze commit. Hearth has `pre-backend` and gains
`pre-apple` at current HEAD. Two rollback points per repository, no ambiguity
about what "before" means.

**Phase 1. Write `apple-client/manifest.yaml`.** Windows. Section A of the
inventory article in machine-readable form: every source path, its destination,
its area number and its disposition. It is what the scrub script iterates, what
`sync-report.py` watches, and what tells a reviewer whether the right files
moved. Nothing is copied until it exists. Same rule as M14, same reason.

**Phase 2. Create the project scaffold on the Mac.** One app target, one widget
extension target, both synchronized folders, both folders empty apart from an
app entry point that shows a label. It builds for iOS and it builds for
visionOS. Commit it on its own, so the diff that adds 20,000 lines of project
file is reviewable as "this is a fresh Xcode project" and never mixed with
source.

**Phase 3. Land the areas, one commit each.** Windows scrubs and stages; the
Mac pulls, builds and reports. Six areas, in the order below, each one a green
build before the next begins.

**Phase 4. The Mac-only settings.** Capabilities, signing, the widget
membership list, the visionOS destination. These are not source and cannot be
scripted; section E owns them.

**Phase 5. Prove first run.** With nothing listening, on a network that cannot
reach Valinor. Section F, and it is the check that matters most.

**Phase 6. Retire nothing.** Valinor's Apple project stays where it is and
stays buildable. Deciding whether it is still the development surface is a
separate decision on a separate day, exactly as M14 step 7 was.

## A3. The six areas, and why in this order

The ordering constraint is not taste, it is the Swift compiler. A module
compiles whole, so an area that references a type from a later area does not
build. Every area below depends only on areas before it, which is what makes
"build after every area" a real gate rather than a slogan.

### Area 1. Foundation, and first run

`ServerConfig.swift`, `Models/`, `Shared/`, the app entry point, a root view
that draws the orb, and the bundled `Resources/personas/sulivan.json`.

First because it has no dependencies, and first because it is the only area
whose result a person can judge by looking. At the end of area 1 the app
launches with nothing listening on any port and draws Sulivan from a persona
file inside the bundle. That is the first-run rule, satisfied at the earliest
possible moment rather than discovered missing at the end.

Note what this area is not: a copy. **The Apple client has no bundled persona
config today.** It asks the server with `get_persona_config` and falls back to
`HearthPalette` when there is no answer, so a phone with nothing to talk to
shows a palette-default orb rather than Sulivan. The desktop client solved this
with `desktop-client/src/personas/sulivan.json` shipping inside the bundle.
Doing the same here is net new work, and it looks like a port, which is why it
belongs in the first area where it cannot be quietly deferred.

### Area 2. Transport and voice

`ValinorWebSocketClient.swift` (renamed), `AudioInputManager`,
`SpeechRecognitionManager`, `TTSStreamPlayer`, `TTSAudioPlayer`.

The shared protocol layer, second because everything above it needs the wire
types and nothing in it needs a view. The two clients' agreement lives here, so
it lands before anything that could disagree.

### Area 3. The turn and the cards

`ViewModels/ChatViewModel.swift` and `Views/Dynamic/` entire: `CardStore`,
`UiComponentDescriptor`, `DynamicComponent`, `EaselStore`, the card renderers,
`RemoteImage`, `ImageActions`, `ImageViewer`.

These land together because `ChatViewModel` owns `CardStore` as a nested
observable and the card views read the view model back. Splitting them produces
an area that cannot compile, and an area that cannot compile is an area whose
gate does not run.

This is the largest single landing and the one to watch. `ChatViewModel` is
past 1,200 lines and is the hub every later area attaches to.

### Area 4. The iOS shell and the house surfaces

`Views/`: the main view, `HouseShelf`, `HouseStatusBar`, `BottomInputBar`,
`TimelineFeed`, `MessageBubble`, `PersonaCanvasView`, then `Views/Settings/`,
`Views/Apps/`, `Views/Persona/`, `Views/Journal/`.

At the end of this area the iOS app is complete against a running backend. It
is the natural place to stop and hold a real conversation before adding
surfaces that only some devices have.

### Area 5. Widgets

`HearthWidgets/` and the second target's membership list.

Fifth because the widget extension's dependency runs the other way: it needs
five files out of the app's folder, and those five have to exist and have their
final names before the exception list can name them. Renaming a file after this
list is written removes it from the widget target silently at the file level
and loudly at the compiler, which is the good kind of failure but a wasted
round trip.

### Area 6. Visualization and visionOS

`Visualization/` (`RealityKitSceneManager`, `PersonaModelView`,
`VisualizationView`, `DeviceMotionTracker`, `CausticsTexture`,
`Caustics.metal`), then `VisionOS/` (`SulivanVolumeView`,
`CausticsImmersiveView`, `CardOrbitLayout`, `LiveTranscriptCardView`,
`SessionGalleryView`), then `Info-visionOS.plist` and the visionOS destination.

Last, for three reasons. It is the only area needing a second device to verify.
It carries the `.metal` file, the one place the target-membership lesson still
bites. And its verification has a hardware prerequisite the others do not:
section E3.

### Not an area: the deferred set

`OnDevice/` (`InferenceRouter`, `LocalModelManager`, `OnDeviceInferenceEngine`,
`PersonaStore`), `Compat/WearablesShim.swift` and the MWDAT integration, and
the classic `ChatView` / `VisualizationChatView` pair.

Each of these needs a disposition in the manifest before phase 3, because
"decide later" during an area landing turns into "copied because it was
adjacent". The inventory article owns the decisions. What the process requires
is only that they are written down as `excluded` with one line of why, in the
shape `backend/manifest.yaml` already uses, before the first area lands.

Two of them carry a specific hazard worth naming here rather than there.
`LocalModelManager` builds its download URL as
`http://\(serverIP):8766/...`, and `PersonaStore` used to do the same. Port
8766 is the Rust brain's asset surface, internal only, and has answered nothing
in the live path for months. It is dead code that greps as live configuration.
If it crosses, it crosses with the port already gone.

---

# B. The scrub, per file

The scrub is `tools/apple-scrub.py`: it reads the manifest, copies each source
file to its destination, and applies the rewrites below. It is deterministic
and re-runnable, which section C depends on. It has a `--check` mode that
reports what it would change without writing, so drift can be inspected.

## B1. Naming

| From | To | Where |
| --- | --- | --- |
| `Valinor` in a type name | `Hearth` | `ValinorApp`, `ValinorMainView`, `ValinorState`, `ValinorWebSocketClient`, `ValinorSnapshot`, `ValinorWidgetProvider`, `ValinorWidgetsBundle` |
| `Valinor` in a filename | `Hearth` | the same set, plus the two folder names |
| `Valinor` in user-facing copy | `Hearth` | seven usage strings in `Info.plist`, every one of which names the product to the person granting the permission |
| `Valinor` in a comment | `Hearth`, or delete the sentence | 73 files, roughly 110 occurrences |

Rename the type and the file in the same pass. Swift does not require them to
match, which is exactly why a half-done rename survives review.

The palette, the icons and the shared snapshot are already named `Hearth`. That
is not an oversight to fix; it is the brand rename that already happened on the
iOS side, and it is why the scrub's rename list is shorter than the file count
suggests.

## B2. Ports and hosts

Hearth's port block is 18700, by design and not only for testing. The desktop
client already defaults there, with the reason written down: the development
machine runs Valinor on 8700 and a Hearth build that defaults to 8700 finds it.

| Literal | Becomes |
| --- | --- |
| `defaultPort = 8700` | `18700` |
| `defaultHost = "10.1.95.5"` | see below, and it is not another address |
| `:8766` in `LocalModelManager` | deleted with the file, or deleted with the feature |
| `8700` in a comment | `18700` |

**The default host is the sharpest item in this migration.** `10.1.95.5` is one
machine on one home network. Shipped, it means a stranger's phone dials a
private address, waits out the timeout, and presents the result as a server
that is not running. On this network it means something worse: it connects, to
Valinor, and the new client comes up wearing someone else's memory, journal and
personas. That is the failure the pre-alpha handoff already recorded once, and
it is the reason the desktop client points at `127.0.0.1`.

`127.0.0.1` is not available here. A phone is never the machine running the
backend, which is the whole reason this field exists on iOS and not on desktop.

The recommendation is **no default host at all**: an unset host is a distinct
state, and the app in that state does not dial. It renders the bundled Sulivan
and shows the connection field. That makes the first run of a phone that has
never been configured correct by construction rather than correct by the
timeout expiring. Bonjour discovery of the backend is the obvious later
refinement and it does not need to exist for this migration to close.

Whatever is chosen, the grep gate in section F is the same: no RFC 1918
literal survives anywhere in `apple-client/`.

## B3. Identifiers

Every one of these is a string that must agree with itself in two or three
places, and every disagreement is silent.

| Identifier | Current | New |
| --- | --- | --- |
| Bundle id, app | `com.joshuajones.Valinor` | `com.hearth.release.ios` |
| Bundle id, widgets | `com.joshuajones.Valinor.ValinorWidgets` | `com.hearth.release.ios.widgets` |
| App group | `group.com.joshuajones.Valinor` | `group.com.hearth.release.ios` |
| URL scheme | `valinor` | `hearth` |
| `DEVELOPMENT_TEAM` | `AS9PH6XDN4` | unset in the project; see E2 |

The app group string appears in **three** files: `Hearth.entitlements`,
`HearthWidgetsExtension.entitlements`, and `SharedSnapshot.swift` as
`static let appGroupID`. A mismatch between any two of them compiles, signs,
installs and runs. The widget simply reads an empty container and draws its
fallback orb with no connection state, which is indistinguishable from a widget
that is working and waiting. Scrub all three from one constant in the manifest,
never by hand.

The URL scheme appears in **three** places too, and one of them is not obvious:
`CFBundleURLSchemes` in `Info.plist`, the `widgetURL(URL(string: "valinor://talk"))`
calls in both widgets, and `MWDAT.AppLinkURLScheme` in the same `Info.plist`,
which is the OAuth callback the Ray-Ban SDK returns to. Miss the third and
pairing opens a sheet that closes with no error and no device.

The bundle identifiers are also a live constraint rather than a preference.
`com.hearth.app` belongs to Valinor's own desktop client and
`com.hearth.release.app` to this repository's. Two builds sharing an identifier
share a data container, which is the desktop lesson about webview profiles in
its iOS form.

## B4. Xcode traps

**The `.metal` file.** `Caustics.metal` compiles today because it lives inside
a synchronized folder. It will compile in the new project for the same reason,
**provided** it lands inside `apple-client/Hearth/Visualization/` and not
beside the project file. If the scaffold turns out to use classic groups (A1),
this is the file that needs Compile Sources by hand, and a missing Metal
function fails at runtime with a shader that does not load rather than at build
time. Check `Caustics` appears in the built product's `default.metallib`.

**`INFOPLIST_FILE` is per-SDK.** The visionOS build reads
`Info-visionOS.plist`, the iOS build reads `Hearth/Info.plist`. A key added to
one never reaches the other. `NSWorldSensingUsageDescription` is the one that
matters: ARKit hard-crashes on the authorization request when it is absent, and
it is absent from the iOS plist's counterpart by design. Carry both plists and
diff them deliberately.

**`Info.plist` is a membership exception.** Both synchronized folders list
their `Info.plist` in `membershipExceptions`, because it is consumed through
`INFOPLIST_FILE` and must not also be copied as a resource. A new project that
omits that exception ships a duplicate and Xcode warns about it in a way that
is easy to scroll past.

**`platformFilter = ios` on the SPM products.** MWDAT is iOS only. Its three
package products carry a platform filter in the current project, which is what
lets the visionOS build link at all. Recreating the package dependencies
without the filter produces a visionOS build that fails to link against an
iOS-only framework, and the error names the framework rather than the filter.

**Broad ignore patterns eat sibling-stack source.** The 2026-07-31 lesson, in
its Apple form. This repository's `.gitignore` was written for Rust, Python and
a Node client. `Models/` is a Swift directory here and a weights directory in
Valinor, and `build/` and `target/` mean different things again. Run
`git ls-files apple-client` after phase 3 and count against the manifest.
Builds pass locally while every clone is broken is the exact failure mode, and
it went undetected for a week last time.

**Asset catalogs.** Two `Assets.xcassets`, one per target, each with an
`AppIcon.appiconset` still holding stock artwork. They cross as directories,
their `Contents.json` files reference nothing named Valinor, and the icons
themselves are a known open item rather than a migration one.

## B5. What the scrub must not do

- Do not rewrite `HearthPalette`, `HearthIcons`, `PersonaOrb` or
  `PersonaPalette` beyond their imports. They are already correct and a
  find-and-replace pass over the word `Hearth` would corrupt them.
- Do not renumber the persisted preference keys silently. `valinor_server_ip`,
  `valinor_server_port`, `valinor_inference_mode`, `valinor_last_persona` and
  `hearth.transcriptShown` are `UserDefaults` keys. Renaming them is correct
  for a product that has never shipped, and it strands any setting on a device
  that has the old build. State that in the manifest as a decision rather than
  letting the scrub make it by accident.
- Do not touch `Package.resolved`. The pinned revisions are the ones that
  build. Let Xcode re-resolve only if the Mac finds a package that cannot be
  fetched.

---

# C. Keeping Valinor alive

The governing rule is M14's, unchanged: **Valinor is never modified during the
migration window.** Not `Apple Client/`, not the project file, not the
branches. Every edit happens to the copy. Valinor's Apple project stays
buildable throughout, which is what gives every "did I break it" question a
working control.

## C1. The shipping set

Everything under `Apple Client/` that the manifest marks as crossing: 73 Swift
files, four plist and entitlement files, one `.metal`, and `Package.resolved`.
The project file itself does not cross, so it is not in the set.

## C2. Freeze, and why it costs more here

M14's freeze was free because its ten files had been stable for weeks. This one
is not. `Apple Client/` took 52 commits in 60 days, the last on 2026-08-03,
and the iOS surface is where the recent product work has been landing. A freeze
long enough to build an Xcode project by hand is a real pause on a real
workstream.

Two adjustments make it affordable.

**Do all the Windows work before the freeze begins.** The manifest, the scrub
script, the staged tree and the grep gates need no coordination and can be
written against a moving source, because re-running the scrub is cheap. The
freeze starts when phase 2 does.

**Freeze only what the Mac has touched.** After an area lands and the Mac
build-verifies it, the Swift sources in that area are still script-derived and
still re-derivable. What is not re-derivable is the project file, the two
entitlements files, the capability configuration and the widget membership
list. Those are hand-made on the Mac and a re-scrub must never write over them,
which is why they are `generated` in the manifest and not `edits`.

That is the substantive divergence from M14. M14 forbade automatic re-sync
because its edits encoded thought. Here the Swift-source edits encode a
substitution table, so re-sync is safe for them and forbidden only for the
project-file layer. The manifest's `disposition` column is what encodes the
boundary, and it is the reason the column exists.

## C3. The drift report

`tools/sync-report.py` already does this for the backend: it reads a manifest,
runs `git log <since>..HEAD -- <source paths>` against Valinor, and prints what
moved. It hard-codes `backend/manifest.yaml`. Teach it `--manifest` and it
serves both migrations; that is the one-line change, and it happens in phase 1
so the report has a baseline from the beginning.

Run it at three moments: at the freeze, so the baseline commit is recorded;
before each area lands, so an area never imports a file that changed since the
scrub ran; and before declaring done.

The response to a non-empty report is not the same as M14's. There, it was
hand-port. Here it is **re-run the scrub for the named files and re-stage
them**, provided no Mac-side hand edit covers the same file. That is faster and
less error-prone, and it is only available because the scrub is a script. If a
report is non-empty twice for the same file, that file is under active
development and the window is too long, which is a scheduling answer rather
than a tooling one.

## C4. What must not be done

- **Never run `git checkout`, `switch`, `restore` or `stash` in
  `D:\tools\valinor`.** It is the live working tree of the daily driver. Read
  the branches with `git log`, `git diff` and `git show`; never move the head.
- **Do not open Valinor's `Valinor.xcodeproj` in the same Xcode session that
  has Hearth's open**, and do not let a Mac session "helpfully" migrate its
  project format. An `objectVersion` bump is a diff nobody reads and a change
  the daily driver's project did not ask for.
- **Do not rename or move anything inside `Apple Client/`.** The move happens
  in Hearth.
- **Do not merge any Valinor branch as part of this migration.** Section D.
- **Do not install both apps on one device expecting them to be independent
  until the identifiers are confirmed distinct.** Bundle id, widget bundle id
  and app group, all three.
- **Do not point the new build at the running Valinor server to "check it
  works".** That is precisely the check that cannot distinguish success from
  the worst failure. Section F.

---

# D. Branches

## D1. What the wiki says, and what git says

`wiki/clients/visionos-client.md` (last reviewed 2026-06-14) describes the
visionOS surface as being built on `visionos-gen-ui` and the caustics work as
pushed unverified to `generative-ui` awaiting a Mac. That was true when it was
written and it is not true now.

Checked against the repository on 2026-08-07, comparing every candidate branch
to `hearth-journal` over the `Apple Client/` path:

```
generative-ui      0 commits ahead
valinor-vision     0 commits ahead
visionos-gen-ui    0 commits ahead
ios-generative-ui  0 commits ahead
echo-backlog-batch 0 commits ahead
mentat-v2          0 commits ahead
main               0 commits ahead
```

Every one of them is behind. **All Apple client work is already consolidated on
`hearth-journal`**, which is the branch the working tree is on. There is no
unmerged Apple work to consolidate, and no branch needs to be merged in Valinor
for this migration to proceed. That was the brief's constraint and it turns out
to also be the fact.

## D2. The table, with verification status

Merged is not the same as verified, and for an Apple client the difference is
the whole question, because verification needs hardware. Status below is from
the git history and the task handoff documents, not from the wiki's frontmatter.

| Feature | Wiki says | Git says | Verified? | Return route |
| --- | --- | --- | --- | --- |
| iOS Hearth shell, house surfaces, cards | shipping | on `hearth-journal`, 52 commits to 2026-08-03 | Yes, on device | Areas 1 to 4 |
| Widgets, App Group snapshot | shipping | on `hearth-journal` | Yes | Area 5 |
| visionOS volumetric orb, orbiting cards | built on `visionos-gen-ui` | merged, `visionos-gen-ui` is behind | Yes, on device 2026-06-12 | Area 6 |
| Immersive caustics, bloom, orb transplant | pushed unverified to `generative-ui` | merged; later commits include `device-build fixes` and a projection-rig fix | Yes, by inference from the commit sequence. Re-confirm on the Mac. | Area 6 |
| Selene RealityKit character path | shipping | on `hearth-journal`, three fix commits 2026-08-03 | Yes | Area 6, needs the USDZ assets |
| MWDAT Ray-Ban audio | shipping, camera wired but silent | on `hearth-journal` | Audio yes, camera never forwarded | Deferred set, decide in the manifest |
| On-device MLX inference | dormant, points at dead `:8766` | on `hearth-journal` | No, and never was | Deferred set. If it returns, it returns without the port. |
| Classic `ChatView` | exists behind a dead `@AppStorage` flag | on `hearth-journal` | Not reachable from the UI | Deferred set, and the honest disposition is excluded |

The two rows to act on are the last three. Everything above them lands as a
scrubbed copy in its area. Everything in the deferred set needs a written
disposition before phase 3, and "it compiles so it came along" is not one.

## D3. The correction that is owed

`wiki/clients/visionos-client.md` in Valinor carries a stale branch and status
line. Fixing it is a Valinor edit, which this migration does not make. Note it
for whoever next touches that article; the return route for the finding is a
`last_reviewed` bump, not a change to any code.

---

# E. Windows and Mac

## E1. The split

| Preparable from Windows | Mac only |
| --- | --- |
| `apple-client/manifest.yaml` | `Hearth.xcodeproj` creation |
| `tools/apple-scrub.py` and its `--check` report | App and widget extension target setup |
| The scrubbed source tree, staged per area | Synchronized root groups and the membership exception list |
| `sync-report.py --manifest`, and every drift run | Capabilities: App Groups, increased memory limit |
| The bundled `sulivan.json`, derived from `backend/personas/Sulivan/` | Signing, provisioning, `DEVELOPMENT_TEAM` |
| Every grep gate in section F | SPM resolution, including the iOS platform filter on MWDAT |
| The identifier constants, in one place | The visionOS destination and deployment target |
| This article and the Mac runbook | Every `xcodebuild`, every simulator run, every device run |
| The `.gitignore` audit and `git ls-files` count | The first-run verification, which needs a real device on a real network |

Roughly: Windows produces text that is reviewable, the Mac produces a binary
that is not. That asymmetry is the argument for keeping the scrub a script.

## E2. The project file is the one thing nobody can review

Twenty thousand lines of `pbxproj` land in phase 2 as a single commit and no
human reads it. Two ways to handle that.

**Generate it.** XcodeGen or Tuist produces `.xcodeproj` from a YAML spec, which
would make the project creatable from Windows and reviewable as text, and would
let the whole migration run without a Mac until the first build.

**Create it once in Xcode.** The recommendation, for a specific reason: with
synchronized folders, the project file is nearly static after phase 2. Only
five filenames appear in the current one, and all five are the widget's
membership list. A generator would be a permanent dependency bought to make one
commit reviewable, and it would have to support `objectVersion = 77`
synchronized groups, which is recent enough that lag is likely.

Create it by hand, commit it alone, and put the five settings that matter into
the runbook so the next person can verify them by reading rather than by
diffing: bundle identifiers, app group, `SUPPORTED_PLATFORMS`, `INFOPLIST_FILE`
per SDK, and `CODE_SIGN_ENTITLEMENTS`.

`DEVELOPMENT_TEAM` is the migration's version of M14's username class. Today it
is `AS9PH6XDN4` in the project file, which is one person's team and makes a
clone unbuildable by anyone else with a provisioning error that does not
explain itself. Leave it unset in the committed project, put it in a
gitignored `Local.xcconfig`, and say so in the runbook.

## E3. The Mac's own hazards

Two are already recorded and both cost a session each.

**The SDK must match the device OS.** A visionOS 26.5 SDK binary on a
visionOS 27.0 Vision Pro crashes at launch before `main()`, and it crashed a
fully stripped plain-`Text` app too, so it looks like the app and it is not.
Confirm the Xcode SDK against the headset before concluding anything about area
6.

**Launch without the debugger when a device launch hangs.** The same
investigation ended at dyld wedging while notifying LLDB, with Main Thread
Checker injected. The app launched in about a second with the debugger
detached. A device hang at launch is a debugger question first.

## E4. The rhythm of phase 3

Per area, exactly this:

1. Windows: run `apple-scrub.py --area N`, review the diff, commit, push.
2. Windows: run `sync-report.py --manifest apple-client/manifest.yaml`, confirm
   nothing in this area moved in Valinor since the scrub.
3. Mac: pull, open Xcode, build for iOS simulator.
4. Mac: report the result in one line. Green, or the first error verbatim.
5. Only then, area N+1.

The Mac never edits source in this loop. If area N does not build, the fix goes
into the scrub script on Windows and the area is re-staged. That keeps the
scrub authoritative and keeps the two trees from diverging in a way no report
can see.

---

# F. Definition of done

Each item is something someone runs. Nothing here is satisfied by reading a
diff.

## F1. The move

1. `git grep -i valinor -- apple-client/` returns nothing.
2. `git grep -i joshuajones -- apple-client/` returns nothing.
3. `git grep -E "\b10\.[0-9]+\.[0-9]+\.[0-9]+\b|\b192\.168\." -- apple-client/`
   returns nothing.
4. `git grep -E ":(8700|8765|8766|8080|8702)\b" -- apple-client/` returns
   nothing. Only 18700 appears.
5. `git grep AS9PH6XDN4 -- apple-client/` returns nothing.
6. `git grep -E "D:/Tools|D:\\\\Tools|/mnt/d|Users/josh" -- apple-client/`
   returns nothing.
7. `git grep "valinor://" -- apple-client/` returns nothing.
8. `git ls-files apple-client | wc -l` matches the manifest's file count.
   This is the `.gitignore` check and it is the one that catches a silent
   ecosystem-pattern swallow.
9. `sync-report.py --manifest apple-client/manifest.yaml` reports no drift.

## F2. It builds

10. From a **fresh clone** on a Mac that has never built this project:
    `xcodebuild -scheme Hearth -destination 'generic/platform=iOS' build`
    succeeds with `DEVELOPMENT_TEAM` supplied only by a local xcconfig.
11. The same for `generic/platform=visionOS`.
12. The widget extension builds as part of both, and
    `PersonaOrb`, `PersonaPalette`, `HearthPalette`, `SharedSnapshot` and the
    state enum resolve inside it. This is the membership-list check and it is
    the only one on this list that fails loudly.
13. `Caustics` appears in the built product's `default.metallib`.

## F3. First run

14. **The app launches with nothing listening on any port and draws Sulivan
    from `Resources/personas/sulivan.json`.** No spinner that never ends, no
    palette-fallback orb, no error dialog.
15. It is run on a network that **cannot reach the Valinor machine**, or with
    Valinor's harness stopped. This is the single most important line here.
    Every other check on this list gives the same answer whether or not the
    default host survived the scrub; this one does not. On this network, with
    the literal intact, item 14 passes and the product is wearing someone
    else's house.
16. Pointed at a Hearth backend on 18700, it completes a spoken turn: connect,
    `client_transcription`, PCM out, a card on screen.
17. The widget renders live state from the App Group after a turn, which
    confirms all three copies of the group identifier agree.

## F4. Valinor is unharmed

18. `git status` in `D:\tools\valinor` is clean, on `hearth-journal`, with no
    change under `Apple Client/` beyond what was deliberately committed.
19. Valinor's `Valinor.xcodeproj` opens and builds for iOS on the Mac, with its
    `objectVersion` unchanged from `rc-pre-apple-move`.
20. Valinor's app and Hearth's app install side by side on one device without
    either replacing the other.

## F5. What breaks silently if an item is missed

Cross-checked against M14's section E3, which is where this table's shape comes
from. Eight of nine fail quietly, and that ratio is the argument for F being a
checklist rather than an impression.

| Missed | What you see |
| --- | --- |
| `defaultHost` still `10.1.95.5` | on this network, a flawless first run against Valinor, with someone else's memory, journal and personas. Off it, a timeout that reads as "the server is not running". |
| App group string disagrees across its three copies | the widget draws its fallback orb and never updates. Identical to a widget waiting for its first turn. |
| `MWDAT.AppLinkURLScheme` not updated with the scheme | Ray-Ban pairing opens a sheet, the sheet closes, no device, no error |
| Bundled `sulivan.json` absent or outside Resources | the orb draws from the palette fallback and looks deliberate |
| `LocalModelManager`'s `:8766` crosses | a GGUF download that hangs to timeout. Already dead in Valinor, so nothing regresses and nothing reports. |
| `NSWorldSensingUsageDescription` missing from `Info-visionOS.plist` | ARKit crashes on the authorization request, on a device, in immersive mode only |
| MWDAT SPM products without `platformFilter = ios` | the visionOS link fails naming a framework, not the filter |
| A `.gitignore` pattern eats a source directory | builds pass on the machine that wrote it; every clone is broken. Undetected for a week last time. |
| Bundle identifier collides with Valinor's client | the two apps share a container and each opens into the other's state |
| A committed `DEVELOPMENT_TEAM` | builds on one Mac. Loud everywhere else, and the only loud row here. |

---

## The first thing to do

Write `apple-client/manifest.yaml`, and give `tools/sync-report.py` its
`--manifest` flag in the same commit. The manifest is the boundary in
machine-readable form, it is what `apple-scrub.py` iterates and what the drift
report watches, and it is what forces the deferred set (`OnDevice/`, MWDAT, the
classic chat views) to get a written disposition before anything crosses
instead of after. It is preparable entirely from Windows, it costs an hour, and
nothing is copied until it exists.
