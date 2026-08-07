---
title: Build Pipeline
status: draft
last_reviewed: 2026-08-06
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

# Build Pipeline

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
| The Rust supervisor, as a release binary | The generated systemd drop-ins or plist |
| Persona configs, prompts, voice clones | The paths, because they are now this user's paths |
| The service units and their ordering | Whether the voice and the brain can coexist |

Anything on the left that leaks to the right becomes a support ticket. The
current stack gets this backwards in several places: it builds a CUDA wheel from
source on the target machine, it compiles the supervisor with `cargo run` on
every service start, and it resolves model paths from literals baked into
persona files.

## The manifest

Both builders read one file so the two artifacts cannot drift. It is the
component catalog made executable: for each component, what it is, which
platforms it ships to, where it comes from, and what it depends on.

```yaml
components:
  - id: llama-server
    kind: binary
    platforms: [windows, macos]
    source:
      windows: { release: llama.cpp, asset: linux-cuda-x64 }   # runs inside WSL
      macos:   { release: llama.cpp, asset: macos-arm64-metal }
  - id: supervisor
    kind: binary
    build: cargo build --release -p valinor-server
  - id: harness
    kind: python
    entry: Valar/app.py
  - id: voice
    kind: python
    package: omnivoice==0.1.5
    torch: { windows: cu130, macos: mps }
personas:
  ship: [sulivan, selene]
```

## Windows: producing `Hearth.wsl`

The artifact is a gzipped tar of a provisioned Linux root filesystem. Since WSL
2.4.4 this is a first-class Microsoft-supported format that installs by being
double-clicked in File Explorer.

1. **Start from a clean Ubuntu 24.04 root filesystem.** Not a copy of the
   working machine. A scripted provision from a base image is the only way the
   artifact is reproducible, and reproducibility is what stops the four
   configuration files that were missing from git happening again.
2. **Install the system dependencies.** `python3-venv`, `python3-dev`,
   `build-essential`, `cmake`, `git`, `libsndfile1`, `ffmpeg`. Note that
   `espeak-ng` leaves with NeuTTS and is no longer needed.
3. **Place `llama-server`.** Use the upstream llama.cpp release binary for
   Linux CUDA rather than building it. This closes a real gap: nothing in the
   repository builds the Linux binary today, and the provenance of the one on
   the working machine is recorded nowhere. Pin the release tag in the manifest.
4. **Build the Python environment once, at build time.** One environment, not
   two. The two-virtualenv split existed because NeuTTS needed a CUDA-built
   `llama-cpp-python` pinned to CUDA 11.8 while OmniVoice needs a newer torch.
   With NeuTTS gone, the CUDA 11.8 pin goes with it and everything converges on
   OmniVoice's torch. Verify this with a dependency resolve before committing to
   it, but the reasoning holds.
5. **Compile the supervisor as a release binary** and place it on the path. The
   current launcher runs `cargo run` on every service start, which means every
   boot needs a Rust toolchain and pays a debug-build resolve. Neither belongs
   in a shipped product.
6. **Copy the product tree.** The harness, the one module of `Server/` that is
   actually live, the persona configs and voice clones for the personas that
   ship. Not the whole repository.
7. **Install the service units, and generate the drop-ins.** The four drop-ins
   that were missing from git are configuration, not content: the TTS endpoint,
   the tool switch, and the reasoning mode. Generate them from the manifest at
   install time so they can never go missing again.
8. **Configure the distro.** `/etc/wsl.conf` with `boot.systemd=true`.
   `/etc/wsl-distribution.conf` with `oobe.defaultName` (required for the
   double-click install to work), an `oobe.command` that runs the first-launch
   setup and gates access until it succeeds, a Start Menu shortcut with the
   Hearth icon, and a Windows Terminal profile.
9. **Apply Microsoft's distro hygiene.** Disable or mask `systemd-resolved`,
   `systemd-networkd`, `NetworkManager`, the `systemd-tmpfiles-*` units and
   `tmp.mount`. Do not include `/etc/resolv.conf`. Include a uid 0 root in
   `/etc/passwd` and leave no password hashes in `/etc/shadow`.
10. **Tar and gzip.** The tar must contain the root of the filesystem, not a
    directory containing it, and must carry no kernel or initramfs. Gzip is the
    recommended compression; other formats risk breaking older WSL versions.

**Not baked in:** model weights. They are gigabytes, they are tier-dependent,
and they are the one thing that genuinely must be chosen on the user's machine.

### The install root

Added 2026-08-06, after the first live install test; the full statement is in
[`../first-run.md`](../first-run.md). The user chooses ONE folder during
setup, `D:\Hearth` by default, and everything above that is install-time
lands under it: the staged weights at `<root>\models`, the install record at
`<root>\hearth-install.json`, the generated configuration, and the distro
itself, imported with `wsl --import` so its virtual disk sits at
`<root>\wsl` rather than in the default location on the system drive.

Two consequences the installer must honor:

- Uninstall is `wsl --unregister` plus deleting the folder. Any step that
  writes product state elsewhere breaks that sentence and does not ship.
- The client revalidates the install record at boot and routes a missing or
  gutted install back into setup, so a half-deleted Hearth degrades into
  "install again", never into a house that dials a backend which is gone.

## macOS: producing `Hearth.app`

No WSL, no systemd, no CUDA. Simpler in structure and harder in signing.

1. **Fetch the upstream `llama-server` for macOS arm64 with Metal.** Same
   pinned release as Windows, different asset.
2. **Ship a relocatable Python.** A `python-build-standalone` interpreter tree
   with site-packages already resolved at build time. This is what `uv` installs
   when it manages a Python version, and it is the shape ComfyUI Desktop ships
   specifically to avoid resolving dependencies on the user's machine.
3. **Build the supervisor for arm64** and register it as the Tauri sidecar.
   Tauri's sidecar mechanism is a naming and permission convention, not a
   process manager, so supervision stays in the Rust process, which is where it
   already lives.
4. **Include the same persona tree** as Windows, from the same manifest.
5. **Code sign and notarize.** Every binary, including the sidecar and anything
   inside the Python tree. This is the step with no equivalent on Windows and it
   is where Mac builds usually fail first.
6. **Package as a `.dmg`.**

**Note the supervision asymmetry**, because it is a real design decision rather
than an accident: on Windows the supervisor runs inside WSL under systemd, on
macOS it runs as a sidecar under the app. The supervisor binary is the same and
the thing it supervises is the same. What differs is who starts the supervisor.
That is the smallest possible difference between the two platforms and it is
worth defending against attempts to unify it further.

## What the client does on first run

This is where the build side hands off to the setup flow.

1. **Scan the hardware.** GPU vendor and memory, unified memory on Apple
   Silicon, system RAM, free disk on the target volume, compute capability where
   applicable. Two rules from the audit: use `nvidia-smi` for VRAM and never
   WMI, which reports 4 GB for a 16 GB card because of a 32-bit field overflow;
   and check free disk against Windows rather than against the distro, which
   reports far more space than the host actually has.
2. **Choose the tier and say so.** Report what was found, which tier it implies,
   how large the download is, and whether the voice and the brain will be able
   to coexist on this machine. On 8 GB they cannot, and the user should learn
   that here rather than as a pause mid-sentence.
3. **Provision the backend.** On Windows: confirm WSL is present, offer to
   install it if not, then fetch and import `Hearth.wsl`. On macOS: unpack the
   bundled runtime.
4. **Download the model** into the backend's own filesystem. On Windows that
   means inside the distro rather than on the Windows mount, because weights on
   the mount take minutes to load and can exceed the model swap timeout.
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

1. **Does the client bundle the backend or fetch it?** Bundling makes one large
   download and a simpler flow. Fetching makes a small client, lets the backend
   update independently, and lets a client-only install skip it entirely. The
   research favours fetching, and it is also the only way a client-only machine
   stays small.
2. **How does a `.wsl` image update?** There is no layer model, so a whole-image
   replacement is a multi-gigabyte redownload for a one-line fix. An in-distro
   updater is the sensible answer and it is code we write. Design it now rather
   than after the first patch.
3. **Does the Mac get the same voice engine on day one?** OmniVoice documents
   Apple Silicon support with torch on MPS, so in principle yes. It has never
   been run there. That is a spike, and it gates whether the Mac artifact is a
   full Hearth or a text-first one.
4. **Where do the shipped voice clones come from, and under what licence?** They
   are the product's voices and this has not been answered.
5. **Who signs the macOS build?** Notarization needs an Apple Developer account
   and a signing identity, and nothing gets past Gatekeeper without it.
