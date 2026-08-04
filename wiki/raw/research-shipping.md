# How local-first AI products actually ship

Research date: 2026-08-04. Every size figure below marked "verified" was read directly from the GitHub Releases API on that date, not from documentation prose.

## Summary table

| Product | Windows format | macOS format | Containers | GPU strategy | Python shipped | Model fetch |
| --- | --- | --- | --- | --- | --- | --- |
| Ollama | `OllamaSetup.exe`, 1563 MB, no admin. Standalone zips also published | `Ollama.dmg`, 181 MB | Official image exists, secondary. Native installers are the consumer path | Per-backend native libs built from source (cuda_v12, cuda_v13, rocm_v7_1, rocm_v7_2, vulkan, jetpack5/6), discovered at runtime from `lib/ollama`. CPU-only if none found | None. Go plus C++/CUDA | Post-install, `ollama pull` / `ollama run` |
| LM Studio | Installer download from site (exact container format not verified) | `.dmg`, Apple Silicon only, macOS 14+ | None | Swappable "LM Runtimes" downloaded on demand: llama.cpp CPU / CUDA / Vulkan / ROCm, plus MLX on Apple Silicon | Yes, but macOS only: Python 3.11 bundled inside the MLX runtime | Post-install, in-app browser |
| Jan | `Jan_0.8.4_x64-setup.exe`, 58 MB (verified) | `Jan_0.8.4_universal.dmg`, 103 MB (verified) | None for desktop | Backend variants downloaded post-install (win-cuda-cu11.7/12.0/13 crossed with avx/avx2/avx512/common, win-vulkan, Metal). User picks from a dropdown | Not in the desktop app as far as I could verify | Post-install, in-app |
| GPT4All | `gpt4all-installer-win64-v3.10.0.exe`, 745 MB (verified). ARM variant 318 MB | `.dmg`, 320 MB (verified) | None | Nomic Vulkan as the portable GPU path. CUDA/Metal specifics not verified | Python bindings are a separate `pip` package, not the desktop app | Post-install, in-app |
| LocalAI | No native binary. WSL or Docker | `LocalAI.dmg` launcher, 21 MB (verified), plus a 150 MB `local-ai` arm64 binary | Docker is primary | Hardware-specific container variants: CUDA, ROCm, Intel, Vulkan. Backends also installable from a gallery | Explicitly not in the binaries. Python backends ship only in images | Post-install, gallery or CLI |
| Open WebUI | Desktop `.exe` 110 MB (verified). Also pip, uvx | Desktop `.dmg` 131 MB (verified) | Docker is the documented production path | Not an inference engine. Torch is used for RAG embeddings only | Yes, it is a Python app. Torch pulled from the CUDA or CPU wheel index depending on `USE_CUDA_DOCKER` | Delegated to Ollama or an API provider |
| Msty | `.exe` installer | `.dmg`, unsigned enough that Gatekeeper prompts | None | Delegated. Bundles Ollama as its "Local AI service"; llama.cpp is an option on Windows and Linux | Not verified, no public source | First-run prompt, default Gemma 2 around 1.6 GB |
| AnythingLLM Desktop | `AnythingLLMDesktop.exe`, 395 MB (verified) | `.dmg` 511 MB Intel / 505 MB Silicon (verified) | Docker is a separate deployment with the built-in provider removed | Not documented beyond "GPU recommended, 8 to 12 GB VRAM" | Node/Electron. Embeddings run on ONNX Runtime via `@xenova/transformers` | Post-install, in-app |
| ComfyUI Desktop | NSIS `.exe` to `%LOCALAPPDATA%\Programs\ComfyUI` | `.dmg`, ARM only, beta | None | Detects `nvidia` / `amd` / `mps` / `unsupported`, then installs the matching torch build | Yes. Bundles `uv`, resolves a Python env at first run | Post-install |
| Stability Matrix | Portable `.zip` | `.dmg`, arm64 | None | Per-GPU torch index selection | Yes. "Embedded Git and Python dependencies, with no need for either to be globally installed" | Post-install, per-package |

## Per-product findings

### Ollama

Release artifacts, read from the GitHub API for tag `v0.32.5` on 2026-08-04:

```
OllamaSetup.exe                 1563.1 MB
ollama-windows-amd64.zip        1457.8 MB
ollama-windows-amd64-rocm.zip    245.4 MB
ollama-windows-amd64-mlx.zip     726.4 MB
ollama-windows-arm64.zip         209.4 MB
Ollama.dmg                       180.6 MB
Ollama-darwin.zip                180.1 MB
ollama-darwin.tgz                145.7 MB
ollama-linux-amd64.tar.zst      1422.4 MB
ollama-linux-amd64-rocm.tar.zst 1047.7 MB
ollama-linux-amd64-mlx.tar.zst   866.9 MB
ollama-linux-arm64.tar.zst      1542.0 MB
ollama-linux-arm64-jetpack5      296.3 MB
ollama-linux-arm64-jetpack6      268.7 MB
install.sh, install.ps1
```

The single most informative number in this research is the ratio between `OllamaSetup.exe` at 1563 MB and `Ollama.dmg` at 181 MB. That 1.4 GB delta is the CUDA runtime. Windows and Linux carry NVIDIA's libraries inside the package; macOS does not need to, because Metal ships with the operating system.

The Windows installer "installs in your account without requiring Administrator rights", placing binaries in `%LOCALAPPDATA%\Programs\Ollama`, logs in `%LOCALAPPDATA%\Ollama`, and models in `%HOMEPATH%\.ollama`. The docs state at least 4 GB of space for the binary install. The base standalone zip "includes GPU library dependencies for Nvidia", with ROCm and MLX shipped as separate add-on zips. Source: https://docs.ollama.com/windows

macOS is a DMG requiring Sonoma (14) or newer, with "Apple M series (CPU and GPU support) or x86 (CPU only)". Source: https://docs.ollama.com/macos

**How it does cross-platform GPU without containers.** Ollama compiles llama.cpp backends itself, one variant per accelerator, and selects among them at runtime by directory search. The build is CMake-driven and the backend set is an explicit list:

```
cmake -B build . -DOLLAMA_LLAMA_BACKENDS="cuda_v13"
```

Documented backends: `cuda_v12`, `cuda_v13`, `rocm_v7_1`, `rocm_v7_2`, `vulkan`, `cuda_jetpack5`, `cuda_jetpack6`. On Apple Silicon, Metal builds automatically and "MLX is enabled by default". At runtime the loader searches `../lib/ollama` (standard installs), `./lib/ollama` (Windows release payloads), `.` (macOS artifacts), and the dev paths, and "if the libraries are not found, Ollama will not run with any acceleration libraries", meaning it silently degrades to CPU. Source: https://github.com/ollama/ollama/blob/main/docs/development.md

Detection is automatic, with environment overrides per vendor: `CUDA_VISIBLE_DEVICES` for NVIDIA, `ROCR_VISIBLE_DEVICES` for AMD, `GGML_VK_VISIBLE_DEVICES` for Vulkan. Setting an invalid ID such as `-1` forces CPU. CUDA needs compute capability 5.0 or better and driver 550 or newer (570 for 5.0 to 6.2). Vulkan "is enabled by default when the backend is installed". Source: https://docs.ollama.com/gpu

**Multi-process supervision.** Ollama does supervise more than one process, and does it without any init system. The server spawns a separate runner subprocess per loaded model using `os/exec`, communicates with it over a local TCP port, polls a `/health` endpoint until ready, passes accelerator selection down through environment variables such as `CUDA_VISIBLE_DEVICES`, tracks per-runner reference counts, and starts an unload timer when usage drops to zero, escalating to termination if the child does not exit. The stated motivation is isolation (an inference crash does not take the server down) and clean VRAM recovery on process exit. Caveat: I verified this description on DeepWiki (https://deepwiki.com/ollama/ollama/5.2-llamaserver-and-runner-implementation and https://deepwiki.com/ollama/ollama/2.2-request-scheduling-and-runner-management), which is an auto-generated third-party wiki over the Ollama source, not first-party documentation. The architecture is consistent with the runtime library layout documented above, but treat the specifics as source-derived rather than officially published.

Ollama does publish a Docker image (https://docs.ollama.com/docker), but it is documented alongside the native installers rather than as the recommended consumer path, and the entire Windows and macOS story is native.

### LM Studio

Closed source. The docs direct users to "head over to the Downloads page and download an installer for your operating system" without naming the container format. I could not verify the widely repeated claim that the Windows build is an MSI; the only download URL I probed returned 404, and the claim traces to SEO content farms rather than lmstudio.ai. Linux is explicitly "distributed as an AppImage". macOS requires Apple Silicon (M1 through M4) and macOS 14.0 or later; Windows requires x64 with AVX2 or ARM (Snapdragon X Elite), 16 GB RAM recommended, and "at least 4GB of dedicated VRAM is recommended". Install size is not documented. Sources: https://lmstudio.ai/docs/app and https://lmstudio.ai/docs/app/system-requirements

The architecturally interesting part is that the inference engine is decoupled from the application. LM Studio calls these "LM Runtimes" and ships a CLI to manage them: `lms runtime ls`, `get`, `select`, `remove`, `update`, described as letting you "list, download, switch, or remove inference runtimes without opening the app". The in-app equivalent is Ctrl+Shift+R. Runtimes update independently of the app, and newer versions auto-delete unused engine dependencies to reclaim disk. Sources: https://lmstudio.ai/docs/cli/runtime/runtime, https://lmstudio.ai/blog/lmstudio-v0.3.9

Engine coverage is llama.cpp GGUF across Mac, Windows and Linux, plus MLX on Apple Silicon, with llama.cpp built in CPU, CUDA, Vulkan, ROCm and Metal variants. Source: https://lmstudio.ai/docs/app

**LM Studio ships a Python interpreter, on macOS.** The MLX engine is Python, and "python3.11 is the python version bundled within the LM Studio MLX runtime", with "LM Studio 0.3.4 and newer for Mac ships pre-bundled with mlx-engine". Source: https://github.com/lmstudio-ai/mlx-engine/blob/main/README.md. This is a real precedent for shipping an embedded interpreter to non-technical users, but note it is the Apple Silicon path only, and MLX is not torch.

No container path at all.

### Jan

Tauri v2 desktop app. Verified release artifacts for `v0.8.4` (2026-07-23):

```
Jan_0.8.4_x64-setup.exe      57.8 MB
Jan_0.8.4_universal.dmg     102.6 MB
Jan_0.8.4_amd64.AppImage    157.5 MB
Jan_0.8.4_amd64.deb          87.0 MB
```

A 58 MB Windows installer cannot contain CUDA. That is the tell: Jan downloads its backend after install. The backend catalogue is a matrix of llama.cpp builds crossing accelerator against CPU instruction set: CUDA 11.7, 12.0 and 13 each in AVX2, AVX512, AVX and "common CPU" flavours; `win-vulkan-x64` and `win-vulkan-common_cpus-x64` for AMD and Intel; no-AVX options for older processors; Metal on Apple Silicon. Source: https://www.jan.ai/docs/desktop/local-engine/llama-cpp

Jan does **not** fully auto-detect. The user selects a backend from a dropdown, with the docs suggesting `win-avx2-cuda-cu12.0-x64` as a starting point for NVIDIA. After a backend is installed, Jan "scans for required libraries (CUDA, Vulkan, cuDNN)" and shows a checklist of what the user still has to install themselves. That is a meaningfully worse first-run experience than Ollama's, and it is the direct cost of the 58 MB installer.

Jan v0.8.0 replaced per-model server processes with "a single unified router process instead of spawning a separate server for every model", loading and unloading models on demand. Source: https://www.jan.ai/changelog/2026-05-22-jan-v0.8.0. This is the opposite choice from Ollama, which keeps a process per model for crash isolation.

### GPT4All (Nomic)

Verified release artifacts for `v3.10.0`, published 2025-02-25:

```
gpt4all-installer-win64-v3.10.0.exe       744.5 MB
gpt4all-installer-win64-arm-v3.10.0.exe   318.1 MB
gpt4all-installer-macos-v3.10.0.dmg       319.6 MB
gpt4all-installer-linux-v3.10.0.run       732.7 MB
```

Status caveat: the repository is not formally archived, but the GitHub API reports the last push as 2025-05-27 and the last release as February 2025. Treat GPT4All as dormant rather than a live reference point.

The 745 MB x64 Windows installer against a 318 MB ARM one again implies bundled GPU libraries on the x64 build. GPT4All's distinguishing bet was Nomic's own Vulkan backend, giving one GPU path that works across NVIDIA, AMD and Intel without shipping vendor toolkits. I could confirm the Vulkan work exists (https://github.com/nomic-ai/gpt4all) but could not confirm from the pages I fetched which of CUDA, Metal and Kompute are in the current desktop build. The Python `gpt4all` package is a separate pip binding, not the desktop app's runtime.

### LocalAI

This is the clearest container-first product in the set, and it also produced the single most useful negative result in this research.

The quickstart leads with Docker: `docker run -p 8080:8080 --name local-ai -ti localai/localai:latest`, with hardware-specific variants for NVIDIA CUDA, AMD ROCm, Intel GPU and Vulkan, selected by adding `--gpus all` or the appropriate `--device` flags. Source: https://localai.io/docs/basics/getting_started/

Native binaries exist but are second-class: Linux amd64 and arm64, macOS arm64, and "Windows users can access these via WSL". Verified release artifacts for `v4.7.1` include `local-ai-v4.7.1-darwin-arm64` at 150 MB, `local-ai-v4.7.1-linux-amd64` at 152 MB, a `LocalAI.dmg` launcher at 20.5 MB and `local-ai-launcher-linux.tar.xz` at 16.6 MB. There is no Windows binary in the release at all.

The critical sentence, from the binaries reference: **"Python-based backends are not shipped with binaries (e.g. `diffusers` or `transformers`)."** Source: https://localai.io/docs/reference/binaries/. The same page notes macOS and Linux arm64 binaries also lack TTS and stablediffusion-cpp support, and Linux binaries omit stablediffusion-cpp. LocalAI supports torch-based backends, and it ships them exclusively inside container images. When it drops to a native binary, the Python half of the product is amputated.

### Open WebUI

Not an inference engine. It "functions as a self-hosted AI platform" connecting to "Ollama and OpenAI-compatible APIs". Four install paths: Docker (recommended for production), `pip install open-webui`, `uvx --python 3.11 open-webui@latest serve`, and a desktop app at github.com/open-webui/desktop. Source: https://docs.openwebui.com/

The desktop app is Electron and modest: verified `v0.0.20` artifacts show `open-webui-x64-setup.exe` at 110 MB, `open-webui-x64.dmg` at 131 MB, plus deb, snap, flatpak and AppImage. That size confirms it is a shell around a remote or local API, not a bundled stack.

Open WebUI is nonetheless a useful torch datapoint. Its Dockerfile conditionally installs `torch torchvision torchaudio` from either the CUDA wheel index or the CPU index depending on a `USE_CUDA_DOCKER` build argument, appends torch, cuDNN and cuBLAS paths to `LD_LIBRARY_PATH`, and checks `torch.cuda.is_available()`. Official images are published under `:cuda` and `:ollama` tags. A plain `pip install open-webui` does not guarantee a CUDA wheel, so the RAG embedding path falls back to CPU even on a GPU machine. Sources: https://github.com/open-webui/open-webui/blob/main/Dockerfile, https://deepwiki.com/open-webui/open-webui/3.1-installation-methods. So: GPU torch is available, and only through the container.

### Msty

Closed source with no public repository, so this entry is the least verified in the set. Desktop app for Windows, macOS and Linux, distributed as a `.exe` on Windows and a `.dmg` on macOS that triggers a Gatekeeper prompt because it comes from outside the App Store. First-run offers "download and install a local AI model on your machine" with Gemma 2 at roughly 1.6 GB as the default. Sources: https://docs.msty.app/, https://docs.msty.app/how-to-guides/download-offline-models

Msty does not build an engine. It bundles Ollama as its "Local AI service", pinned to whatever Ollama version was current at app release, and integrates with an existing Ollama install if one is present. Windows and Linux users can opt into llama.cpp instead. Source: https://docs.msty.app/how-to-guides/get-the-latest-version-of-local-ai-service. This is the cheapest viable strategy in the whole survey: let Ollama solve GPU packaging and ship a UI on top.

### AnythingLLM Desktop

Verified release artifacts for `v1.15.0` (2026-06-25):

```
AnythingLLMDesktop.exe          394.5 MB
AnythingLLMDesktop-Arm64.exe    541.5 MB
AnythingLLMDesktop.dmg          511.1 MB
AnythingLLMDesktop-Silicon.dmg  504.5 MB
AnythingLLMDesktop.AppImage     575.2 MB
```

Described as "a single-player application you can install on any Mac, Windows, or Linux operating system". The desktop build has a "Built-in LLM provider"; the Docker build explicitly does not, and Docker is presented as a distinct deployment for multi-user server use. The built-in provider "ships with a built-in LLM engine and provider that enables you to download popular and highly-rated LLMs ... that can run locally on your CPU and GPU", and is "only present on Desktop Version". Sources: https://docs.anythingllm.com/installation-desktop/overview, https://docs.anythingllm.com/setup/llm-configuration/local/built-in

I could not verify which engine the desktop bundles. The public repository's server `package.json` lists an `ollama` npm client and `@xenova/transformers` (ONNX Runtime) for embeddings, and the frontend lists `onnxruntime-web`, but the desktop packaging is not in the open repo and no first-party doc names the engine. System requirements are vague: 16 GB RAM, 8-core CPU, "on Windows, a GPU is recommended ... (8-12GB+ VRAM is great!)", with no GPU backend detail. Source: https://docs.anythingllm.com/installation-desktop/system-requirements

### ComfyUI Desktop (the torch case study)

Not an LLM product, but it is the closest existing solution to Hearth's actual packaging problem, because it must deliver torch on CUDA to people who have never opened a terminal.

Distribution: Electron plus Vue, built and code-signed through ToDesktop. Windows is an NSIS `.exe` installing bundled resources to `%LOCALAPPDATA%\Programs\ComfyUI` with user files in `%APPDATA%\ComfyUI`; macOS is a `.dmg`. Supported platforms are "Windows and MacOS (ARM), currently in Beta". Docs recommend "at least 4.85 GB recommended per installation". Sources: https://github.com/Comfy-Org/desktop, https://docs.comfy.org/installation/system_requirements, https://docs.comfy.org/installation/desktop/windows

The mechanism, read directly from source on 2026-08-04:

`src/preload.ts` defines the hardware taxonomy the whole installer branches on:

```ts
export type GpuType = 'nvidia' | 'amd' | 'mps' | 'unsupported';
export type TorchDeviceType = GpuType | 'cpu';
```

`src/constants.ts` holds the wheel selection. NVIDIA gets a pinned CUDA 13 build from PyTorch's own index; AMD gets direct ROCm wheel URLs; there is a legacy CUDA 12.9 mirror for older installs and a CPU index:

```ts
export const NVIDIA_VENDOR_ID = '10DE';
export enum TorchMirrorUrl {
  Cuda = 'https://download.pytorch.org/whl/cu130',
  NightlyCuda = 'https://download.pytorch.org/whl/nightly/cu130',
  NightlyCpu = 'https://download.pytorch.org/whl/nightly/cpu',
}
export const LEGACY_NVIDIA_TORCH_MIRROR = 'https://download.pytorch.org/whl/cu129';
export const NVIDIA_TORCH_VERSION = '2.10.0+cu130';
export const NVIDIA_TORCHVISION_VERSION = '0.25.0+cu130';
export const AMD_TORCH_PACKAGES: string[] = [
  getAmdRocmWindowsPackageUrl('torch-2.9.1+rocm7.2.1-cp312-cp312-win_amd64.whl'),
  ...
];
export const AMD_PYTORCH_WINDOWS_REQUIRED_DRIVER = '26.2.2';
```

`src/install/installationManager.ts` handles the failure modes. It sets `NVIDIA_DRIVER_MIN_VERSION = '580'`, shells out to `nvidia-smi` (with a fallback parse of plain `nvidia-smi` output when the `--query-gpu` form fails), and warns "Your NVIDIA driver may be too old for PyTorch ${NVIDIA_TORCH_VERSION}". Hardware that does not map to a supported device routes to a dedicated `not-supported` page. There is also a revealing commented-out line and its justification: "Disable automatic NVIDIA torch upgrades so users control large downloads."

`src/install/installWizard.ts` writes the chosen mirror into ComfyUI's own settings as `Comfy-Desktop.UV.TorchInstallMirror`, and when the device is `cpu` it passes `Comfy.Server.LaunchArgs.cpu`.

Nothing about this is bundled into the installer. The app ships `uv` and, per the README, "on startup, it will install all the necessary python dependencies with uv and start the ComfyUI server". The installer stays small; the multi-gigabyte torch download happens on first run, after hardware detection has chosen the index.

There is a second, blunter ComfyUI distribution that goes further: "The Windows portable build currently comes with Python 3.13 and PyTorch CUDA 13.0", shipped as a zip. Source: https://docs.comfy.org/installation/system_requirements. That is torch plus CUDA fully bundled in the artifact, at the cost of being a single-GPU-vendor download.

### Stability Matrix (LykosAI)

Downloads are `StabilityMatrix-win-x64.zip`, `StabilityMatrix-macos-arm64.dmg`, `StabilityMatrix-linux-x64.zip` and an AUR package. The README states "Embedded Git and Python dependencies, with no need for either to be globally installed" and describes the app as "fully portable". Source: https://github.com/LykosAI/StabilityMatrix

Secondary sources describing recent releases state that bundled installs use the `cu130` torch index (`cu126` for legacy NVIDIA GPUs) or `rocm7.2` depending on GPU, and that the app ships upgraded Visual C++ redistributables "required by modern native dependencies such as PyTorch and ONNX Runtime". I did not verify those specifics against the LykosAI repository directly, so treat the exact index versions as unconfirmed; the embedded-Python claim is first-party.

### NVIDIA ChatRTX

Worth naming as the extreme case, but I could not verify it. NVIDIA's own user guide returned HTTP 403 to my fetch. Secondary sources report an installer around 35 GB expanding to roughly 50 GB, requiring an RTX 30 or 40 series GPU with 8 GB VRAM and 100 GB of disk, and shipping TensorRT-LLM locally. If accurate, it demonstrates that a hardware vendor will ship an enormous accelerated Python stack to consumers, but the sourcing is not good enough to lean on.

## The torch plus CUDA question

**Yes, consumer products do ship torch on CUDA to end users, but not one of them puts it inside the installer artifact, and not one of them is an LLM server. It is exclusively the diffusion and image-generation lineage, and the universal pattern is: small installer, hardware detection at first run, then a package manager pulls the correct wheel from PyTorch's own index.**

The strongest positive evidence is ComfyUI Desktop, verified in source rather than documentation. It classifies hardware into `nvidia | amd | mps | unsupported | cpu`, pins `torch==2.10.0+cu130` from `https://download.pytorch.org/whl/cu130` for NVIDIA, uses direct ROCm 7.2.1 Windows wheel URLs for AMD, keeps a CUDA 12.9 mirror for legacy installs, checks the NVIDIA driver against a minimum of 580 via `nvidia-smi` and warns when it is too old, routes unsupported hardware to a dedicated dead-end page, and installs the whole environment with `uv` on first launch. There is even an explicit product decision in the code to disable automatic torch upgrades because the downloads are too large to spring on a user. Stability Matrix does the same job with an embedded Python and per-GPU torch indexes. ComfyUI's Windows portable zip goes furthest and genuinely bundles Python 3.13 with PyTorch CUDA 13.0 in the artifact, which is possible only because it gives up on being one download for all hardware.

The negative evidence is just as sharp and comes from the product closest to a multi-backend server. LocalAI's own binaries reference states plainly that "Python-based backends are not shipped with binaries (e.g. `diffusers` or `transformers`)". LocalAI supports torch backends and ships them only in container images. When it produces a native binary it drops the Python half of its own product, and it also drops TTS on macOS and Linux arm64. Open WebUI tells the same story from the other side: its Dockerfile branches between the CUDA and CPU torch indexes on `USE_CUDA_DOCKER`, publishes a `:cuda` image tag, and a plain `pip install` yields CPU torch, so GPU torch in that project is a container feature.

Meanwhile every product whose job is running an LLM locally, Ollama, LM Studio, Jan, GPT4All, ships zero torch. They ship compiled C++ and Go engines: llama.cpp variants, Nomic's Vulkan backend, MLX. The only embedded Python interpreter anywhere in that group is the Python 3.11 inside LM Studio's macOS MLX runtime, and MLX is not torch and involves no CUDA. That absence is not an oversight. It is the settled answer of four independent teams to the same question.

## What this implies for Hearth

The llama.cpp half of Hearth is a solved problem with a proven blueprint, and Ollama is the blueprint. Compile llama.cpp yourself once per accelerator, ship the resulting native libraries in a per-platform payload, and select among them by directory search at runtime with a silent CPU fallback. Accept the size consequence, because it is unavoidable and the market has already accepted it: the Windows installer is 1563 MB and the macOS one is 181 MB, and the entire delta is CUDA. Windows gets a per-user NSIS or equivalent installer needing no admin rights; macOS gets a notarized DMG that carries no GPU payload at all because Metal is already on the machine. Containers are not the answer for either target. Of the products surveyed, exactly one treats Docker as the primary consumer path, LocalAI, and it is a server product with no Windows binary. Every product that succeeded with non-technical users on Windows and macOS ships native.

The Rust supervisor is fine and is in fact the mainstream design. Ollama supervises a separate runner subprocess per resident model over a local TCP port, health-polls it, passes accelerator selection down by environment variable, and unloads on an idle timer, with no init system involved. Jan moved the other way to a single router process. Both are viable; Ollama's per-process isolation buys clean VRAM recovery when a model crashes, which is worth having on a single 4080. What is not viable is carrying systemd assumptions across the boundary. That supervision logic belongs in the Rust process on both platforms, and Whisper should follow the same reasoning as the LLM: the consumer-shipping form of speech recognition is a compiled runtime, not a Python import.

The TTS service is the genuine problem, and the evidence says so clearly. Nobody ships torch on CUDA as part of a voice or LLM product. The people who do ship torch to consumers are image-generation apps, and even they refuse to put it in the installer, instead detecting hardware and downloading multiple gigabytes of wheels on first run behind a progress bar, while maintaining pinned wheel URLs per vendor, a driver version floor, and a hardware-unsupported dead end. That is a permanent maintenance surface that scales with every NVIDIA driver and PyTorch release, and it lands on the M1 MacBook Air as an MPS path that shares almost no code with the CUDA one. If the goal is a single unified package for a non-technical person, the honest reading is that the diffusion TTS engine should be replaced with something that compiles, in the ONNX Runtime or C++ lineage where whisper.cpp and llama.cpp already live. If the voice quality is non-negotiable, the fallback is ComfyUI's shape: keep torch out of the installer, isolate it behind a first-run hardware-detecting `uv` install in its own environment, treat it as an optional component the app can start without, and be prepared to own the wheel matrix indefinitely. What should not happen is torch and CUDA being treated as an implementation detail of the main package, because no shipped product in this survey treats it that way.
