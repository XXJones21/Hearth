---
title: Building a Hearth release
status: draft
last_reviewed: 2026-08-26
related:
  - _index.md
  - developing.md
  - install-macos.md
  - installing.md
  - backend/build-pipeline.md
  - backend/native-runtime.md
sources:
  - README.md
  - wiki/developing.md
  - tasks/clients/macos-package-handoff.md
  - scripts/pack_backend.sh
  - scripts/build_omnivoice.sh
  - desktop-client/src-tauri/tauri.conf.json
  - android-client/app/build.gradle.kts
  - releases/0.1.0-alpha/NOTES.md
---

# Building a Hearth release

Four artifacts, three of them shipping today. This is the procedure for all of
them, written after 0.1.0 alpha so the next release does not have to
rediscover it.

`developing.md` covers the ship loop for one platform on one machine. This
covers a RELEASE: every artifact, in order, with the parts that are per
platform made explicit.

## What a release is

| Platform | Artifact | Built on | Signed |
| --- | --- | --- | --- |
| Windows | `Hearth_<v>_x64-setup.exe` and `.msi` | Windows | no |
| macOS | `Hearth_<v>_aarch64.dmg` | a Mac | no, and not notarized |
| Android | `Hearth_<v>_android.apk` | any machine with the JDK | yes |
| iOS and visionOS | TestFlight build | a Mac with Xcode | via Apple |

Three of the four shipped in 0.1.0 alpha. iOS and visionOS did not, and remain
the outstanding half.

**Nothing but Android is signed today.** That is a deliberate alpha position,
not an oversight, and it is the first thing to change when the audience stops
being people who expect roughness. See the signing section below.

## The rule that governs everything else

The installer bundles the backend as a tarball INSIDE the client. A rebuilt
client with a stale tarball ships old backend code and reports no error at all.

So the order is always: **supervisor, then voice engine, then pack, then
build.** Every time backend code changes, on every platform.

`pack_backend.sh` guards half of this for you. It compares the supervisor
binary's timestamp against every `.rs` file under `backend/supervisor/src` and
fails loudly if a source file is newer. That gate exists because of a real
incident: a supervisor built before a source change shipped in an installer
that did not know about a newer environment variable, and every install that
planned a non-default model tier died at boot with the house already on screen.

Nothing guards the harness half. The habit has to be mechanical.

## The desktop artifacts, Windows and macOS

Both follow the same four steps. Run them from the repository root.

### 1. Build the supervisor, for THIS platform

```
cd backend/supervisor
cargo build --release
```

This is the step people skip when moving between build seats, and it is the
reason the macOS bundle cannot reuse the Windows one: `pack_backend.sh` stages
whatever binary is already at `backend/supervisor/target/release/`, and that
binary is per platform. Packing on the Mac after building here is what puts
the Mach-O supervisor in the bundle rather than a `.exe`.

### 2. Build the voice engine

First time on a machine, or whenever the pin or the patches changed:

```
bash scripts/build_omnivoice.sh
```

It builds from a pinned upstream commit plus the patches in
`vendor/omnivoice/patches` and writes its binaries into the same `resources/`
folder the tarball lands in. `pack_backend.sh` only WARNS when the voice binary
is missing rather than failing, so a bundle built without it installs and runs
text-only. Check the warning.

### 3. Pack the backend

```
ENGRAM_MCP_SRC=../engram-mcp bash scripts/pack_backend.sh
```

It stages `backend/harness`, `backend/memory`, `backend/personas`,
`backend/scripts`, `backend/config`, `backend/manifest.yaml`, the probe's model
dictionary, and the engram-mcp memory client into
`desktop-client/src-tauri/resources/`.

engram-mcp vendors from a sibling checkout, and the script hard errors without
one, deliberately: a bundle missing the memory client is a silent memory
regression. Clone it if the machine has none:

```
git clone https://github.com/XXJones21/engram-mcp.git ../engram-mcp
```

### 4. Build the client

```
cd desktop-client
npm install
npm run tauri build
```

**The artifact comes out at the WORKSPACE root**, not under
`desktop-client/src-tauri/target/`. The tauri crate is a member of the root
workspace, so cargo resolves one shared target directory and bundles there. The
build prints the real paths in its closing lines; trust those over any path
written down here.

## Android

```
cd android-client
./gradlew assembleRelease
```

Signing needs a `keystore.properties` beside the keystore, and **both stay out
of the repository**. Without that file a release build is simply unsigned
rather than failing, so confirm the signature rather than assuming it.

The APK is sideloaded. The phone is a companion to a house rather than a house:
it pairs with a running desktop install from Settings and reaches it over a
tailnet when away from home.

## iOS and visionOS

Not shipped in 0.1.0 and the procedure is not yet written down here, because it
has not been run end to end. Both go through TestFlight, both need the Apple
developer account that Developer ID signing also needs, and both build from
`apple-client/` on a Mac with Xcode.

Two hazards already recorded from device work, worth carrying into the first
release attempt:

- The SDK must match the headset or phone OS, or the app crashes before
  `main()` and reads as an app bug rather than a toolchain mismatch.
- A hang at launch is a debugger question before it is an app question.

## Signing, honestly

**Android is signed.** Release builds pick up the keystore when
`keystore.properties` is present.

**Windows and macOS are not.** There is no signing configuration in
`tauri.conf.json` for either: no `certificateThumbprint`, no
`signingIdentity`, no notarization step, no hardened runtime.

For macOS specifically this has a user-visible cost. Gatekeeper refuses a plain
double-click on first open. A tester gets past it with right-click, Open, Open
anyway, once, and it opens normally afterwards. **Say this in the note that
goes out with the link**, because a person who hits the refusal without warning
concludes the download is broken.

Proper Developer ID signing and notarization is a release task rather than an
alpha one, and it belongs with the TestFlight work since both need the same
Apple developer account. That work is tracked in
`tasks/release-signing.md`, including what each platform costs unsigned and
why the Apple account should be bought once rather than twice.

## Verify before shipping

On the platform you built for, not on the build machine's assumptions:

1. Install the artifact.
2. First run reaches the hardware scan and plans a model tier. The probe
   decides; an M-series Mac takes the small or medium tier.
3. Complete first run far enough that the house boots and a text turn round
   trips.
4. Sulivan renders as the flame. **If the panel shows the plain face, the
   frontend bundle is stale**: rebuild the client.

That last check is the cheapest stale-bundle detector there is, because it
fails visibly rather than silently.

## Publishing

Artifacts and a `SHA256SUMS.txt` go in `releases/<version>/` alongside a
`NOTES.md`, then to the GitHub release. Keep the notes honest about maturity;
0.1.0's closing line is the right register:

> Hearth is pre-alpha software. It is not ready for people who are not already
> expecting it to be rough.

## History

0.1.0 alpha, published 2026-08-22, shipped Windows, macOS and Android. Its
macOS half was built from a dedicated handoff document written for the Mac
seat. This article supersedes it, that task is complete, and the original is
kept at `wiki/raw/legacy/macos-package-handoff.md`.
