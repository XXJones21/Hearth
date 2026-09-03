---
title: Native runtime
status: draft
last_reviewed: 2026-09-03
related:
  - packaging-options.md
  - component-catalog.md
  - build-pipeline.md
  - portability-ledger.md
  - ../first-run.md
sources:
  - D:/Tools/Valinor/tasks/architecture-decision-native-windows.md
  - D:/Tools/Valinor/tasks/research-native-windows.md
  - D:/Tools/Valinor/tasks/research-backend-linuxisms.md
  - D:/Tools/Valinor/tasks/research-wsl-steelman.md
---

# Native runtime
Hearth's backend runs as native processes on both platforms. No WSL, no
container, no Linux layer of any kind on the user's machine. Decided
2026-08-06 after four parallel investigations; the decision memo and the three
research reports are named in the frontmatter sources. WSL remains what it
always was: the developer testbed where the Valinor house runs.

## Why, in three sentences

Every component has a first-party Windows build or wheel, and the backend
audit found the Linux binding to be three systemd units, five bash scripts,
and two path defaults, roughly eight files across seven thousand lines.
Microsoft documents WSL as inner-loop tooling whose VM may be suspended when
no Windows process holds a handle, which is disqualifying for an always-on
companion, and the consumer hazards (antivirus breakage, the shared
`.wslconfig`, the never-shrinking vhdx, error 0x80370102) each land on
exactly the kind of machine a stranger owns. The product category agrees:
Ollama, LM Studio, Jan, GPT4All and ComfyUI Desktop all ship native, and no
consumer product ships a `.wsl`.

The 2026-08-04 packaging research already chose native as the destination and
kept `.wsl` only as a speed bridge, gated on the belief that going native
required the voice engine to leave torch first. That gate fell on 2026-08-06:
`omnivoice==0.1.5` resolves its full dependency tree, torch and torchaudio
included, on native Windows Python 3.13. Native no longer waits for a TTS
rewrite; the ONNX and `neutts-rs` routes in
[`packaging-options.md`](packaging-options.md) remain worthwhile
simplifications, not gates.

## The process model, both platforms

One architecture, two builds. The Hearth client is the root of the tree and
supervises everything; there is no init system.

```
Hearth client (Tauri)
  hearth-supervisor (Rust)          18765 WS control, 18766 assets
    llama-server                    18080, CUDA or Vulkan on Windows, Metal on macOS
  harness (vendored Python)         18700, the client gateway; holds Whisper
  voice worker (OmniVoice env)      18702, torch; own environment, see below
```

- The supervisor keeps its existing job: model residency, llama-server
  spawn and health, persona switching. This is the Ollama shape, a runner
  subprocess health-polled over a local port, and it is what was already
  built.
- The client owns process lifecycle: ordered start (supervisor, then
  harness, then voice), health gate per stage, restart with backoff on
  crash, logs captured to `<root>/logs`, and a kill that takes the whole
  tree with it (a Job Object on Windows, a process group on macOS) so no
  orphan ever survives the app.
- **The house outlives the window.** Closing the client window minimizes to
  the tray (menu bar on macOS) and the backend keeps running; Quit is the
  explicit stop. An always-on companion cannot die with a window, and this
  is the behavior WSL could never guarantee and native trivially can.

## The install root, per platform

The one-folder rule from [`../first-run.md`](../first-run.md) holds
unchanged; only the `wsl\` entry from the earlier draft is superseded.

```
Windows: <root> = D:\Hearth (chosen at setup)     macOS: <root> = ~/Hearth
  hearth-install.json     the record, extended with a provisioning section
  models\                 GGUFs, sha256-verified
  runtime\                vendored Python tree, llama-server, hearth-supervisor,
                          the backend (harness, memory, personas, scripts)
  envs\voice\             the OmniVoice environment, installed at first run
  config\                 hearth.env and anything else generated
  logs\                   one file per supervised process
```

Uninstall is deleting the folder. No distro to unregister, no vhdx, no
registry surface beyond the client's own installer entry.

An entire class of host plumbing is deleted rather than ported: the portproxy and its logon task, the Hyper-V firewall policy, the
`.wslconfig` idle timeout, the WSLDistroKeeper task, and linger. Native
processes on localhost need none of it. What remains host-side is one
Windows Firewall rule if other devices should reach 18700, and it stays
opt-in.

## Platform differences, and they are small

| Concern | Windows | macOS |
| --- | --- | --- |
| llama-server asset | upstream win-cuda (cudart bundled alongside), win-vulkan fallback for non-NVIDIA | upstream macos-arm64 with Metal |
| Voice torch | CUDA wheels, proven resolving | MPS wheels; synthesis on MPS is the open spike |
| GPU facts | nvidia-smi, as the probe does today | unified memory, as the probe does today |
| Kill semantics | Job Object | process group |
| App data | the chosen root, plus the WebView2 profile | the chosen root, plus the app container |
| Signing | optional now, MSI/NSIS as today | required eventually; unsigned local builds fine for the M1 Air round |

The probe already handles both machines; the plan's `backend` field
(cuda, metal, cpu) now simply selects which llama-server asset the installer
fetches.

## What the installer rows mean now

The mockup's installing screen maps cleaner natively than it ever did to WSL:

| Mockup row | Native meaning |
| --- | --- |
| Prepared the environment | unpack the vendored Python tree and the backend into `runtime\` |
| Installed the runtime | fetch llama-server, sha256-verified like the models, and place hearth-supervisor, which is built from this repository and ships inside the app |
| Installed the voice engine | create `envs\voice`, pip install the pinned set, fetch the OmniVoice weights |
| Downloading the model | unchanged, already built and verified |
| Writing your configuration | `render_config.py` from the record, native paths, ports 18700/18080/18702/18765/18766 |
| Starting Hearth | the client spawns the tree and health-gates each stage |

Then the verify screen and the voice test exactly as designed. Nothing in the
verify design was WSL-specific.

## The voice, honestly

Torch stays, for now, in its own environment under `envs\voice`, installed at
first run behind the progress bar, the ComfyUI pattern, and the app starts
without it (text works, voice arrives when the row finishes). This is the
one place the payload is measured in gigabytes and the one place a wheel
matrix is owned. The standing simplification routes, `sherpa-onnx` (same
organization as OmniVoice) and `neutts-rs` with pre-encoded voices, would
each delete this section, and Whisper moving to `whisper-rs` inside the
supervisor deletes the speech half of Python. None of them block shipping.

## Open items

1. OmniVoice GPU synthesis smoke: CUDA on the 4080, then MPS on the M1 Air.
   The resolve is proven; the synthesis run is not. First task of the port.
2. The supervisor's two Windows edits: `normalize_path` and the
   `llama_server_bin` default.
3. The client supervision layer, replicating the units' seven behaviors.
4. CUDA DLL search-order hygiene for the vendored trees, the one isolation
   gap WSL genuinely covered better.
5. Tray lifecycle and autostart-at-login, the native answer to always-on.
6. macOS signing and notarization, deferred until after the M1 Air round.
