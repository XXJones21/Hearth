# Container and GPU feasibility for Hearth, August 2026

Scope: can the Hearth backend (llama-server with a resident GGUF, a Python torch diffusion TTS service, a Rust supervisor, a FastAPI harness) ship as one containerized package to Windows/NVIDIA and macOS/Apple Silicon.

## Verdict up front

**Windows: yes, with a caveat that changes the value proposition. macOS: no.**

A single unified container package covering both targets is not achievable in August 2026. The blocking facts:

1. **There is no GPU passthrough to containers on macOS, and there is no path to one.** Docker states this in its own product documentation: "Metal GPU access requires direct hardware access and there is no GPU passthrough for Metal in containers" ([Docker blog, 2026-02-26](https://www.docker.com/blog/docker-model-runner-vllm-metal-macos/)). Apple's own container maintainer said "we do not currently support this" and a commenter identifies the hardware reason: "Apple GPUs are not behind an IOMMU and cannot be passed through to a guest" ([apple/container discussion 62](https://github.com/apple/container/discussions/62)). Docker's response to its own limitation was to run the inference engine natively on the host instead.

2. **Docker on Windows does not remove a WSL2 dependency, it adds Docker on top of one.** Docker's documentation is unambiguous: "GPU support in Docker Desktop is only available on Windows with the WSL2 backend" ([Docker Docs](https://docs.docker.com/desktop/features/gpu/)). The alternative, native Windows containers, supports only DirectX and explicitly not CUDA ([Microsoft Learn](https://learn.microsoft.com/en-us/virtualization/windowscontainers/deploy-containers/gpu-acceleration)).

3. **Docker Desktop cannot be redistributed.** The Docker Subscription Service Agreement permits redistributing Docker *Images* bundled into your product, but grants no equivalent right for Docker Desktop itself ([DSSA](https://www.docker.com/legal/docker-subscription-service-agreement/)). Every end user installs and licenses it themselves.

The consequence: any cross-platform Hearth package must contain a **native, non-containerized GPU component on macOS**. Once that is accepted, containers on Windows are a choice about Windows packaging convenience, not about architectural uniformity, because the two platforms will not share a deployment shape regardless.

The most interesting finding in this research is item 4 below. On Windows, `.wsl` is a real, Microsoft-supported, double-click-installable distribution format that gives CUDA access with zero container tooling. It is a genuine candidate for the Windows package.

---

## Windows

### GPU access requires the WSL2 backend, confirmed

Docker's prerequisites, verbatim from [docs.docker.com/desktop/features/gpu](https://docs.docker.com/desktop/features/gpu/):

> To enable WSL 2 GPU Paravirtualization, you need:
> - A Windows machine with an NVIDIA GPU
> - Up to date Windows 10 or Windows 11 installation
> - Up to date drivers from NVIDIA supporting WSL 2 GPU Paravirtualization
> - The latest version of the WSL 2 Linux kernel. Use `wsl --update` on the command line
> - To make sure the WSL 2 backend is turned on in Docker Desktop

And: "GPU support in Docker Desktop is only available on Windows with the WSL2 backend." The Hyper-V backend is not mentioned as an option. Podman Desktop states the same constraint independently for its own Windows path: "WSL2 (Hyper-V not supported)" ([Podman Desktop GPU docs](https://podman-desktop.io/docs/podman/gpu)).

**The claim to confirm is confirmed.** Choosing Docker on Windows means the user needs WSL2 installed and working, plus Docker Desktop, plus a GPU-capable image. It is strictly additive to the WSL2 dependency Hearth already has.

### Windows containers are not an escape hatch

GPU acceleration in native Windows containers requires process isolation mode, and "DirectX (and all the frameworks built on top of it) are the only APIs that can be accelerated with a GPU today, and 3rd party frameworks are not supported." GPU acceleration in Hyper-V isolated Windows containers is not supported ([Microsoft Learn](https://learn.microsoft.com/en-us/virtualization/windowscontainers/deploy-containers/gpu-acceleration)). CUDA is out. This route is dead for llama.cpp and torch.

### What the end user must install for the NVIDIA Container Toolkit

Two paths, with different requirements, and the sources genuinely disagree on one of them.

**Path A, Docker Desktop.** Docker's GPU prerequisites list does not mention the NVIDIA Container Toolkit at all; it lists drivers, the WSL2 kernel, and the WSL2 backend toggle ([Docker Docs](https://docs.docker.com/desktop/features/gpu/)). This implies Docker Desktop supplies the runtime hook. NVIDIA's CUDA on WSL User Guide, however, lists "NVIDIA Container Toolkit - Minimum versions - v2.6.0 with libnvidia-container - 1.5.1+" as a requirement and notes "CLI and Docker Desktop Supported" without distinguishing installation location ([NVIDIA CUDA on WSL guide](https://docs.nvidia.com/cuda/wsl-user-guide/index.html)). There is also a hard version floor: NVIDIA warns that "Windows WSL users will fail execution on the GPUs from containers if they are running Docker Desktop versions older than 4.31.1" ([NVIDIA developer forums](https://forums.developer.nvidia.com/t/windows-wsl-docker-desktop-users-must-update-to-docker-desktop-v4-31-1/299421)).

**Path B, Docker Engine or Podman inside a WSL distro.** The toolkit must be installed manually, inside the Linux distribution, not on the Windows host. Podman additionally requires generating a CDI specification: `sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml`, and if using a Podman machine, the CDI spec must live inside `podman-machine-default` rather than the user's own distro ([Podman Desktop GPU docs](https://podman-desktop.io/docs/podman/gpu), [oneuptime](https://oneuptime.com/blog/post/2026-03-18-run-nvidia-gpu-containers-podman/view)).

**One rule is universal and worth encoding in any installer:** the user must not install a Linux NVIDIA driver inside WSL. NVIDIA: "users must not install any NVIDIA GPU Linux driver within WSL 2" and "Do not install any Linux display driver in WSL." The Windows driver is stubbed into WSL as `libcuda.so` ([NVIDIA CUDA on WSL guide](https://docs.nvidia.com/cuda/wsl-user-guide/index.html)). This is the single most common way users break their own CUDA-in-WSL setup.

### Licensing

Docker Subscription Service Agreement, Section 4.2, quoted:

> The use of Docker Desktop without a paid Subscription, is further restricted (i) to use for a non-commercial open source project and/or (ii) use in a commercial undertaking with fewer than 250 employees and less than US $10,000,000 (or equivalent local currency) in annual revenue.

Government entities are explicitly excluded from free use ([DSSA](https://www.docker.com/legal/docker-subscription-service-agreement/), [Docker Desktop license docs](https://docs.docker.com/subscription/desktop-license/)). Paid tiers run roughly $9 to $24 per user per month.

On redistribution, the agreement permits: "Customers may redistribute Docker Images to third parties but solely when bundled with or incorporated into its own software products, and not on a standalone basis." There is no parallel grant for Docker Desktop. **You may ship images. You may not ship the runtime.** Each Hearth user therefore has to acquire Docker Desktop themselves and independently satisfy the free-tier thresholds. For a consumer or prosumer product most users will qualify, but any user at a company over 250 employees who installs Hearth at work is out of compliance unless their employer holds licenses. That is a support burden and a legal footgun you would be handing to your users.

### Friction and disk

Docker Desktop requires roughly 6 GB of disk for installation, with a ~640 MB installer, but "real-world stacks reach 20 to 40 GB once databases, language images, and build layers accumulate" ([usedocker system requirements](https://usedocker.com/system-requirements)). Steps for a non-technical user, per Docker's own install docs and third-party guides: enable virtualization in BIOS if not already on, run `wsl --install` (reboot), download and run `Docker Desktop Installer.exe`, allow the wizard to configure WSL2, log out and back in for group membership, launch Docker Desktop, wait for the whale icon, then verify with `docker run hello-world` ([Docker Docs install](https://docs.docker.com/desktop/setup/install/windows-install/), [geeksforgeeks](https://www.geeksforgeeks.org/cloud-computing/how-to-install-docker-on-windows/)).

For Hearth specifically, add on top of that: a CUDA-runtime base image plus a torch stack, which routinely runs 6 to 10 GB compressed before your own code, plus the GGUF weights. Realistically you are asking a user for 30 GB or more and a BIOS visit. Six or seven discrete steps, at least two of which (BIOS virtualization, log out and back in) are where non-technical users stall.

---

## macOS

Be precise here, because the naive statement and the accurate statement differ.

### The naive claim is correct in effect, but the mechanism matters

Docker Desktop on macOS runs containers inside a Linux VM, and the Apple GPU cannot be presented to that VM as a device. Docker says so directly ([Docker blog, 2026-02-26](https://www.docker.com/blog/docker-model-runner-vllm-metal-macos/)). Apple's `container` tool does not support it; maintainer `egernst` replied "we do not currently support this" on 2025-06-09, and the hardware reason given in the same thread is that "Apple GPUs are not behind an IOMMU and cannot be passed through to a guest" ([apple/container discussion 62](https://github.com/apple/container/discussions/62)). Apple's `container` was introduced at WWDC 2025 and was at version 0.11.0 as of March 2026, using a one-VM-per-container model; it still lacks Compose support ([Wikipedia](https://en.wikipedia.org/wiki/Apple_container)).

### But there IS a way to get GPU work out of a Linux container on Apple Silicon, and it is not passthrough

Two distinct mechanisms exist, and both work by **shipping the GPU work back to a host process**. Neither is passthrough; both mean you still have a native macOS component.

**1. Vulkan via virtio-gpu and Venus (libkrun/krunkit).** Podman Desktop officially documents this: on a Mac with Apple Silicon, using a Podman machine backed by `libkrun`, you get "a virtualized GPU from within the Podman Machine that provides translation support from Vulkan and MoltenVK calls to MSL (Metal Shading Language)." Stated limitations: it "only supports vulkan compute shaders, not rendering / draw," and it requires a specialized Containerfile with a patched MESA driver from a Fedora COPR repository ([Podman Desktop GPU docs](https://podman-desktop.io/docs/podman/gpu)).

Measured cost, on an M2 Max, running llama.cpp ([ggml-org/llama.cpp discussion 12985](https://github.com/ggml-org/llama.cpp/discussions/12985)):

| | pp512 | tg128 |
| --- | --- | --- |
| Native Metal | 746 t/s | 71.36 t/s |
| Container, Vulkan via Venus | 428.47 t/s (57%) | 35.88 t/s (50%) |

The author's summary: "the overhead vs. running llama.cpp directly is still significant. In my M2 Max based tests they are approx. 40% slower." That is on an M2 Max. There is no published M1 MacBook Air number. Also note this delivers Vulkan compute only, which does nothing for the torch TTS service.

**2. ggml API remoting (Red Hat).** Rather than remoting the graphics API, this remotes the ggml library calls themselves: `ggml-remotingfrontend` in the container, a modified virglrenderer, and `ggml-remotingbackend` on the host invoking `ggml-metal`. On an M4 Pro this reaches native prompt-processing speed and roughly 95 percent of native token generation on smaller models (151.59 t/s native vs 145.29 t/s remoted). It requires Podman Desktop with a specific remoting extension build, RamaLama 0.12+, and a krunkit-backed machine, and is explicitly a preview whose next step is upstreaming into llama.cpp and virglrenderer ([Red Hat Developer, 2025-09-18](https://developers.redhat.com/articles/2025/09/18/reach-native-speed-macos-llamacpp-container-inference)).

**3. container-toolkit-mlx.** Same architecture, MLX flavored: a Swift gRPC daemon on the host with Metal access, a Python client in the container, AF_VSOCK transport, roughly 95 percent of native MLX throughput on an M5 ([RobotFlow-Labs/container-toolkit-mlx](https://github.com/RobotFlow-Labs/container-toolkit-mlx)). The repo has 15 commits and 4 stars and describes itself as "in active early development." Not shippable.

**What all three prove is the same thing:** the fastest known way to use the Apple GPU "from a container" is to not use it from the container. The model runs in a host process either way. Every one of these approaches requires you to install and maintain a native macOS binary, and then adds an RPC boundary, a patched Mesa driver, or a preview-grade extension on top. You would be paying the full cost of a native component and the full cost of a container, for a result slower than native.

Docker itself reached this conclusion and shipped it as product. `vllm-metal` "runs natively on the host. This is necessary because Metal GPU access requires direct hardware access and there is no GPU passthrough for Metal in containers." Docker Model Runner pulls a Docker image containing a self-contained Python 3.12 environment, extracts it to `~/.docker/model-runner/vllm-metal/`, and runs it as a host process ([Docker blog, 2026-02-26](https://www.docker.com/blog/docker-model-runner-vllm-metal-macos/)).

### What CPU-only inference costs on an M1 MacBook Air

llama.cpp on base M1 (8 GPU cores), LLaMA 7B Q4_0, Metal backend ([ggml-org/llama.cpp discussion 4167](https://github.com/ggml-org/llama.cpp/discussions/4167), commit 8e672ef):

- pp512: 117.96 t/s
- tg128: 14.15 t/s

Note how modest that already is. The M1 base has 68 GB/s memory bandwidth, and 14 t/s generation is the *good* case.

For the CPU-only comparison I could not find a published M1 MacBook Air `-ngl 0` benchmark. The best-sourced ratios available: "Metal GPU inference is 3-5x faster than CPU-only on Apple Silicon," with a concrete example of Qwen 3.5 9B Q4_K_M at approximately 28 tok/s on M3 Pro with Metal versus 7 tok/s CPU-only ([CloudAtler](https://cloudatler.com/blog/llama-cpp-metal-on-apple-silicon-the-complete-architectural-finops-review)). Applying that to the M1 numbers above puts CPU-only 7B generation in the region of 3 to 5 t/s. That is below conversational usability for a voice product.

The prompt-processing number is the one that actually kills it. Text generation on Apple Silicon is memory-bandwidth bound, so CPU degrades but does not collapse. Prompt processing is compute bound, so it does. A persona system prompt plus conversation history means every turn pays that cost, and the sub-second first-audio target Hearth already achieved on the 4080 is not reachable.

**Model size is a separate hard wall.** An M1 MacBook Air at 8 GB "is best treated as a small-model machine, suitable for 3B to 8B quantized models and shorter context windows"; at 16 GB, "the optimal size of model is around 7 billion parameters" and 13B-class models "push the machine to the limit" ([MacMyths](https://macmyths.com/local-llms-apple-silicon-mac-2026-m1-m2-m3-guide/), [Medium/Dennis Layton](https://medium.com/@dlaytonj2/can-you-run-a-large-language-model-llm-locally-on-an-m1-macbook-air-with-only-16-gb-of-memory-cd9741af27bb)). A 12B on an 8 GB M1 Air does not fit at all. Whether containerized or not, the M1 Air target implies a 4B class model.

### Is a torch diffusion TTS model viable on CPU at all?

Marginally, and not without work you have not done. Real Time Factor below 1.0 means faster than real time. Diffusion TTS requires multiple denoising steps per synthesis, which is exactly the workload CPUs are worst at. There is a research literature specifically about making this possible: Fast Grad-TTS exists to address diffusion TTS on CPU ([Interspeech 2022](https://www.isca-archive.org/interspeech_2022/vovk22_interspeech.pdf)). One reported optimization path took a TTS model from RTF 0.44 to 0.09, but through deliberate quantization and distillation work ([Medium/mllopartbsc](https://medium.com/@mllopart.bsc/optimizing-a-multi-speaker-tts-model-for-faster-cpu-inference-part-1-165908627829)).

Relevant history from your own stack: NeuTTS-Air sat at RTF 4.4x when llama-cpp-python was a CPU-only wheel, and only reached RTF 0.4x after a CUDA source build. That is direct, measured evidence from this project that the CPU path for this class of model is roughly an order of magnitude off real time. An unoptimized torch diffusion TTS on an M1 Air CPU will not be usable for a live voice loop.

**Combined macOS conclusion:** a container on Apple Silicon gets no GPU. CPU fallback is not viable for either GPU component. The only workable macOS architecture puts both llama-server and the TTS service natively on the host with Metal.

---

## The WSL image as a distribution format

This is a real, first-class, Microsoft-supported format, and it is materially better than I expected. It deserves serious consideration as the Windows package.

### What it actually is

Since **WSL release 2.4.4**, "WSL distributions are defined by a tar file with a `.wsl` file extension on Windows." The tar contains a complete Linux root filesystem plus WSL configuration files that tell Windows how to install and launch it ([Microsoft Learn, build-custom-distro](https://learn.microsoft.com/en-us/windows/wsl/build-custom-distro), page dated 2025-09-12, updated 2026-06-02).

Two config files ship inside the image:

- `/etc/wsl-distribution.conf` controls first-launch behavior. Keys include `oobe.command` (a script that runs the first time the user opens a shell, and if it returns non-zero the user cannot get a shell, so it is a real gate), `oobe.defaultUid`, `oobe.defaultName`, `shortcut.enabled` and `shortcut.icon` (a Start Menu shortcut with your icon, `.ico`, max 10 MB), and `windowsterminal.profileTemplate` (a custom Windows Terminal profile).
- `/etc/wsl.conf` sets per-distro system settings including `boot.systemd=true`.

### The end-user install experience

Three supported routes, per the same Microsoft doc:

1. **Double-click.** "Once the tar has be renamed from `.tar` to `.wsl`, the file will install correctly on Windows when opened (double-clicked) in File Explorer. A `oobe.defaultName` entry is required in the `/etc/wsl-distribution.conf` file for this double-click experience to function properly."
2. **One command.** `wsl --install --from-file <fileLocation>`.
3. **Registry-scoped manifest.** `HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss\DistributionListUrl` or `DistributionListUrlAppend` can point at your own JSON manifest, making `wsl --install hearth` work and giving you a versioned update channel (`hearth-v1`, `hearth-v2`, with a `Default` flag). Microsoft documents this explicitly as the mechanism for "your enterprise or business group," and `file://` URLs are supported from 2.4.4 for local testing.

So the end user experience can be: install WSL if absent, download `Hearth.wsl`, double-click, answer an OOBE prompt. Compare that to the Docker path (BIOS, WSL, Docker Desktop installer, re-login, image pull, compose up).

### Why this is genuinely attractive for Hearth specifically

- **CUDA works with no container tooling whatsoever.** The Windows NVIDIA driver stubs `libcuda.so` into WSL at `/usr/lib/wsl/lib/`. No NVIDIA Container Toolkit, no CDI spec generation, no `nvidia-ctk`, no `--gpus all`, no Docker Desktop version floor. `llama-server` compiled for CUDA simply runs ([NVIDIA CUDA on WSL guide](https://docs.nvidia.com/cuda/wsl-user-guide/index.html)).
- **No Docker licensing question at all.** Nothing to redistribute, no per-user thresholds, no government-entity exclusion.
- **systemd is supported** via `boot.systemd=true`, which means the always-on stack Hearth already uses (`valar.service`) transplants directly rather than being re-expressed as container orchestration.
- **You already build and run in WSL.** The image is close to a snapshot of an environment you have already debugged, rather than a new abstraction to learn.
- **It is one artifact.** That is literally the stated goal.

### The honest costs

- **It does not remove the WSL2 dependency, it commits to it.** Same as Docker, but without the extra layer. If the objection to WSL was "users should not need WSL," this does not answer it.
- **Size and compression.** Microsoft recommends gzip: "The recommended compression format is gzip. Other compression formats run the risk of breaking compatibility with older WSL versions." A rootfs containing a CUDA runtime, torch, llama.cpp, and Python is multiple GB, and gzip is a weak compressor for that payload. The tar must contain the root of the filesystem, not a directory containing it, and must not contain a kernel or initramfs.
- **Updates are entirely your problem.** There is no layer model and no diffing. Either you ship a whole new `.wsl` (multi-GB re-download for a Python-side fix) or you build an in-distro updater, which is the more sensible design but is code you write and maintain. The manifest route gives you version *listing*, not incremental delivery.
- **The distro is a growing VHDX.** WSL disks expand and do not automatically reclaim space. Model swaps and cache churn will grow it, and users will need a documented compaction step.
- **systemd unit hygiene is required.** Microsoft lists units that must be disabled or masked: `systemd-resolved.service`, `systemd-networkd.service`, `NetworkManager.service`, the `systemd-tmpfiles-*` units, and `tmp.mount`. Also do not include `/etc/resolv.conf`, do include a uid 0 root in `/etc/passwd`, and leave no password hashes in `/etc/shadow`.
- **Windows only.** macOS gets nothing from this. You will build a second, different package for Mac regardless.
- **Weaker isolation than a container**, which for a local-first product on a user's own machine is arguably a non-issue, but it is a real difference.
- **Reproducibility depends on your build process, not the format.** A `.wsl` file is a filesystem snapshot. If you want the image to be reproducible you need something like Nix, pixi, or a scripted debootstrap producing it. The format itself gives you distribution, not determinism.

### Assessment

For Windows, this is a stronger option than Docker for Hearth. It removes Docker Desktop, its licensing, the container toolkit, and CDI, while preserving CUDA and systemd, and delivers a genuinely one-double-click install. The cost you take on is update delivery, which you should build as an in-distro updater from day one rather than as whole-image replacement.

---

## Alternatives assessed

**Podman and podman-compose.** On Windows: same WSL2 requirement as Docker, Hyper-V explicitly unsupported, plus manual NVIDIA Container Toolkit installation and CDI spec generation inside the machine, and the confusing detail that the spec must live in `podman-machine-default` rather than the user's own distro ([Podman Desktop](https://podman-desktop.io/docs/podman/gpu)). Net: more setup steps than Docker Desktop, not fewer. What you gain is the absence of the Docker license. On macOS: the libkrun path described above, Vulkan compute shaders only, patched Mesa from a COPR repo, roughly half of native speed on an M2 Max, and nothing at all for torch TTS. Not a solution to the stated problem on either platform.

**Rootless containers.** Do not pursue for this product. NVIDIA CDI in rootless mode has long-standing unresolved problems: CDI injection failing rootless regardless of cgroup setting ([podman issue 17539](https://github.com/containers/podman/issues/17539)), "unresolvable CDI devices" errors ([nvidia-container-toolkit issue 434](https://github.com/NVIDIA/nvidia-container-toolkit/issues/434)), and a config conflict where `no-cgroups = true` makes rootless work but breaks rootful GPU access with "Failed to initialize NVML: Unknown Error." Workarounds exist (`--cdi-spec-dir` pointing at a user-space spec) but they are the kind of thing a support forum solves for one user at a time. Shipping this to non-technical users is not viable.

**WSL distro export/import as the package.** Covered in full above. Best Windows candidate.

**Nix.** Real reproducibility, and the ComfyUI-Nix flake demonstrates the exact shape you want, supporting macOS with Metal and Linux with CUDA from one flake ([utensils/comfyui-nix](https://github.com/utensils/comfyui-nix)). The problems: Nix does not run natively on Windows, only inside WSL, so on Windows it sits *inside* the thing you are trying to package rather than replacing it; and "in practice, the CUDA packaging in nixpkgs is large, slow to build, and not always up to date with the latest Nvidia releases" ([zenvanriel](https://zenvanriel.com/ai-engineer-blog/arch-vs-ubuntu-vs-nixos-local-llm-home-lab/)). It is a strong tool for making your `.wsl` image reproducible. It is not an end-user install format.

**Pixi and conda-forge.** The most credible cross-platform "one environment definition" for a mixed Python plus native stack. It produces cross-platform lockfiles spanning conda and PyPI, handles CUDA toolkits on Windows and Metal-enabled builds on macOS, and includes a task runner that works on Windows ([Pixi PyTorch docs](https://prefix-dev.github.io/pixi/latest/python/pytorch/), [pydevtools](https://pydevtools.com/handbook/reference/pixi/)). Guidance from 2026 explicitly frames it as replacing Docker "when you need binary-level reproducibility without the container overhead." Caveat: it is a developer tool. It gives you one environment spec that resolves correctly on both targets, but you still wrap it in a platform installer for the end user. This is the closest thing to a genuine cross-platform answer to the actual goal.

**Purpose-built local-AI packaging.** The entire category has converged on native installers. Ollama on Windows "installs natively via a single installer and runs as a system tray app with a background server, no WSL, no Docker, no PATH configuration required," with automatic CUDA and ROCm detection. LM Studio ships a native GUI using MLX on Apple Silicon ([hybrid-llm.com](https://hybrid-llm.com/tutorial/ollama/ollama-setup-guide-2026/), [codersera](https://codersera.com/blog/lm-studio-complete-guide-2026/)). Nobody who has solved this problem for consumers solved it with a container.

---

## Hybrid architectures: native GPU workers plus containerized orchestration

Yes, there is prior art, and it is the dominant pattern rather than an obscure one.

**Docker Model Runner is exactly this architecture, built by Docker, because Docker hit the same wall.** The inference engine "doesn't actually run inside a container at all. Instead, the inference server uses llama.cpp as the engine, running as a native host process that loads models on demand and performs inference directly on your hardware." Model Runner uses Docker's ecosystem for distribution and management while inference runs on the host: "Metal on Mac, CUDA on Linux." Model distribution still uses OCI images, pulled with `docker model pull` into a shared model store ([Docker blog on vllm-metal](https://www.docker.com/blog/docker-model-runner-vllm-metal-macos/), [Docker Model Runner intro](https://www.docker.com/blog/introducing-docker-model-runner/)).

Note Docker's platform split, which mirrors your situation exactly:

| Platform | Backend | GPU | Runs where |
| --- | --- | --- | --- |
| Linux | vllm | NVIDIA CUDA | container |
| Windows (WSL2) | vllm | NVIDIA CUDA | container |
| macOS | vllm-metal | Apple Silicon Metal | **host, natively** |

**The community pattern is the same shape.** The standard advice for local AI on a Mac is "run Ollama natively, keep only Open WebUI in Docker," and that advice is unchanged from M1 through M5 ([TechXplainator](https://techxplainator.com/docker-mac-gpu-guide/)).

**Does it reduce complexity or just move it?** It moves it, and the move is favorable. You gain: two install paths instead of one, two update mechanisms, and a host-to-container network boundary that must be configured on both platforms. You lose: GPU-in-VM configuration, the container toolkit, CDI, driver-version-to-CDI-spec mismatches, and the macOS impossibility entirely. The complexity lands in a place where it is cheap (one native binary per platform, which you already build) and leaves the place where it is expensive (GPU access through a hypervisor). That is why Docker itself shipped it this way.

For Hearth the mapping is direct: `llama-server` and the TTS service are the native GPU workers; the Rust supervisor and the FastAPI harness are the parts that could sit in a container if a container earns its place. Note that this also means the supervisor's process-lifecycle responsibilities, which are the reason it exists, would straddle the boundary. That is worth designing deliberately rather than discovering.

---

## What I could not determine

- **Whether Docker Desktop on Windows fully bundles the NVIDIA container runtime hook.** Docker's own prerequisites list omits the NVIDIA Container Toolkit entirely; NVIDIA's CUDA on WSL guide lists it with minimum versions. The sources genuinely disagree and neither states the other's position. This is testable in five minutes on the 4080 machine and should be, not researched further.
- **Apple `container` version and roadmap.** Wikipedia says 0.11.0 as of March 2026. A Medium roadmap post claims 1.0 landed in June 2026 with GPU passthrough as a future roadmap item. I found no Apple release note or official statement confirming either the 1.0 date or any GPU commitment. The only sourced Apple statement remains "we do not currently support this" from June 2025. Treat any 2026 GPU roadmap claim as unconfirmed.
- **Whether the Red Hat ggml API remoting work has landed upstream.** The September 2025 article states upstreaming into llama.cpp and virglrenderer as a next step. I found a 2026 reference stating the work is still pending acceptance, but no merge confirmation. Status as of August 2026 is unresolved.
- **Measured M1 MacBook Air CPU-only llama.cpp numbers** for the specific 4B and 12B sizes at issue. Published CPU-versus-Metal ratios come from M3 Pro and generalized 3-5x claims. The M1 Metal figures are solid (117.96 pp / 14.15 tg on 7B Q4_0); the CPU figures are inferred, not measured. Also no published M1 numbers for the Podman Vulkan container path, only M2 Max.
- **Which M1 MacBook Air configuration is the target**, 8 GB or 16 GB. This materially changes what runs at all, independent of the container question.
- **Whether Docker's DSSA permits a product to require its users to install Docker Desktop.** The agreement is silent on that scenario. The safe reading is that each end user is independently bound by Section 4.2 and you carry no license on their behalf. A definitive answer needs Docker legal, not a doc page.
