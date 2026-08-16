"""The BrainProvider seam — the whole point of the decoupling.

A clean interface: chat(messages, opts) -> async stream of token deltas.
Valar NEVER bundles inference; it calls a provider for tokens only. The
default backend is the existing Rust llama.cpp endpoint (OpenAI-compatible
/v1/chat/completions). Ollama / vLLM / OpenRouter / cloud can be added later
by implementing this interface and registering in brain/__init__.py — with
NO changes to the gateway or voice loop.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import AsyncIterator, Protocol

from .prompt_dialect import PromptDialect


@dataclass
class ChatMessage:
    role: str  # "system" | "user" | "assistant" | "tool"
    content: str
    # Additive tool-calling fields (all default None => today's behavior). They
    # let a message carry the OpenAI tool-call turn for the FINAL streaming call
    # after the flag-gated tool round-trip has run:
    #   - assistant tool-call turn: tool_calls set (content may be "")
    #   - tool-result turn (role="tool"): tool_call_id + name + content
    # When all three are None the message serializes exactly as before.
    tool_calls: list | None = None
    tool_call_id: str | None = None
    name: str | None = None


@dataclass
class ChatOptions:
    max_tokens: int = 2048
    temperature: float = 0.7
    top_p: float = 0.9
    top_k: int = 40
    model: str = ""
    # Parser-safety only (e.g. JSON-mode personas). NOT used as cost control —
    # the banned "thinking-token suppression as cost control" is deliberately
    # absent; this defaults to None (let the brain reason).
    enable_thinking: bool | None = None
    # Persona-driven model routing (used by the "router" backend). persona_name
    # is what gets sent to the Rust supervisor's switch_persona; model_path is the
    # persona's deep_model.path, used as the model-class key so same-class persona
    # changes (e.g. daily<->orchestrate, both gemma-4-E4B) are a no-op while a real
    # class change (daily->Sulivan 35B) triggers exactly one swap. Empty = the
    # router streams against whatever model is currently resident.
    persona_name: str = ""
    model_path: str = ""
    # Additive: OpenAI function-calling tool schemas, passed as tools=[...] on a
    # tool-aware (non-streaming) brain call. Default None => no tools => today's
    # behavior. Only consulted by the flag-gated tool round-trip; the streaming
    # chat() path ignores it.
    tools: list[dict] | None = None
    # Set by the router when a GGUF becomes resident. Default OpenAI preset.
    # Unimplemented families (qwen, glimmer) stay stamped here and wire as OpenAI.
    prompt_dialect: PromptDialect = PromptDialect.OPENAI


@dataclass
class BrainUsage:
    """Token counts, when the backend reports them. Estimates fill gaps."""

    prompt_tokens: int = 0
    completion_tokens: int = 0


@dataclass
class BrainStreamResult:
    """Carries usage out of the stream once it completes (set by the provider)."""

    usage: BrainUsage = field(default_factory=BrainUsage)
    model_used: str = ""


class BrainProvider(Protocol):
    """Pluggable inference provider. Implementations stream token deltas."""

    name: str

    async def chat(
        self,
        messages: list[ChatMessage],
        opts: ChatOptions,
        result: BrainStreamResult,
    ) -> AsyncIterator[str]:
        """Yield content deltas (token text) as they arrive. Populate `result`
        with usage/model info before the iterator is exhausted."""
        ...

    async def health(self) -> bool:
        """True when the backend is reachable and ready to serve tokens."""
        ...
