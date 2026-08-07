"""OmniVoice TTS streamer -- the NeuTTS-Air replacement engine (2026-06-04).

k2-fsa/OmniVoice: 0.6B Qwen3-base diffusion-LM TTS, Apache-2.0, zero-shot voice
cloning from ``ref_audio`` + ``ref_text`` -- the exact per-request contract the
valar-tts WS protocol already carries, so the gateway and every client are
untouched (the TTS seam). Chosen over NeuTTS after a same-reference A/B: clearly
better quality (the NeuTTS artifacts are gone), naturally paced, warm RTF
0.15-0.19 vs 0.51 on the shared 4080, peak VRAM 2.18 GB.

Implements the same streamer interface as ``NeuTTSStreamer``
(``sync_persona_voice`` + ``stream_sentence``) for ``create_tts_app``'s backend
fork (``HEARTH_TTS_SERVICE=omnivoice``). Runs in the ISOLATED ``omnivoice-venv``
(its torch is newer than valar-venv's cu118 pin -- never install omnivoice into
valar-venv).

Engine notes:
  * Generation is whole-sentence (no intra-sentence streaming); at warm RTF
    ~0.17 a typical sentence synthesizes in under a second, which beats the old
    streamed first-chunk latency. Output is chunked to ~0.25 s frames for client
    pacing parity.
  * Output is 24 kHz; resampled here (torchaudio) to the configured output rate
    (48 kHz -- the rate ``tts_chunk_start`` advertises).
  * The first generation pays a ~8 s CUDA warm-up; ``sync_persona_voice`` primes
    it once so turn 1 is fast (the service startup warm calls it).
  * All load + generate work is serialized behind one lock -- the lesson from
    the NeuTTS concurrent-load race (alive-but-voiceless service, 2026-06-03).
"""

from __future__ import annotations

import asyncio
import logging
import os
import threading
from pathlib import Path
from typing import AsyncIterator, Optional

logger = logging.getLogger("valar.voice.tts_omnivoice")

MODEL_ID = "k2-fsa/OmniVoice"
NATIVE_SAMPLE_RATE = 24000

# Diffusion steps: THE latency lever. 32 (model default) = RTF ~1.05 on the
# shared 4080; 16 = RTF ~0.5 (parity with the NeuTTS pace it replaces) with
# quality confirmed by ear. Override per deployment via env.
DEFAULT_NUM_STEPS = int(os.environ.get("HEARTH_OMNIVOICE_STEPS", "16"))


class OmniVoiceStreamer:
    """Async streamer over OmniVoice. Interface-compatible with NeuTTSStreamer."""

    def __init__(self, repo_root: Path, service: str = "omnivoice", sample_rate: int = 48000):
        self.repo_root = Path(repo_root)
        self.service = service
        self.sample_rate = sample_rate
        self._model = None
        self._ref_audio: Optional[str] = None
        self._ref_text: Optional[str] = None
        self._warmed = False
        self._gen_config = None  # OmniVoiceGenerationConfig(num_step=...)
        # Precomputed VoiceClonePrompt per ref-audio path (the NeuTTS
        # _voice_cache pattern): the ref is tokenized ONCE per persona, not per
        # sentence (~0.4 s/call saved), and switching back is instant.
        self._prompt = None  # the ACTIVE persona's prompt
        self._prompt_cache: dict = {}  # ref path -> VoiceClonePrompt
        # Serializes model load + generation (single GPU; and the NeuTTS race
        # taught us concurrent first-loads fail in ways that look like hangs).
        self._lock = threading.Lock()

    # --- health duck-typing (tts_service.py /health) ------------------------
    @property
    def _loaded(self) -> bool:  # "imported"
        return self._model is not None

    @property
    def _ref_codes(self):  # "ready": a voice prompt is set and the engine is warmed
        return True if (self._warmed and self._prompt is not None) else None

    # --- streamer interface --------------------------------------------------
    def sync_persona_voice(self, ref_audio: Optional[Path], ref_text: Optional[str]) -> None:
        """Make the requested persona voice the active one: load the model on
        first use, tokenize the reference ONCE into a cached VoiceClonePrompt,
        and pay the one-time CUDA warm-up generation. Runs off the event loop
        (executor) like the NeuTTS equivalent."""
        if ref_audio is None:
            return
        key = str(ref_audio)
        with self._lock:
            self._ensure_loaded()
            self._ref_audio = key
            self._ref_text = ref_text
            cached = self._prompt_cache.get(key)
            if cached is None:
                logger.info("creating voice clone prompt for %s ...", ref_audio)
                cached = self._model.create_voice_clone_prompt(  # type: ignore[union-attr]
                    ref_audio=key, ref_text=ref_text
                )
                self._prompt_cache[key] = cached
            self._prompt = cached
            if not self._warmed:
                logger.info("OmniVoice warm-up generation (one-time CUDA prime)...")
                self._model.generate(  # type: ignore[union-attr]
                    text="Hello.",
                    voice_clone_prompt=self._prompt,
                    generation_config=self._gen_config,
                )
                self._warmed = True
                # Release the warm-up diffusion high-water mark. PyTorch's caching
                # allocator otherwise keeps the prime's transient arena reserved
                # (~2GB idle), which on the shared 4080 is the difference between
                # fit and sysmem spillover. expandable_segments (set in the run
                # script) lets these freed blocks actually return to the driver.
                try:
                    import torch

                    torch.cuda.empty_cache()
                except Exception:  # pragma: no cover - best-effort VRAM reclaim
                    pass
                logger.info("OmniVoice warmed (voice ref=%s)", ref_audio)

    async def stream_sentence(self, text: str) -> AsyncIterator[bytes]:
        """Synthesize one sentence and yield float32 PCM chunks (~0.25 s each)
        at the configured output rate."""
        loop = asyncio.get_running_loop()
        pcm = await loop.run_in_executor(None, self._synth, text)
        if not pcm:
            return
        step = int(self.sample_rate * 0.25) * 4  # 0.25 s of float32 samples
        for i in range(0, len(pcm), step):
            yield pcm[i : i + step]

    # --- internals ------------------------------------------------------------
    def _ensure_loaded(self) -> None:
        if self._model is not None:
            return
        import torch
        from omnivoice import OmniVoice  # heavy; isolated venv only
        from omnivoice.models.omnivoice import OmniVoiceGenerationConfig

        device = "cuda:0" if torch.cuda.is_available() else "cpu"
        logger.info(
            "loading OmniVoice (%s) on %s (num_step=%d) ...", MODEL_ID, device, DEFAULT_NUM_STEPS
        )
        self._model = OmniVoice.from_pretrained(
            MODEL_ID, device_map=device, dtype=torch.float16 if device != "cpu" else None
        )
        self._gen_config = OmniVoiceGenerationConfig(num_step=DEFAULT_NUM_STEPS)
        logger.info("OmniVoice loaded")

    def _synth(self, text: str) -> bytes:
        import time

        import numpy as np

        with self._lock:
            self._ensure_loaded()
            if self._prompt is None:
                logger.warning("no voice reference set -- cannot synthesize")
                return b""
            t0 = time.monotonic()
            audio = self._model.generate(  # type: ignore[union-attr]
                text=text,
                voice_clone_prompt=self._prompt,
                generation_config=self._gen_config,
            )
            gen_s = time.monotonic() - t0
        dur = len(np.asarray(audio[0]).reshape(-1)) / NATIVE_SAMPLE_RATE
        logger.info("generate %.2fs for %.2fs audio (rtf %.3f)", gen_s, dur, gen_s / max(dur, 0.01))
        wav = np.asarray(audio[0], dtype=np.float32).reshape(-1)
        if self.sample_rate != NATIVE_SAMPLE_RATE:
            import torch
            import torchaudio.functional as AF

            t = torch.from_numpy(wav).unsqueeze(0)
            wav = AF.resample(t, NATIVE_SAMPLE_RATE, self.sample_rate).squeeze(0).numpy()
        wav = np.clip(wav, -1.0, 1.0)
        return wav.astype("<f4").tobytes()

    def design_sample(self, text: str, attributes: list[str]) -> bytes:
        """Voice DESIGN: synthesize `text` in a voice described by validated
        instruct attributes rather than cloned from a reference. Returns WAV
        bytes at NATIVE_SAMPLE_RATE, mono float32.

        The design-once-clone-always architecture: this runs exactly once per
        persona, at creation. The output becomes the persona's reference clip
        and every later sentence is ordinary cloning from it, so runtime
        never depends on design support. Never touches the cloning prompt or
        the resident voice.
        """
        import io
        import time

        import numpy as np
        import soundfile as sf

        # A LIST here is a batch dimension (one instruct per text); a single
        # text takes its attributes as one comma-joined string.
        attrs = [str(a).strip().lower() for a in attributes if str(a).strip()]
        instruct = ", ".join(attrs) if attrs else None
        with self._lock:
            self._ensure_loaded()
            # Design is a one-time cost per persona, so it buys quality that
            # streaming cannot afford: more MaskGIT steps than the resident
            # config runs (a 16-step design came back garbled once).
            from omnivoice.models.omnivoice import OmniVoiceGenerationConfig
            design_config = OmniVoiceGenerationConfig(num_step=max(32, DEFAULT_NUM_STEPS))
            t0 = time.monotonic()
            audio = self._model.generate(  # type: ignore[union-attr]
                text=text,
                instruct=instruct,
                generation_config=design_config,
            )
            gen_s = time.monotonic() - t0
        wav = np.asarray(audio[0], dtype=np.float32).reshape(-1)
        dur = len(wav) / NATIVE_SAMPLE_RATE
        logger.info(
            "design %.2fs for %.2fs audio (rtf %.3f, instruct=%s)",
            gen_s, dur, gen_s / max(dur, 0.01), attrs,
        )
        buf = io.BytesIO()
        sf.write(buf, np.clip(wav, -1.0, 1.0), NATIVE_SAMPLE_RATE, format="WAV")
        return buf.getvalue()
