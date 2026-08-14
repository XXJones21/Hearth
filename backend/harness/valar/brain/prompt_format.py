"""Render ChatMessage IR into a wire prompt for the active dialect.

Brain code calls render_prompt() directly so it does not import the gateway.
ContextAssembler.render() is the same function with the assembler's dialect.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from typing import Any

from .prompt_dialect import PromptDialect, wire_dialect

STR_DELIM = '<|"|>'
GEMMA4_STOP = ["<turn|>", "<|tool_response>"]

_THOUGHT_RE = re.compile(r"<\|channel>thought(.*?)<channel\|>", re.DOTALL)
_TOOL_CALL_RE = re.compile(r"<\|tool_call>(.*?)<tool_call\|>", re.DOTALL)
_SCHEMA_TYPES = frozenset(
    {"object", "string", "number", "integer", "boolean", "array", "null"}
)
_CALL_HEAD_RE = re.compile(r"call:([A-Za-z0-9_]+)(\{.*\})\s*$", re.DOTALL)


@dataclass
class RenderedPrompt:
    kind: str  # "chat" | "completion"
    messages: list | None = None
    prompt: str = ""
    stop: list[str] = field(default_factory=list)


def render_prompt(
    messages: list,
    *,
    dialect: PromptDialect,
    tools: list[dict] | None = None,
    enable_thinking: bool = False,
) -> RenderedPrompt:
    wire = wire_dialect(dialect)
    if wire is PromptDialect.GEMMA4:
        return render_gemma4(
            messages, tools=tools, enable_thinking=enable_thinking
        )
    return RenderedPrompt(kind="chat", messages=list(messages))


def render_gemma4(
    messages: list,
    *,
    tools: list[dict] | None = None,
    enable_thinking: bool = False,
) -> RenderedPrompt:
    """Native Gemma 4 turns, tool declarations, and think token.

    Official contract: https://ai.google.dev/gemma/docs/core/prompt-formatting-gemma4
    """
    msgs = [_as_dict(m) for m in messages]
    system_parts: list[str] = []
    rest: list[dict] = []
    for m in msgs:
        if m.get("role") == "system" and not rest:
            system_parts.append(str(m.get("content") or ""))
        else:
            rest.append(m)

    system_body = "<|think|>" if enable_thinking else ""
    system_body += "\n".join(p for p in system_parts if p)
    for spec in tools or []:
        system_body += _declaration(spec)

    chunks = [f"<|turn>system\n{system_body}<turn|>"]
    i = 0
    while i < len(rest):
        m = rest[i]
        role = m.get("role")
        if role == "user":
            chunks.append(f"<|turn>user\n{m.get('content') or ''}<turn|>")
            i += 1
            continue
        if role == "assistant":
            tool_calls = m.get("tool_calls")
            content = str(m.get("content") or "")
            if tool_calls:
                body = content
                for call in tool_calls:
                    body += _encode_tool_call(call)
                i += 1
                while i < len(rest) and rest[i].get("role") == "tool":
                    body += _encode_tool_response(rest[i])
                    i += 1
                if i >= len(rest):
                    chunks.append(f"<|turn>model\n{body}")
                else:
                    chunks.append(f"<|turn>model\n{body}<turn|>")
                continue
            chunks.append(f"<|turn>model\n{_strip_thoughts(content)}<turn|>")
            i += 1
            continue
        if role == "tool":
            chunks.append(_encode_tool_response(m))
            i += 1
            continue
        i += 1

    prompt = "".join(chunks)
    if rest and rest[-1].get("role") == "user":
        prompt += "<|turn>model\n"
    return RenderedPrompt(kind="completion", prompt=prompt, stop=list(GEMMA4_STOP))


def parse_gemma4_completion(text: str) -> dict:
    """Native Gemma 4 completion -> OpenAI-shaped {content, tool_calls, reasoning}."""
    text = text or ""
    reasoning = "\n".join(
        part.strip() for part in _THOUGHT_RE.findall(text) if part.strip()
    )
    tool_calls: list[dict] = []
    for idx, raw in enumerate(_TOOL_CALL_RE.findall(text)):
        call = _parse_tool_call_body(raw.strip())
        if call is None:
            continue
        name, args = call
        tool_calls.append(
            {
                "id": f"gemma4_call_{idx + 1}",
                "type": "function",
                "function": {"name": name, "arguments": json.dumps(args)},
            }
        )
    content = _TOOL_CALL_RE.sub("", text)
    content = _THOUGHT_RE.sub("", content)
    for tag in (
        "<turn|>",
        "<|turn>model",
        "<|turn>system",
        "<|turn>user",
        "<|turn>",
        "<|think|>",
        "<|tool_response>",
        "<tool_response|>",
    ):
        content = content.replace(tag, "")
    content = _LEADING_THOUGHT_RE.sub("", content.strip())
    return {
        "content": content.strip(),
        "tool_calls": tool_calls,
        "reasoning": reasoning,
    }


_THOUGHT_OPEN_RE = re.compile(r"^<\|channel>\s*thought")
_LEADING_THOUGHT_RE = re.compile(
    r"^(?:thought\s*\n)+|^(?:thought)\s*$", re.IGNORECASE
)


class Gemma4SpeechFilter:
    """Drop thought / tool-call / control tokens from a streamed completion."""

    _SKIP = (
        ("<|channel>thought", "<channel|>"),
        ("<|tool_call>", "<tool_call|>"),
    )
    _DROP = (
        "<turn|>",
        "<|turn>",
        "<|think|>",
        "<|tool_response>",
        "<tool_response|>",
        "<channel|>",
        "<|channel>",
    )

    def __init__(self) -> None:
        self.buf = ""
        self.skip_until: str | None = None

    def feed(self, chunk: str) -> list[str]:
        if not chunk:
            return []
        self.buf += chunk
        out: list[str] = []
        while self.buf:
            if self.skip_until:
                idx = self.buf.find(self.skip_until)
                if idx < 0:
                    keep = max(0, len(self.skip_until) - 1)
                    self.buf = self.buf[-keep:] if keep else ""
                    break
                self.buf = self.buf[idx + len(self.skip_until) :]
                self.skip_until = None
                continue
            thought_open = _THOUGHT_OPEN_RE.match(self.buf)
            if thought_open:
                self.buf = self.buf[thought_open.end() :]
                self.skip_until = "<channel|>"
                continue
            started = False
            for start, end in self._SKIP:
                if self.buf.startswith(start):
                    self.buf = self.buf[len(start) :]
                    self.skip_until = end
                    started = True
                    break
            if started:
                continue
            dropped = False
            for tag in self._DROP:
                if self.buf.startswith(tag):
                    self.buf = self.buf[len(tag) :]
                    dropped = True
                    break
            if dropped:
                continue
            if (
                _pending_channel_thought(self.buf)
                or _pending_bare_thought(self.buf)
                or _is_control_prefix(self.buf, self._SKIP, self._DROP)
            ):
                break
            lt = self.buf.find("<")
            if lt == 0:
                out.append("<")
                self.buf = self.buf[1:]
                continue
            if lt < 0:
                out.append(self.buf)
                self.buf = ""
                break
            out.append(self.buf[:lt])
            self.buf = self.buf[lt:]
        return [_strip_leading_thought(part) for part in out if part]

    def flush(self) -> str:
        if self.skip_until:
            self.buf = ""
            return ""
        leftover = _strip_leading_thought(self.buf)
        self.buf = ""
        return leftover


def _strip_leading_thought(text: str) -> str:
    return _LEADING_THOUGHT_RE.sub("", text or "")


def _pending_bare_thought(buf: str) -> bool:
    """Hold a streamed 'thought' word until we know it is not a channel leak."""
    low = (buf or "").lower()
    if not low or low.startswith("<"):
        return False
    if "thought".startswith(low) and len(low) < len("thought"):
        return True
    if low == "thought":
        return True
    if low.startswith("thought") and buf[len("thought") : len("thought") + 1] in " \t":
        return True
    return False


def _pending_channel_thought(buf: str) -> bool:
    """True while buf could still become a thought-channel open tag."""
    if not buf.startswith("<") or _THOUGHT_OPEN_RE.match(buf):
        return False
    if "<|channel>thought".startswith(buf):
        return True
    if buf.startswith("<|channel>"):
        stripped = buf[len("<|channel>") :].lstrip()
        return stripped == "" or "thought".startswith(stripped)
    return False


def _is_control_prefix(
    buf: str, skip: tuple[tuple[str, str], ...], drop: tuple[str, ...]
) -> bool:
    if not buf or buf[0] != "<":
        return False
    tags = [start for start, _ in skip] + list(drop)
    return any(tag.startswith(buf) for tag in tags)


def _as_dict(m: Any) -> dict:
    if isinstance(m, dict):
        return m
    return {
        "role": getattr(m, "role", "user"),
        "content": getattr(m, "content", "") or "",
        "tool_calls": getattr(m, "tool_calls", None),
        "tool_call_id": getattr(m, "tool_call_id", None),
        "name": getattr(m, "name", None),
    }


def _strip_thoughts(text: str) -> str:
    return _THOUGHT_RE.sub("", text or "").strip()


def _declaration(schema: dict) -> str:
    fn = schema.get("function") if isinstance(schema.get("function"), dict) else schema
    name = str((fn or {}).get("name") or "tool")
    desc = str((fn or {}).get("description") or "")
    params = (fn or {}).get("parameters") or {}
    inner = _encode_value(
        {"description": desc, "parameters": params}, schema_mode=True
    )
    return f"<|tool>declaration:{name}{inner}<tool|>"


def _encode_tool_call(call: dict) -> str:
    fn = call.get("function") if isinstance(call.get("function"), dict) else {}
    name = str((fn or {}).get("name") or "")
    raw = (fn or {}).get("arguments") or "{}"
    if isinstance(raw, dict):
        args = raw
    else:
        try:
            parsed = json.loads(raw) if raw else {}
            args = parsed if isinstance(parsed, dict) else {}
        except ValueError:
            args = {}
    return f"<|tool_call>call:{name}{_encode_value(args)}<tool_call|>"


def _encode_tool_response(m: dict) -> str:
    name = str(m.get("name") or "")
    content = str(m.get("content") or "")
    payload: Any = {"result": content}
    try:
        parsed = json.loads(content)
        if isinstance(parsed, dict):
            payload = parsed
    except (ValueError, TypeError):
        pass
    return f"<|tool_response>response:{name}{_encode_value(payload)}<tool_response|>"


def _encode_value(value: Any, *, schema_mode: bool = False) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, str):
        if schema_mode and value in _SCHEMA_TYPES:
            return value
        return f"{STR_DELIM}{value}{STR_DELIM}"
    if isinstance(value, list):
        parts = []
        for item in value:
            if schema_mode and isinstance(item, str) and item.isidentifier():
                parts.append(item)
            else:
                parts.append(_encode_value(item, schema_mode=schema_mode))
        return "[" + ",".join(parts) + "]"
    if isinstance(value, dict):
        parts = [
            f"{key}:{_encode_value(val, schema_mode=schema_mode)}"
            for key, val in value.items()
        ]
        return "{" + ",".join(parts) + "}"
    return f"{STR_DELIM}{value}{STR_DELIM}"


def _parse_tool_call_body(raw: str) -> tuple[str, dict] | None:
    match = _CALL_HEAD_RE.match(raw)
    if not match:
        return None
    name, body = match.group(1), match.group(2)
    try:
        args = _Scanner(body).parse_value()
    except (ValueError, IndexError):
        args = {}
    if not isinstance(args, dict):
        args = {}
    return name, args


class _Scanner:
    def __init__(self, text: str):
        self.s = text
        self.i = 0

    def skip_ws(self) -> None:
        while self.i < len(self.s) and self.s[self.i] in " \t\n\r":
            self.i += 1

    def _atom_end(self, end: int) -> bool:
        return end >= len(self.s) or self.s[end] in ",}] \t\n\r"

    def parse_value(self) -> Any:
        self.skip_ws()
        s, i = self.s, self.i
        if s.startswith(STR_DELIM, i):
            i += len(STR_DELIM)
            close = s.find(STR_DELIM, i)
            if close < 0:
                self.i = len(s)
                return s[i:]
            self.i = close + len(STR_DELIM)
            return s[i:close]
        if i < len(s) and s[i] == "{":
            return self.parse_object()
        if i < len(s) and s[i] == "[":
            return self.parse_array()
        if s.startswith("true", i) and self._atom_end(i + 4):
            self.i = i + 4
            return True
        if s.startswith("false", i) and self._atom_end(i + 5):
            self.i = i + 5
            return False
        if s.startswith("null", i) and self._atom_end(i + 4):
            self.i = i + 4
            return None
        num = re.match(r"-?\d+(?:\.\d+)?", s[i:])
        if num and self._atom_end(i + num.end()):
            self.i = i + num.end()
            token = num.group()
            return float(token) if "." in token else int(token)
        ident = re.match(r"[A-Za-z_][A-Za-z0-9_]*", s[i:])
        if ident:
            self.i = i + ident.end()
            return ident.group()
        raise ValueError(f"unreadable Gemma value at {i}: {s[i:i + 40]!r}")

    def parse_object(self) -> dict:
        self.skip_ws()
        if self.i >= len(self.s) or self.s[self.i] != "{":
            raise ValueError("expected object")
        self.i += 1
        out: dict = {}
        while True:
            self.skip_ws()
            if self.i >= len(self.s):
                break
            if self.s[self.i] == "}":
                self.i += 1
                break
            key_m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", self.s[self.i :])
            if not key_m:
                raise ValueError("expected object key")
            key = key_m.group()
            self.i += key_m.end()
            self.skip_ws()
            if self.i < len(self.s) and self.s[self.i] == ":":
                self.i += 1
            out[key] = self.parse_value()
            self.skip_ws()
            if self.i < len(self.s) and self.s[self.i] == ",":
                self.i += 1
        return out

    def parse_array(self) -> list:
        self.skip_ws()
        if self.i >= len(self.s) or self.s[self.i] != "[":
            raise ValueError("expected array")
        self.i += 1
        out: list = []
        while True:
            self.skip_ws()
            if self.i >= len(self.s):
                break
            if self.s[self.i] == "]":
                self.i += 1
                break
            out.append(self.parse_value())
            self.skip_ws()
            if self.i < len(self.s) and self.s[self.i] == ",":
                self.i += 1
        return out
