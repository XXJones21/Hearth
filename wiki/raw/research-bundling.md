# Shipping a mixed Rust and Python backend as one installable artifact

Research date: 2026-08-04. Targets under consideration: Windows x86_64 and macOS on Apple Silicon.

## Verdict up front

The shortest honest path is a **Tauri app that ships a Rust supervisor as its only sidecar, plus relocatable Python trees as bundled resources, plus a first run download for the CUDA payload on Windows**. Concretely:

1. Do not freeze the Python services into executables. PyInstaller and Nuitka both work with torch, but the artifacts are 2.6 GB to 4 GB per service and you would pay that twice because you have two torch versions ([pyinstaller#8551](https://github.com/pyinstaller/pyinstaller/issues/8551)). Freezing buys you nothing that a shipped interpreter tree does not already give you.
2. Ship a `python-build-standalone` interpreter tree per service, with the site-packages already resolved at build time. This is what uv installs when it manages a Python version ([uv docs](https://docs.astral.sh/uv/concepts/python-versions/)), and it is exactly the shape ComfyUI Desktop ships: a relocatable Python with PyTorch and GPU wheels prebuilt, specifically to avoid pip and CUDA resolution on the user's machine ([Comfy-Desktop](https://github.com/Comfy-Org/Comfy-Desktop)).
3. Make the Rust supervisor the single `externalBin` sidecar. Everything else goes in `bundle.resources`. Tauri's sidecar mechanism is a naming and permission convention for a small number of executables ([Tauri sidecar docs](https://v2.tauri.app/develop/sidecar/)); it is not a process manager, and there is no supervision plugin ([plugins-workspace#3062](https://github.com/tauri-apps/plugins-workspace/issues/3062)). You write the supervisor. That is normal.
4. On Windows, the CUDA torch payload is a first run download. On macOS Apple Silicon there is no CUDA at all, so the Mac artifact is a fundamentally different and much smaller problem than the Windows one. Treat them as two size budgets, not one.
5. Converge on one torch version before you package anything. Your CUDA 11.8 pin is not merely awkward, it is off the supported matrix entirely: PyTorch 2.12 builds CUDA 12.6.3, 13.0, and 13.2, and 2.13 removed the 12.8 and 12.9 builds ([dev-discuss 2.12](https://dev-discuss.pytorch.org/t/introducing-cuda-13-2-and-deprecating-cuda-12-8-release-2-12/3337), [2.13 release blog](https://pytorch.org/blog/pytorch-2-13-release-blog/)).

The thing that actually reduces the problem, rather than repackaging it, is getting torch out of the product. See the all-Rust section: Whisper has a clean Rust path today, llama.cpp already is a binary, and the TTS piece has an ONNX path that removes torch without requiring Rust at all.

## Shipping Python

### PyInstaller

Status: actively maintained, largest hook ecosystem, and the default choice for Tauri Python sidecars in every worked example I found ([Tauri sidecar docs](https://v2.tauri.app/develop/sidecar/) names pyinstaller explicitly).

Torch plus CUDA: yes, it works, and people ship it. The sizes are the problem. Reported real numbers: a `--onedir` build of a torch 2.3 cu118 app came out at roughly 4 GB with the torch library alone at about 4 GB of that, and a `--onefile` build of the same came out at 2.6 GB ([pyinstaller#8551](https://github.com/pyinstaller/pyinstaller/issues/8551), [pyinstaller discussion #8552](https://github.com/orgs/pyinstaller/discussions/8552)). The maintainer-side answer in that thread is that most of the size is binary extensions and CUDA and cuDNN shared libraries which cannot be split. Reports of 200 MB to 300 MB torch executables are CPU-only builds.

Two operational hazards worth knowing before you commit:

- `--onefile` extracts the whole payload to a temp directory on every launch. With torch-scale payloads that is a visible startup stall, and the extract-then-execute pattern is exactly what AV heuristics flag ([pythonguis writeup](https://www.pythonguis.com/faq/problems-with-antivirus-software-and-pyinstaller/), [pyinstaller#6754](https://github.com/pyinstaller/pyinstaller/issues/6754)). Use `--onedir`. At torch sizes `--onefile` is not a real option.
- PyInstaller misses native libraries silently. The worked Tauri plus FastAPI plus llama.cpp writeup says the whole thing hinges on a hand-written spec file calling `collect_dynamic_libs`, and that stock commands build fine and then crash at model load ([aiechoes](https://aiechoes.substack.com/p/building-production-ready-desktop)). That article's backend executable was 35 MB to 40 MB, but that is llama-cpp-python, not torch.

### Nuitka

Status: alive and moving fast. Version 4.0.5 was published 2026-03-12 and there is a 4.1.x line ([PyPI](https://pypi.org/project/Nuitka/), [changelog](https://nuitka.net/changelog/)). Torch support is real but is maintained as a stream of per-version workarounds rather than a settled contract: 2.4 added a workaround for the torch submodule import function and numpy 2 support ([2.4 release notes](https://nuitka.net/posts/nuitka-release-24.html)), and there is an open 4.0 issue about a torch package-config regression ([Nuitka#3760](https://github.com/Nuitka/Nuitka/issues/3760)).

The real disqualifier for your case is that Nuitka's standalone mode rewrites `sys.path` to the binary directory and ignores `PYTHONPATH`, so the obvious trick of compiling your code and pointing it at an external torch does not work ([Nuitka#3740](https://github.com/Nuitka/Nuitka/issues/3740), [#2218](https://github.com/Nuitka/Nuitka/issues/2218)). Nuitka's genuine advantage over PyInstaller is that it compiles rather than self-extracts, which measurably reduces AV false positives. That advantage is irrelevant to torch, which is shipped as prebuilt `.so` and `.pyd` files either way.

### PyOxidizer

Dead for practical purposes. Last release 0.24.0 on 2022-12-30 ([releases](https://github.com/indygreg/PyOxidizer/releases)). The maintainer has stated he is unlikely to work on it again ([discussion #737](https://github.com/indygreg/PyOxidizer/discussions/737)), and Anki, its highest profile user, opened an issue in March 2024 titled "PyOxidizer has been abandoned and will need replacing" ([anki#3081](https://github.com/ankitects/anki/issues/3081)). Not archived on GitHub, but do not build on it.

### python-build-standalone

This is the load-bearing piece and it is the healthiest thing in this list. Astral took stewardship on 2024-12-17; it powers Python installation for uv, Rye, mise, rules_python, pipx and Hatch, with over 70 million downloads ([Astral blog](https://astral.sh/blog/python-build-standalone), [repo](https://github.com/astral-sh/python-build-standalone)). Distributions are plain tarballs you extract wherever you like ([running docs](https://github.com/astral-sh/python-build-standalone/blob/main/docs/running.rst)).

It is not a packaging tool. It is the interpreter you place next to your code. That is precisely what you want here, because it composes with the fact that torch already ships as prebuilt binaries: you are moving files, not compiling anything.

### uv

uv is now the default answer for the resolve-and-install half of the problem, and is explicitly **not** an app bundler. It downloads managed CPython from python-build-standalone into a user-owned directory with no admin rights and no interference with system Python ([uv Python versions](https://docs.astral.sh/uv/concepts/python-versions/), [install-python guide](https://docs.astral.sh/uv/guides/install-python/)).

The most instructive data point in this whole report is Anki's arc. Anki went PyOxidizer, then in 25.07 to a uv-based online launcher that installed a managed Python on first run, then in 26.05b1 back to a conventional bundle via Briefcase. The stated reasons for abandoning the uv launcher were user-visible: a terminal window appearing during install and update, installation requiring network access, and accumulating "uv edge cases" ([anki#4556](https://github.com/ankitects/anki/issues/4556), [26.05b1 release](https://github.com/ankitects/anki/releases/tag/26.05b1), [forum thread](https://forums.ankiweb.net/t/new-25-07-5-launcher-process-poor-user-experience/66080)).

Read that as: use uv at build time to resolve and materialize the environments, and do not make uv a runtime dependency the end user experiences. Your constraint is that the user must not know what a virtualenv is. Anki tried the launcher route with a far simpler dependency set than yours and walked it back.

### PyApp

Worth naming because it is the strongest version of the launcher idea. A few-megabyte Rust binary that bootstraps an interpreter and installs your project on first run, from the author of Hatch ([repo](https://github.com/ofek/pyapp), [docs](https://ofek.dev/pyapp/latest/how-to/)). It is a good fit for CLIs. It has the same first run network dependency Anki rejected, and it does not solve the torch size question, it defers it.

### Briefcase / BeeWare

Still pre-1.0 at 0.4.2 as of June 2026 ([BeeWare July 2026 status](https://beeware.org/news/buzz/2026/july-2026-status-update/)). It produces MSI installers on Windows and it is now Anki's chosen path, which is meaningful validation for a desktop Python app of real complexity. Recent work added per-app isolated virtual environments, uv-managed app environments, and conda-managed app environments in review ([January 2026 status](https://beeware.org/news/buzz/january-2026-status-update/)).

I could not confirm anybody shipping torch with CUDA through Briefcase. Anki's own GPU story is not documented in the sources I reached. Treat Briefcase as a credible installer-generation layer, not as a torch solution.

### Conda: constructor and conda-pack

`constructor` builds `.sh`, `.pkg`, `.exe` and `.msi` installers from a set of conda packages ([repo](https://github.com/conda/constructor)). `conda-pack` archives an existing environment for relocation, with the caveats that the build host OS must match the target and that whatever cruft is in your env comes along ([conda-pack docs](https://conda.github.io/conda-pack/)). Anaconda's own guidance is that configuring constructor is difficult enough that they recommend professional services, which is a candid signal.

This is the family that most obviously *can* carry torch plus CUDA, because that is what the conda ecosystem was built for. The cost is that you adopt conda as your dependency substrate for the whole product, on both platforms, forever. Given that you are already standardized on pip-style resolution and that macOS needs no CUDA, this looks like a large tax for a Windows-only benefit.

### Recommendation

Use **uv at build time** to resolve each service into a directory tree on a `python-build-standalone` interpreter, and ship those trees as Tauri resources. Use PyInstaller only if you later find a reason to hide the source, and if you do, use `--onedir`. Skip Nuitka, PyOxidizer, conda and Briefcase for the backend. Briefcase is worth revisiting only if you ever want a Python-first installer independent of Tauri.

## The torch problem

### Real sizes

- torch 2.13.0 wheel on PyPI: 122.0 MB for `win_amd64`, 111.2 MB for `macosx_14_0_arm64` ([PyPI files](https://pypi.org/project/torch/#files), release 2026-07-08). These are the *wheel* sizes and they are misleading on their own, because on Linux and Windows the CUDA runtime arrives through separate `nvidia-*` wheels.
- A PyTorch maintainer's figure for the installed CUDA build is about 2.3 GB, before CUDA runtime dependencies from PyPI ([PyTorch forums](https://discuss.pytorch.org/t/pytorch-install-is-that-large-5-gbs/213629)). Users in that same thread report total disk growth of 5.1 GB and needing 5 GB free to complete an install.
- Bundled with PyInstaller: about 4 GB `--onedir`, about 2.6 GB `--onefile`, for torch 2.3 cu118 ([pyinstaller#8551](https://github.com/pyinstaller/pyinstaller/issues/8551)).
- macOS on Apple Silicon has no CUDA option at all. PyTorch's install selector offers no compute platform choice for macOS ([pytorch.org/get-started](https://pytorch.org/get-started/locally/)), and the uv PyTorch guide states plainly that PyTorch does not publish CUDA builds for macOS and shows gating on `sys_platform` accordingly ([uv PyTorch guide](https://docs.astral.sh/uv/guides/integration/pytorch/)). Your Mac artifact carries a roughly 111 MB wheel plus normal deps. Your Windows artifact carries multiple gigabytes.

So the honest framing is: **you do not have a torch size problem on macOS. You have a Windows CUDA size problem.**

### What shipping products actually do

I found no product that ships CUDA torch inside its primary installer. The pattern is consistently deferred acquisition, with the sophistication going into hiding that from the user.

- **ComfyUI Desktop** is the closest thing to your case, an Electron app whose whole job is to give non-developers a torch application. It ships a roughly 15 MB to 20 MB bootstrap standalone Python with pygit2 baked in, then provisions a per-install relocatable Python with PyTorch and GPU wheels prebuilt ([Comfy-Desktop](https://github.com/Comfy-Org/Comfy-Desktop)). Prebuilt, but provisioned, not shipped in the installer.
- **Jan**, a Tauri v2 app, does not bundle llama.cpp at all. It downloads backend binaries at runtime and picks among CPU variants (noavx, avx, avx2, avx512), CUDA and Vulkan on Windows and Linux, and Metal on macOS, using a `determineBestBackend` step that inspects CPU instruction sets, GPU memory and driver versions ([DeepWiki on Jan's llama.cpp extension](https://deepwiki.com/menloresearch/jan/4.2-llamacpp-extension)).
- **LM Studio** ships a GUI and downloads a small runtime bundle on first launch, then manages multiple engine variants (CPU-only, CUDA, Vulkan, ROCm, Metal, plus MLX on Apple Silicon) with auto-update ([LM Studio docs](https://lmstudio.ai/docs/app)).
- The Tauri plus FastAPI plus llama.cpp writeup keeps the installer compact by downloading the roughly 0.7 GB model after installation ([aiechoes](https://aiechoes.substack.com/p/building-production-ready-desktop)).

### Does shipping versus downloading matter to the user

Yes, in four specific ways, and only these four.

1. **Offline install.** Anki's users complained specifically that the launcher required network access to install ([anki#4556](https://github.com/ankitects/anki/issues/4556)). If your user installs on a machine that is online anyway to download models, this is close to moot.
2. **Failure surface.** A download can fail, resume wrong, or be corrupted. Every product above accepted that risk, which tells you it is manageable; corrupted model downloads are named as one of the most common runtime issues in the aiechoes writeup.
3. **Visible progress.** A 400 MB installer that then downloads 3 GB with a progress bar reads better than a 3.5 GB installer, as long as the progress bar is inside your UI and not a terminal. Anki's terminal window was the actual complaint, not the download itself.
4. **Correctness.** Downloading lets you pick the right CUDA build for the user's driver instead of guessing at build time. Jan's `determineBestBackend` exists for this reason.

Since you already download GGUF weights, a first run acquisition step is not a new concept in your product. The recommendation is to ship the harness venv (small, no torch if you can manage it) inside the installer, and acquire the TTS torch payload on first run into a versioned directory that the supervisor validates before starting the service.

## Two incompatible torch versions

There is no packaging approach that makes two torch versions in one process tree elegant. There are only two shapes:

**Keep them separate.** Nothing about packaging forbids this. Two Python trees, two site-packages, two processes. PyInstaller `--onedir` produces exactly this by construction. uv's `conflicts` mechanism is explicitly designed so mutually exclusive accelerator extras cannot be installed together in one environment, which is a statement that the tool does not intend to solve within-environment coexistence ([uv PyTorch guide](https://docs.astral.sh/uv/guides/integration/pytorch/)). The cost is duplicated payload. On Windows that duplication is measured in gigabytes; on macOS it is roughly 111 MB plus deps and honestly not worth worrying about.

**Converge.** This is the right answer and the cost is lower than it looks, because your CUDA 11.8 pin is already unsupported upstream. PyTorch 2.12 builds CUDA 12.6.3, 13.0 and 13.2 and removed 12.8 ([dev-discuss](https://dev-discuss.pytorch.org/t/introducing-cuda-13-2-and-deprecating-cuda-12-8-release-2-12/3337)); 2.13 removed 12.8 and 12.9 and keeps 13.0 as default ([2.13 blog](https://pytorch.org/blog/pytorch-2-13-release-blog/)); PyPI CUDA wheels moved to 13.0 as stable at 2.11 ([dev-discuss](https://dev-discuss.pytorch.org/t/transitioning-pypi-cuda-wheels-to-cuda-13-0-as-the-stable-release-2-11/3325)); and conda-forge dropped 11.8 as a default on 2025-06-05 ([conda-forge](https://conda-forge.org/news/2025/05/29/cuda-118/)). Note that the pytorch.org install selector page I fetched still lists a cu118 option, which I could not reconcile against the release notes; either way, staying on 11.8 means staying on a build line the project has moved past.

The real convergence cost is whatever in the harness venv pinned you to 11.8 in the first place. That is almost always one dependency with a compiled extension built against an old CUDA, or a driver constraint on a specific machine. Find that one thing. Converging on torch 2.13 with CUDA 13.0 also halves your Windows download and removes an entire class of supervision bug, because you go from two GPU-holding Python processes to one.

Blunt version: shipping two torch builds to end users so that a development-time pin can survive is the wrong trade. Converge.

## Tauri sidecars

### What the mechanism is

`bundle.externalBin` takes a list of paths; each entry needs one file per target with a `-$TARGET_TRIPLE` suffix, for example `my-sidecar-x86_64-pc-windows-msvc.exe` or `my-sidecar-aarch64-apple-darwin`. Spawning requires an explicit capability grant, `shell:allow-execute` or `shell:allow-spawn`, naming the binary with `"sidecar": true`. Arguments must be declared in the capability as static values or regex validators ([Tauri sidecar docs](https://v2.tauri.app/develop/sidecar/)). The docs mention no size limit.

Getting the target triple suffix wrong is the single most common failure; the executable simply is not found ([aiechoes](https://aiechoes.substack.com/p/building-production-ready-desktop), [dev.to writeup](https://dev.to/chenxxpro/bundling-a-cli-binary-as-a-tauri-v2-sidecar-lessons-from-building-a-desktop-app-5po)).

### Can it supervise a multi-process backend

It can spawn and it can kill. It does not supervise. From Rust you call `app.shell().sidecar(name).spawn()`, which returns a receiver plus a `CommandChild` handle you are responsible for storing in app state and killing on shutdown ([Tauri sidecar docs](https://v2.tauri.app/develop/sidecar/)).

Everything past that is yours. The open feature request for `tauri-plugin-sidecar-lifecycle`, filed 2025-10-23 by the Mediar team out of production experience, enumerates what every Tauri app currently reimplements: crash detection with auto-restart, port conflict resolution, health checking before use, graceful shutdown, orphan cleanup, and cross-platform signal handling. Its status is open with no assigned development ([plugins-workspace#3062](https://github.com/tauri-apps/plugins-workspace/issues/3062)). Independently, developers report trouble fully closing PyInstaller sidecars on app close and resort to parent-process-alive polling from inside the child ([tauri discussion #2759](https://github.com/orgs/tauri-apps/discussions/2759)).

This is the strongest argument for your Rust supervisor being the sidecar and owning the other three processes itself, rather than Tauri spawning four sidecars.

### Real examples

- **Jan** (Tauri v2, local LLM app): ships Cortex as a sidecar binary across both its Electron and Tauri builds, but downloads the llama.cpp backends at runtime rather than bundling them ([DeepWiki](https://deepwiki.com/menloresearch/jan/4.2-llamacpp-extension)). Confirmed shipping product, and it chose *not* to bundle the heavy part.
- **Hyprnote** (Tauri 2.x, local-first meeting notes): Rust and TypeScript monorepo, actor-based concurrency via the `ractor` crate for long-running stateful processes, local STT through a `tauri-plugin-local-stt` plugin and a local LLM plugin ([DeepWiki](https://deepwiki.com/fastrepl/hyprnote)). No Python in the desktop app. This is the all-Rust shape working in a shipping product.
- The **Tauri plus FastAPI plus PyInstaller** writeup is a real build with real numbers, but its backend is 35 MB to 40 MB and its model is downloaded ([aiechoes](https://aiechoes.substack.com/p/building-production-ready-desktop)).
- **dieharders/example-tauri-v2-python-server-sidecar** is the canonical reference implementation of a PyInstaller FastAPI sidecar under Tauri v2 ([repo](https://github.com/dieharders/example-tauri-v2-python-server-sidecar)).

I found no example of a Tauri app bundling multi-gigabyte torch payloads as sidecars. That absence is itself the finding.

### Signing and notarization limits

This is where sidecars actually hurt, and it is macOS-specific.

- There is an open Tauri bug, [tauri#11992](https://github.com/tauri-apps/tauri/issues/11992), filed with a minimal reproduction: adding any `externalBin` causes notarization to fail with an invalid signature error, and removing `externalBin` makes notarization succeed. Still open, no official workaround in the thread, and the reporter's fallback was to drop sidecars entirely.
- Notarization validates the entire bundle. Apple's guidance is inside-out signing of every nested bundle and Mach-O, with a secure timestamp, and notarization reports improperly signed frameworks, dylibs and other binaries as failures ([WWDC19 All About Notarization](https://developer.apple.com/videos/play/wwdc2019/703/), [Apple forums thread 679044](https://developer.apple.com/forums/thread/679044)). Hardened runtime is required for executables, not for dylibs.

Apply that to a shipped Python tree: every `.so` in site-packages is a Mach-O that must be signed. A torch install has hundreds. This is scriptable and people do it, but budget for it as a real build-system task, not a checkbox. It is another argument for the macOS build having no torch in it.

- Tauri does not build universal binaries for your sidecars. If you need Intel plus Apple Silicon you produce both slices yourself ([community writeup](https://dev.to/0xmassi/shipping-a-production-macos-app-with-tauri-20-code-signing-notarization-and-homebrew-mc3)). You said Apple Silicon only, so this is avoidable.

On Windows the situation is milder. There is no equivalent deep-signing gate. The relevant fact is that since 2024 Microsoft no longer grants EV-signed binaries instant SmartScreen reputation, so EV and OV both build reputation over downloads ([Microsoft Learn code signing options](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options)). Sign the installer, expect a warning period, and avoid PyInstaller `--onefile` which independently attracts AV heuristics.

## Process supervision without systemd

A Rust supervisor process is the normal answer, and every comparable product has written one.

**Ollama** is the clearest reference implementation, in Go rather than Rust but structurally identical to what you need. Runners execute in separate processes from the main server for isolation; the main process spawns them and talks to them over localhost HTTP; `llamaServerRunner` wraps the `llama-server` binary as an `os/exec.Cmd` and models the lifecycle as explicit states of launched, loading model, ready when `/health` returns ok, and no slots available; a scheduler unloads models on an idle timer; and the manager monitors child health and restarts on failure, with subprocess isolation meaning a failing inference cannot crash the management layer ([DeepWiki on Ollama's LlamaServer and runner](https://deepwiki.com/ollama/ollama/5.2-llamaserver-and-runner-implementation), [scheduling](https://deepwiki.com/ollama/ollama/2.2-request-scheduling-and-runner-management)).

**LM Studio** moved in the same direction, introducing a headless daemon called `llmster` in v0.4+ that decouples the GUI from inference ([overview](https://codersera.com/blog/lm-studio-complete-guide-2026/)). The GUI is a client of the daemon rather than its parent.

**Tauri** offers you nothing here, as covered above ([plugins-workspace#3062](https://github.com/tauri-apps/plugins-workspace/issues/3062)).

Design notes that fall out of this:

- Dependency order is expressed as health gating, not as sleeps. Ollama's `getServerStatus` polling `/health` until ok is the pattern to copy. Your llama-server has a `/health` endpoint already, and FastAPI gives you one for free.
- Orphan cleanup is the piece people get wrong, and it is platform-specific. On Windows the reliable mechanism is a Job Object created at startup with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, so the kernel kills the whole tree when the handle closes, with no polling. PostgreSQL adopted exactly this for the same reason ([patch on pgsql-hackers](https://www.postgresql.org/message-id/attachment/184076/v2-0001-Use-Windows-Job-Objects-to-prevent-orphaned-child.patch)). The `processkit` crate packages this for tokio, using Job Objects on Windows and cgroup v2 or POSIX process groups elsewhere ([docs.rs](https://docs.rs/processkit/latest/processkit/)). Whether you take the crate or write the twenty lines yourself, do not rely on Tauri killing your grandchildren.
- Port allocation should be dynamic and passed down, not fixed. Port conflicts are named as a top runtime failure in both the Tauri sidecar writeup and the lifecycle plugin request.
- Keep the supervisor's own dependencies boring. It already uses tokio; `tokio::process` plus a Job Object plus an HTTP health poll is the entire mechanism.

Your existing Rust supervisor is the right architecture. The change is that it becomes the Tauri sidecar and the sole parent of the other three processes, rather than four peers spawned by Tauri.

## The all-Rust option

Taken component by component, honestly.

### llama-server

Already solved, and not by rewriting. Upstream publishes prebuilt binaries for Windows x64 and arm64 across CPU, CUDA 12, CUDA 13 and Vulkan, and macOS arm64 ([llama.cpp releases](https://github.com/ggml-org/llama.cpp/releases)). Jan and LM Studio both consume these rather than building. Keep it as a supervised binary. Rust bindings exist if you ever want in-process inference: `llama-cpp-2` is the actively maintained one ([crates.io](https://crates.io/crates/llama-cpp-2)), and `llama-cpp-rs` tracks upstream closely ([repo](https://github.com/eugenehp/llama-cpp-rs)). Both carry the caveat that they track a fast-moving C++ library and break between versions ([llama_cpp docs](https://docs.rs/llama_cpp)). There is no reason to take that on when the binary works.

### Whisper

Real, mature, and the clearest win. `whisper-rs` provides bindings to whisper.cpp with CUDA and ROCm GPU support and is actively maintained with no plans to discontinue ([crates.io](https://crates.io/crates/whisper-rs), [lib.rs](https://lib.rs/crates/whisper-rs)). It is used in a shipping Tauri product: Hyprnote does local STT in Rust with no Python in the desktop app ([DeepWiki](https://deepwiki.com/fastrepl/hyprnote)).

Since your Whisper is currently in-process Python, moving it into the Rust supervisor is the single highest ratio of Python removed to risk taken in this whole list. Do this one first.

### Harness (FastAPI)

This is plain application code with no ML dependency. Nothing blocks a rewrite into axum, and nothing forces one either. It is the cheapest Python to keep and the least interesting to port. Decide it on maintenance grounds, not packaging grounds, because a torch-free Python tree is small enough to ship without complaint.

### TTS with voice cloning

This is the honest gap, and it is smaller than it was a year ago but it is not closed.

There is a direct Rust port of your engine. `neutts-rs` is a Rust port of NeuTTS with a GGUF backbone and the NeuCodec decoder, claiming pure Rust with no ONNX Runtime or native ML dependency, streaming synthesis, pure-Rust phonemization for 114 languages, and optional GPU via `wgpu` on Metal, Vulkan and DX12 with fallback to Burn NdArray on CPU ([repo](https://github.com/eugenehp/neutts-rs), [crates.io](https://crates.io/crates/neutts)).

Now the caveats, which matter more than the feature list. It is at version 0.1.0, it has 4 stars and 1 fork, it is one person's project, and by its own README the **NeuCodec encoder is not yet implemented in Rust**, so the example falls back to Python `neucodec`. The encoder is the voice-cloning path, the step that turns a reference WAV into conditioning. It caches per voice, so if you pre-encode your voices at build time you never need the encoder at runtime, which would make this usable. That is a real strategy and it is worth a spike. It is not a thing you can depend on shipping without doing that spike first.

Broader Rust TTS landscape, all young: `any-tts` wraps VibeVoice-1.5B with reference-audio conditioning and optional cloning when the checkpoint has style-encoder weights ([lib.rs](https://lib.rs/crates/any-tts)); `qwen3-tts-rs` does voice cloning from reference audio but its backends are libtorch through the `tch` crate, or MLX on Apple Silicon ([repo](https://github.com/second-state/qwen3_tts_rs)). Note what that means: `tch` links libtorch, so it does not remove the torch payload, it only removes the Python around it.

**The pragmatic middle path is ONNX, not Rust.** `sherpa-onnx` runs STT, TTS, diarization and VAD on onnxruntime with no internet, supports 7 TTS model families including zero-shot voice cloning, is callable from 12 languages, and has a Rust crate ([repo](https://github.com/k2-fsa/sherpa-onnx), [crates.io](https://crates.io/crates/sherpa-onnx), [DeepWiki TTS](https://deepwiki.com/k2-fsa/sherpa-onnx/3.2-text-to-speech-(tts))). Separately, zero-shot cloning models with published ONNX exports now exist, for instance a 0.6B multilingual model with INT4 ONNX weights reported at roughly 1.1 GB to 1.2 GB peak memory on an M2 MacBook Air ([Hugging Face](https://huggingface.co/Audio8/Audio8-TTS-Preview-0.6B-ONNX-INT4)), and OpenVoice v2 has community ONNX exports under MIT. The general size argument is stark: the ONNX Runtime CPU wheel is around 15 MB against a minimal PyTorch install around 1 GB ([pydevtools](https://pydevtools.com/handbook/explanation/how-do-i-ship-a-python-application-to-end-users/)).

### Summary of the all-Rust option

Not a fantasy, but not one project either. Ranked by ratio of payoff to risk:

1. Whisper to `whisper-rs` in the supervisor. Low risk, removes torch's speech-side justification, proven in a shipping Tauri app.
2. llama-server stays a supervised prebuilt binary. Already done, do not change it.
3. TTS off torch. Either the ONNX route, which is available today and kills the multi-gigabyte CUDA payload outright, or the `neutts-rs` route with pre-encoded voices, which needs a spike before you can trust it.
4. FastAPI harness to axum. Optional, and only worth doing once it is the last Python left.

If steps 1 and 3 land, torch leaves the product, the two-incompatible-versions question dissolves, the Windows installer drops by gigabytes, and the macOS notarization problem shrinks to signing a handful of binaries instead of a site-packages tree. That is the version of this plan actually worth pursuing.

## What I could not determine

- **How Anki ships GPU-accelerated components, if at all.** The launcher and Briefcase discussions cover Python and Qt, not torch. I could not confirm any Briefcase-packaged product shipping CUDA torch.
- **Whether tauri#11992 has since been fixed.** The issue page I fetched shows it open with no official workaround. Many Tauri apps clearly do ship notarized sidecars, so either there is a build-configuration workaround not captured in that thread or the bug is conditional. I could not resolve the contradiction.
- **Exact `nvidia-*` wheel sizes.** The PyPI pages did not render file listings through the fetch tool. The 2.3 GB core plus roughly 5 GB total figures come from the PyTorch maintainer and user reports on the forums, not from summing wheel sizes.
- **Whether cu118 wheels are still published.** The pytorch.org install selector page I fetched still offered CUDA 11.8, which contradicts the 2.11 through 2.13 release notes. That page may have been served from cache. Verify directly against `https://download.pytorch.org/whl/cu118/` before planning around it.
- **`neutts-rs` quality under load.** I read its README and metadata. I did not build it, benchmark it, or verify the pre-encoded-voice workaround actually avoids the missing encoder. That is a spike, not a search.
- **Real installed sizes for the two Hearth Python services.** Everything in the torch section is from public reports. Measure your own two venvs before choosing a size budget; you may find the harness venv has no real torch dependency at all, which would change the recommendation.
- **Current status of the `sherpa-onnx` Rust crate specifically.** I confirmed the upstream project is active and that a crate exists. I did not verify the crate's binding coverage, freshness relative to upstream, or whether the zero-shot cloning models are reachable through the Rust API rather than only C++ and Python.
