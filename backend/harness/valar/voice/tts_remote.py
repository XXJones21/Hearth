"""Remote TTS client — the thin Valar-side half of the decoupled TTS.

Talks to the persistent ``valar-tts`` service (tts_service.py) over WebSocket, so
the Valar gateway NEVER loads NeuTTS in-process and a gateway restart costs no GPU
reload. Implements the SAME interface as the in-process ``NeuTTSStreamer``
(``sync_persona_voice`` + ``stream_sentence``), so the voice loop is unchanged and
the backend is a config switch.

``sync_persona_voice`` does NO GPU work here — it just records the active voice
reference, sent per call so the service (which owns the encode + cache) uses the
right clone. ``stream_sentence`` opens a fresh WS per sentence: simple, and
concurrency-safe (each call is independent; the service serializes on its GPU),
with negligible connect cost on loopback. A failure yields nothing, so the voice
loop's ``_speak`` keeps the turn alive (same contract as a local TTS error).
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import AsyncIterator, Optional

import websockets

logger = logging.getLogger("valar.voice.tts_remote")


class RemoteNeuTTSStreamer:
    """Drop-in remote replacement for NeuTTSStreamer (WS client to valar-tts)."""

    def __init__(self, service_url: str, sample_rate: int = 48000):
        self.service_url = service_url
        self.sample_rate = sample_rate
        self._ref_audio: Optional[str] = None
        self._ref_text: Optional[str] = None

    def sync_persona_voice(self, ref_audio: Optional[Path], ref_text: Optional[str]) -> None:
        """Record the active persona voice reference (no GPU work). The service
        encodes + caches it on first use of this ref."""
        self._ref_audio = str(ref_audio) if ref_audio else None
        self._ref_text = ref_text

    async def stream_sentence(self, text: str) -> AsyncIterator[bytes]:
        """Stream one sentence's float32 PCM from the TTS service. Yields nothing
        on any failure (the turn continues without that sentence's audio)."""
        try:
            async with websockets.connect(
                self.service_url, ping_interval=None, max_size=None, open_timeout=10
            ) as ws:
                await ws.send(
                    json.dumps(
                        {"text": text, "ref_audio": self._ref_audio, "ref_text": self._ref_text}
                    )
                )
                frames = 0
                while True:
                    msg = await ws.recv()
                    if isinstance(msg, (bytes, bytearray)):
                        frames += 1
                        yield bytes(msg)
                        continue
                    obj = json.loads(msg)
                    action = obj.get("action")
                    if action == "tts_error":
                        logger.error("remote TTS error: %s", obj.get("message"))
                        break
                    if action == "tts_done":
                        break
                logger.info("remote TTS: yielded %d frames for %r", frames, text[:40])
        except Exception as exc:  # noqa: BLE001 - never break the turn for TTS
            logger.error("remote TTS stream failed (%s): %s", self.service_url, exc)
            return
