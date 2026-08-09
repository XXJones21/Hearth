---
title: Voice
status: draft
last_reviewed: 2026-08-08
related:
  - ../backend/voice-engine.md
  - personas.md
sources:
  - backend/harness/valar/voice/tts_cpp.py
  - backend/harness/valar/voice/tts_remote.py
  - backend/harness/valar/tools/handlers/creation.py
  - crates/hearth-probe/dictionary.yaml
  - wiki/backend/voice-engine.md
---

# Voice

Every persona in Hearth speaks out loud, and the whole path from text to sound
runs on your own machine. This page covers how a persona gets its voice, what
runs underneath it, and what the voice can do beyond reading words flatly.

## How a persona gets a voice

You give a persona its voice during the creation interview, not by picking
from a list. You describe it in plain attributes, drawn from a fixed
vocabulary: a gender, an age range (child through elderly), a pitch (very low
through very high, or a whisper), and optionally an accent (American,
British, Australian, Japanese, and others). Hearth passes those attributes to
the voice engine's design mode, which synthesizes one sample clip from them.

That clip becomes the persona's permanent reference. Every sentence the
persona speaks afterward is cloned from it, the same cloning technique behind
any modern voice engine, just run against a voice that was designed rather
than recorded from a real person. Design happens once, at creation; cloning
happens on every turn after that.

Voice design is best effort. If the engine that can design a voice is not
available at the moment you create a persona, Hearth still creates the
persona, just without a reference clip yet, rather than having it borrow
another persona's voice to cover the gap. The design is recorded and
completed the next time the voice engine can run it. See
[Personas](personas.md) for the rest of what the creation interview sets up.

## The engine

Personas speak through OmniVoice, run locally by `omnivoice.cpp`, a compiled
C++ engine built on the same GGUF weight format and GGML backend that
`llama.cpp` uses for text generation. Nothing about your voice, or what your
persona says with it, leaves your machine. The compiled engine is the default
on both Windows and macOS: it runs on Metal, CUDA, or Vulkan, so it is native
to Apple Silicon and to a Windows GPU alike, unlike an earlier Python
implementation that had no path onto Apple's GPUs at all and fell back to the
CPU there. On the reference Windows machine, measured on CUDA with Q8_0
weights, first audio starts about 0.53 seconds into a turn, comfortably under
a second, with the engine itself taking roughly 5 percent of the audio's own
length to generate it.

## Expressive performance

A persona's voice can do more than read text aloud. Its system prompt teaches
it a small set of non-verbal tags, including `[laughter]`, `[sigh]`,
`[confirmation-en]`, and several tags for questions and surprise, which it can
place inline in a reply. The engine performs these rather than reading them as
words: `[laughter]` produces a laugh, not the word "laughter". A listening
test against the compiled engine confirmed this by ear, comparing plain,
tagged, and tag-only audio.

The same mechanism carries exact pronunciation. Hearth can steer a word's
sound using CMU arpabet brackets, a phoneme-by-phoneme spelling the engine
performs instead of reading literally. The persona Sulivan is one example:
spelled with a single L on screen, but sent to the voice as
`[S AH1 L AH0 V AH0 N]` so it comes out sounding like "Sullivan."

None of this markup reaches your eyes. The text shown in the chat window is
cleaned of both the performance tags and any pronunciation brackets before
display; only the voice engine receives them, whole.

## Local speech recognition

On desktop, Hearth listens to you locally too. It transcribes speech with a
Whisper base model running on your machine, sized into the same memory budget
as the language model and the voice engine, so nothing you say has to leave
the device to be turned into text.

## Status

The compiled engine is proven on Windows and macOS. Linux still runs the
older Python-based engine until the same measurement is repeated there. The
engine loads its list of voices at startup, so when a new persona is created
the desktop app restarts the voice engine with a fresh scan; their voice
wakes during the handover, which is why the setup guide asks for a moment
before the new persona speaks.
