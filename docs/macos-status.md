# The macOS pass, where it stands

Written 2026-08-07, from the first real run on the Air. The runbook
(`m1-air-runbook.md`) said what to do; this says what happened, what was wrong,
and what the numbers turned out to be. Read the runbook first if you have not.

The machine: 8 GB M2 Air (the fixture is named `m1-air-8gb`; the install record
reports **Apple M2**, so the fixture models a slightly different machine than
the one it ran on), macOS 27.0, arm64, Xcode 26.5.

## It runs

The Mac build installs, provisions, boots, and answers. Sulivan holds a
conversation on this machine through Metal. Boot revalidation works: quit,
relaunch, and the house comes back from the persisted install root without
passing through setup. Quitting leaves no orphaned processes, twice measured,
so the process-group reaping the runbook flagged as unknown is fine on unix.

Toolchain notes, because the runbook's prerequisites were not quite the whole
story: the first arm64 build of the supervisor crate compiled clean with no
unix-side fixes. Two machine-level snags stood between a clean checkout and a
build, neither of them Hearth's fault but both of them yours to hit again:

- `~/.npm` contained root-owned files and `npm install` refused. Permanent fix
  is `sudo chown -R 501:20 ~/.npm`.
- npm 11 installed **no** rolldown native binding, because the lockfile was
  authored on Windows and its optional platform deps were skipped. The build
  dies in `vite build` with `Cannot find module @rolldown/binding-darwin-*`.
  Fix: `npm install --no-save @rolldown/binding-darwin-arm64@<version>`. This
  does NOT survive a clean `npm install`, so it will recur on every fresh
  checkout until the lockfile grows the darwin entries properly.

Gatekeeper never came up. A locally built `.app` carries `com.apple.provenance`
and not `com.apple.quarantine`, so the runbook's right-click-Open dance applies
only to a bundle that was downloaded or transferred.

## What was broken, and is now fixed

### The plan chose a model; nothing told the house

The fatal one. `model_candidates()` in `backend/supervisor/src/llama.rs` built
its candidate list solely from the persona's `deep_model.id`, and
`Sulivan/sulivan.json` names `gemma-4-12b-qat` — tier 2's model. The renderer
wrote `HEARTH_MODELS` (which directory) and never wrote which FILE. So every
install that was not a tier 2 machine asked llama-server for weights the
installer had never downloaded:

    Error: llama-server readiness failed
      Caused by: model file not found: .../gemma-4-12B-it-qat-UD-Q4_K_XL.gguf

llama-server never became ready, the supervisor exited, and the harness spent
the rest of its life reporting `cannot reach Rust WS at ws://127.0.0.1:18765`.
The house was on screen the whole time. **This was never a macOS bug** — a
tier 0 or tier 1 install failed identically on Windows; tier 2 worked only
because the hardcoded id happened to match what tier 2 downloads.

Fixed by having the renderer write `HEARTH_DEEP_MODEL_FILE` from the install
record, honoured by both the supervisor and `valar/models.py`. Precedence is
`HEARTH_DEEP_MODEL_OVERRIDE` (a developer pointing somewhere on purpose) >
`HEARTH_DEEP_MODEL_FILE` (what this install actually placed) > the persona's
declared id (a default for a checkout with no install record).

### Two budgets for one context

`HEARTH_CTX_MAX_TOKENS` defaults to 32768 in `settings.py` and the renderer
never wrote it, so the harness packed prompts against 32768 while llama-server
was started with the plan's window. Latent while the brain was dead; a
truncation waiting for a long enough conversation. The renderer writes it now.

### An install that could not serve a model still reported success

`build_specs` in `house.rs` validated the backend, python and supervisor and
then started the house anyway. The missing-model failure surfaced four screens
later as a refused WebSocket during the first conversation. It now checks the
planned model and `llama-server` before anything starts, and says which file is
missing.

### PYTHONPATH used the Windows separator

`house.rs` built `PYTHONPATH` with `;`, hardcoded from the Windows-only days.
On macOS that makes both entries one nonexistent directory, which Python
discards in silence — the harness only kept importing because its working
directory covered for it. Now platform-correct.

### The first greeting raced the brain and hung forever

`VoiceTest.tsx` fires its greeting 800 ms after the socket opens when the voice
is non-resident, waiting for nothing. llama-server needs ~23 s to load weights
on a cold install, so the greeting always lost, the harness emitted
`{"action":"error"}`, and the client — which handled only `tts_chunk_start`,
`ai_response` and `speaking_complete` — ignored it. `phase` stayed `asking`,
and the one button on that screen is disabled while `phase === 'asking'`. The
person was trapped on the last screen of setup with no way forward.

It now retries for the same 150 s the resident path spends waiting on the
voice, then surfaces the real error and lets the person through. **Built but
not yet exercised** — reaching it again needs another clean install.

## The catalogue, and why context stopped being residue

The planner took the best quantisation that fit and let the context window be
whatever survived. On this machine that produced **9216 tokens** against a
persona prompt measured at **1263** — a model that cannot hold a conversation
it is otherwise good enough to have.

`TARGET_CTX = 16384` is a constraint now. Tier selection is untouched: trading
down a MODEL to buy context would mean more memory could yield a worse brain,
and that ordering is load-bearing. The trade happens only within the chosen
tier, walking a `builds:` ladder ordered best-quality-first. Tier 0 grew four
rungs; every size and hash was read from the Hugging Face LFS records rather
than a model card, and builds whose hashes were not verified were deliberately
left out — a build the planner can choose is a build the installer must be able
to check.

The result on this machine, derived rather than hardcoded:

    The Q4_K_M build fits but would leave only 9216 tokens of context,
    so this is the IQ4_XS build, which holds 18432 instead.

Tiers 1-3 still carry the old single-fallback shape. They want the same ladder
once someone reads their numbers off the host.

Measured, once running: prompt processing **260-358 tok/s**, generation
**19.5-32 tok/s**. (An early "71 tok/s" figure came from a 2-token smoke test
and is not a real measurement — do not quote it.)

## The voice: the real finding

The 8 GB machine plans `coexist: false`, so `house.rs` never starts the voice
and the closing screen becomes a written first meeting. That is deliberate and
documented. But the reasoning underneath it does not survive contact.

**OmniVoice has no Metal path.** `tts_omnivoice.py:140` reads

    device = "cuda:0" if torch.cuda.is_available() else "cpu"

There is no MPS branch, so on **any** Mac of any size the voice runs on CPU.
Started by hand on this machine it loads fine, warms in 39 s, encodes Sulivan's
reference voice and reports ready — then synthesises at **7.6x realtime**
(64 s for 8.5 s of audio), and does not stream: first frame arrives with the
last. The 8 GB path is silent for a memory reason it never measured, while the
actual disqualifier is a device gap it does not model. **A 16 GB Mac plans
`coexist: true`, promises audio, and would deliver about a minute per
sentence.** That is the more urgent bug of the two.

The reserves driving the coexist decision were also checked against the
machine, and they are half right:

| Reserve | Dictionary | Measured here |
|---|---|---|
| `voice_resident_bytes` | 2.2 GiB | **2.27 GiB** — accurate |
| `stt_bytes` | 1.0 GiB | Whisper base is a **139 MB** download |
| `os_unified_bytes` | 3.0 GiB | **~2.0 GiB** wired, nothing running |

Roughly 1.5 GiB of phantom reservation, on a machine where 12 MB of weights
costs about 1000 tokens of context.

### Two replacement engines, benchmarked

Same sentence, same cloned reference voice, same machine.

| Engine | Memory | Device | RTF |
|---|---|---|---|
| torch (shipping) | 2.27 GiB | CPU | 7.6x |
| MLX-4bit | 0.66 GiB | Apple GPU | 3.7x best, ~10x avg |
| **omnivoice.cpp Q8_0** | ~900 MB | **Metal** | **see below** |

MLX loads in 2.1 s and is small, but is not fast enough, and its per-call time
climbed within a single process (3.67x -> 14.20x -> 15.56x) for reasons that
were not chased down. Not recommended.

`omnivoice.cpp` builds on macOS with `cmake .. -DGGML_METAL=ON` (there is no
`buildmetal.sh`; `buildcpu.sh` uses `nproc`, which does not exist here).
It reports `LM backend: MTL0` and ships a `tts-server` binary that speaks
OpenAI's `/v1/audio/speech`, which is the same shape as llama-server and would
drop into the existing supervisor pattern. Its GGUF weights come from
`Serveurperso/OmniVoice-GGUF`; the repo that `models.sh` points at is gated.

MaskGIT decode steps are the lever, and they are nearly linear:

| Steps | Synth | RTF (cloned voice) |
|---|---|---|
| 32 (default) | 19.6 s | 4.37x |
| 16 | 9.8 s | 2.18x |
| 8 | 5.2 s | 1.16x |
| 4 | 2.8 s | **0.63x** |

**Under realtime, with voice cloning, on an 8 GB Air.** Quality at 4 steps has
not been judged; samples went to Joshua to listen to, and that ear decides
whether this is shippable or whether 8 steps is the floor.

Voice cloning roughly doubles cost: the server with its default voice runs
1.73x at 32 steps where the cloned CLI runs 4.37x.

### Both resident at once

The Windows shape, tested directly: llama-server holding IQ4_XS at 18432
context, and `tts-server` holding OmniVoice, at the same time on 8 GB.

- Both worked. The brain answered; the voice synthesised.
- Voice cost of coexistence: **1.73x alone -> 1.79x together**, about 3.5%.
- Wired 5.55 GiB, and macOS *shrank* its swap file rather than growing it.

So the planner's `coexist: false` verdict for this class of machine is an
artifact of the engine it was measured against. With a Metal voice at ~900 MB
instead of a CPU voice at 2.27 GiB, this Air has room for both — and the
take-turns orchestration that `coexist: false` promises as an interim may never
need to be built.

## Open, in the order I would take them

1. **Adopt `omnivoice.cpp` as the voice engine.** One engine covers Metal,
   CUDA, Vulkan and CPU, replacing the torch path everywhere rather than adding
   a third Mac-only engine. It needs a per-platform binary in the dictionary's
   `runtime` block, exactly like llama-server already has. It emits 24 kHz
   against the configured `HEARTH_TTS_SAMPLE_RATE=48000`. The server API does
   not expose a per-request reference voice, so cloning needs either a
   server-side default or an ABI change.
2. **Re-derive the reserves from measurement**, and revisit `coexist` for
   8 GB once the voice is ~900 MB.
3. **The tool round trip costs 25 seconds a turn.** A successful two-word reply
   measured `turn_total_ms: 33403`, of which `tool_round_trip_ms: 25528` with
   `tools_invoked: []`. llama-server's own log shows that call generating
   **270 tokens to decide to call nothing** (3511 tokens total, 13.8 s of eval
   at 19.5 tok/s). Suspect `--reasoning auto` letting the model think out loud
   in the decision call; unproven. This is the single biggest thing between
   this install and feeling usable.
4. **Tell the truth about audio.** `server.py:606` hardcodes
   `"audio_generation": True` while `/voice/ready` correctly reports false; the
   turn emits `tts_chunk_start`/`speaking_complete` with no frames behind them;
   and the house has none of the honest copy the setup screen has. The one
   machine that cannot speak is the one that never explains itself.
5. **`default_install_root()` collides with a checkout.** It returns
   `$HOME/Hearth` with no override, which on this machine was the git repo —
   provisioning wrote into the working tree, and the runbook's uninstall test
   (`delete ~/Hearth`) would have destroyed it. Refusing a root containing
   `.git` is a few lines.
6. **The `n_ctx` warning is now misleading.** `HEARTH_LLAMA_CTX=18432 is below
   persona deep_model.n_ctx=65536` still fires, but the persona's declared
   context has no bearing on what runs. Read it from the resolved model.

## One trap worth carrying to the other session

`git status` will lie to you after an install that touched the checkout.
Python's `venv` writes a `.gitignore` containing `*` INSIDE the environment it
creates, so a 1.2 GB `envs/` directory sat in the working tree reporting
nothing. Use `git status --short --ignored=matching` to see it.
