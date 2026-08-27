---
area: clients/desktop-client
status: open
depends_on: []
blocks: []
updated: 2026-08-26
---

# The desktop client cannot listen

Hearth's desktop client speaks and does not hear. Every other client can be
talked to; this one is text and images in, voice out.

## What is actually there

Verified 2026-08-26 against `hearth-client/`:

- `src/lib/audioPlayer.ts` holds an `AudioContext`, and it is playback only. It
  is the streaming TTS path and a one-shot path that deliberately shares the
  same context.
- There is **no** `getUserMedia`, `MediaRecorder`, or `SpeechRecognition`
  anywhere in the web layer.
- There is **nothing audio-related in the Tauri side** at all: no `cpal`, no
  capture, no permission plumbing.

So this is a missing capability, not a broken one. Nothing to debug.

## The part that is worse than the gap

The composer's placeholder reads **"Ask anything, or just start talking"**, and
the client has no way to hear someone start talking. A person who says the
words at their computer gets nothing and has no way to know why.

Either the capability lands or the sentence goes. The sentence is a one-line
change and should not wait for the capability.

## Where the transcription would happen

The house already runs Whisper for its other clients, so a desktop client does
not need its own model. Three shapes, and the choice is the whole design:

1. **Capture in the browser layer, transcribe on the house.** `getUserMedia`
   plus `MediaRecorder`, ship the audio to Valar, let the existing Whisper path
   answer. Least new code, one permission prompt, and it matches how the phone
   already works.
2. **Capture in Tauri.** A Rust capture path with `cpal`, which is what the
   voice engine already uses elsewhere in the product. More code and a better
   story for always-on listening, since a webview microphone is a poor place to
   put a wake word.
3. **On-device transcription in the client.** Not obviously worth it while the
   house is on the same machine.

The first is the one to build unless push-to-talk is not the target and a wake
word is.

## Open questions

- **Push to talk, or open mic?** The phone is tap-to-talk. A desktop that
  listens all the time is a different product decision and a different privacy
  conversation, and it should be made deliberately rather than arrived at.
- **Where the control goes.** There is no microphone affordance in the composer
  today, only Send.
- **What happens when the house is not reachable.** Speech that cannot be
  transcribed should fail visibly, not silently swallow what someone said.

## Related

[layout-modes.md](layout-modes.md) proposes a conversational layout whose whole
point is talking to the persona. A text-only conversational mode is honest but
thin, so these two are worth sequencing together.
