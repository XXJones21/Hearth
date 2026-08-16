"""Valar configuration — the single source of truth for the gateway.

Everything tunable lives here and is overridable via environment variables.
Crucially, the context budget is a CONFIG VALUE (not a hardcoded band-aid):
there is NO 4-turn / 120-char history truncation, NO 6000-char persona cap,
NO fixed 16k-ctx / q4-KV assumption. The resident brain is a 200k-capable MoE;
the budget below is sane, generous, and bounded — and observable via telemetry.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path


def _env_str(key: str, default: str) -> str:
    val = os.environ.get(key)
    return val if val is not None and val.strip() else default


def _env_int(key: str, default: int) -> int:
    raw = os.environ.get(key)
    if raw is None or not raw.strip():
        return default
    try:
        return int(raw.strip())
    except ValueError:
        return default


def _env_float(key: str, default: float) -> float:
    raw = os.environ.get(key)
    if raw is None or not raw.strip():
        return default
    try:
        return float(raw.strip())
    except ValueError:
        return default


def _env_bool(key: str, default: bool) -> bool:
    raw = os.environ.get(key)
    if raw is None:
        return default
    return raw.strip().lower() in ("1", "true", "yes", "on")


class HearthConfigError(RuntimeError):
    """A required location was neither configured nor derivable."""


# The file that marks the top of the product tree. It sits at HEARTH_ROOT in
# both layouts: /opt/hearth/manifest.yaml in the image, backend/manifest.yaml
# in a checkout.
_ROOT_MARKER = "manifest.yaml"


@lru_cache(maxsize=1)
def hearth_root() -> Path:
    """The product tree.

    HEARTH_ROOT if set, otherwise the nearest ancestor of this file holding the
    marker. What this deliberately is not is a count of directory levels. The
    code it replaces computed parents[3] here and parents[4] in the tool
    handlers, so moving a file one level silently repointed the whole tree at a
    different real directory and nothing raised. Both wrong answers resolve to
    something that exists, which is why an integer would have been the
    dangerous choice in exactly this spot.
    """
    configured = os.environ.get("HEARTH_ROOT", "").strip()
    if configured:
        return Path(configured).expanduser().resolve()
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / _ROOT_MARKER).is_file():
            return parent
    raise HearthConfigError(
        f"cannot locate the Hearth product tree: HEARTH_ROOT is unset and no "
        f"{_ROOT_MARKER} was found above {here}"
    )


@lru_cache(maxsize=1)
def hearth_home() -> Path:
    """Everything the user owns: configuration, memory, model weights.
    Replacing the product tree on an update must never touch this."""
    configured = os.environ.get("HEARTH_HOME", "").strip()
    return Path(configured).expanduser() if configured else Path.home() / ".hearth"


@lru_cache(maxsize=1)
def hearth_models() -> Path:
    """Where model weights live. Outside the product tree, and not the
    repository: weights on a mounted Windows filesystem take minutes to load
    where the native filesystem takes seconds, and that can exceed the model
    swap timeout."""
    configured = os.environ.get("HEARTH_MODELS", "").strip()
    return Path(configured).expanduser() if configured else hearth_home() / "models"


def _persona_dir() -> Path:
    """Conversational personas. HEARTH_PERSONA_DIR when a supervisor is
    sharing another household; otherwise the product tree's personas/."""
    configured = os.environ.get("HEARTH_PERSONA_DIR", "").strip()
    return Path(configured).expanduser() if configured else hearth_root() / "personas"


def hearth_engram() -> Path:
    """The memory tree.

    HEARTH_ENGRAM and nothing else. There is no candidate list and no fallback,
    because a fallback that finds someone else's brain is worse than a hard
    failure: it produces an install that looks like it works while presenting
    one person's memory, journal and personas as the new user's.
    """
    configured = os.environ.get("HEARTH_ENGRAM", "").strip()
    if not configured:
        raise HearthConfigError(
            "HEARTH_ENGRAM is not set. Memory has no root and Hearth will not "
            "guess one. Point it at an empty directory for a fresh brain."
        )
    return Path(configured).expanduser()


@dataclass
class BrainConfig:
    """Brain-provider seam config. Default backend = the existing Rust
    llama.cpp chat endpoint (OpenAI-compatible). Swappable later (ollama/
    vllm/openrouter) with NO gateway change — see brain/provider.py."""

    # Which BrainProvider implementation to use. "rust" is the only one wired;
    # the registry in brain/__init__.py is where new backends register.
    backend: str = field(default_factory=lambda: _env_str("HEARTH_BRAIN_BACKEND", "rust"))

    # OpenAI-compatible chat-completions base URL. The Rust server fronts
    # llama.cpp at :8765 (/v1/chat/completions) and llama itself at :8080/v1.
    # Default to the Rust server so Valar calls the brain, never bundles it.
    base_url: str = field(
        default_factory=lambda: _env_str("HEARTH_BRAIN_BASE_URL", "http://127.0.0.1:8765/v1")
    )
    # Optional model label to pass through; the resident MoE is pinned so this
    # is usually advisory. Empty = let the backend pick the loaded model.
    model: str = field(default_factory=lambda: _env_str("HEARTH_BRAIN_MODEL", ""))

    # Per-turn generation bounds. max_tokens is generous (a resident MoE is
    # cheap to generate on) — NOT a cost-control band-aid.
    max_tokens: int = field(default_factory=lambda: _env_int("HEARTH_BRAIN_MAX_TOKENS", 2048))
    # Sampling defaults match the Qwen family; env-overridable per model
    # (e.g. Gemma 4 wants 1.0 / 0.95 / 64). Set in the launch env, not hardcoded.
    temperature: float = field(default_factory=lambda: _env_float("HEARTH_BRAIN_TEMPERATURE", 0.7))
    top_p: float = field(default_factory=lambda: _env_float("HEARTH_BRAIN_TOP_P", 0.9))
    top_k: int = field(default_factory=lambda: _env_int("HEARTH_BRAIN_TOP_K", 40))

    # Streaming request timeout (seconds). Generous; the brain may think.
    request_timeout_s: int = field(default_factory=lambda: _env_int("HEARTH_BRAIN_TIMEOUT_S", 300))

    # --- daily-model + on-demand-swap control plane (backend="router") --------
    # Valar owns persona->model routing. The router streams tokens from base_url
    # (data plane, e.g. llama-server :8080/v1 native SSE) and, when the active
    # persona's model class changes, sends switch_persona to the Rust supervisor's
    # WebSocket (control plane) to load the right model. Same-class changes are a
    # no-op (Rust dedupes by model spec); cross-class triggers one reload.
    switch_ws_url: str = field(
        default_factory=lambda: _env_str("HEARTH_BRAIN_SWITCH_WS_URL", "ws://127.0.0.1:8765")
    )
    # Cross-class cold load on a 16 GB card is 60-180s; bound generously. Mirrors
    # the proven Hermes HERMES_GATEWAY_SWITCH_TIMEOUT_S.
    switch_timeout_s: int = field(default_factory=lambda: _env_int("HEARTH_BRAIN_SWITCH_TIMEOUT_S", 330))

    # --- idle-persona watchdog (router) ---------------------------------------
    # After a heavy model has been idle this long, the router swaps the brain back
    # to the idle (daily) persona's model to release VRAM, so the next daily turn
    # is fast and NeuTTS has the GPU room it needs. 0 disables. Mirrors Hermes'
    # idle-persona watchdog; lives in Valar now (the single front door).
    # The resident always-gemma holder to revert to when freeing heavy VRAM. Inert
    # until heavy escalation is wired (all daily personas share gemma-4-E4B, so the
    # watchdog never fires today). TODO(escalation): revert the model in-place for
    # the current persona instead of switching identity.
    idle_persona: str = field(default_factory=lambda: _env_str("HEARTH_IDLE_PERSONA", "valinor-orchestrate"))
    idle_swap_timeout_s: int = field(default_factory=lambda: _env_int("HEARTH_IDLE_SWAP_TIMEOUT_S", 300))


@dataclass
class ContextBudget:
    """The SANE, bounded context budget (banned-band-aid replacement).

    These are deliberately generous for a 200k-capable resident MoE and tuned
    by config, not hardcoded. Telemetry logs actual fill every turn so the
    budget can be raised/lowered with evidence instead of fear.
    """

    # Total token budget Valar will assemble into the prompt (system + memory
    # + history). Well within a 200k window, generous vs the legacy [:120]/[-4:].
    max_context_tokens: int = field(
        default_factory=lambda: _env_int("HEARTH_CTX_MAX_TOKENS", 32768)
    )
    # How many tokens of recent conversation history to keep, bounded but large.
    # (Legacy band-aid was 4 turns / 120 chars each — explicitly NOT carried in.)
    history_token_budget: int = field(
        default_factory=lambda: _env_int("HEARTH_CTX_HISTORY_TOKENS", 16000)
    )
    # Hard cap on number of history turns considered (a safety bound, generous).
    max_history_turns: int = field(
        default_factory=lambda: _env_int("HEARTH_CTX_MAX_HISTORY_TURNS", 100)
    )
    # Token budget for retrieved Engram memory injected per turn.
    memory_token_budget: int = field(
        default_factory=lambda: _env_int("HEARTH_CTX_MEMORY_TOKENS", 4000)
    )
    # Persona system-prompt budget. NO 6000-char default cap; this is a
    # generous token bound so a rich persona prompt is never silently chopped.
    persona_token_budget: int = field(
        default_factory=lambda: _env_int("HEARTH_CTX_PERSONA_TOKENS", 8000)
    )
    # Rough chars-per-token for the heuristic estimator (no tokenizer dependency).
    chars_per_token: float = 3.6


@dataclass
class VoiceConfig:
    # Server-side STT engine size (Whisper). "base" matches the legacy server.
    whisper_model: str = field(default_factory=lambda: _env_str("HEARTH_WHISPER_MODEL", "base"))
    # Client PCM contract for server-side STT: 16 kHz mono 16-bit.
    input_sample_rate: int = 16000
    # TTS output sample rate streamed to clients (matches Quest/Echo contract).
    output_sample_rate: int = field(
        default_factory=lambda: _env_int("HEARTH_TTS_SAMPLE_RATE", 48000)
    )
    # TTS backend service key understood by Server.tools.tts_generator.
    tts_service: str = field(default_factory=lambda: _env_str("HEARTH_TTS_SERVICE", "neutts_air"))

    # --- TTS process decoupling -----------------------------------------------
    # "local"  = load NeuTTS in the gateway process (simple; reloads the GPU model
    #            on every gateway restart -> the NeuTTS VRAM-churn).
    # "remote" = talk to the persistent valar-tts service (tts_app.py) over WS, so
    #            the gateway never loads NeuTTS and a restart costs no GPU reload.
    tts_backend: str = field(default_factory=lambda: _env_str("HEARTH_TTS_BACKEND", "local"))
    # WS endpoint of the persistent TTS service (backend="remote"). Internal only.
    tts_service_url: str = field(
        default_factory=lambda: _env_str("HEARTH_TTS_SERVICE_URL", "ws://127.0.0.1:8701/tts")
    )
    # Port the standalone TTS service (tts_app.py) binds on 127.0.0.1.
    tts_port: int = field(default_factory=lambda: _env_int("HEARTH_TTS_PORT", 8701))


@dataclass
class ValarConfig:
    # The single LAN entry point clients connect to. This is the ONLY surface
    # exposed; the Rust brain stays internal.
    host: str = field(default_factory=lambda: _env_str("HEARTH_HOST", "0.0.0.0"))
    port: int = field(default_factory=lambda: _env_int("HEARTH_PORT", 8700))

    persona_dir: Path = field(default_factory=lambda: _persona_dir())
    default_persona: str = field(default_factory=lambda: _env_str("HEARTH_DEFAULT_PERSONA", "Sulivan"))
    assets_dir: Path = field(default_factory=lambda: hearth_root() / "harness" / "assets")

    brain: BrainConfig = field(default_factory=BrainConfig)
    context: ContextBudget = field(default_factory=ContextBudget)
    voice: VoiceConfig = field(default_factory=VoiceConfig)

    # Memory toggle — when off (or Engram unavailable) the voice loop still runs.
    memory_enabled: bool = field(default_factory=lambda: _env_bool("HEARTH_MEMORY_ENABLED", True))

    # Auto session-end (harness-owned): after this many seconds with no turns,
    # Valar persists the session to Engram + a continuity summary, clears the
    # history, and emits `session_ended` to the client. 0 disables the watchdog.
    session_idle_s: int = field(default_factory=lambda: _env_int("HEARTH_SESSION_IDLE_S", 120))


def load_config() -> ValarConfig:
    """Build the config from defaults + environment. Single entry point."""
    return ValarConfig()
