---
title: Build pipeline
status: draft
last_reviewed: 2026-09-03
related:
  - component-catalog.md
  - portability-ledger.md
  - packaging-options.md
  - ../_index.md
sources:
  - D:/Tools/Valinor/tasks/first-time-user.md
  - D:/Tools/Hearth/wiki/raw/research-shipping.md
  - D:/Tools/Hearth/wiki/raw/research-containers.md
  - D:/Tools/Hearth/wiki/raw/research-bundling.md
---

# Build pipeline
How Hearth becomes two downloadable artifacts, one per platform, and what each
of them contains. This is the build side. What the user experiences afterwards
is the first-time setup, drafted in `tasks/first-time-user.md` in the Valinor
repository.

## The shape: the client is the installer

The user downloads one thing, the desktop client, and everything else is
handled through it.

This is what the products that solved this problem do. ComfyUI Desktop ships a
small installer, then on first run classifies the hardware, pins an exact
dependency set for that classification, and provisions the environment. Ollama
ships a per-user installer that needs no administrator rights and discovers its
own accelerator backends at runtime. Neither asks the user to assemble anything.

Three things follow from adopting it here.

**The client/host question disappears.** The doc's step 1 asks whether this is a
client or a host machine. As a question on a wizard screen that is a confusing
thing to ask a stranger. As a consequence of a scan it is easy: the client
always installs, then it either provisions a backend on this machine or asks
for the address of one that already exists.

**The hardware scan gets a place to speak.** A scan buried in an install script
can only fail silently or print to a console nobody reads. A scan inside the
client can say what it found, what tier it chose, how big the download is, and
why, which is the "cool, downloading this" moment in the draft.

**The client is small and the backend is large.** The download the user starts
with is tens of megabytes. Everything expensive is fetched afterward, sized to
the machine that will run it.

## Build time against install time

The single most useful discipline in this pipeline is deciding, for every piece,
whether it is resolved when we build or when the user installs.

| Resolved at build time | Resolved at install time |
| --- | --- |
| Every apt package and its version | Which model tier fits this machine |
| The Python interpreter and every pinned wheel | Which model file to download |
| The compiled `llama-server` for each accelerator | Which accelerator backend to select |
| The Rust supervisor, as a release binary | The generated configuration, with this machine's paths and ports |
| Persona configs, prompts, voice clones | The paths, because they are now this user's paths |
| The process tree and its start order, compiled into the client | Whether the voice and the brain can coexist |

Anything on the left that leaks to the right becomes a support ticket. The
current stack gets this backwards in several places: it builds a CUDA wheel from
source on the target machine, it compiles the supervisor with `cargo run` on
every service start, and it resolves model paths from literals baked into
persona files.

## Windows: producing the installers

Hearth ships to Windows as a native installer. Decided 2026-08-06; see
[`native-runtime.md`](native-runtime.md) for the process model and install
layout, and [`packaging-options.md`](packaging-options.md) for how the decision
was made.

The build is two commands: `bash scripts/pack_backend.sh` stages the backend,
then `npm run tauri build` produces the bundle. Because
`desktop-client/src-tauri` is a member of the workspace, both artifacts land at
the workspace root rather than under the crate:

- `target/release/bundle/nsis/Hearth_0.1.0_x64-setup.exe`
- `target/release/bundle/msi/Hearth_0.1.0_x64_en-US.msi`

`tauri.conf.json` sets `bundle.targets` to `all`, so the NSIS installer and the
MSI are both produced and both ship.

`hearth-supervisor` is built, never downloaded. `cargo build --release` in
`backend/supervisor` produces it, `pack_backend.sh` stages it into the client's
resources, and it ships as a Tauri bundle resource rather than a sidecar.
Provisioning copies it to `<root>\runtime\hearth-supervisor.exe`.

**Not baked in:** model weights. They are gigabytes, they are tier-dependent,
and they are the one thing that genuinely must be chosen on the user's machine.

**The rejected alternative.** The Windows artifact was once going to be a
`.wsl` image: a gzipped tar of a provisioned Linux root filesystem, carrying an
apt set, a distro configuration, and systemd to run the supervisor. That
approach was rejected on 2026-08-06 in favor of the native runtime, and Hearth
does not ship a `.wsl`. [`packaging-options.md`](packaging-options.md) holds the
comparison that retired it.

### The install root

Added 2026-08-06, after the first live install test; the full statement is in
[`../first-run.md`](../first-run.md). The user chooses ONE folder during
setup, `D:\Hearth` by default, and everything above that is install-time
lands under it: the staged weights at `<root>\models`, the install record at
`<root>\hearth-install.json`, the generated configuration, and the runtime
itself at `<root>\runtime` with the voice environment at `<root>\envs`
(native, per [`native-runtime.md`](native-runtime.md)).

Two consequences the installer must honor:

- Uninstall is deleting the folder. Any step that writes product state
  elsewhere breaks that sentence and does not ship.
- The client revalidates the install record at boot and routes a missing or
  gutted install back into setup, so a half-deleted Hearth degrades into
  "install again", never into a house that dials a backend which is gone.

## macOS: producing `Hearth.app`

No CUDA. Simpler in structure and harder in signing.

1. **Fetch the upstream `llama-server` for macOS arm64 with Metal.** Same
   pinned release as Windows, different asset.
2. **Ship a relocatable Python.** A `python-build-standalone` interpreter tree
   with site-packages already resolved at build time. This is what `uv` installs
   when it manages a Python version, and it is the shape ComfyUI Desktop ships
   specifically to avoid resolving dependencies on the user's machine.
3. **Build the supervisor for arm64** and ship it as a Tauri bundle resource.
   `tauri.conf.json` declares no `externalBin`, so the supervisor is not a
   sidecar: the client spawns it as an ordinary child process, and supervision
   stays in the Rust process, which is where it already lives.
4. **Include the same persona tree** as Windows.
5. **Code sign and notarize.** Every binary, including the supervisor and
   anything inside the Python tree. This is the step with no equivalent on
   Windows and it is where Mac builds usually fail first.
6. **Package as a `.dmg`.**

**Note the supervision asymmetry**, because it is a real design decision rather
than an accident: the client starts and supervises the same process tree on
both platforms, and all that differs is how a child is contained and killed, a
kill-on-job-close Job Object and a suppressed console window on Windows against
a process group on macOS. The supervisor binary is the same and the thing it
supervises is the same. That is the smallest possible difference between the
two platforms and it is worth defending against attempts to unify it further.

## What the client does on first run

This is where the build side hands off to the setup flow.

1. **Scan the hardware.** GPU vendor and memory, unified memory on Apple
   Silicon, system RAM, free disk on the target volume, compute capability where
   applicable. One rule from the audit: use `nvidia-smi` for VRAM and never
   WMI, which reports 4 GB for a 16 GB card because of a 32-bit field overflow.
2. **Choose the tier and say so.** Report what was found, which tier it implies,
   how large the download is, and whether the voice and the brain will be able
   to coexist on this machine. On 8 GB they cannot, and the user should learn
   that here rather than as a pause mid-sentence.
3. **Provision the backend.** The same chains run in parallel on both
   platforms, and only the fetched assets differ:
   - Unpack the bundled `backend.tar.gz` into `<root>\runtime\backend`, then
     copy the supervisor and the voice binaries into place.
   - Fetch and unpack the `llama-server` build for the accelerator the scan
     chose.
   - Fetch and unpack a `python-build-standalone` interpreter tree.
   - Pip install the harness requirements into it.
   - Fetch the voice weights.
4. **Download the model** into `<HEARTH_DIR>/Models`.
5. **Generate the configuration** from the scan: the model path, the context
   size, the offload depth, the accelerator backend, the coexistence policy.
   Every one of these is a hard-coded constant today.
6. **Start the stack and verify.** Not "did the processes start" but "did a real
   completion come back, is the voice service ready, does the tool registry
   resolve to something non-empty". An installer that cannot tell you it failed
   is worse than no installer, because it turns a loud problem into a silent one.
7. **Hand off to Sulivan** for the persona conversation.

## What has to be fixed before any of this builds

Directly from the portability ledger, in the order the pipeline hits them.

| Fix | Why the pipeline needs it |
| --- | --- |
| Derive the repository root instead of hard-coding it | roughly 110 literals; nothing in the image can carry `/mnt/d/Tools/Valinor` |
| Remove the `jones` username assumption | four unit files, twelve persona manifests, six scripts |
| Model path as an identifier plus a resolver | persona files cannot carry absolute paths into a shipped product |
| Context size and offload from the scan | currently a unit-file constant that overrides every persona |
| CUDA architecture from the scan | currently `89`, correct only for this exact card |
| One Python environment | verify the NeuTTS removal collapses the two |
| Release binary, not `cargo run` | no Rust toolchain in a shipped artifact |
| Startup self-check | five failure modes currently degrade silently |

The first two are mechanical and wide. The rest are small and specific. None of
them is research.

## Open questions

1. **Does the Mac get the same voice engine on day one?** OmniVoice documents
   Apple Silicon support with torch on MPS, so in principle yes. It has never
   been run there. That is a spike, and it gates whether the Mac artifact is a
   full Hearth or a text-first one.
2. **Where do the shipped voice clones come from, and under what license?** They
   are the product's voices and this has not been answered.
3. **Who signs the macOS build?** Notarization needs an Apple Developer account
   and a signing identity, and nothing gets past Gatekeeper without it.
