---
title: Packaging Options
status: draft
last_reviewed: 2026-08-04
related:
  - component-catalog.md
  - portability-ledger.md
  - ../_index.md
sources:
  - D:/Tools/Valinor/wiki/raw/backend-audit-2026-08-04/
---

# Packaging Options

How Hearth's backend becomes something another person installs. Written from
three parallel research passes on 2026-08-04: how comparable products actually
ship, what containers can and cannot do with a GPU, and what it takes to bundle
a mixed Rust and Python stack as one artifact.

The goal stated at the outset was a single unified package, with containers as
the presumed vehicle. The research says the goal is right and the presumed
vehicle is wrong, and it points at a different route that is shorter than it
looks.

## The three findings that decide it

**1. Containers cannot host the GPU work on either target.**

On macOS this is permanent rather than immature. Apple GPUs are not behind an
IOMMU and cannot be passed through to a guest, so no container runtime on Apple
Silicon can use Metal. Docker documents the limitation in its own product pages,
and Apple's container maintainer confirmed it directly. The proof that this is
structural: Docker hit the same wall building Model Runner and shipped their own
macOS inference engine as a native host process while keeping containers for
Linux and Windows.

On Windows the limitation is different but points the same way. Docker's GPU
support requires the WSL2 backend, so choosing Docker adds a layer on top of a
WSL dependency rather than removing one. Native Windows containers accelerate
only DirectX and explicitly not CUDA. Docker Desktop also cannot be
redistributed: images may be bundled, the runtime may not, so every user
installs and licenses it themselves, and the free tier excludes organisations
over 250 employees or $10M revenue.

**2. The entire product category ships native installers.**

Nine comparable products were surveyed. Exactly one, LocalAI, treats Docker as
the primary consumer path, and it is a server product with no Windows binary.
Ollama, LM Studio, Jan, GPT4All, ComfyUI Desktop, Stability Matrix, Msty and
AnythingLLM all ship platform-native installers.

Ollama is the closest analogue and the useful blueprint. Its Windows installer
is 1563 MB and requires no administrator rights; its macOS disk image is 181 MB,
and essentially the whole difference is CUDA. It compiles llama.cpp once per
accelerator, ships the resulting native libraries in a per-platform payload, and
selects among them by directory search at runtime with a silent CPU fallback.

**3. Nobody ships torch to consumers as part of a voice or LLM product.**

This is the finding that matters most, because it lands on a specific component
rather than on the packaging format.

Ollama, LM Studio, Jan and GPT4All ship zero torch. They ship compiled C++ and
Go engines. The only consumer products that ship torch at all are the
image-generation lineage, and even they refuse to put it in the installer:
ComfyUI Desktop detects hardware at first run, pins an exact wheel per vendor,
enforces a minimum driver version, routes unsupported hardware to a dead-end
page, and downloads gigabytes behind a progress bar. It deliberately disables
automatic torch upgrades because the downloads are too large to spring on a
user.

The sharpest evidence comes from the product closest to Hearth's shape.
LocalAI's own documentation states that Python-based backends are not shipped
with its binaries. When LocalAI produces a native binary, it drops the Python
half of its own product.

Freezing is not an escape. PyInstaller and Nuitka both work with torch, and both
produce artifacts of 2.6 GB to 4 GB per service. Hearth would pay that twice,
because it currently runs two incompatible torch versions.

## What this means for Hearth, component by component

| Component | Verdict |
| --- | --- |
| `llama-server` | Already correct. Keep it as a supervised prebuilt binary. Upstream publishes builds for Windows x64 CPU, CUDA 12, CUDA 13 and Vulkan, and macOS arm64. Jan and LM Studio both consume these rather than building. |
| Rust supervisor | Already correct, and mainstream. Ollama supervises a runner subprocess per resident model over a local TCP port, health-polls it, and unloads on an idle timer, with no init system. That is what we built. What does not transfer is the systemd assumption wrapped around it. |
| Whisper | Move into the supervisor via `whisper-rs`, which binds whisper.cpp with GPU support and is proven in a shipping Tauri product. This is the highest ratio of Python removed to risk taken in the whole plan. |
| TTS | The genuine gap, and the reason torch is in the product at all. See below. |
| FastAPI harness | Plain application code with no ML dependency. Once torch is gone, a Python tree is small enough to ship without complaint. Port it to axum on maintenance grounds or not at all, but not for packaging reasons. |

### The voice engine is the whole problem

Everything else is either already right or cheap. OmniVoice is why torch is in
the product, why there are two incompatible virtualenvs, why the Windows payload
would be measured in gigabytes, and why the macOS story needs a second wheel
matrix that shares almost no code with the first.

Three routes off it, in order of readiness:

**ONNX, available today.** `sherpa-onnx` runs speech recognition, text to
speech, diarization and voice activity detection on ONNX Runtime with no
network, supports seven TTS model families including zero-shot voice cloning,
and has a Rust crate. It is worth noting that this comes from **k2-fsa, the same
organisation that publishes OmniVoice**, so this is not a jump to a stranger's
ecosystem. Zero-shot cloning models with published ONNX exports exist, including
a 0.6B multilingual model with INT4 weights reported at roughly 1.1 to 1.2 GB
peak memory on an M2 MacBook Air. The size argument is stark: the ONNX Runtime
CPU wheel is about 15 MB against roughly 1 GB for a minimal PyTorch install.

**`neutts-rs`, promising and unproven.** A Rust port of NeuTTS with a GGUF
backbone and the NeuCodec decoder, claiming no ONNX Runtime and no native ML
dependency, streaming synthesis, and optional GPU through `wgpu` on Metal,
Vulkan and DX12. The caveats matter more than the feature list: version 0.1.0,
one author, and the NeuCodec **encoder is not implemented in Rust**, so voice
cloning still falls back to Python. Since encodings cache per voice, pre-encoding
the shipped voices at build time would sidestep the encoder entirely. That is a
real strategy and it needs a spike before anyone depends on it.

**Keep torch, isolate it.** ComfyUI's shape: torch out of the installer, a
first-run hardware-detecting install into its own environment, the voice treated
as an optional component the app can start without. This works and it means
owning a wheel matrix indefinitely, across every future NVIDIA driver and
PyTorch release, on both platforms.

There is also a live problem independent of packaging. The harness venv is
pinned to CUDA 11.8, which is now off PyTorch's supported matrix entirely:
PyTorch 2.12 builds CUDA 12.6.3, 13.0 and 13.2. The two-version split has to be
resolved regardless of which route is chosen.

## The two paths, and why they are not exclusive

### Path A: the WSL image

Since WSL 2.4.4, `.wsl` is a first-class Microsoft-supported distribution
format. A tar of a root filesystem that installs by being double-clicked in File
Explorer. Inside it, `/etc/wsl-distribution.conf` provides a first-launch script
that gates access until it succeeds, a Start Menu shortcut with a custom icon,
and a Windows Terminal profile; `/etc/wsl.conf` enables systemd. A registry
manifest entry makes `wsl --install hearth` work and provides named version
channels.

For Hearth this means CUDA with no container tooling at all, because the Windows
driver already stubs `libcuda.so` into WSL. No container toolkit, no CDI
generation, no Docker version floor, no licensing question. The existing systemd
units transplant unchanged.

**What it costs.** It commits to WSL rather than removing it. It gives macOS
nothing. And updates are entirely ours: there is no layer model, so every fix is
either a multi-gigabyte redownload or an in-distro updater we write. That
updater should be designed from the start, not retrofitted.

**What it is good for.** Getting a working Hearth onto a Windows tester's
machine in days rather than months, with the architecture we have already
debugged.

### Path B: native, per platform

A Tauri application shipping the Rust supervisor as its single sidecar, with
compiled engines beside it and a relocatable Python tree for whatever Python
remains. Tauri's sidecar mechanism is a naming and permission convention rather
than a process manager, so the supervision stays in the Rust process, which is
where it already is.

This is what the category converged on. It is the only path where the M1 Air
works at all, and it is the only one that produces a genuinely unified answer
across both platforms.

**What it costs.** It requires the voice engine to leave torch. That is the
gating work, and it is real work.

### The recommendation

Do both, in this order.

1. **Fix the three defects now**, independently of any packaging decision:
   disable the OpenCode boot dependency, correct `valar_install_service.sh` so
   it installs the OmniVoice unit and the drop-ins, and remove the context
   override capping the coding executor. None of these are packaging work; all
   three are live faults.
2. **Build the startup self-check.** Nothing else in this document matters if a
   broken install reports itself healthy. See the portability ledger, section 9.
3. **Ship pre-alpha as a `.wsl` image.** Windows only, testers only, honest
   about being a home system. This gets feedback flowing this month against the
   architecture that already works.
4. **Move Whisper to `whisper-rs`.** Low risk, proven, and it removes the
   speech-side justification for Python entirely.
5. **Spike the TTS route.** ONNX first, since it is available today and comes
   from the same organisation as the current engine. `neutts-rs` with
   pre-encoded voices as the alternative if voice quality demands it.
6. **When torch leaves, build Path B.** The Windows installer drops by
   gigabytes, the macOS notarization problem shrinks to signing a handful of
   binaries, the two-torch-version question dissolves, and the M1 Air becomes a
   target rather than an aspiration.

The reason this ordering works is that step 3 does not block step 6. A `.wsl`
image is a wrapper around the current architecture, so nothing built for it is
wasted when the architecture changes underneath. The alternative, holding
pre-alpha until the native path is ready, trades months of tester feedback for
packaging purity.

## Open questions

1. **Is the M1 MacBook Air 8 GB or 16 GB?** At 8 GB it is a 3B to 8B machine and
   a 12B does not load at all. This decides whether the low model tier is the Mac
   default rather than a fallback, and it changes what "works on Mac" means.
2. **Is voice quality negotiable?** If OmniVoice's output is the product, the
   ONNX route needs an A/B before it is chosen. If it is not, the ONNX route is
   simply better on every axis that matters for shipping.
3. **Does Hearth ship a voice at all in pre-alpha?** Text-only would remove the
   hardest component from the first package entirely. It would also remove the
   thing that makes Hearth feel like Hearth.
4. **Which torch version does the product converge on**, given 11.8 is off the
   supported matrix. Only relevant if torch stays.

## What could not be determined

- Whether Docker Desktop on Windows fully bundles the NVIDIA container runtime
  hook. Docker's prerequisites omit the container toolkit; NVIDIA's guide lists
  it with minimum versions. Testable in five minutes on the existing machine and
  not worth further research.
- Measured CPU-only llama.cpp figures for an M1 MacBook Air at the specific model
  sizes at issue. The Metal figures are solid at roughly 14 tokens per second for
  a 7B; the CPU figures are inferred from a 3 to 5 times ratio measured on other
  hardware.
- Whether Apple's `container` tool has any committed GPU roadmap. The only
  sourced Apple statement remains that it is not supported.
