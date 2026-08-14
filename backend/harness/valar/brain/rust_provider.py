"""Default BrainProvider backend: the existing Rust llama.cpp chat endpoint.

WIRED: calls the OpenAI-compatible POST {base_url}/chat/completions exposed by
the Rust server (rust/hearth-supervisor, :8765/v1) which fronts llama.cpp. We
request stream=true and parse SSE deltas.

NOTE on the seam: the Rust WS gateway's `prepare_generic_llm_payload` currently
forces stream=false and injects enable_thinking=false (a band-aid). Valar does
NOT go through that band-aid path — it calls the chat-completions HTTP endpoint
directly and requests streaming. If the deployed Rust build does not honor
stream=true on this route, set HEARTH_BRAIN_BASE_URL to the llama-server itself
(http://127.0.0.1:8080/v1), which streams natively. Both are the same brain;
this is purely which front door we knock on. Flagged for live-runtime validation.
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import AsyncIterator

import httpx

from .prompt_dialect import PromptDialect, dialect_from_model, wire_dialect
from .prompt_format import (
    Gemma4SpeechFilter,
    parse_gemma4_completion,
    render_prompt,
)
from .provider import (
    BrainProvider,
    BrainStreamResult,
    BrainUsage,
    ChatMessage,
    ChatOptions,
)

logger = logging.getLogger("valar.brain.rust")

# Phase 1a: bounded retry for CONNECTION-class failures only (refused/timeout
# while establishing the connection). 3 retries after the initial attempt,
# 1/2/4s backoff. Read errors, 5xx bodies, and anything after the first
# streamed token are NOT retried — a partially spoken answer cannot be
# replayed. Module-level so the smoke test can assert the schedule;
# _retry_sleep is swappable so tests run offline without real sleeps.
_CONNECT_RETRIES = 3
_CONNECT_BACKOFF_S = (1.0, 2.0, 4.0)
_CONNECT_ERRORS = (httpx.ConnectError, httpx.ConnectTimeout)
_retry_sleep = asyncio.sleep


class RustBrainProvider:
    """Streams tokens from the Rust-fronted llama.cpp OpenAI-compatible API."""

    name = "rust"

    def __init__(
        self,
        base_url: str,
        request_timeout_s: int = 300,
        transport: httpx.AsyncBaseTransport | None = None,
    ):
        self.base_url = base_url.rstrip("/")
        self.timeout = httpx.Timeout(request_timeout_s, connect=10.0)
        # Test seam: offline smoke tests inject a MockTransport; production
        # passes nothing and gets the default HTTP transport.
        self._transport = transport

    def _client(self) -> httpx.AsyncClient:
        return httpx.AsyncClient(timeout=self.timeout, transport=self._transport)

    def _chat_url(self) -> str:
        return f"{self.base_url}/chat/completions"

    def _completions_url(self) -> str:
        return f"{self.base_url}/completions"

    def _resolved_dialect(self, opts: ChatOptions) -> PromptDialect:
        dialect = getattr(opts, "prompt_dialect", None) or PromptDialect.OPENAI
        if dialect is PromptDialect.OPENAI and (opts.model_path or ""):
            dialect = dialect_from_model(opts.model_path)
        return dialect

    def _wire_dialect(self, opts: ChatOptions) -> PromptDialect:
        return wire_dialect(self._resolved_dialect(opts))

    def _completion_payload(
        self,
        prompt: str,
        opts: ChatOptions,
        *,
        stream: bool,
        stop: list[str],
    ) -> dict:
        payload: dict = {
            "prompt": prompt,
            "max_tokens": opts.max_tokens,
            "temperature": opts.temperature,
            "top_p": opts.top_p,
            "top_k": opts.top_k,
            "stream": stream,
            "stop": stop,
        }
        if opts.model:
            payload["model"] = opts.model
        return payload

    def _msg_to_dict(self, m: ChatMessage) -> dict:
        """Serialize one ChatMessage to the OpenAI wire shape. Tool fields are
        emitted ONLY when present so a message without them is byte-identical to
        the pre-tools serialization ({"role", "content"})."""
        d: dict = {"role": m.role, "content": m.content}
        # Assistant turn that issued tool calls (content may be empty string).
        if getattr(m, "tool_calls", None) is not None:
            d["tool_calls"] = m.tool_calls
        # role="tool" result turn carries the call id + tool name.
        if getattr(m, "tool_call_id", None) is not None:
            d["tool_call_id"] = m.tool_call_id
        if getattr(m, "name", None) is not None:
            d["name"] = m.name
        return d

    def _build_payload(self, messages: list[ChatMessage], opts: ChatOptions) -> dict:
        payload: dict = {
            "messages": [self._msg_to_dict(m) for m in messages],
            "max_tokens": opts.max_tokens,
            "temperature": opts.temperature,
            "top_p": opts.top_p,
            "top_k": opts.top_k,
            "stream": True,
        }
        if opts.model:
            payload["model"] = opts.model
        # Only set enable_thinking when explicitly requested (parser-safety).
        # Default None => omit => the brain reasons freely. No cost-control band-aid.
        if opts.enable_thinking is not None:
            payload["chat_template_kwargs"] = {"enable_thinking": opts.enable_thinking}
        return payload

    async def chat_tools(
        self,
        messages: list[ChatMessage],
        opts: ChatOptions,
        tools: list[dict],
    ) -> dict:
        """Tool-aware, NON-streaming brain call (the flag-gated tool round-trip).

        OpenAI dialect: POST /chat/completions with tools=[...] and tool_choice=auto.
        Gemma 4 dialect: render native turns/declarations and POST /completions so
        llama-server does not re-wrap the prompt. Returns OpenAI-shaped
        {content, tool_calls, reasoning} in both cases."""
        if self._wire_dialect(opts) is PromptDialect.GEMMA4:
            return await self._chat_tools_gemma4(messages, opts, tools)
        payload = self._build_payload(messages, opts)
        payload["stream"] = False
        payload["tools"] = tools
        payload["tool_choice"] = "auto"
        obj = await self._post_json(self._chat_url(), payload, what="tools")
        choices = obj.get("choices") or []
        if not choices:
            return {"content": "", "tool_calls": [], "reasoning": ""}
        choice = choices[0]
        message = choice.get("message") or {}
        content = message.get("content") or ""
        tool_calls = message.get("tool_calls") or []
        reasoning = message.get("reasoning_content") or ""
        logger.info(
            "brain tools: finish=%s calls=%d content=%d reasoning=%d head=%r",
            choice.get("finish_reason"),
            len(tool_calls),
            len(content),
            len(reasoning),
            (content or reasoning)[:120],
        )
        return {
            "content": content,
            "tool_calls": tool_calls,
            "reasoning": reasoning,
        }

    async def _chat_tools_gemma4(
        self,
        messages: list[ChatMessage],
        opts: ChatOptions,
        tools: list[dict],
    ) -> dict:
        rendered = render_prompt(
            messages,
            dialect=PromptDialect.GEMMA4,
            tools=tools,
            enable_thinking=bool(opts.enable_thinking),
        )
        payload = self._completion_payload(
            rendered.prompt, opts, stream=False, stop=rendered.stop
        )
        obj = await self._post_json(self._completions_url(), payload, what="tools")
        text = _completion_text(obj)
        parsed = parse_gemma4_completion(text)
        logger.info(
            "brain tools: finish=%s calls=%d content=%d reasoning=%d head=%r dialect=gemma4",
            (obj.get("choices") or [{}])[0].get("finish_reason") if obj.get("choices") else "",
            len(parsed["tool_calls"]),
            len(parsed["content"]),
            len(parsed["reasoning"]),
            (parsed["content"] or parsed["reasoning"] or text)[:120],
        )
        return parsed

    async def _post_json(self, url: str, payload: dict, *, what: str) -> dict:
        obj: dict = {}
        last_exc: Exception | None = None
        for attempt in range(1 + _CONNECT_RETRIES):
            if attempt:
                delay = _CONNECT_BACKOFF_S[attempt - 1]
                logger.warning(
                    "brain (%s) connect failed (%s); retry %d/%d in %.0fs",
                    what, last_exc, attempt, _CONNECT_RETRIES, delay,
                )
                await _retry_sleep(delay)
            try:
                async with self._client() as client:
                    resp = await client.post(url, json=payload)
                    if resp.status_code != 200:
                        body = resp.text
                        raise BrainError(
                            f"brain ({what}) returned {resp.status_code}: {body[:500]}"
                        )
                    obj = resp.json()
                break
            except _CONNECT_ERRORS as exc:
                last_exc = exc
        else:
            raise BrainError(
                f"brain ({what}) unreachable after {1 + _CONNECT_RETRIES} attempts: {last_exc}"
            ) from last_exc
        return obj

    async def chat_structured(
        self,
        messages: list[ChatMessage],
        opts: ChatOptions,
        schema: dict,
        name: str = "structured_reply",
    ) -> str:
        """Grammar-constrained, NON-streaming brain call: the model cannot emit
        anything but JSON matching `schema` (llama-server converts the schema
        to a GBNF grammar). Returns the raw JSON text for the caller to parse.

        The interview runs on this (2026-08-08): tool selection by a 12B was
        non-deterministic three different ways -- proper calls, calls leaked
        into the speech channel, and plain omission -- and each got its own
        guard. A response format enforced at the token level replaces all
        three hopes with a certainty."""
        payload = self._build_payload(messages, opts)
        payload["stream"] = False
        payload["response_format"] = {
            "type": "json_schema",
            "json_schema": {"name": name, "schema": schema, "strict": True},
        }
        obj = await self._post_json(self._chat_url(), payload, what="structured")
        choices = obj.get("choices") or []
        if not choices:
            return ""
        message = choices[0].get("message") or {}
        return str(message.get("content") or "")

    async def chat(
        self,
        messages: list[ChatMessage],
        opts: ChatOptions,
        result: BrainStreamResult,
    ) -> AsyncIterator[str]:
        if self._wire_dialect(opts) is PromptDialect.GEMMA4:
            async for delta in self._chat_gemma4(messages, opts, result):
                yield delta
            return
        payload = self._build_payload(messages, opts)
        async for delta in self._stream_sse(self._chat_url(), payload, result):
            yield delta

    async def _chat_gemma4(
        self,
        messages: list[ChatMessage],
        opts: ChatOptions,
        result: BrainStreamResult,
    ) -> AsyncIterator[str]:
        rendered = render_prompt(
            messages,
            dialect=PromptDialect.GEMMA4,
            tools=opts.tools,
            enable_thinking=bool(opts.enable_thinking),
        )
        payload = self._completion_payload(
            rendered.prompt, opts, stream=True, stop=rendered.stop
        )
        speech = Gemma4SpeechFilter()
        async for raw in self._stream_sse(self._completions_url(), payload, result):
            for piece in speech.feed(raw):
                yield piece
        leftover = speech.flush()
        if leftover:
            yield leftover

    async def _stream_sse(
        self,
        url: str,
        payload: dict,
        result: BrainStreamResult,
    ) -> AsyncIterator[str]:
        yielded = False
        last_exc: Exception | None = None
        for attempt in range(1 + _CONNECT_RETRIES):
            if attempt:
                delay = _CONNECT_BACKOFF_S[attempt - 1]
                logger.warning(
                    "brain connect failed (%s); retry %d/%d in %.0fs",
                    last_exc, attempt, _CONNECT_RETRIES, delay,
                )
                await _retry_sleep(delay)
            try:
                async with self._client() as client:
                    async with client.stream("POST", url, json=payload) as resp:
                        if resp.status_code != 200:
                            body = (await resp.aread()).decode("utf-8", "replace")
                            raise BrainError(
                                f"brain returned {resp.status_code}: {body[:500]}"
                            )
                        async for line in resp.aiter_lines():
                            delta = _parse_sse_line(line, result)
                            if delta:
                                yielded = True
                                yield delta
                        return
            except _CONNECT_ERRORS as exc:
                if yielded:
                    raise
                last_exc = exc
        raise BrainError(
            f"brain unreachable after {1 + _CONNECT_RETRIES} attempts: {last_exc}"
        ) from last_exc

    async def health(self) -> bool:
        # Probe the OpenAI-compatible /models endpoint (sibling of chat).
        url = f"{self.base_url}/models"
        try:
            async with httpx.AsyncClient(timeout=httpx.Timeout(5.0)) as client:
                resp = await client.get(url)
                return resp.status_code == 200
        except Exception as exc:  # noqa: BLE001 - health probe is best-effort
            logger.warning("brain health probe failed: %s", exc)
            return False


class BrainError(RuntimeError):
    """Raised when the brain backend returns an error or unreachable response."""


def _parse_sse_line(line: str, result: BrainStreamResult) -> str | None:
    """Parse one Server-Sent-Events line from an OpenAI-style stream.

    Returns the content delta text, or None for non-content lines. Captures
    usage and model into `result` when the backend reports them.
    """
    if not line or not line.startswith("data:"):
        return None
    data = line[len("data:"):].strip()
    if not data or data == "[DONE]":
        return None
    try:
        obj = json.loads(data)
    except json.JSONDecodeError:
        return None

    if not result.model_used:
        model = obj.get("model")
        if isinstance(model, str):
            result.model_used = model

    usage = obj.get("usage")
    if isinstance(usage, dict):
        result.usage = BrainUsage(
            prompt_tokens=int(usage.get("prompt_tokens", result.usage.prompt_tokens)),
            completion_tokens=int(
                usage.get("completion_tokens", result.usage.completion_tokens)
            ),
        )

    choices = obj.get("choices")
    if not isinstance(choices, list) or not choices:
        return None
    choice = choices[0]
    # Chat stream: choices[].delta.content. Completions stream: choices[].text.
    delta = choice.get("delta") or {}
    content = delta.get("content")
    if content is None:
        content = delta.get("text")
    if content is None:
        content = choice.get("text")
    if content is None:
        message = choice.get("message") or {}
        content = message.get("content")
    return content or None


def _completion_text(obj: dict) -> str:
    """Pull generated text out of a /v1/completions (or native /completion) body."""
    choices = obj.get("choices") or []
    if choices:
        choice = choices[0] or {}
        text = choice.get("text")
        if text:
            return str(text)
        message = choice.get("message") or {}
        if message.get("content"):
            return str(message["content"])
    if obj.get("content"):
        return str(obj["content"])
    return ""
