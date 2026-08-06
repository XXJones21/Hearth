"""Server-side Speech-to-Text (Whisper).

WIRED-via-reuse: uses the same `whisper` model the legacy Valinor server used
(`whisper.load_model("base")` + `.transcribe()` over a float32 16 kHz buffer),
extracted into a clean adapter. Lazy-loads the model on first use to avoid
paying the load cost (and VRAM) until a server-STT client actually connects.

The model import is deferred so the gateway can import/start without `whisper`
installed (it's only needed for the stt:"server" fork). If whisper is missing,
transcribe() raises a clear error that the gateway surfaces to the client.
"""

from __future__ import annotations

import logging
import struct
import threading
import time
from typing import Optional

logger = logging.getLogger("valar.voice.stt")


class WhisperSTT:
    """Lazy Whisper adapter. 16 kHz mono 16-bit PCM in, text out."""

    def __init__(self, model_size: str = "base", sample_rate: int = 16000):
        self.model_size = model_size
        self.sample_rate = sample_rate
        self._model = None  # loaded on first transcribe()
        # Serialize inference: whisper/torch is not safe under concurrent
        # transcribe on one model (the keep-warm tick vs a real utterance).
        self._infer_lock = threading.Lock()
        self._last_infer = 0.0  # monotonic; drives the keep-warm skip

    def _ensure_loaded(self) -> None:
        if self._model is not None:
            return
        try:
            import whisper  # type: ignore
        except ImportError as exc:  # pragma: no cover - runtime dependency
            raise SttUnavailable(
                "openai-whisper is not installed; server-side STT requires it "
                "(pip install openai-whisper). Clients can use stt:'local' instead."
            ) from exc
        logger.info("loading Whisper model '%s'", self.model_size)
        self._model = whisper.load_model(self.model_size)
        logger.info("Whisper model loaded")

    def warm(self) -> None:
        """Eagerly load the Whisper model AND run one dummy inference (startup
        warm-up). Loading alone is not enough: the first real transcribe still
        paid GPU graph init / VRAM paging inline on turn 1 (measured 31s on
        2026-06-06 with the 12B resident), which outlived the client's
        conversation timeout and produced zombie turns. Warm runs a short
        silence through the model so that cost lands in the background task."""
        self._ensure_loaded()
        try:
            silence = bytes(self.sample_rate)  # 0.5s of 16-bit silence
            self.transcribe_pcm16(silence)
            logger.info("Whisper warm inference complete")
        except Exception as exc:  # noqa: BLE001 - warm is best-effort
            logger.warning("Whisper warm inference failed: %s", exc)

    def keep_warm(self, max_idle_s: float) -> None:
        """Periodic keep-warm tick (gateway background task). The boot warm-up
        is not enough on the shared GPU: WDDM pages Whisper's VRAM out after
        idle minutes next to the resident brain + TTS, and the next real
        utterance pays 13-31s inline (measured 2026-06-06), outliving the
        client's listening window. A warm tick is ~0.1-0.3s. No-op when the
        model is not loaded or a real inference ran within ``max_idle_s``."""
        if self._model is None:
            return
        if time.monotonic() - self._last_infer < max_idle_s:
            return
        try:
            self.transcribe_pcm16(bytes(self.sample_rate))
            logger.debug("Whisper keep-warm tick complete")
        except Exception as exc:  # noqa: BLE001 - keep-warm is best-effort
            logger.warning("Whisper keep-warm tick failed: %s", exc)

    def transcribe_pcm16(self, pcm16: bytes) -> str:
        """Transcribe a buffered 16-bit PCM utterance to text."""
        if not pcm16:
            return ""
        self._ensure_loaded()
        audio_float = self._pcm16_to_float32(pcm16)
        if audio_float is None:
            return ""
        with self._infer_lock:
            result = self._model.transcribe(audio_float)  # type: ignore[union-attr]
            self._last_infer = time.monotonic()
        text = (result.get("text") or "").strip()
        logger.info("STT transcribed %d bytes -> %r", len(pcm16), text[:80])
        return text

    @staticmethod
    def _pcm16_to_float32(pcm16: bytes) -> Optional["object"]:
        try:
            import numpy as np  # type: ignore
        except ImportError as exc:  # pragma: no cover
            raise SttUnavailable("numpy is required for STT") from exc
        count = len(pcm16) // 2
        if count == 0:
            return None
        samples = struct.unpack(f"<{count}h", pcm16[: count * 2])
        arr = np.asarray(samples, dtype=np.float32) / 32768.0
        return arr


class SttUnavailable(RuntimeError):
    pass
