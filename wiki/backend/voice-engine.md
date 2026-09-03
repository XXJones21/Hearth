---
title: The voice engine
status: draft
last_reviewed: 2026-09-03
related:
  - build-pipeline.md
  - native-runtime.md
  - component-catalog.md
  - ../first-run.md
sources:
  - backend/harness/valar/voice/tts_cpp.py
  - backend/harness/valar/voice/tts_omnivoice.py
  - backend/harness/valar/voice/tts_service.py
  - backend/harness/valar/tools/handlers/creation.py
  - scripts/build_omnivoice.sh
  - vendor/omnivoice/patches/
  - a live first run on macOS, 2026-08-08
---

# The voice engine
How a persona gets a voice, and what the two engines underneath can and cannot
do. Written after a made persona spoke in someone else's voice on its first
sentence, which turned out to be three defects stacked on a capability everyone
assumed was missing and was not.

## Design once, clone always

One sentence carries the whole architecture. A persona's voice is **designed**
exactly once, at creation, from a handful of instruct attributes; the audio
that comes back becomes their reference clip; and every sentence they ever
speak afterwards is ordinary **cloning** from that clip.

This is why the runtime never depends on design support, why design can afford
to be slow, and why a persona whose design failed is not a persona with a
degraded voice. It is a persona with no voice at all, falling back to whatever
the engine was last told to use.

## Two engines behind one seam

Everything above the TTS seam is engine-agnostic: `sync_persona_voice` then
`stream_sentence`, and the layer above neither knows nor cares which is
underneath.

| | `OmniVoiceStreamer` | `OmniVoiceCppStreamer` |
| --- | --- | --- |
| Implementation | Python, torch | C++/GGML, `omnivoice.cpp` |
| Where it runs | CUDA | Metal, CUDA, Vulkan, ROCm |
| Weights | HF snapshot + torch env | two GGUF files |
| Cost in the install | ~2.27 GiB torch process | a socket |
| Voice design | `design_sample()`, in-process | a second binary, below |

The split is not a preference. Torch selects `cuda:0 if available else cpu`,
which on Apple Silicon means the CPU and about 7.6x realtime: unusable, and
unusable on every Mac rather than only the small ones. `omnivoice.cpp` clears
realtime on an 8 GB Air, so macOS runs it. The same engine covers CUDA and
Vulkan, so this is not a Mac-only detour.

## Four binaries upstream, two of them ours

`omnivoice.cpp` builds four things. Which ones we ship is the decision this
article exists to record, because getting it wrong is invisible until a
persona opens its mouth.

| Binary | What it is | Shipped |
| --- | --- | --- |
| `tts-server` | HTTP, OpenAI `/v1/audio/speech`, streaming, cloned voices | yes |
| `omnivoice-tts` | CLI, one-shot synthesis, **`--instruct`** | yes, since 2026-08-08 |
| `omnivoice-codec` | pre-encode a reference to `.rvq` | no |
| `quantize` | GGUF quantization | no |

`scripts/build_omnivoice.sh` builds both shipped binaries from a pinned
upstream (`4f33af8`) plus our patches in `vendor/omnivoice/patches/`, and drops
them in `desktop-client/src-tauri/resources/`. Nothing is compiled on a user's
machine.

### What `tts-server` can do, and the wall it hits

Routes and request fields, read off the binary rather than assumed:

```
routes:  /health   /v1/audio/speech   /v1/models   /v1/voices
fields:  input  model  response_format  speed  voice
flags:   --batch --codec --host --lang --model --no-fa --port --steps --voice
```

Voices are loaded **at the engine's startup**, one `--voice name:clip.wav:transcript.txt`
per persona, because encoding a reference is the expensive half of cloning and
doing it once is the whole reason the server exists. `house.rs`'s
`persona_voices()` builds that list by scanning the personas directory at
launch, and the persona's DIRECTORY names the voice, lowercased, so the
supervisor and `tts_cpp.voice_name_for()` agree without a table between them.

Two consequences:

- **A voice the engine was not given does not exist.** `{"voice":"silas"}`
  returns `400 unknown voice 'silas'`, which is the correct and loud failure.
- **A persona created after launch is not registered until the engine
  restarts.** Open, see below.

**There is no way to design a voice through this server.** `/v1/audio/speech`
validates `voice` against the registered names before anything else, so
instruct attributes cannot reach the engine. Passing them as the voice field
returns `unknown voice 'female, young adult, very high pitch, british accent'`.

### The capability was there the whole time

This is the part worth remembering, because it cost a wrong diagnosis twice.
The shipped `tts-server` binary contains:

```
ov_synthesize : instruct '%s' could not be resolved against the voice-design vocabulary
Unsupported instruct items found in
Conflicting instruct items within the same category:
[TTS-Stream] voice design + streaming : peak normalisation disabled
omnivoice.special.instruct_start / instruct_end
```

The engine has voice design, with vocabulary validation and category-conflict
checks matching [OmniVoice's own documentation](https://github.com/k2-fsa/OmniVoice/blob/master/docs/voice-design.md).
The **server** simply never surfaces it. So "macOS cannot design voices" was
wrong, and so was "this needs an upstream patch": it needed a binary we were
already building the source for and throwing away.

`omnivoice-tts` reaches it:

```
omnivoice-tts --model <base.gguf> --codec <tokenizer.gguf> \
              --instruct "female, young adult, british accent" \
              -o out.wav  < text
```

Verified by measuring the output rather than trusting the exit code, because a
process that returns a WAV has not necessarily honoured anything:

| instruct | median F0 |
| --- | --- |
| `female, young adult, very high pitch, british accent` | 235, 209 Hz |
| `male, elderly, very low pitch, russian accent` | 106, 88 Hz |

A 2.3x separation with no overlap. Through the server, the same two instructs
both landed at 99–152 Hz, the default voice with sampling noise, which is what
"the attribute never arrived" looks like when you only listen once.

## What the cpp engine does NOT do

**Performance tags.** Every made persona's system prompt offers thirteen
non-verbal tags (`[laughter]`, `[sigh]`, `[confirmation-en]` and the rest)
promising they "will be sounded rather than read". The torch engine sounds
them. This one does not, and its own log says why:

```
[BPE] Registered 7 OmniVoice special tokens (total specials=8)
```

Those seven are `denoise`, `lang_start/end`, `instruct_start/end` and
`text_start/end`. The tags are not among them, so BPE tokenizes them as
ordinary text and the persona reads them aloud. Measured: `"[confirmation-en]
Good day."` runs 1.93s against 0.93s for the bare sentence and 1.85s for the
words read as prose.

`tts_cpp.stream_sentence` strips them before synthesis. The prompt keeps them,
deliberately: they are correct on the other engine, and a persona's system
prompt should not be rewritten by which binary happens to be installed. The
difference between engines belongs in the engine adapter, which is where it now
lives.

## How a persona gets a voice, end to end

1. The interview commits. `create_persona` validates the instruct attributes
   against the vocabulary OmniVoice accepts and drops unknown ones, so a
   creative interviewer cannot crash the commit.
2. `_design_voice` runs `omnivoice-tts --instruct` as a subprocess, up to a
   300s timeout: a cold model load plus a full synthesis pass.
3. The WAV lands at `personas/<Name>/voice/<name>_voice_reference.wav` with its
   transcript beside it. That pair is what `--voice` will point at.
4. Every later sentence clones from it through `tts-server`.

Design unavailable stays a **normal state** rather than an error: a house with
no voice engine still makes personas. What changed is that it is now
unavailable for a reason that gets logged, and the persona that results does
not borrow someone else's voice to cover it.

## The failure that produced this article

Worth keeping in full, because each layer hid the one below.

1. **Design 500'd.** `_design_voice` POSTed to the voice service's `/design`,
   which only the torch engine implements. On the cpp engine it raised
   `AttributeError: 'OmniVoiceCppStreamer' object has no attribute
   'design_sample'`. Logged as `voice design unavailable` and moved on.
2. **The persona was created anyway**, with no reference clip:
   `loaded persona Silas (system_prompt=748 chars, voice_ref=none)`.
3. **The streamer kept the last voice it had.** `tts_service` only called
   `sync_persona_voice` `if ref_audio:`, so with no clip it was never called,
   `self._voice` still held `sulivan`, and every sentence went out under that
   name. `tts_cpp`'s docstring had already argued the exact point: *"a persona
   silently speaking in the default voice is worse than an error, nothing
   downstream can tell it happened"*. The guard that says so lives inside
   the call being skipped.

All three are fixed. The third is the one to remember: a guard is only a guard
if the path reaches it.

## Traps

- **`tauri.macos.conf.json` REPLACES the base resource list**, it does not
  merge into it. Adding a binary to `tauri.conf.json` alone produces a macOS
  bundle without it, with no warning anywhere, and the failure appears later as
  a missing capability rather than a missing file.
- **Tauri's resource copy does not carry the execute bit.** `provision.rs` sets
  0755 after copying each engine binary.
- **A designed WAV is not proof that instruct worked.** Measure the audio. The
  engine is non-deterministic, so byte comparison proves nothing either: two
  identical requests differ.

## Open questions

1. **When does a newly made persona's voice become available?** The engine
   loads voices at startup, so today the clip exists but the engine does not
   know it until something restarts the voice service. Restart it at commit, or
   defer the new voice to the next launch and accept that the persona's first
   conversation is voiceless?
2. **Should the performance tags be registered upstream?** It is the same patch
   shape as `vendor/omnivoice/patches/0001`, and it would let the cpp engine
   keep a promise the prompt already makes.
3. **Do the two engines keep two design paths?** The torch engine still has
   `design_sample` and the service's `/design` route. One of them is now dead
   weight on any install running the cpp engine.
4. **Which voices ship, and under what license?** Inherited from
   [build-pipeline.md](build-pipeline.md) and still unanswered.
