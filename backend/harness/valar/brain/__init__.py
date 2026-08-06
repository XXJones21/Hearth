"""Brain-provider registry — the swap point for inference backends.

To add Ollama / vLLM / OpenRouter / cloud later: implement BrainProvider in a
new module and register a factory here. The gateway and voice loop are unchanged.
"""

from __future__ import annotations

from typing import Callable

from ..config import BrainConfig
from .provider import (
    BrainProvider,
    BrainStreamResult,
    BrainUsage,
    ChatMessage,
    ChatOptions,
)
from .router_provider import RouterBrainProvider
from .rust_provider import BrainError, RustBrainProvider

# backend key -> factory(BrainConfig) -> BrainProvider
_REGISTRY: dict[str, Callable[[BrainConfig], BrainProvider]] = {
    # Single fixed model, no routing. base_url points at the resident endpoint.
    "rust": lambda cfg: RustBrainProvider(cfg.base_url, cfg.request_timeout_s),
    # Daily-model + on-demand persona->model swap (the single-pipeline default).
    # Streams from base_url (data plane) and swaps via switch_ws_url (control plane).
    "router": lambda cfg: RouterBrainProvider(
        cfg.base_url,
        cfg.switch_ws_url,
        cfg.request_timeout_s,
        cfg.switch_timeout_s,
        idle_persona=cfg.idle_persona,
        idle_swap_timeout_s=cfg.idle_swap_timeout_s,
    ),
    # Future (no gateway change needed):
    #   "ollama":     lambda cfg: OllamaBrainProvider(cfg.base_url, ...),
    #   "vllm":       lambda cfg: OpenAICompatProvider(cfg.base_url, ...),
    #   "openrouter": lambda cfg: OpenRouterProvider(cfg.base_url, cfg.model, ...),
}


def build_brain(cfg: BrainConfig) -> BrainProvider:
    factory = _REGISTRY.get(cfg.backend)
    if factory is None:
        raise ValueError(
            f"unknown brain backend '{cfg.backend}'; known: {sorted(_REGISTRY)}"
        )
    return factory(cfg)


__all__ = [
    "BrainError",
    "BrainProvider",
    "BrainStreamResult",
    "BrainUsage",
    "ChatMessage",
    "ChatOptions",
    "build_brain",
]
