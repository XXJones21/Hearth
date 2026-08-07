# The macOS pass, where it stands

Written 2026-08-07, across the first real run on the Air and the work that
followed it. The runbook (`m1-air-runbook.md`) said what to do; this says what
happened, what was wrong, and what the numbers turned out to be.

The machine: 8 GB M2 Air (the fixture is named `m1-air-8gb`; the install record
reports **Apple M2**, so the fixture models a slightly different machine than
the one it ran on), macOS 27.0, arm64, Xcode 26.5.

## Where it ended up

Hearth installs, provisions, boots, holds a conversation, and **speaks in
Sulivan's own cloned voice, on Metal, with the mind and the voice both
resident on 8 GB**. The plan for this machine:

    tier 0  Gemma 4 E2B  Q4_K_M   coexist: true   n_ctx 17408
    downloads: 2.89 GiB weights + 0.88 GiB voice = 3.77 GiB

That is the preferred quantisation, the voice held in memory, and an install
little more than half the size of this morning's. Synthesis measured **RTF
0.961** on a real tool-grounded reply: faster than realtime, on the smallest
machine the product supports.

Boot revalidation works, quitting leaves no orphaned processes, and the
supervisor crate compiled clean on arm64 first try with no unix-side fixes.

## The install, before any of the voice work

### The plan chose a model; nothing told the house

The fatal one. `model_candidates()` built its candidate list solely from the
persona's `deep_model.id`, and Sulivan names `gemma-4-12b-qat` — tier 2's
model. The renderer wrote `HEARTH_MODELS` (which directory) and never wrote
which FILE, so every install that was not a tier 2 machine asked llama-server
for weights the installer had never downloaded, died at boot, and surfaced as
a refused WebSocket during the first conversation with setup already reporting
success.

**This was never a macOS bug.** Tier 0 and tier 1 installs failed identically
on Windows; tier 2 worked only because the hardcoded id happened to match.

The renderer writes `HEARTH_DEEP_MODEL_FILE` now, honoured by the supervisor
and the harness, ranked below the developer override and above the persona's
declared default.

### Two budgets for one context

`HEARTH_CTX_MAX_TOKENS` defaults to 32768 and was never written, so the
harness packed prompts against 32768 while llama-server ran the plan's window.
Latent while the brain was dead; a truncation waiting for a long enough
conversation. Written now.

### Failures that arrived four screens late

`build_specs` validated the backend, python and supervisor and then started the
house anyway. It checks the planned model and the engine binaries first now,
and names the missing file.

### Smaller things that were still wrong

- `PYTHONPATH` used `;`, hardcoded from the Windows-only days. On macOS that
  makes both entries one nonexistent directory, which Python discards in
  silence; the harness only kept importing because its working directory
  covered for it.
- The first greeting fired 800 ms after the socket opened and lost a race with
  a 23-second model load. The harness emitted `{"action":"error"}`, the client
  had no handler for it, and the only button on that screen is disabled while
  a question is outstanding — so setup trapped the person on its last screen.
  It retries for 150 s now and then lets them through.

## Context stopped being residue

The planner took the best quantisation that fit and let the context window be
whatever survived. On this machine that produced **9216 tokens** against a
persona prompt measured at **1263**.

`TARGET_CTX = 16384` is a constraint now, and a tier only counts as fitting if
some build of it can hold that window. That second half came from the RTX 4080
fixture: with slightly more budget it reached the 26B and sat at the 4096
floor, which is a worse machine than the same card running the 12B at 65536.
Largest model that technically loads is not the best plan.

Tier 0 grew a `builds:` ladder, every size and hash read from the Hugging Face
LFS records. Builds whose hashes were not verified were left out: a build the
planner can choose is a build the installer must be able to check.

Measured on the machine: prompt processing **260-358 tok/s**, generation
**19.5-32 tok/s**. (An early "71 tok/s" came from a 2-token smoke test and is
not a real measurement.)

## The voice: what was actually wrong

The 8 GB Air planned `coexist: false` and the house never started the voice.
The reasoning underneath that turned out not to survive contact.

**OmniVoice has no Metal path.** `tts_omnivoice.py` reads

    device = "cuda:0" if torch.cuda.is_available() else "cpu"

No MPS branch, so on **any** Mac of any size the voice runs on the CPU. Started
by hand it loads fine, warms in 39 s, encodes the reference voice — and then
synthesises at **7.6x realtime**, first frame arriving with the last. The 8 GB
path was silent for a memory reason it never measured, while the real
disqualifier was a device gap it does not model. A 16 GB Mac plans
`coexist: true`, promises audio, and would deliver about a minute a sentence.

### The reserves were half right

| Reserve | Was | Measured |
|---|---|---|
| voice resident (torch) | 2.2 GiB | 2.27 GiB — accurate |
| Whisper STT | 1.0 GiB | **717 MiB** — sound |
| OS on unified memory | 3.0 GiB | ~2.0 GiB wired |

Whisper nearly got cut to a quarter on the strength of its 139 MB download.
Measured resident it is 213 MiB of torch import, 459 MiB of model, and 45 MiB
through one inference. **A download size is not a resident cost.**

### Three engines, benchmarked

Same sentence, same cloned reference voice, same machine.

| Engine | Memory | Device | RTF |
|---|---|---|---|
| torch (was shipping) | 2.27 GiB | CPU | 7.6x |
| MLX-4bit | 0.66 GiB | Apple GPU | 3.7x best, ~10x avg |
| **omnivoice.cpp Q8_0** | ~900 MB | **Metal** | **4.37x → 0.63x** |

MLX loads in 2.1 s and is small, but is not fast enough, and its per-call time
climbed within a single process for reasons that were not chased down.

`omnivoice.cpp` is a C++17/GGML implementation with real Metal, CUDA and
Vulkan backends, so it replaces the torch engine everywhere rather than adding
a Mac-only third one. MaskGIT decode steps are the lever, near linear:

| Steps | RTF (cloned voice) |
|---|---|
| 32 (upstream default) | 4.37x |
| 16 | 2.18x |
| **8 (shipped)** | **1.16x** |
| 4 | 0.63x |

Eight was chosen by ear from samples, not from the table.

### Both resident, which was the whole question

llama-server holding IQ4_XS at 18432 context and the voice engine holding
OmniVoice, at once, on 8 GB: both worked, and the voice went **1.73x alone →
1.79x together**, about 3.5%. macOS shrank its swap file rather than growing
it. That measurement is why `coexist: false` is gone for this class of machine
and why the take-turns orchestration may never need building.

## How the voice is built and shipped

**Bundled, not installed.** `scripts/build_omnivoice.sh` clones a pinned
upstream (`4f33af82`), applies `vendor/omnivoice/patches`, and builds;
`pack_backend.sh` ships the binary exactly as it already ships
hearth-supervisor. Nothing is cloned or compiled on a user's machine.

Statically linked: a default ggml build emits five dylibs linked by `@rpath`,
which inside a relocatable `.app` means shipping five more files and rewriting
install names. `BUILD_SHARED_LIBS=OFF` with the Metal shaders embedded gives
one 4 MB binary against system frameworks only.

Two patches upstream does not have:

- `--steps`, so the one performance lever is reachable from the server.
- `--voice name:clip.wav:transcript.txt`, resolving the OAI `voice` field into
  the ABI's reference fields. The ABI always took a reference; the server had
  no way to pass one. It accepts the persona's own `.wav` rather than a
  pre-encoded `.rvq`, which is what keeps `omnivoice-codec` and an encode pass
  out of provisioning entirely. Unknown voice names are refused BEFORE a
  response is committed, because the streaming path installs a chunked
  provider that sends 200 the moment it exists — a late error cannot change
  the status, and the caller would hear the default voice instead of the one
  it asked for. Both are worth upstreaming.

The Python side is now a client. `tts_service.py` already forked on
`HEARTH_TTS_SERVICE` and called that fork the TTS seam; `omnivoice-cpp` slots
in beside `omnivoice`. **The entire torch voice environment is gone** — no
`envs/voice`, no torch, no 3.1 GB snapshot. That was the slowest and most
failure-prone part of provisioning.

The reserve is gated by `cpp_platforms: [macos]`. Every other platform still
pays the torch figure until someone measures the C++ engine on CUDA. Cutting
it everywhere at once silently promoted an RTX 4080 to the 26B, which is
exactly what `rtx4080_does_not_reach_the_26b` exists to catch.

## Bugs found downstream of a working engine

Three, all mine, all found only by running it:

- **The voice stopped mid-word.** "I'm Sulivan" and then silence. The engine
  logged a clean `[TTS-Stream] Done`; the truncation was in the client. A
  bounded `asyncio.Queue` fed through `call_soon_threadsafe` fills before the
  consuming coroutine is scheduled, `put_nowait` raises `QueueFull` inside a
  loop callback, and the default handler swallows it. 2 MB of tracebacks
  nobody was reading. Unbounded now; the utterance is the bound.
- **The words arrived after he stopped talking.** Text came only from
  `ai_response`, which the harness emits after the whole reply is generated.
  Every `tts_chunk_start` already carries its segment's text; it is shown when
  that segment's first audio frame arrives, so the words track the voice. The
  house had the same silence, and its store has carried an unused
  `appendAssistantDraft` the whole time.
- **Audio generated but never heard.** `reset()` closed the AudioContext on
  every socket close, so a reconnect built a fresh one — and a context created
  outside a user gesture starts suspended. A suspended context does not
  advance `currentTime`, so frames scheduled against it start in the past and
  are discarded with no error. Frames are held until the context runs, the
  context is no longer closed on reset, and the first click or keypress of the
  session unlocks it.

## Toolchain traps, which will recur

- `~/.npm` contained root-owned files; `npm install` refuses.
  `sudo chown -R 501:20 ~/.npm`.
- **npm 11 installed no rolldown native binding**, because the lockfile was
  authored on Windows and its optional platform deps were skipped. The build
  dies in `vite build` with `Cannot find module @rolldown/binding-darwin-*`.
  `npm install --no-save @rolldown/binding-darwin-arm64@<version>` fixes it and
  does NOT survive a clean install, so it recurs on every fresh checkout.
- cmake is not on macOS by default (`brew install cmake`), and upstream's build
  scripts call `nproc`, which does not exist here.
- Gatekeeper never came up: a locally built `.app` carries
  `com.apple.provenance` and not `com.apple.quarantine`.
- **`git status` lies after an install that touched the checkout.** Python's
  `venv` writes a `.gitignore` containing `*` INSIDE the environment, so a
  1.2 GB `envs/` sat in the tree reporting nothing. Use
  `git status --short --ignored=matching`.
- **Building is not shipping.** `tts-server` was silently absent from the
  built `.app` because Tauri bundles only what `resources` lists, and a
  `backend.tar.gz` packed before a fix will happily unpack over it. Both were
  caught by looking inside the artifact, not by watching the build succeed.

## Open, in the order I would take them

1. **The tool round trip costs 25-35 seconds a turn.** A two-word reply
   measured `turn_total_ms: 33403` with `tool_round_trip_ms: 25528` and
   `tools_invoked: []`; the weather turns spent 34-35 s of a 49-52 s turn
   there. llama-server's log shows that call generating **270 tokens to decide
   to call nothing**. Suspect `--reasoning auto` letting the model think out
   loud in the decision call; unproven. Now that the voice clears realtime,
   this is the only thing between this install and feeling fast.
2. **A tool answer that announces instead of answering.** A weather query
   returned "Calling get_weather for your current location." as the whole
   reply — the progress filler, spoken as the answer, which the persona
   prompt explicitly forbids. The follow-through path in `voice_loop` exists
   for this; it did not fire.
3. **Measure omnivoice.cpp on CUDA and move Windows over.** One line in
   `cpp_platforms`. The torch engine is the reason Windows still reserves
   2.2 GiB for a voice.
4. **`App.tsx` gates house startup on `setupComplete`**, which is only set by
   the last button of the voice test. One stuck voice test makes a finished
   install unreachable forever — which happened here.
5. **`default_install_root()` collides with a checkout.** It returns
   `$HOME/Hearth` with no override, which on this machine was the git repo.
   The runbook's uninstall test would have destroyed it. Refusing a root
   containing `.git` is a few lines.
6. **Verify the voice GGUFs.** Their sha256 is not recorded, so the installer
   downloads them unchecked while checking everything else.
7. **The within-tier trade-down is untested.** With the measured reserves
   every fixture affords its preferred build, so nothing exercises the ladder.
8. The `n_ctx` warning still compares against the persona's declared 65536,
   which no longer has any bearing on what runs.
