---
title: Backend Component Catalog
status: draft
last_reviewed: 2026-08-04
related:
  - ../_index.md
sources:
  - D:/Tools/Valinor/wiki/raw/backend-audit-2026-08-04/audit-rust.md
  - D:/Tools/Valinor/wiki/raw/backend-audit-2026-08-04/audit-valar.md
  - D:/Tools/Valinor/wiki/raw/backend-audit-2026-08-04/audit-server-tts.md
  - D:/Tools/Valinor/wiki/raw/backend-audit-2026-08-04/audit-scripts.md
  - D:/Tools/Valinor/wiki/raw/backend-audit-2026-08-04/audit-assets.md
  - D:/Tools/Valinor/wiki/raw/backend-audit-2026-08-04/audit-host.md
---

# Backend Component Catalog

Everything that has to be true on a host machine for one voice turn to
complete. Compiled 2026-08-04 from six parallel read-only audits of the Valinor
repository, with all live-state questions resolved in a single verification pass
against the running machine.

This is the inventory the packaging decision, the installer, and the first-time
user experience all depend on. It is written to answer three questions at once,
so the same reading of the same files does not have to happen three times:

1. What is the backend made of.
2. What does each piece assume about the machine it was built on.
3. Which pieces belong in Hearth at all.

## How to read this

Every component carries a `ships in Hearth` verdict. Valinor is the superset and
keeps everything. Hearth ships the subset. That column is the boundary between
the two products and it is the one to argue with first, because the public wiki
gets written from the `yes` rows.

`status` is honest rather than flattering. `live` means it runs and something
uses it. `stale` means it runs or exists but has been superseded. `dead` means
nothing reaches it. Where a claim of `dead` would drive a deletion it was
checked against source before being recorded.

Machine state was verified directly on 2026-08-04 rather than inferred. See
[Verified machine state](#verified-machine-state) for what was observed.

## The shape of an install

Every component sorts into one of four kinds, and those four kinds are exactly
what an installer does, in this order:

1. **Asset.** Something that must exist on disk before anything runs. Model
   weights, persona configs, voice clones, the memory tree.
2. **Host config.** A setting that lives outside the repository entirely. A
   firewall policy, a port forward, a scheduled task, an environment variable in
   a systemd drop-in.
3. **Launcher.** The unit or script that starts a process.
4. **Process.** The thing that ends up running and holding a port or a model.

Fetch assets, apply host config, install launchers, start processes. If the
install guide follows that order it will not double back on itself.

## The minimum house

The repository is much larger than the thing that answers a voice turn. Five
processes and four kinds of asset are the whole live path:

```
client (desktop, iOS, Echo)
  |
  v
Valar harness            :8700   the single client entry point
  |-- brain data plane   :8080   llama-server, holds the resident GGUF
  |-- brain control      :8765   Rust supervisor, swaps which GGUF is resident
  `-- voice              :8702   OmniVoice TTS service
```

Everything else in the repository is either a Valinor-only surface, a developer
tool, or dead. Two findings sharpen that considerably:

**Almost none of `Server/` is live.** Valar imports exactly three things from
it: `brain_sync` for memory, and `tts_generator` plus
`ModelManager.ensure_neutts_backbone` for the NeuTTS engine. NeuTTS is not the
running engine, so under the shipped OmniVoice configuration the latter two are
never imported at all. The five-stage skills pipeline, the SCX session store,
and the standalone server are reachable only from
`start_valinor_deepagent_server.py`, which nothing starts and which cannot run
alongside the Rust brain because it binds the same two ports. What Hearth needs
from `Server/` is one module.

**The Rust supervisor refuses to boot without OpenCode, and OpenCode feeds
nothing.** `VALINOR_OPENCODE_PERSONA_HARNESS` defaults to on, both launchers set
it explicitly, and readiness is a five-part preflight: a healthy endpoint, a
non-empty provider list, an agent literally named `Mentat`, and a create-then-
delete session round trip. Failure aborts the whole server. What it produces is
a process on `:4096` whose only consumer is a WebSocket path no client uses.
OpenCode was cut as the Mentat executor in July 2026. Removing this dependency
is the single highest-value change available before packaging: it deletes a
170 MB binary, a separate checkout at `D:\Tools\mentat-workspace\valinor-webapp`
that no document tells anyone to create, and a hard boot failure from the
install path.

## Processes

| Component | Port | Started by | GPU | Ships | Status |
| --- | --- | --- | --- | --- | --- |
| Valar harness | 8700 | `valar.service` via `valar_run.sh` | yes, holds Whisper | yes | live |
| llama-server | 8080 | spawned by the Rust supervisor | yes | yes | live |
| Rust supervisor | 8765 WS, 8766 assets | `valinor-rust.service` | no, owns residency | undecided | live |
| OmniVoice TTS | 8702 | `valar-tts-omni.service` | yes, about 2.2 GB | yes | live |
| NeuTTS TTS | 8701 | `valar-tts.service` | yes | no | stale, not enabled |
| `opencode serve` | 4096 | spawned by the Rust supervisor | no | no | live process, dead feature |
| Hermes gateway | 8770 | `hermes-gateway.service` | no | no | live, Valinor-only |
| Sulivan Telegram bot | none | `sulivan-bot.service` | no | no | live, Valinor-only |
| ComfyUI | 8189 Windows loopback | manual, on Windows | yes | no | live, Valinor-only |

**Valar harness.** The product's server. WebSocket voice protocol, persona
engine, tool loop, memory, card surfaces, journal API, and the read-only HTTP
surfaces the clients poll. It is resilient by design: a missing brain, a missing
memory tree, or a missing TTS service each degrade rather than crash. That
resilience is also its most dangerous property on a stranger's machine, covered
under [Silent degradation](#silent-degradation).

**Rust supervisor.** The control plane. It owns which GGUF is resident and
performs the swap when a persona needs a different model. It also serves the
entire repository tree over plain HTTP on 8766. Whether Hearth needs this
specific Rust implementation or just its function is an open decision.

**OmniVoice TTS.** The voice a Hearth user hears. Chosen over NeuTTS Air on
2026-06-04. It runs in its own virtualenv because its torch is newer than the
one the rest of the stack is pinned to, which is a real constraint rather than
tidiness: the gateway venv is cu118 and the TTS venv is cu130.

## Assets

| Component | Where | Ships | Notes |
| --- | --- | --- | --- |
| Brain GGUF | `~/models/valinor/` inside WSL | as a download step | every persona points at an absolute path in one Linux user's home |
| Persona configs | `Persona/<Name>/<name>.json` | Sulivan and Selene only | 12 exist, 10 are internal |
| Voice clones | `Persona/<Name>/voice/*.wav` plus `.txt` | yes | a licensing question packaging must answer |
| OmniVoice weights | Hugging Face cache, 3.1 GB | as a download step | fetched by model id on first load |
| Selene 3D model | `Persona/Selene/` GLB plus USDZ | optional | 11 MB GLB, 19 MB USDZ set for Apple clients |
| Engram tree | `D:\Tools\personalAI\Engram` via a junction | mechanism yes, content never | see below |
| `neutts-air/` package | in repo | only if NeuTTS ships | vendored engine source |

**The model path problem.** All twelve persona manifests carry
`deep_model.path` as an absolute path under `/home/jones/models/valinor/`. That
tree holds 84 GB across ten GGUF files and is entirely separate from the
repository's own `models/` directory, which contains different files. The split
is deliberate rather than accidental: weights on the ext4 filesystem load in
seconds while the same file on the Windows mount takes minutes and can exceed
the model-switch timeout. So this is not fixed by repointing at `models/`. It
needs a model-home variable, a download step, and a resolver. The persona page
already works around it at the edit boundary by showing model names and
resolving them back to paths, but the file format still stores absolute paths.

**Engram.** The memory layer, and the sharpest line in this catalog. The
mechanism ships and the content never does. Two modules hard-code
`D:/Tools/personalAI/Engram` as a fallback candidate with no environment
override, and one carries a 25-entry table of personal project names used to
guess which project a question is about. A Hearth install seeds an empty brain.
It never clones anyone else's.

## Host configuration

The most expensive category, because none of it appears in any source file,
which is exactly why it has cost this project multiple days of debugging.

| Component | Where | Elevation | Ships | Status |
| --- | --- | --- | --- | --- |
| WSL2 platform, Ubuntu-24.04 | Windows feature | yes, once | yes | live, 2.4.13.0 |
| Hyper-V firewall inbound policy | firewall, keyed by VM creator GUID | yes | yes | live, set to Allow |
| `.wslconfig` idle timeout | `%USERPROFILE%\.wslconfig` | no | yes | live, max int32 |
| `WSLDistroKeeper` task | Task Scheduler, at logon | no | yes | live, Running |
| `loginctl enable-linger` | inside the distro | no | yes | live |
| portproxy 8700 to the WSL IP | IP Helper table | yes | yes for multi-device | live but stale by design |
| firewall rule "Valar 8700" | Windows Firewall | yes | yes, needs scoping | live, open to any remote |
| `ValarPortproxy` task | Task Scheduler, at logon | yes | yes | live, undocumented in the wiki |
| Engram junction | `D:\Tools\Valinor\Engram` | no | no, needs a data dir | live |
| systemd drop-ins | `~/.config/systemd/user/<unit>.d/` | no | yes | live, see below |
| ComfyUI portproxy 8188 to 8189 | IP Helper table | yes | undecided | live, no logon task |

**The drop-ins were the headline of the whole audit.** Four files supplied
configuration that existed in no repository:

| File | Supplies |
| --- | --- |
| `valar.service.d/zz-tts-omnivoice.conf` | the TTS endpoint. Without it the gateway dials `:8701`, the retired port, and Hearth is silent |
| `valar.service.d/zz-tools.conf` | `VALAR_TOOLS_ENABLED=1`. The tool layer defaults to off |
| `valar.service.d/wright-env.conf` | Wright's grounding paths, and the tool switch again |
| `valinor-rust.service.d/reasoning.conf` | `VALINOR_LLAMA_REASONING=auto`, so per-request thinking is honored |

They are now captured in the Valinor repository under
`scripts/systemd/dropins/`. The general lesson outlives the specific files: any
configuration that only exists on the machine it was configured on is invisible
to packaging until something goes looking for it.

**Two always-on gaps nobody had written down.** Both host-side launchers are
interactive-logon tasks, so a machine that reboots and sits at the lock screen
has no distro pin and no port forward, and every LAN client fails until somebody
logs in. Separately, the ComfyUI bridge has no scheduled task at all, so image
generation is broken after every reboot until an elevated script is re-run by
hand.

## Silent degradation

The single most important property to fix before anyone else installs this.

Every import of the `Server` package inside Valar is wrapped in a bare
`except Exception` that logs and continues. Missing that package yields a
gateway that starts, binds, serves, and answers with no memory and no voice.
PyYAML is not in `Valar/requirements.txt`, and without it the tool registry
resolves to empty, which is indistinguishable from tools being switched off on
purpose. A missing Engram junction gives empty recall and a 503 on the journal
and nothing else. A missing TTS endpoint gives silence.

Each of those individually is a reasonable resilience choice for a system whose
operator built it. Together they mean a stranger can complete an install, see a
healthy status, hold a conversation, and never learn that half the product is
not running. Hearth needs a startup self-check that distinguishes "switched off"
from "broken", and it needs it before the installer, not after.

## Security posture

Three audits reached this independently from three directions, so it is recorded
as a property of the system rather than as scattered rows.

Valar binds `0.0.0.0:8700` with CORS set to allow any origin and no
authentication of any kind. Anything that can reach that port can switch
personas, rewrite the tool registry through `POST /apps/apply`, rewrite persona
files through `POST /personas/apply`, terminate the process (both apply
endpoints call `os._exit(0)` deliberately, relying on `Restart=always`), and
reach the brain unmediated through `/v1/raw/*`, which is a bare reverse proxy.
The Windows firewall rule for that port is scoped to any profile and any remote
address. Separately, the Rust asset server on 8766 serves the entire repository
tree to the LAN.

The code names this a home-LAN trust boundary and defers tightening it to the
remote-access work. That was a defensible call for one machine in one house. It
is not defensible for software handed to someone else, and it means the
remote-access decision and the authentication decision are the same decision.

## What does not ship in Hearth

Recorded so the boundary is decided once rather than re-argued per article.

| Component | Why not |
| --- | --- |
| Hermes gateway `:8770` | the trading and messaging entry point, not a client path |
| Sulivan Telegram bot | a personal surface |
| CHOAM wallet bridge and tools | personal trading integration, needs a backend not in any repo |
| Liara persona | requires the CHOAM backend |
| Wright and its four worker personas | game-development harness, needs a UEFN install |
| Verse digest allow-list | hard-codes a Windows username and a specific UEFN project |
| f1-principal, f1-vision | require a specific racing game |
| Mentat runs registry | 22 absolute paths, every run is personal project work |
| `valar-brain-reset` timer | exists so a trading agent finds the right model at the market open |
| `valar-brain-watchdog` | probes the trading path on a trading schedule |
| OpenCode and its workspace | cut as the Mentat executor in July 2026 |
| ComfyUI | a large third-party application with its own weights and GPU budget |
| NeuTTS Air | ship one voice engine, not two |
| Two of nine card types | commissioned for the trading dashboard |

Of twelve personas, two are user-facing. Hearth ships Sulivan, plus Selene if
the memory and journal features ship with her, and the product's own plan is for
the user to build their own persona through Sulivan rather than receive a roster.

## What is dead

Roughly twenty files exist only to mislead the next reader. Three of the four
`start_valinor_deepagent_server_*.bat` variants target a model pin removed in
June and a llama.cpp fork nothing consumes. All four Hermes launchers, both
OpenCode launchers, the Mentat desktop stack script, the TurboQuant build
script, and ten `mentat_loop_*` files are OpenCode-driven or point at the
`valinor-webapp` checkout that `hearth-client/` replaced in July. There is also
a committed `.bak` copy of the gateway from May.

None of it should be carried into Hearth. Whether it is deleted from Valinor is
a separate call, and the tag `rc-pre-hearth-move` is the rollback point either
way.

## Documentation that disagrees with the machine

Found while auditing, recorded here so the Valinor wiki correction is driven by
a list rather than by memory.

| Article | Error |
| --- | --- |
| `valinor-always-on-stack.md` | devotes a section to creating a `ValinorStack` scheduled task that was never created; says to unregister `ValinorSulivanBot`, which was not done; does not document `ValarPortproxy`, which is what actually runs |
| `valinor-always-on-stack.md` | gives the brain-reset timer as 06:00 weekdays; the unit says 05:35, retuned because 06:00 fired at the exact minute of the market open |
| `valinor-always-on-stack.md` | lists `opencode serve` on 4096 as a supervised component without recording the July cut |
| `scripts/systemd/README.md` | does not mention `valar-tts-omni`, `valar-brain-reset`, or `valar-brain-watchdog`; describes the wrong service ordering; its enable list omits `valar.service` |
| `deep-agent-pipeline.md` | documents an `env` handler and an `image` handler that are not in the skill frontmatter, and names the engram handler function incorrectly |
| `wiki/server/rust/README.md` | lists OpenCode control as current scope |
| `Valar/README.md` | advertises a 32k context budget; the run script sets 16384 |
| `valinor-rust.service` | its own description says "daily gemma-4-E4B resident"; the resident model is the 12B QAT |

`scripts/valar_install_service.sh` is not documentation but belongs on this
list: it installs the retired NeuTTS unit and never installs the OmniVoice unit
that `valar.service` requires. Running our own documented install today produces
a broken stack.

## Verified machine state

Observed 2026-08-04 on VYTAL in a single batched session, because repeated
one-off WSL invocations bounce the systemd user manager and restart the resident
model.

**Enabled units.** `valinor-rust`, `valar`, `valar-tts-omni`, `hermes-gateway`,
`sulivan-bot`, `valinor-prewarm`, plus the `selene-review`, `valar-brain-reset`,
and `valar-brain-watchdog` timers. `valar-tts.service` is present but not
enabled, so the retired engine is not holding VRAM.

**Running.** Valar reports `brain_ready: true`, persona Sulivan, and exactly two
selectable personas. The resident model is
`gemma-4-12B-it-qat-UD-Q4_K_XL.gguf`. OmniVoice on 8702 reports ready. Nothing
answers on 8701.

**Inference.** llama-server build 8967 (`fc2b0053f`), built with GNU 13.3.0,
supporting every flag the supervisor passes. One RTX 4080, 16375 MiB, compute
capability 8.9. VRAM at 13860 MiB used, 2189 free.

**Environments.** The gateway venv is pinned to cu118. The TTS venv is torch
2.12.0+cu130, torchaudio 2.11.0, omnivoice 0.1.5, numpy 2.4.6. That second set
was previously unrecorded anywhere and was the single largest reproducibility
gap in the stack; it is now four lines and a build script can be written from
it.

**Storage.** 84 GB of GGUF weights inside WSL, separate from the repository's
own model directory. The distro disk is 124.8 GB and lives on the C: drive,
where it grows with anything copied in and never shrinks. From inside the distro
the filesystem reports far more free space than the host actually has, which is
the trap behind the recorded incident where a model copy took down the whole VM.

## Download manifest

What a fresh install actually has to fetch, as distinct from what this machine
happens to hold.

| Artifact | Size | Required |
| --- | --- | --- |
| One brain GGUF, tier depending on hardware | 5.5 GB to 12.7 GB | required |
| OmniVoice weights | 3.1 GB | required |
| llama.cpp runtime for the platform | about 0.7 GB | required |
| Persona bundle for Sulivan | about 2 MB | ships with the app |
| Engram skeleton | negligible | created by the installer |

Three brain tiers are named in the product plan: gemma-4-E4B for low-end
hardware, gemma-4-12B QAT as the current default, and gemma-4-26B-A4B for large
machines. Only the 12B is in service. The E4B copy on this machine is a Q5_K_M
quant that no persona references, and the 26B has never been benchmarked in
place. Hardware detection choosing between three tiers is therefore a real piece
of unbuilt work, not a configuration switch.

Realistic minimum for a working install is roughly 9 to 13 GB of downloads, on
top of whatever the platform runtime costs. That is before the WSL distro
itself, which on this machine has grown to 124.8 GB.

## Open decisions

Ordered by how much else depends on them.

1. **Does the Rust supervisor ship, or just its function?** It is the model
   control plane and it also carries the OpenCode dependency, an unauthenticated
   whole-repository file server, and a `cargo run` debug launch. Hearth needs
   model swapping. Whether it needs this is unanswered.
2. **One TTS engine or two?** Shipping both doubles the install surface and
   requires two virtualenvs with incompatible torch builds, for a rollback path
   the product does not need.
3. **Does memory ship in v1?** The mechanism is sound and the implementation is
   welded to a specific junction, a sibling checkout, and a personal project
   table. A stranger gets an empty brain either way; the question is how much
   plumbing that requires.
4. **Does image generation ship?** It works, and it depends on a large
   third-party application with its own weights, its own GPU budget, and a
   manual Windows-side bridge that does not survive a reboot.
5. **What replaces the home-LAN trust boundary?** See
   [Security posture](#security-posture). This is the same decision as remote
   access.
