---
title: Developing on Hearth
status: draft
last_reviewed: 2026-08-15
related:
  - _index.md
  - first-run.md
  - backend/build-pipeline.md
  - backend/component-catalog.md
  - backend/native-runtime.md
sources:
  - README.md
  - wiki/backend/build-pipeline.md
  - wiki/backend/component-catalog.md
  - wiki/backend/native-runtime.md
  - wiki/first-run.md
  - wiki/_index.md
  - scripts/pack_backend.sh
  - scripts/build_omnivoice.sh
  - backend/scripts/build_env.sh
  - backend/manifest.yaml
  - desktop-client/src-tauri/tauri.conf.json
  - desktop-client/src/lib/config.ts
  - Cargo.toml
  - backend/supervisor/Cargo.toml
---

# Developing on Hearth

This is the front door for anyone who has cloned the repository and wants to
build, run, or change Hearth. It maps the tree, walks through the two build
loops you will use, and points at the rest of the wiki for how the product
works underneath.

## The repository map

| Directory | What it is |
| --- | --- |
| `backend/` | The Python harness and gateway: persona engine, tool loop, memory, the client-facing WebSocket. |
| `desktop-client/` | The Hearth app. Tauri v2 and React, the thing a user downloads and runs. |
| `crates/hearth-probe` | The hardware probe crate. Scans a machine and decides which model tier it can run. |
| `backend/supervisor` | The Rust supervisor. Owns model residency and spawns `llama-server`. Built separately from the workspace above it; see [Building the supervisor](#building-the-supervisor). |
| `vendor/omnivoice` | Patches against the pinned upstream voice engine, applied by `scripts/build_omnivoice.sh`. |
| `scripts/` | Build and packaging scripts: `pack_backend.sh` and `build_omnivoice.sh`. |
| `wiki/` | This documentation. |
| `apple-client/` | The iOS app. |

`crates/hearth-probe` and `desktop-client/src-tauri` share one Cargo
workspace at the repository root, so `cargo build` from the root builds both.
`backend/supervisor` keeps its own `Cargo.toml` and lockfile, because it
targets the product's backend rather than the host running the client; see
its own comment header for why.

## Prerequisites

You need Node.js and npm for the client, a Rust toolchain (`cargo`) for the
probe and the supervisor, and Python 3 if you are touching the backend
harness or building its environment with `backend/scripts/build_env.sh`. The
repository does not pin exact versions of any of these; whatever is current
and available on your platform is what the scripts assume.

## Three build loops

Which loop you need depends on what you changed and what you are testing
against. Client-only changes use the first. Anything under `backend/` or the
supervisor needs the ship loop before it can reach an installer, every time,
because the desktop app ships the backend as a bundled tarball rather than
reading it from disk. The third loop is for trying backend work against a
house that is already installed, without rebuilding anything.

### The client dev loop

For UI work, or any change confined to `desktop-client/`.

1. Change into the client directory.

   ```
   cd desktop-client
   ```

2. Install dependencies.

   ```
   npm install
   ```

3. Start the dev server.

   ```
   npm run tauri dev
   ```

The client looks for a Hearth backend at `127.0.0.1:18700` by default. If
nothing is listening there, it fails to connect, and that failure is
correct: a fresh checkout has no backend running yet. Settings, then
Connection, takes a different address if you have a backend up elsewhere.

`18700` is Hearth's own port, chosen so a development build never
accidentally finds an unrelated server on the machine's usual ports. See
`desktop-client/src/lib/config.ts` for the full block.

### The installed-house loop

For trying backend changes against a house that is already installed and has
real data in it. Nothing is rebuilt: the installed tree at
`<install root>/runtime/backend/harness/valar` is the Python the house
imports, so copying source over it and restarting is the whole loop.

1. Copy the package, adding and overwriting but never deleting.

   ```
   cp -r backend/harness/valar/. "<install root>/runtime/backend/harness/valar/"
   ```

2. Drop stale bytecode.

   ```
   find "<install root>/runtime/backend/harness/valar" -name __pycache__ -type d -prune -exec rm -rf {} +
   ```

3. Import-smoke it with the house's own Python, which is the interpreter that
   will actually load it and the only one with the dependencies.

   ```
   cd "<install root>/runtime/backend/harness"
   "<install root>/runtime/python/python.exe" -c "import valar.gateway.server"
   ```

4. Restart the house from **Settings > The house > Restart**. Python is read
   at import, so nothing you copied is live until the process restarts.

**Never copy over these.** They are the installed house's own state, and a
recursive copy that includes them silently replaces someone's setup with the
repository's defaults:

| Path | Why |
| --- | --- |
| `tools/file_grants.yaml` | Folder grants the operator approved on this machine. Not in the repository at all, so it survives a copy that does not delete. |
| `tools/file_roots.yaml` | The curated roots for this install. The repository ships defaults, which is not the same list. |
| `backend/personas/` | Personas created or edited on this machine, and any persona set swapped in for testing. |
| `config/hearth.env` | Ports, model paths, and `HEARTH_ENGRAM`, all resolved for this install at provisioning time. |

Import-smoke before the restart rather than after. A missing symbol makes
`app.py` crash-loop and the port never binds, and from the client that looks
identical to a slow model load until the boot gate gives up.

This loop is a testing shortcut and not a delivery mechanism. Anything proved
this way still has to go through the ship loop to reach an installer.

### The ship loop

For any change under `backend/`, the supervisor, or the voice engine. The
installer bundles the backend as a tarball inside the client, so a rebuilt
client with a stale tarball ships old backend code with no error.

1. Repack the backend tarball.

   ```
   bash scripts/pack_backend.sh
   ```

2. Build the client.

   ```
   npm run tauri build
   ```

Run them in that order, every time backend code changes. `pack_backend.sh`
stages `backend/harness`, `backend/memory`, `backend/personas`,
`backend/scripts`, `backend/config`, `backend/manifest.yaml`, and the
probe's model dictionary into `desktop-client/src-tauri/resources/`, where
`tauri.conf.json` lists `resources/backend.tar.gz` and
`resources/hearth-supervisor*` as bundled resources. `npm run tauri build`
picks up whatever is in that folder at the time it runs, stale or not.

#### Building the supervisor

`pack_backend.sh` does not build the supervisor binary; it only packs
whatever is already at `backend/supervisor/target/release/`. Build it first.

```
cd backend/supervisor
cargo build --release
```

The pack script refuses to run against a stale binary: it compares the
binary's timestamp against every `.rs` file under `backend/supervisor/src`
and fails loudly if a source file is newer. This gate exists because of a
real incident: a supervisor built before a source change shipped in an
installer that did not know about a newer environment variable, and every
install that planned a non-default model tier died at boot. If you see the
staleness error, rebuild the supervisor and repack.

#### The voice engine

`scripts/build_omnivoice.sh` builds the voice engine from a pinned upstream
commit plus the patches in `vendor/omnivoice/patches`, and writes its two
binaries into the same `resources/` folder the backend tarball lands in. It
is a separate build step from `pack_backend.sh`, and the pack script only
warns, rather than fails, if the voice binary is missing: a bundle built
without it installs and runs text-only.

```
bash scripts/build_omnivoice.sh
```

### The standing discipline

A stale bundle is the classic mistake on this project: edit the backend,
forget to repack, ship a client that still runs the old code. The freshness
check in `pack_backend.sh` catches the supervisor half of that mistake.
Nothing catches the harness half, so the habit to keep is mechanical: touch
anything under `backend/`, run `pack_backend.sh` before your next
`tauri build`, no exceptions.

## Writing documentation

The wiki follows a fixed set of conventions, listed in full in
[`_index.md`](_index.md):

- Markdown only, relative links only.
- Frontmatter carries `title`, `status`, `last_reviewed`, `related`, and
  `sources`.
- One H1 per article, matching the frontmatter `title`.
- Sentence case headings.
- No emojis.
- Canonical articles never link to `wiki/raw/`. If an article is compiled
  from staged sources, name them in `sources` instead.

## Where to start reading

Start at [`_index.md`](_index.md); it links every article by the question it
answers. If you are building the install experience or the first-time setup
flow, read [`first-run.md`](first-run.md) next. If you are touching the
backend or the packaging pipeline, [`backend/component-catalog.md`](backend/component-catalog.md)
and [`backend/build-pipeline.md`](backend/build-pipeline.md) cover what the
backend is made of and how the two platform artifacts get built.
