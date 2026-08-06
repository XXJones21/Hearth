from .segmenter import SentenceSegmenter
from .stt import SttUnavailable, WhisperSTT
from .vad import EnergyVAD, VadEvent


class TtsUnavailable(RuntimeError):
    """The voice service could not produce audio for this sentence."""


__all__ = [
    "EnergyVAD",
    "SentenceSegmenter",
    "SttUnavailable",
    "TtsUnavailable",
    "VadEvent",
    "WhisperSTT",
]
