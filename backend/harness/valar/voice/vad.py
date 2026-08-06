"""Server-side Voice Activity Detection.

Clean rewrite of the energy-based adaptive VAD from the legacy Valinor server
(archive/legacy-langgraph/start_sulivan_lan.py::UnifiedAudioProcessor). Same
algorithm and tuned constants (16 kHz mono, 100 ms frames, adaptive threshold,
3-frame speech onset / 10-frame silence offset) — extracted behind a clean,
testable class with no server coupling.

Consumes 16-bit PCM frames as they stream in over the WS; emits speech
start/end transitions so the gateway can buffer an utterance and hand it to STT.
"""

from __future__ import annotations

import logging
import struct
from dataclasses import dataclass

logger = logging.getLogger("valar.voice.vad")


@dataclass
class VadEvent:
    is_speaking: bool          # current speech-active state after this frame
    started: bool = False      # True on the frame speech turned on
    ended: bool = False        # True on the frame speech turned off


class EnergyVAD:
    """Adaptive energy-RMS VAD. One instance per active audio session."""

    def __init__(
        self,
        sample_rate: int = 16000,
        energy_threshold: float = 1000.0,
        speech_start_ms: float = 300.0,  # accumulated speech to start
        silence_end_ms: float = 800.0,   # accumulated trailing silence to end
        max_history: int = 50,
    ):
        # Time-based (ms), NOT frame-count: clients stream different frame sizes
        # (the Echo sends 20 ms frames, the legacy path 100 ms). Counting frames
        # made the silence window 5x too short on 20 ms frames; accumulating
        # milliseconds is frame-size agnostic.
        self.sample_rate = sample_rate
        self.energy_threshold = energy_threshold
        self.speech_start_ms = speech_start_ms
        self.silence_end_ms = silence_end_ms
        self.max_history = max_history
        self.reset()

    def reset(self) -> None:
        self._speech_ms = 0.0
        self._silence_ms = 0.0
        self._active = False
        self._history: list[float] = []

    @property
    def is_speaking(self) -> bool:
        return self._active

    def _adaptive_threshold(self) -> float:
        if not self._history:
            return self.energy_threshold
        ordered = sorted(self._history)
        background = ordered[len(ordered) // 4]  # 25th-percentile noise floor
        return background + self.energy_threshold

    def process_frame(self, pcm16: bytes) -> VadEvent:
        """Process one 16-bit PCM frame; return the resulting speech transition."""
        if len(pcm16) < 2:
            return VadEvent(is_speaking=self._active)
        n = len(pcm16) // 2
        samples = struct.unpack(f"<{n}h", pcm16[: n * 2])
        if not samples:
            return VadEvent(is_speaking=self._active)

        frame_ms = (n / self.sample_rate) * 1000.0
        energy = (sum(s * s for s in samples) / len(samples)) ** 0.5
        self._history.append(energy)
        if len(self._history) > self.max_history:
            self._history.pop(0)

        has_speech = energy > self._adaptive_threshold()
        if has_speech:
            self._speech_ms += frame_ms
            self._silence_ms = 0.0
        else:
            self._silence_ms += frame_ms
            self._speech_ms = 0.0

        event = VadEvent(is_speaking=self._active)
        if not self._active and self._speech_ms >= self.speech_start_ms:
            self._active = True
            event.is_speaking = True
            event.started = True
            logger.debug("VAD speech start (energy=%.1f)", energy)
        elif self._active and self._silence_ms >= self.silence_end_ms:
            self._active = False
            event.is_speaking = False
            event.ended = True
            logger.debug("VAD speech end")
        return event
