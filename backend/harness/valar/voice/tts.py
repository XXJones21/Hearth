"""Streaming TTS adapter over the existing NeuTTS-Air implementation.

WIRED-via-reuse: delegates to Server.tools.tts_generator (the existing
NeuTTS-Air voice-cloning engine with a real streaming generator,
generate_tts_stream -> (float32_chunk, sample_rate)). We do NOT reimplement
TTS; we adapt the existing synchronous generator into an async stream the
gateway can pump out as PCM chunks.

Coupling note (the one real seam): the existing TTSGenerator pulls the voice
reference from Server.model_manager.ModelManager (a singleton tied to the old
server's persona state), NOT from a per-call argument. For Valar's clean
persona engine to drive the voice, ModelManager's current persona must match
Valar's. Two ways to satisfy this at runtime, both flagged TODO for live
validation:
  1. Point ModelManager at the same persona on startup/switch (call its
     load/switch), or
  2. Add a per-call ref_codes/ref_text override to generate_tts_stream.
For v1 this adapter calls the existing stream as-is (uses ModelManager's loaded
voice). The persona-sync hook is a clear, isolated TODO below — no TTS logic is
reimplemented here.
"""

from __future__ import annotations

import asyncio
import logging
import sys
import threading
from pathlib import Path
from typing import AsyncIterator, Optional

logger = logging.getLogger("valar.voice.tts")


class NeuTTSStreamer:
    """Async wrapper around the existing synchronous NeuTTS streaming generator."""

    def __init__(self, repo_root: Path, service: str = "neutts_air", sample_rate: int = 48000):
        self.repo_root = Path(repo_root)
        self.service = service
        self.sample_rate = sample_rate
        self._manager = None  # the existing tts_manager singleton
        self._loaded = False
        # Per-persona voice reference, encoded once and passed per TTS call. The
        # active selection (_ref_codes/_ref_text/_voice_key) plus a cache of every
        # persona's encoded codes keyed by ref-audio path, so switching back to a
        # persona is instant instead of paying a ~7s re-encode every switch.
        self._ref_codes = None
        self._ref_text: Optional[str] = None
        self._voice_key: Optional[str] = None  # source ref-audio path of the active codes
        self._voice_cache: dict = {}  # key -> (codes, ref_text)
        # Serializes import + backbone load + reference encode. The startup warm-up
        # and a client request both call sync_persona_voice via run_in_executor; an
        # unguarded race means two threads construct NeuTTSAir concurrently, which
        # fails in the torch codec init ("Cannot copy out of meta tensor") in BOTH
        # threads and leaves the process alive but permanently voiceless (0 frames,
        # /health ready:false). Reproduced 2026-06-03 on the valar-tts service;
        # the same race explains the gateway's historical meta-tensor failures.
        self._sync_lock = threading.Lock()

    def _ensure_imported(self) -> None:
        if self._loaded:
            return
        # Make the existing Server package importable (its modules use
        # `from Server.model_manager import ...`, so the repo root must be on path).
        repo_str = str(self.repo_root)
        if repo_str not in sys.path:
            sys.path.insert(0, repo_str)
        try:
            from Server.tools.tts_generator import tts_manager  # type: ignore
        except Exception as exc:  # noqa: BLE001 - heavy optional deps
            raise TtsUnavailable(
                f"could not import existing NeuTTS-Air TTS (Server.tools.tts_generator): {exc}"
            ) from exc
        self._manager = tts_manager
        self._loaded = True

    def sync_persona_voice(self, ref_audio: Optional[Path], ref_text: Optional[str]) -> None:
        """Encode the active persona's voice reference once and cache it.

        Valar's PersonaEngine is the source of truth for the cloned voice. We
        encode the reference here via the shared NeuTTS backbone and pass the
        codes per-call into generate_tts_stream (see stream_sentence) — so the
        voice never depends on the legacy server's ModelManager persona state.
        Cached by source path so repeated turns on one persona don't re-encode;
        a no-op when ref_audio is None. encode_reference is GPU-heavy, so callers
        should run this off the event loop (the voice loop uses an executor).
        """
        if ref_audio is None:
            return
        key = str(ref_audio)
        # The cache checks live INSIDE the lock so a caller that raced the warm-up
        # blocks until the load/encode finishes, then takes the cached-hit path.
        with self._sync_lock:
            if key == self._voice_key and self._ref_codes is not None:
                return  # already the active voice
            cached = self._voice_cache.get(key)
            if cached is not None:
                # Encoded on a previous turn — reselect instantly. This removes the
                # ~7s re-encode tax when toggling personas (e.g. Sulivan <-> Selene),
                # which the old single-slot cache paid on every switch-back.
                self._ref_codes, self._ref_text = cached
                self._voice_key = key
                logger.info("persona voice (cached) -> %s", ref_audio)
                return
            self._ensure_imported()
            from Server.model_manager import ModelManager  # type: ignore

            engine = ModelManager.get_instance().ensure_neutts_backbone()
            if engine is None:
                logger.warning("NeuTTS backbone unavailable — cannot encode persona voice")
                return
            codes = engine.encode_reference(str(ref_audio))
            self._voice_cache[key] = (codes, ref_text)
            self._ref_codes = codes
            self._ref_text = ref_text
            self._voice_key = key
            logger.info("persona voice synced (ref=%s)", ref_audio)

    async def stream_sentence(self, text: str) -> AsyncIterator[bytes]:
        """Yield float32 PCM byte chunks for one sentence as TTS generates them.

        Bridges the existing synchronous generator (generate_tts_stream, which
        yields (float32 ndarray, sample_rate)) onto the event loop via a queue
        fed from a worker thread, emitting each chunk as little-endian float32
        PCM bytes (the format the Echo/Apple clients decode).
        """
        self._ensure_imported()
        loop = asyncio.get_running_loop()
        queue: asyncio.Queue = asyncio.Queue(maxsize=64)
        _SENTINEL = object()

        def _produce() -> None:
            try:
                for chunk_np, _sr in self._manager.generate_tts_stream(  # type: ignore[union-attr]
                    text,
                    service=self.service,
                    target_sample_rate=self.sample_rate,
                    ref_codes=self._ref_codes,
                    ref_text=self._ref_text,
                ):
                    pcm = _chunk_to_pcm_bytes(chunk_np)
                    if pcm:
                        loop.call_soon_threadsafe(queue.put_nowait, pcm)
            except Exception as exc:  # noqa: BLE001
                logger.error("TTS stream worker error: %s", exc)
            finally:
                loop.call_soon_threadsafe(queue.put_nowait, _SENTINEL)

        worker = loop.run_in_executor(None, _produce)
        try:
            while True:
                item = await queue.get()
                if item is _SENTINEL:
                    break
                yield item
        finally:
            await worker


class TtsUnavailable(RuntimeError):
    pass


def _chunk_to_pcm_bytes(chunk_np) -> bytes:
    """Serialize a float32 audio chunk to little-endian float32 PCM bytes.

    Matches the proven legacy deep-agent server's tts_chunk_* streaming format
    (Server/skills/tts_subagent.py emits `chunk_np.tobytes()` on float32 arrays)
    and what the voice clients decode: Echo `ENCODING_PCM_FLOAT`, Apple
    `pcmFormatFloat32`. 4 bytes/sample, range [-1, 1]. (Was int16 — a bug that
    played as noise on the float32 clients.)
    """
    try:
        import numpy as np  # type: ignore
    except ImportError:  # pragma: no cover
        return b""
    arr = np.asarray(chunk_np, dtype=np.float32).reshape(-1)
    arr = np.clip(arr, -1.0, 1.0)
    return arr.astype("<f4").tobytes()
