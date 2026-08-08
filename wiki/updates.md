---
title: Updating an Install
status: draft
last_reviewed: 2026-08-07
related:
  - backend/build-pipeline.md
  - install-macos.md
  - _index.md
sources:
  - docs/macos-status.md
---

# Updating an Install

How an installed Hearth becomes a newer Hearth without being uninstalled
first. Nothing here is built yet; this is the design and the decision that
sits under it.

## An update is two halves, and they are very different sizes

**The app.** `Hearth.app` is 41 MB, and a `.dmg` of it is 29 MB. Inside it are
the client and the three things the installer lays down: `backend.tar.gz`
(21 MB), `hearth-supervisor` (8 MB), `tts-server` (3.8 MB). Every release
changes some of this.

**The install root.** `~/Hearth` is roughly 4.8 GB, of which **3.8 GB is model
weights** that a release almost never changes. The rest is unpacked from the
app bundle, so it is derived rather than downloaded.

The whole design follows from that asymmetry. An update should move about
30 MB, not 3.8 GB, and it should never touch `home/`, where the person's
memory and journal live.

## Half of it already works

`provision.rs` states its own contract: *"Idempotent by construction: fetches
skip files already at exact size, unpacks clear their target first. Retry is
rerun."*

Re-running provisioning against an existing install already does the right
thing:

- `untar_gz` clears and re-unpacks `runtime/backend` from the new tarball.
- The supervisor and voice engine are re-copied from the new bundle.
- `fetch_verified` skips the weights, the Python runtime and the inference
  engine, because they are present at the exact size and hash the dictionary
  names.
- `config_gen::render` regenerates `config/hearth.env` from the record.
- `home/` is never written.

So the backend half of an update is a function that already exists and is
already exercised on every install. It is simply not reachable from anywhere
in the interface.

The install record anticipated this. Its comment reads: *"this file is what a
support conversation, an upgrade, or the backend provisioner reads."*

## What is missing

**A version stamp.** Nothing records which app build provisioned an install
root. The `version: 2` in `hearth-install.json` is the record's own schema
version. Without a stamp, a newer app sitting on an older backend is
indistinguishable from a matched pair, and there is nothing to detect.

This is the small piece everything else hangs from, and it is one field.

**A way to replace the app.** Dragging a new `.dmg` over the old app works and
requires nothing to be built. It is also a step a person has to know to take.

**A trigger.** Something has to notice and offer.

## Layer one: the backend catches up

The version the app was built with is written into the install record at
provision time. On launch the client compares it with its own. If they differ,
Settings offers to update, and the button calls the provisioning that already
exists.

The person gets a new app by downloading a `.dmg` and dragging it over, which
is the same motion as installing. The backend catches up by itself the next
time they open it.

This needs no signing keys, no manifest, no hosting, and no release
infrastructure. It works with the artifacts already being produced.

**What it does not solve:** the person still has to learn that an update
exists and go and get it.

## Layer two: the app replaces itself

`tauri-plugin-updater` is the standard route and does the whole job: check a
JSON manifest, download, verify a signature, swap the bundle, restart. The
manifest can be a GitHub Release asset.

It needs a minisign keypair, `createUpdaterArtifacts` in the bundle config,
and a release step that publishes the manifest alongside the artifact. None of
that is exotic, but it is infrastructure that has to exist and keep existing.

With layer one already in place, layer two only replaces the manual `.dmg`
step. The backend still catches up the same way, because the update mechanism
does not need to know that a backend exists.

## The decision underneath: signing

Hearth is not signed. That is why [`install-macos.md`](install-macos.md) tells
people to right-click and choose Open on first launch, and it is why the
updater story has a rough edge: an updater replacing an unsigned bundle is a
known sore point on macOS.

Signing and notarizing would remove the first-launch instruction from the
install guide **and** make in-app updates behave. It costs an Apple Developer
account at 99 USD a year plus the build-time work already sketched in
[`backend/build-pipeline.md`](backend/build-pipeline.md), which notes that
every binary needs signing including the sidecar and everything inside the
Python tree, and that this is where Mac builds usually fail first.

This is worth deciding before layer two rather than after. If Hearth is going
to be signed, the updater is straightforward and the install guide gets
simpler. If it is not, layer one plus a downloaded `.dmg` is the honest
ceiling, and the guide keeps its right-click paragraph.

## Weights that outlive their plan

A release that changes the model tier or quantisation makes the update bigger
than 30 MB: the provisioner fetches whatever the new plan names.

That part works. What does not is cleanup. The previous GGUF stays where it
was, because nothing removes weights, and the dictionary has no notion of
which files a superseded plan left behind. Two model changes on an 8 GB Air
would quietly cost 6 GB of disk on a machine that had 13 GB free.

The install record already lists `landed`, the files a plan put down. Comparing
the old record's `landed` against the new plan before overwriting the record
gives an exact answer to "what is now orphaned", without guessing from
filenames. That comparison is the cleanup story, and it should be built at the
same time as the first update that can change a model.

## What I would do, in order

1. **Stamp the app version into the install record.** One field. Nothing else
   is possible without it, and it costs nothing to add now even if the rest
   waits.
2. **Layer one.** Detect the mismatch, expose the update in Settings beside
   Start and Stop, reuse the provisioning that exists.
3. **Decide on signing.** It changes whether layer two is pleasant or fiddly,
   and it changes the install guide either way.
4. **Layer two, if signed.** The updater plugin and a published manifest.
5. **Orphaned weights**, before the first release that changes a model, not
   after.

## What this closes elsewhere

[`backend/build-pipeline.md`](backend/build-pipeline.md) carries open questions
that this and the macOS run have overtaken:

- *"Does the client bundle the backend or fetch it?"* Decided by the shipped
  build: it bundles. `backend.tar.gz` and both binaries ride inside the app.
- *"How does a `.wsl` image update?"* Moot. WSL was ruled out on 2026-08-06.
- *"Does the Mac get the same voice engine on day one?"* Answered on
  2026-08-07, and not as expected: the torch build has no MPS path at all, so
  it runs on the CPU at about 7.6x realtime. The Mac ships omnivoice.cpp on
  Metal instead, which clears realtime. See `docs/macos-status.md`.
- *"Who signs the macOS build?"* Still open, and now blocking more than it was.
