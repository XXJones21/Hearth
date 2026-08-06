"""Valar tool registry -- the additive, opt-in tool-calling seam (Keystone 2).

This package is the YAML-as-plugin-registry for Valar's daily-driver tools,
following the ``Server/skills/execute/execute.md`` precedent
(``task_handlers: {name: "module:function"}``). Adding a tool is one entry in
``tools.yaml`` + one handler function with the ``handler(args) -> ToolResult``
signature from ``spec.py``.

IMPORTANT -- additive and opt-in. Nothing here is wired into ``voice_loop.run_turn``.
The registry is built only when ``VALAR_TOOLS_ENABLED`` is truthy (default OFF),
and even then the tool-calling round-trip is a *separate* module
(``valar.tools.loop.ToolCallingLoop``) the gateway can choose to invoke. The
working voice turn is unaffected until that wiring is added deliberately behind
the flag. This module imports no heavy deps at import time -- handler modules are
imported lazily on first invoke.
"""

from __future__ import annotations

import asyncio
import importlib
import logging
import os
from pathlib import Path
from typing import Any, Callable

from .spec import ToolResult, ToolSpec

logger = logging.getLogger("valar.tools")

# Default registry config path: alongside this package.
DEFAULT_TOOLS_YAML = Path(__file__).resolve().parent / "tools.yaml"


def tools_enabled() -> bool:
    """Whether the tool layer is opt-in enabled. Default OFF so the live voice
    turn is never changed implicitly."""
    raw = os.environ.get("VALAR_TOOLS_ENABLED")
    if raw is None:
        return False
    return raw.strip().lower() in ("1", "true", "yes", "on")


class ToolRegistry:
    """Loads tool specs from YAML and resolves + invokes their handlers.

    Handlers are imported lazily (first invoke of each tool) so importing the
    registry costs nothing and a broken/optional handler dependency does not take
    down the others. Each handler resolves from its ``"module:function"`` string.
    """

    def __init__(self, specs: dict[str, ToolSpec]):
        self._specs = specs
        self._resolved: dict[str, Callable[..., Any]] = {}

    # ---- construction -----------------------------------------------------
    @classmethod
    def from_yaml(cls, path: Path | str | None = None) -> "ToolRegistry":
        """Build a registry from a tools.yaml file. Missing file or PyYAML
        absence yields an empty registry (the layer is additive)."""
        path = Path(path) if path else DEFAULT_TOOLS_YAML
        specs: dict[str, ToolSpec] = {}
        if not path.exists():
            logger.info("tools.yaml not found at %s; empty registry", path)
            return cls(specs)
        try:
            import yaml  # type: ignore
        except Exception as exc:  # noqa: BLE001
            logger.warning("PyYAML unavailable; tool registry empty: %s", exc)
            return cls(specs)
        try:
            doc = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except Exception as exc:  # noqa: BLE001
            logger.warning("failed to parse %s; empty registry: %s", path, exc)
            return cls(specs)
        for entry in doc.get("tools", []) or []:
            try:
                spec = ToolSpec(
                    name=entry["name"],
                    description=entry.get("description", ""),
                    handler=entry["handler"],
                    parameters=entry.get("parameters", {}) or {},
                    enabled=bool(entry.get("enabled", True)),
                    speak=str(entry.get("speak", "") or "").strip(),
                    domain=str(entry.get("domain", "") or "").strip(),
                    risk=str(entry.get("risk", "read") or "read").strip(),
                    requires_capability=str(
                        entry.get("requires_capability", "") or ""
                    ).strip(),
                )
            except KeyError as exc:
                logger.warning("skipping malformed tool entry %r (missing %s)", entry, exc)
                continue
            if spec.enabled:
                specs[spec.name] = spec
        logger.info("tool registry loaded %d tool(s): %s", len(specs), sorted(specs))
        return cls(specs)

    # ---- introspection ----------------------------------------------------
    def names(self) -> list[str]:
        return sorted(self._specs)

    def subset(self, allowed: list | None) -> "ToolRegistry":
        """A registry restricted to ``allowed`` tool names -- the per-persona
        tool-subset seam (selection reliability degrades with tool-set size;
        measured 2026-06-05, see proactive-tools-roadmap.md). ``None`` means no
        restriction (this registry unchanged). Unknown names are logged and
        ignored; an empty list yields an empty registry (tools off for that
        persona without touching the global flag)."""
        if allowed is None:
            return self
        wanted = {str(n).strip() for n in allowed if str(n).strip()}
        unknown = sorted(wanted - set(self._specs))
        if unknown:
            logger.warning("tool subset: unknown tool name(s) ignored: %s", unknown)
        specs = {n: s for n, s in self._specs.items() if n in wanted}
        logger.info(
            "tool subset: %d of %d tool(s): %s",
            len(specs),
            len(self._specs),
            sorted(specs),
        )
        return ToolRegistry(specs)

    def resolve(
        self,
        tool_grants: dict | None = None,
        client_capabilities: dict | list | None = None,
    ) -> "ToolRegistry":
        """The per-session registry: persona grants then the client capability
        gate. Offered set = enabled tools ∩ persona grants ∩ client capabilities
        (see wiki/architecture/harness/tool-catalog.md).

        ``tool_grants`` is the persona's top-level ``tool_grants`` config:
        ``{"domains": [...], "allow": [tool names], "deny": [tool names]}`` --
        tools whose ``domain`` is granted, plus ``allow`` names, minus ``deny``
        names. ``None``/absent = no persona restriction (backward compatible).

        ``client_capabilities`` is the session's ``client_info`` capabilities
        (dict of truthy flags, or a list of keys). A tool with
        ``requires_capability`` is offered only when the client advertises it;
        tools without the field pass on any client."""
        reg = self
        if isinstance(tool_grants, dict):
            domains = {
                str(d).strip() for d in (tool_grants.get("domains") or []) if str(d).strip()
            }
            allow = {
                str(n).strip() for n in (tool_grants.get("allow") or []) if str(n).strip()
            }
            deny = {
                str(n).strip() for n in (tool_grants.get("deny") or []) if str(n).strip()
            }
            known_domains = {s.domain for s in reg._specs.values() if s.domain}
            unknown = sorted(domains - known_domains)
            if unknown:
                logger.warning("tool grants: unknown domain(s) ignored: %s", unknown)
            names = [
                n
                for n, s in reg._specs.items()
                if ((s.domain and s.domain in domains) or n in allow) and n not in deny
            ]
            reg = reg.subset(names)
        caps: set[str] = set()
        if isinstance(client_capabilities, dict):
            caps = {str(k) for k, v in client_capabilities.items() if v}
        elif isinstance(client_capabilities, (list, tuple, set)):
            caps = {str(c) for c in client_capabilities}
        gated = [
            n
            for n, s in reg._specs.items()
            if s.requires_capability and s.requires_capability not in caps
        ]
        if gated:
            logger.info("tool capability gate: withheld %s", sorted(gated))
            reg = reg.subset([n for n in reg._specs if n not in gated])
        return reg

    def schemas(self) -> list[dict[str, Any]]:
        """OpenAI-compatible tool schemas for every enabled tool -- what gets
        passed as ``tools=[...]`` on the brain's function-calling request."""
        return [s.to_openai_schema() for s in self._specs.values()]

    def has(self, name: str) -> bool:
        return name in self._specs

    def speak_phrase(self, names: list[str]) -> str:
        """The thinking-filler phrase for a set of called tools: the first
        non-empty ``speak:`` among them (one phrase per turn, never a chorus).
        Empty string when none of the tools define one (silent fallback)."""
        for n in names:
            spec = self._specs.get(n)
            if spec is not None and spec.speak:
                return spec.speak
        return ""

    # ---- dispatch ---------------------------------------------------------
    def _resolve(self, name: str) -> Callable[..., Any]:
        if name in self._resolved:
            return self._resolved[name]
        spec = self._specs[name]
        mod_name, _, fn_name = spec.handler.partition(":")
        if not mod_name or not fn_name:
            raise ValueError(f"tool '{name}' has malformed handler '{spec.handler}'")
        module = importlib.import_module(mod_name)
        fn = getattr(module, fn_name)
        self._resolved[name] = fn
        return fn

    async def invoke(self, name: str, args: dict[str, Any] | None) -> ToolResult:
        """Invoke a tool by name with the model's argument dict. Sync handlers run
        in a thread (so a blocking HTTP call never stalls the event loop); async
        handlers are awaited. A missing tool or a handler exception returns a
        ToolResult.error so the loop can keep the turn alive."""
        args = args or {}
        if name not in self._specs:
            return ToolResult.error(f"unknown tool: {name}")
        try:
            fn = self._resolve(name)
        except Exception as exc:  # noqa: BLE001
            logger.error("failed to resolve tool '%s': %s", name, exc)
            return ToolResult.error(f"tool '{name}' is unavailable")
        try:
            if asyncio.iscoroutinefunction(fn):
                result = await fn(args)
            else:
                loop = asyncio.get_running_loop()
                result = await loop.run_in_executor(None, fn, args)
        except Exception as exc:  # noqa: BLE001
            logger.error("tool '%s' raised: %s", name, exc)
            return ToolResult.error(f"tool '{name}' failed: {exc}")
        if isinstance(result, ToolResult):
            return result
        # Tolerate a handler that returns a bare string.
        return ToolResult(content=str(result))


def build_registry(
    path: Path | str | None = None, allow: list | None = None
) -> ToolRegistry:
    """Convenience builder. Returns an empty registry when the layer is disabled,
    so callers can construct unconditionally and check ``names()``. ``allow``
    restricts the result to those tool names (a raw name subset); None
    means the full registry."""
    if not tools_enabled():
        logger.info("VALAR_TOOLS_ENABLED is off; tool registry disabled (empty)")
        return ToolRegistry({})
    return ToolRegistry.from_yaml(path).subset(allow)


def resolve_registry(
    tool_grants: dict | None = None,
    client_capabilities: dict | list | None = None,
    path: Path | str | None = None,
) -> ToolRegistry:
    """The per-session registry the gateway uses: the full catalog resolved
    through the persona's ``tool_grants`` and the session's client capabilities.
    Empty when the tool layer is disabled."""
    if not tools_enabled():
        logger.info("VALAR_TOOLS_ENABLED is off; tool registry disabled (empty)")
        return ToolRegistry({})
    return ToolRegistry.from_yaml(path).resolve(tool_grants, client_capabilities)


__all__ = [
    "ToolRegistry",
    "ToolResult",
    "ToolSpec",
    "build_registry",
    "resolve_registry",
    "tools_enabled",
    "DEFAULT_TOOLS_YAML",
]
