---
title: Portability ledger
status: draft
last_reviewed: 2026-09-03
related:
  - component-catalog.md
  - ../_index.md
sources:
  - D:/Tools/Valinor/wiki/raw/backend-audit-2026-08-04/
---

# Portability ledger
Every assumption the backend makes that is false on a machine other than the one
it was built on. This is the projection of the component catalog's
`assumes about this machine` column, reorganized by the kind of assumption
rather than by component, because that is how the work gets done: one pass fixes
all the path literals, a different pass fixes all the hardware constants.

It is the honest answer to "how far are we from someone else running this."

## How to read the severity

| Severity | Meaning |
| --- | --- |
| **Blocker** | A stranger cannot get a working install. The failure is loud. |
| **Silent** | The install appears to succeed and a feature is quietly absent. Worse than a blocker. |
| **Degraded** | It runs, but wrongly configured for their hardware. |
| **Valinor-only** | Only affects the personal superset. Not Hearth's problem, listed so it is not mistaken for one. |

Effort is `trivial` (a variable), `moderate` (a refactor with a clear shape), or
`structural` (a design decision has to be made first).

## The summary

| Class | Items | Worst severity |
| --- | --- | --- |
| [Repository path](#1-the-repository-path) | about 110 literals | Blocker |
| [The Linux username](#2-the-linux-username) | 4 units, 12 persona files, 6 scripts | Blocker |
| [The Windows username](#3-the-windows-username) | 2 files | Valinor-only |
| [The platform itself](#4-the-platform-itself) | WSL, systemd, the distro name | Blocker, structural |
| [The hardware](#5-the-hardware) | GPU architecture, VRAM, context size | Blocker on other GPUs |
| [Software that must already exist](#6-software-that-must-already-exist) | 8 external dependencies | Blocker |
| [State that exists in no repository](#7-state-that-exists-in-no-repository) | 4 drop-ins plus the enable set | Silent |
| [One person's data](#8-one-persons-data) | Engram, aliases, project paths | Silent |
| [Things that fail quietly](#9-things-that-fail-quietly) | 5 degradation paths | Silent |

Nothing in this ledger is unknown-hard. There are no mysteries left after the
audit. What there is instead is a large amount of mechanical work plus five
genuine design decisions, and the design decisions gate the mechanical work
rather than the other way round.

---

## 1. The repository path

**Severity: Blocker. Effort: trivial but wide.**

About 110 literal occurrences of `/mnt/d/Tools/Valinor` or `D:\Tools\Valinor`,
concentrated in three places:

| Location | Count | Notes |
| --- | --- | --- |
| `scripts/systemd/*.service` | 11 | every `ExecStart`, so every unit fails |
| `scripts/*.sh` | roughly 25 | `REPO=` assignments, wrapper paths, log paths |
| root `start_*` files | roughly 20 | mostly in dead launchers |
| `Valar/valar/tools/mentat_runs.yaml` | 22 | Valinor-only, the run allow-list |
| `Valar/valar/tools/handlers/forge.py` | 2 | the client checkout path |
| `Valar/valar/gateway/journal.py` | 2 | Engram fallback candidates |
| `rust/valinor-server/src/config.rs` | 1 | the default `repo_root` |

The fix is the same everywhere: derive the root from the script or binary
location instead of hard-coding it, and let an environment variable override.
Two files already do this correctly and can be the pattern:
`scripts/tasks_dashboard.py` derives from `__file__`, and
`start_mentat_desktop_stack.bat` uses `%~dp0`.

There is one trap. `Valar/valar/config/settings.py` computes the repository root
as `Path(__file__).resolve().parents[3]`, and the tool handlers use
`parents[4]`. Those encode the current directory depth. Moving a file up or down
one level silently repoints the entire repository root, and nothing errors.
Any restructuring has to fix this properly rather than adjusting the integers.

**Also in this class, and easy to miss:** the distro name `Ubuntu-24.04` is
hard-coded in seven places, including `valar_portproxy.ps1`, which is the script
a reboot depends on.

## 2. The Linux username

**Severity: Blocker. Effort: trivial but wide.**

The backend assumes the WSL user is literally `jones`.

| Where | What breaks |
| --- | --- |
| `valinor-rust.service` PATH | cannot find cargo or the OpenCode binary |
| `valar.service` PATH | cannot find the gateway's Python |
| `valar-tts-omni.service` PATH | cannot find the TTS Python |
| `valar-tts.service` PATH | same, for the retired engine |
| `valar_run.sh`, `valar_tts_run.sh` | `VENV=/home/jones/...`, unparameterised |
| `valar_wsl_env_build.sh`, `valar_llama_cuda_rebuild.sh` | build into a fixed path |
| all 12 `Persona/*/*.json` | `deep_model.path` under `/home/jones/models/valinor/` |

The persona files are the interesting entry. Those are not environment paths,
they are product data, and they carry absolute paths to model weights inside one
Linux user's home directory. The persona page already works around this at the
edit boundary by displaying model names and resolving them back to paths, which
means the display problem is solved and the storage problem is not. Persona
manifests should reference a model by identifier and let a resolver find it.

**Do not fix this by repointing at the repository's `models/` directory.** The
split is deliberate: weights on the Linux-native filesystem load in seconds,
while the same file on the Windows mount takes minutes and can exceed the model
swap timeout. The fix is a model home variable plus a download step, not a
relocation.

## 3. The Windows username

**Severity: Valinor-only. Effort: trivial.**

Two files assume the Windows user is `josh2`:

- `Valar/valar/tools/handlers/uefn.py` hard-codes three paths under
  `C:/Users/josh2/AppData/Local/UnrealEditorFortnite/...`. This is the Verse API
  allow-list for the game-development harness. Wright does not ship in Hearth,
  so this leaves with it.
- `Valar/valar/tools/handlers/claude_code.py` globs
  `/mnt/c/Users/*/.local/bin/claude.exe`, which is already wildcarded and
  therefore fine.

Listed because a grep for the username finds them and they should not be
mistaken for Hearth blockers.

## 4. The platform itself

**Severity: Blocker. Effort: structural.**

This is the entry the packaging investigation exists to resolve. The backend
does not merely run on Linux, it assumes a specific hosting arrangement:

- **WSL2 with a named distro.** Not "Linux". A specific distro name, in seven
  files, on a Windows host, reached across a NAT boundary.
- **systemd user services with lingering.** All supervision, ordering, restart
  policy, and environment injection is systemd. There is no other supervisor and
  no fallback. macOS has no systemd.
- **The NAT boundary itself.** `valar_run.sh` derives the Windows host address
  from `ip route show default` in order to reach services running on the Windows
  side. That is WSL-NAT-specific and produces wrong URLs on mirrored networking
  or on a native Linux machine.
- **`/usr/lib/wsl/lib` on PATH.** Every unit hard-codes it, because that is where
  the WSL CUDA stubs live and systemd does not inherit the interop PATH.
- **The Windows side.** A portproxy that must be re-run when the WSL IP changes,
  a firewall rule, a Hyper-V VM firewall policy stamped at vNIC creation, an idle
  timeout, and a scheduled task that pins the VM alive.

None of that transfers to macOS. On Apple Silicon there is no WSL, no systemd,
no portproxy, and no CUDA. Python and llama.cpp both run natively and more
simply, but nothing from the Windows path carries over. The macOS backend is a
second implementation, not a port.

**This is the decision the whole ledger waits on.** Every mechanical fix above
is cheaper to do once, after the hosting model is chosen, than twice.

## 5. The hardware

**Severity: Blocker on any other GPU. Effort: moderate.**

The stack is tuned to one card, an RTX 4080 with 16 GB, and several of those
tunings are compile-time or hard-coded rather than detected.

| Assumption | Where | Consequence elsewhere |
| --- | --- | --- |
| CUDA architecture 89 (Ada) | `valar_wsl_env_build.sh`, `valar_llama_cuda_rebuild.sh` | the CUDA build fails or produces a binary that will not run. Ampere is 86, Hopper 90, consumer Blackwell 120 |
| `g++-12` as the CUDA host compiler | same two files | required because the local nvcc is CUDA 12.0 and rejects newer gcc. Wrong on a machine with a different toolkit |
| Context size 16384 | `valinor-rust.service` | overrides every persona's declared `n_ctx` unconditionally. Mentat declares 65536 and never gets it |
| 20000 MiB VRAM gate | the Rust launcher | speculative decoding silently off below that |
| A single CUDA device at index 0 | ModelManager, the TTS streamer | no multi-GPU and no device selection |
| No CPU fallback anywhere | the Rust crate | a machine without a supported GPU has no path at all |

The VRAM budget is the deeper version of this. The whole coexistence design,
brain plus TTS plus Whisper on one card, is written against 16 GB. Currently
13.8 GB of 16.4 is in use. A smaller card does not fit this configuration and a
larger one changes the rules. Model tier selection by detected VRAM is named in
the product plan and does not exist in code.

**One item here is a live bug worth fixing regardless of packaging.** The
context override in `valinor-rust.service` is the mechanism behind a
long-standing open issue where the coding executor needed 65K context and kept
receiving errors at 16K. It is one line.

## 6. Software that must already exist

**Severity: Blocker. Effort: moderate, mostly by deletion.**

Eight things must be installed and are not installed by anything in the
repository. Two of them block boot.

| Dependency | Where it must be | Blocks boot | Ships in Hearth |
| --- | --- | --- | --- |
| OpenCode CLI, native Linux binary | `~/.opencode/bin/` | **yes** | no |
| A second checkout at `D:\Tools\mentat-workspace\valinor-webapp` | outside the repo | **yes** | no |
| `llama-server` binary | `/usr/local/bin/` | yes | yes, must ship |
| Rust toolchain | the WSL user's home | yes, the launcher runs `cargo run` | no, ship a binary |
| eSpeak NG | `C:\Program Files\eSpeak NG` | only the NeuTTS path | only if NeuTTS ships |
| `engram-mcp` checkout | `D:\Tools\claude-marketplace\engram-mcp` | no, degrades | undecided |
| `EngramMCP` checkout | `D:\Tools\EngramMCP` | no, nightly digest only | undecided |
| ComfyUI portable plus a system Python 3.12 | `D:\Tools\ComfyUI_windows_portable_nvidia` | no | no |

The first two are the same finding and it is the best news in this ledger. The
Rust supervisor refuses to start unless OpenCode passes a five-part preflight,
including the presence of an agent literally named `Mentat` inside a separate
checkout that no document tells anyone to create. OpenCode was cut as the
executor in July 2026 and the code path that consumed it has no live caller.
Setting one environment variable to zero removes a 170 MB binary, a hidden
checkout, and a hard boot failure from every future install.

`llama-server` deserves a note: nothing in the repository builds the Linux
binary. Both build scripts produce a Windows executable, while the live brain
runs `/usr/local/bin/llama-server`, whose provenance is recorded nowhere.
Verified as build 8967, but how it got there is not written down.

## 7. State that exists in no repository

**Severity: Silent. Effort: trivial, and already partly done.**

Four systemd drop-ins supplied configuration that no repository had ever seen:
the TTS endpoint, the tool-layer master switch, the game-harness grounding, and
the reasoning mode. They are now captured in the Valinor repository under
`scripts/systemd/dropins/`.

Two related items are not yet fixed:

- **`valar_install_service.sh` installs the wrong things.** It copies the retired
  NeuTTS unit and never copies the OmniVoice unit that `valar.service` declares
  in its `After=` and `Wants=`. The omni unit on the live machine was placed by
  hand in June. Running our own documented installer today produces a stack that
  orders after a unit which does not exist.
- **The enable set was assembled by hand.** The documented enable list in
  `scripts/systemd/README.md` is the previous-generation stack and omits
  `valar.service` entirely. What is actually enabled was verified directly and
  is recorded in the component catalog.

The general form of this class is the one to carry forward: any configuration
that lives only on the machine where it was configured is invisible until
something goes looking for it. An installer that cannot regenerate the drop-ins
has not installed the product.

## 8. One person's data

**Severity: Silent. Effort: moderate.**

The memory layer is welded to one person's memory.

- `Server/tools/brain_sync.py` and `Server/tools/engram_writer.py` both hard-code
  `D:/Tools/personalAI/Engram` as a fallback candidate, with **no environment
  variable to point them elsewhere**.
- `Valar/valar/gateway/journal.py` probes three candidates, two of which are that
  same personal path spelled two ways.
- `brain_sync.py` carries a 25-entry hand-maintained table of personal project
  names, used to guess which project a question is about.
- The Journal shelf reads its curated summaries at runtime from
  `hearth-pitch/mockups/selene-pages.json`. A pitch deck's mockup folder is
  load-bearing production data.
- Wright's grounding config points at a specific game project on a specific
  drive.

The product decision here is already made and worth restating because it
constrains the code: a Hearth install seeds an **empty** brain. It never clones
anyone else's. So the work is to make the memory root configurable, move the
project inference from a static table to something derived, and relocate the
shelf data out of the pitch directory.

## 9. Things that fail quietly

**Severity: Silent. Effort: moderate. Highest priority in this document.**

Listed last because it is the one that changes what gets built first.

| Missing thing | What the user sees |
| --- | --- |
| The `Server` package | a healthy gateway with no memory and no voice |
| PyYAML, absent from `Valar/requirements.txt` | an empty tool registry, identical to tools being switched off |
| The Engram junction | empty recall, a 503 on the journal, nothing else |
| A TTS endpoint pointing at a dead port | silence |
| `torchaudio`, absent from both requirements files | the TTS service fails to start |

Every import of the `Server` package inside Valar is wrapped in a bare
`except Exception` that logs and continues. Individually each of these is a
reasonable resilience choice for a system whose operator built it and would
recognize the symptom. Collectively they mean a stranger can complete an
install, see a healthy status, hold a conversation, and never discover that half
the product is not running.

**Hearth needs a startup self-check that distinguishes "switched off" from
"broken", and it needs it before the installer rather than after.** An installer
that cannot tell you it failed is worse than no installer, because it converts a
loud problem into a silent one and moves the cost onto a tester who has no way
to diagnose it.

---

## What this ledger implies

Three things, in order.

**First, the mechanical work is large but understood.** Roughly 110 path
literals, one username in twenty places, seven distro-name literals, and six
hardware constants. None of it is research. All of it is cheaper to do once,
after the hosting model is decided, than twice.

**Second, three fixes are worth doing immediately and independently of any
packaging decision**, because each removes a real defect from the running
system: turn off the OpenCode boot dependency, fix the installer to copy the
OmniVoice unit and the drop-ins, and remove the context override that has been
silently capping the coding executor.

**Third, the platform decision gates everything else.** Whether the backend
ships as containers, as native per-platform binaries, as a prepared WSL image,
or as something else determines what "fix the path" and "fix the username" even
mean. That investigation is running now and its conclusions belong in a separate
article. Until it lands, this ledger is a description of the distance rather
than a plan for crossing it.
