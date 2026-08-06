"""Read-only Apps surface: what the house is connected to.

An **app** is a bundle of up to four parts, any of which may be absent:
capability (tools), connection (the credential or endpoint it needs), surface
(the cards it draws), and permission (which personas may use it). See
`tasks/apps-extensions-investigation.md` for how that definition was reached.

Everything here is DERIVED, never stored twice. Tools come from tools.yaml,
cards from card_catalog.yaml, permissions from each persona's
`tool_grants.domains`, and connection state from the environment. Adding a
tool to an existing app is a tools.yaml edit and nothing else.

The MCP slot is deliberately present and deliberately empty: once Valar has an
MCP client, discovered servers become apps through `_discovered()` with no
client change (decided 2026-08-03, Q4). Until then this surface describes the
capability the house actually has rather than pretending otherwise.
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import JSONResponse

from ..config.settings import ValarConfig

logger = logging.getLogger("valar.gateway.apps")

# Each app claims tools by exact name or by prefix. Anything unclaimed belongs
# to Hearth core, so a new tool is never invisible.
_APPS: list[dict] = [
    {
        "key": "claude",
        "name": "Claude Code",
        "kind": "cli",
        "tagline": "The frontier agent, for work Mentat is not sized for",
        "transport": "Command line, headless, on the Windows host",
        "claims": ["consult_claude", "claude_status"],
    },
    {
        "key": "mentat",
        "name": "Mentat",
        "kind": "core",
        "tagline": "The in-house executor: plans, beats, gates",
        "transport": "In process, against the mentat_runs allow-list",
        "claims_prefix": "mentat_",
    },
    {
        "key": "comfyui",
        "name": "Local ComfyUI",
        "kind": "local",
        "tagline": "Image generation on the GPU in this house",
        "transport_env": ("HEARTH_COMFY_URL", "http://127.0.0.1:8188"),
        "claims": ["generate_image", "check_image"],
    },
    {
        "key": "choam",
        "name": "CHOAM",
        "kind": "local",
        "tagline": "The trading desk, through Liara",
        "transport_env": ("CHOAM_WALLET_URL", "http://127.0.0.1:8091/wallet/query"),
        "claims": ["consult_liara"],
    },
    {
        "key": "engram",
        "name": "Engram",
        "kind": "local",
        "tagline": "The second brain Selene keeps",
        "transport": "On disk, this machine only",
        "claims": ["remember", "recall", "consult_memory"],
    },
    {
        "key": "uefn",
        "name": "UEFN bridge",
        "kind": "local",
        "tagline": "Perceive and act inside the live editor",
        "transport": "HTTP listener on the Windows host, ports 8780-8785",
        "claims_prefix": "uefn_",
    },
    {
        "key": "wright",
        "name": "Wright",
        "kind": "core",
        "tagline": "The five-beat game-dev orchestrator",
        "transport": "In process",
        "claims": ["wright"],
    },
    {
        "key": "hass",
        "name": "Home Assistant",
        "kind": "local",
        "tagline": "Lights, locks, climate",
        "transport": "Not configured",
        "claims": ["hass_call"],
        "needs": ["HEARTH_HASS_URL", "HEARTH_HASS_TOKEN"],
    },
    {
        "key": "calendar",
        "name": "Google Calendar",
        "kind": "local",
        "tagline": "Schedule and reminders",
        "transport": "Not signed in",
        "claims": ["calendar_today", "calendar_next"],
        "needs": ["HEARTH_GOOGLE_CLIENT_SECRET", "HEARTH_GOOGLE_TOKEN"],
    },
]

_CORE = {
    "key": "core",
    "name": "Hearth core",
    "kind": "core",
    "tagline": "The tools the house was born with",
    "transport": "Built in",
    "locked": True,
}

_MCP_CONFIG = Path(__file__).resolve().parents[2] / "valar" / "tools" / "mcp_servers.json"


def _all_specs() -> dict:
    """Every tool in the registry, enabled or not. The registry drops disabled
    entries, so read the YAML directly to show what the house COULD do."""
    try:
        import yaml  # type: ignore

        doc = yaml.safe_load(
            (Path(__file__).resolve().parents[1] / "tools" / "tools.yaml").read_text(
                encoding="utf-8"
            )
        ) or {}
    except Exception as exc:  # noqa: BLE001
        logger.warning("tools.yaml unreadable for the apps surface: %s", exc)
        return {}
    out = {}
    for entry in doc.get("tools", []) or []:
        name = entry.get("name")
        if name:
            out[name] = entry
    return out


def _persona_grants(persona_dir: Path) -> dict[str, list[str]]:
    """persona -> granted domains. Only conversational personas: the internal
    routing and executor personas are not household members."""
    hidden = {"valinor-orchestrate", "f1-principal", "f1-vision"}
    grants: dict[str, list[str]] = {}
    for cfg in sorted(persona_dir.glob("*/*.json")):
        name = cfg.parent.name
        if name in hidden or name.startswith("wright-"):
            continue
        try:
            doc = json.loads(cfg.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            continue
        if doc.get("name", "").lower() != name.lower():
            continue
        domains = (doc.get("tool_grants") or {}).get("domains")
        if isinstance(domains, list):
            grants[name] = domains
    return grants


def _cards_by_source() -> dict[str, list[str]]:
    """tool name -> card types it feeds."""
    from ..tools.handlers.forge import _load_catalog  # noqa: PLC0415

    out: dict[str, list[str]] = {}
    for entry in _load_catalog():
        src = str(entry.get("data_source") or "")
        if src:
            out.setdefault(src, []).append(str(entry.get("type")))
    return out


def _discovered() -> list[dict]:
    """MCP servers the house has been told about. Empty until Valar has an MCP
    client; the shape is here so discovery is a server change, not a client
    one."""
    try:
        doc = json.loads(_MCP_CONFIG.read_text(encoding="utf-8"))
    except OSError:
        return []
    except json.JSONDecodeError as exc:
        logger.warning("mcp_servers.json is not valid JSON: %s", exc)
        return []
    servers = doc.get("mcpServers") or {}
    return [
        {
            "key": f"mcp-{name}",
            "name": name,
            "kind": "mcp",
            "tagline": "Discovered on this machine, not let in yet",
            "transport": "MCP",
            "tools": [],
            "cards": [],
            "who": [],
            "state": "available",
        }
        for name in sorted(servers)
    ]


def _build(config: ValarConfig) -> dict:
    from ..tools import tools_enabled  # noqa: PLC0415
    from ..tools.handlers.forge import _load_catalog, card_status  # noqa: PLC0415

    specs = _all_specs()
    grants = _persona_grants(config.persona_dir)
    cards_for = _cards_by_source()
    claimed: set[str] = set()
    apps: list[dict] = []

    def assemble(meta: dict, names: list[str]) -> dict:
        tools = sorted(names)
        domains = {str(specs[t].get("domain") or "") for t in tools if t in specs}
        who = sorted(n for n, d in grants.items() if domains.intersection(d))
        cards = sorted({c for t in tools for c in cards_for.get(t, [])})
        missing = [k for k in (meta.get("needs") or []) if not os.environ.get(k, "").strip()]
        any_enabled = any(specs.get(t, {}).get("enabled", True) for t in tools)
        risks = {str(specs[t].get("risk") or "read") for t in tools if t in specs}
        risk = "control" if "control" in risks else ("write" if "write" in risks else "read")

        if missing:
            state = "setup"
        elif not tools_enabled() or not any_enabled:
            state = "setup"
        else:
            state = "active"

        transport = meta.get("transport", "")
        if meta.get("transport_env"):
            key, fallback = meta["transport_env"]
            transport = os.environ.get(key, "").strip() or fallback

        return {
            "key": meta["key"],
            "name": meta["name"],
            "kind": meta["kind"],
            "tagline": meta["tagline"],
            "transport": transport,
            "tools": tools[:10],
            "more": max(0, len(tools) - 10),
            "cards": cards,
            "who": who,
            "state": state,
            "risk": risk,
            "needs": missing,
            "locked": bool(meta.get("locked")),
        }

    for meta in _APPS:
        names = [t for t in meta.get("claims", []) if t in specs]
        prefix = meta.get("claims_prefix")
        if prefix:
            names += [t for t in specs if t.startswith(prefix)]
        if not names:
            continue
        claimed.update(names)
        apps.append(assemble(meta, names))

    core_names = [t for t in specs if t not in claimed]
    if core_names:
        apps.insert(0, assemble(_CORE, core_names))

    order = {"active": 0, "setup": 1, "available": 2}
    apps.sort(key=lambda a: (order.get(a["state"], 3), a["key"] != "core", a["name"]))
    apps.extend(_discovered())

    cards = [
        {
            "type": str(e.get("type")),
            "purpose": str(e.get("purpose") or "").strip(),
            "data_fields": str(e.get("data_fields") or ""),
            "state": "builtin"
            if e.get("builtin")
            else ("forged" if card_status(e) == "built" else "scaffold"),
        }
        for e in _load_catalog()
    ]

    return {
        "apps": apps,
        "cards": cards,
        "personas": sorted(grants),
        "tools_enabled": tools_enabled(),
    }


def register(app: FastAPI, config: ValarConfig) -> None:
    @app.get("/apps/surface")
    async def apps_surface() -> JSONResponse:
        return JSONResponse(_build(config))

    @app.post("/apps/apply")
    async def apps_apply(payload: dict) -> JSONResponse:
        return JSONResponse(apply_changes(config, payload))


# ---------------------------------------------------------------------------
# The write path.
#
# Turning an app on writes `enabled:` in tools.yaml; granting it to a persona
# writes that persona's `tool_grants.domains`. Both are read ONCE at process
# start, so a change means a restart. Rather than hide that, the client
# batches edits and the operator presses Save, which applies them and bounces
# the service (Restart=always in scripts/systemd/hearth-harness.service brings it back
# in about five seconds). Honest and legible beats a toggle that silently
# does nothing until the next reboot.
#
# tools.yaml is edited LINE BY LINE, never re-serialized: the file carries the
# registry's documentation and a yaml.safe_dump round trip would delete every
# comment in it.
# ---------------------------------------------------------------------------

_TOOLS_YAML = Path(__file__).resolve().parents[1] / "tools" / "tools.yaml"


def _app_tools(specs: dict) -> dict[str, list[str]]:
    """app key -> tool names, the same claim rules the read path uses."""
    claimed: set[str] = set()
    out: dict[str, list[str]] = {}
    for meta in _APPS:
        names = [t for t in meta.get("claims", []) if t in specs]
        prefix = meta.get("claims_prefix")
        if prefix:
            names += [t for t in specs if t.startswith(prefix)]
        if names:
            out[meta["key"]] = sorted(names)
            claimed.update(names)
    out["core"] = sorted(t for t in specs if t not in claimed)
    return out


def _set_enabled(text: str, tool: str, enabled: bool) -> str:
    """Set `enabled:` inside one tool block, preserving everything else."""
    lines = text.split("\n")
    start = next((i for i, l in enumerate(lines) if l.strip() == f"- name: {tool}"), None)
    if start is None:
        return text
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if lines[i].lstrip().startswith("- name:") and not lines[i].startswith(" " * 6):
            end = i
            break
    indent = " " * (len(lines[start]) - len(lines[start].lstrip()) + 2)
    for i in range(start, end):
        if lines[i].strip().startswith("enabled:"):
            lines[i] = f"{indent}enabled: {'true' if enabled else 'false'}"
            return "\n".join(lines)
    anchor = next(
        (i for i in range(start, end) if lines[i].strip().startswith("handler:")), start
    )
    lines.insert(anchor + 1, f"{indent}enabled: {'true' if enabled else 'false'}")
    return "\n".join(lines)


def apply_changes(config: ValarConfig, payload: dict) -> dict:
    specs = _all_specs()
    if not specs:
        return {"ok": False, "error": "The tool registry could not be read."}

    by_app = _app_tools(specs)
    changed: list[str] = []

    # --- apps on/off ------------------------------------------------------
    apps = payload.get("apps") or {}
    if apps:
        try:
            text = _TOOLS_YAML.read_text(encoding="utf-8")
        except OSError as exc:
            return {"ok": False, "error": f"tools.yaml is unreadable: {exc}"}
        for key, want in apps.items():
            if key == "core":
                continue  # core is not switchable; the read path locks it too
            for tool in by_app.get(key, []):
                text = _set_enabled(text, tool, bool(want))
            if by_app.get(key):
                changed.append(f"{key} {'on' if want else 'off'}")
        try:
            _TOOLS_YAML.write_text(text, encoding="utf-8")
        except OSError as exc:
            return {"ok": False, "error": f"tools.yaml could not be written: {exc}"}

    # --- per-persona grants ----------------------------------------------
    grants = payload.get("grants") or {}
    for persona, wanted_keys in grants.items():
        cfg = config.persona_dir / persona / f"{persona.lower()}.json"
        try:
            doc = json.loads(cfg.read_text(encoding="utf-8"))
        except OSError:
            continue
        current = list((doc.get("tool_grants") or {}).get("domains") or [])
        for key, want in (wanted_keys or {}).items():
            domains = {
                str(specs[t].get("domain") or "") for t in by_app.get(key, []) if t in specs
            }
            domains.discard("")
            for d in domains:
                if want and d not in current:
                    current.append(d)
                elif not want and d in current:
                    current.remove(d)
            changed.append(f"{persona} {'gains' if want else 'loses'} {key}")
        doc.setdefault("tool_grants", {})["domains"] = current
        try:
            cfg.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        except OSError as exc:
            return {"ok": False, "error": f"{persona} could not be written: {exc}"}

    if not changed:
        return {"ok": True, "changed": [], "restarting": False}

    logger.info("apps: applied %s; restarting", ", ".join(changed))

    def _bounce() -> None:
        import time as _t

        _t.sleep(0.6)  # let the response reach the client first
        os._exit(0)  # systemd Restart=always brings us back

    import threading

    threading.Thread(target=_bounce, daemon=True).start()
    return {"ok": True, "changed": changed, "restarting": True}
