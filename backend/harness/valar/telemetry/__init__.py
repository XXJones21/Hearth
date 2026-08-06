"""Per-turn telemetry — the instrument §4.1 said was missing.

Logs context-fill (how much of the budget each prompt section used) and token
counts every turn from day one, so the sane context budget can be tuned with
evidence rather than fear. Emits a structured one-line JSON record per turn.
"""

from __future__ import annotations

import json
import logging
import time
from dataclasses import asdict, dataclass, field
from typing import Optional

logger = logging.getLogger("valar.telemetry")


@dataclass
class TurnTelemetry:
    """One conversational turn's instrumentation."""

    session_id: str
    persona: str
    stt_mode: str = "server"  # "server" | "local"

    # Context-fill accounting (token estimates from the budget estimator).
    persona_tokens: int = 0
    memory_tokens: int = 0
    history_tokens: int = 0
    user_tokens: int = 0
    prompt_tokens_est: int = 0
    context_budget: int = 0
    context_fill_pct: float = 0.0

    # History accounting (proves no 4-turn truncation).
    history_turns_included: int = 0

    # Generation accounting.
    completion_tokens_est: int = 0
    sentences_spoken: int = 0

    # Tool-calling accounting (Keystone 2). Empty on the default flag-OFF path.
    tools_invoked: list = field(default_factory=list)

    # Error accounting (Phase 1b). Empty/False on a clean turn. `partial` means
    # the stream died AFTER the first token — the user heard an incomplete
    # answer (the Hermes partial-stream-stub pattern); the truncated text is
    # recorded in history with an explicit marker.
    error_stage: str = ""
    error_kind: str = ""
    partial: bool = False

    # Timing (ms).
    stt_ms: float = 0.0
    brain_first_token_ms: float = 0.0
    brain_total_ms: float = 0.0
    tts_total_ms: float = 0.0
    turn_total_ms: float = 0.0
    # Flag-gated tool round-trip cost (decision call + handler exec). 0.0 when
    # tools are off; the number that decides whether a "thinking" filler is worth it.
    tool_round_trip_ms: float = 0.0

    _start: float = field(default_factory=time.monotonic, repr=False)

    def finalize(self) -> None:
        self.turn_total_ms = (time.monotonic() - self._start) * 1000.0
        if self.context_budget > 0:
            self.context_fill_pct = round(
                100.0 * self.prompt_tokens_est / self.context_budget, 2
            )

    def emit(self) -> None:
        self.finalize()
        record = {k: v for k, v in asdict(self).items() if not k.startswith("_")}
        logger.info("turn %s", json.dumps(record, separators=(",", ":")))


class Timer:
    """Context manager to measure a phase and record milliseconds into a slot.

    With ``accumulate=True`` the elapsed time is ADDED to the slot instead of
    overwriting it — for phases that run once per sentence (TTS) where the turn
    metric is the sum, not the last sentence's time.
    """

    def __init__(self, telemetry: TurnTelemetry, field_name: str, accumulate: bool = False):
        self.telemetry = telemetry
        self.field_name = field_name
        self.accumulate = accumulate
        self._t0 = 0.0

    def __enter__(self) -> "Timer":
        self._t0 = time.monotonic()
        return self

    def __exit__(self, *exc) -> None:
        elapsed_ms = (time.monotonic() - self._t0) * 1000.0
        if self.accumulate:
            elapsed_ms += getattr(self.telemetry, self.field_name, 0.0)
        setattr(self.telemetry, self.field_name, round(elapsed_ms, 2))
