"""Tool interface: the clean contract every Valar tool handler implements.

A handler is a plain callable ``handler(args: dict) -> ToolResult`` (sync or
async). It takes a JSON-decodable argument dict (the model's function-call
arguments) and returns a ToolResult. Handlers are pure with respect to the voice
loop: they never touch the websocket, the session, or the brain -- they do one
thing and return a string result the loop can feed back to the model. That keeps
every handler unit-testable in isolation, with no live loop.

The registry (``valar.tools.ToolRegistry``) maps a tool name to a
``"module:function"`` string and exposes ``schemas()`` (OpenAI function-calling
tool schemas) + ``invoke(name, args)``. This mirrors the established Valinor idiom
in ``Server/skills/execute/execute.md`` (``task_handlers: {name: "module:function"}``)
so adding a tool is one YAML entry + one handler function -- no bespoke loop.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class ToolResult:
    """The outcome of a tool call, ready to feed back to the model.

    ``content`` is the human/model-readable result string (what the brain reads on
    the second round-trip). ``ok`` is False for a handled failure (the loop still
    feeds ``content`` back so the model can apologize gracefully). ``data`` is the
    optional structured payload (e.g. for a client to render), never required.
    """

    content: str
    ok: bool = True
    data: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def error(cls, message: str) -> "ToolResult":
        return cls(content=message, ok=False)


@dataclass
class ToolSpec:
    """A registered tool: its name, description, JSON-schema parameters, and the
    ``"module:function"`` handler reference. ``enabled`` lets the YAML disable a
    tool without removing it. ``speak`` is an optional short filler phrase the
    voice loop says while the tool executes (the ~2s tool-turn gap); empty means
    silent. Built from a tools.yaml entry by the registry.

    Catalog metadata (harness-side only; never sent to the model):
    ``domain`` is the catalog tag persona grants select on (weather, timers,
    search, news, memory, projects, smarthome, calendar, media, ui, device,
    spatial). ``risk`` classifies the blast radius: ``read`` (no durable effect),
    ``write`` (durable state: memory, timers), ``control`` (physical/device
    action). ``requires_capability`` names a client capability key (from the
    ``client_info`` handshake) without which the tool is not offered on that
    session -- e.g. ``ui_render``, ``device_actions``, ``spatial``; empty = any
    client. See wiki/architecture/harness/tool-catalog.md."""

    name: str
    description: str
    handler: str  # "package.module:function"
    parameters: dict[str, Any] = field(default_factory=dict)  # JSON Schema (object)
    enabled: bool = True
    speak: str = ""
    domain: str = ""
    risk: str = "read"
    requires_capability: str = ""

    def to_openai_schema(self) -> dict[str, Any]:
        """Render as an OpenAI-compatible function-calling tool schema."""
        return {
            "type": "function",
            "function": {
                "name": self.name,
                "description": self.description,
                "parameters": self.parameters
                or {"type": "object", "properties": {}, "required": []},
            },
        }
