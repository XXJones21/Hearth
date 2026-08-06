"""Read-only settings surface for the Hearth clients.

Answers "what is this house made of" for the Settings panel: the folders a
client can open in a file browser, the connections the house has registered,
and the resolved config the developer pane shows. Strictly read-only. There
is no write path yet, by design -- every server-side value is still an env
var read once at process start (see config/settings.py), so a setter would
have to answer "hot-reload or restart?" per key first.

Folders and connections are registries rather than fixed lists: a client
renders whatever rows arrive, so adding a folder or packaging CHOAM as an
extension (M11) is a change here and nowhere in any client.
"""

from __future__ import annotations

import logging
import os
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import JSONResponse

from ..config.settings import ValarConfig

logger = logging.getLogger("valar.gateway.settings")

# Connections the house can hold. `tools` names the tools.yaml entries that
# make the connection useful; `requires` names the env vars without which it
# cannot answer. State is derived, never stored.
_CONNECTIONS: list[dict] = [
    {
        "key": "comfyui",
        "name": "Local ComfyUI",
        "role": "Image generation",
        "tools": ["generate_image", "check_image"],
        "requires": [],
        "detail_env": ("HEARTH_COMFY_URL", "http://127.0.0.1:8188"),
    },
    {
        "key": "choam",
        "name": "CHOAM",
        "role": "Trading desk, via Liara",
        "tools": ["consult_liara"],
        "requires": [],
        "detail_env": ("CHOAM_WALLET_URL", "http://127.0.0.1:8091/wallet/query"),
    },
    {
        "key": "telegram",
        "name": "Telegram",
        "role": "Build notifications",
        "tools": [],
        "requires": ["HEARTH_NOTIFY_TG_TOKEN", "HEARTH_NOTIFY_TG_CHAT"],
        "detail_env": None,
    },
    {
        "key": "hass",
        "name": "Home Assistant",
        "role": "Lights, locks, climate",
        "tools": ["hass_call"],
        "requires": ["HEARTH_HASS_URL", "HEARTH_HASS_TOKEN"],
        "detail_env": None,
    },
    {
        "key": "calendar",
        "name": "Google Calendar",
        "role": "Schedule and reminders",
        "tools": ["calendar_today", "calendar_next"],
        "requires": ["HEARTH_GOOGLE_CLIENT_SECRET", "HEARTH_GOOGLE_TOKEN"],
        "detail_env": None,
    },
]


def _dir_stats(path: Path) -> tuple[int, int]:
    """(file count, total bytes) one level deep. Shallow on purpose: the
    models dir holds a handful of very large files, and a recursive walk of
    Engram would stat thousands of notes on every panel open."""
    count = 0
    size = 0
    try:
        with os.scandir(path) as entries:
            for entry in entries:
                if entry.is_file():
                    count += 1
                    try:
                        size += entry.stat().st_size
                    except OSError:
                        pass
                elif entry.is_dir():
                    count += 1
    except OSError:
        return (0, 0)
    return (count, size)


def _human_size(n: int) -> str:
    if n <= 0:
        return ""
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:.0f} {unit}" if unit in ("B", "KB") else f"{n:.1f} {unit}"
        n /= 1024.0
    return ""


def _folder(key: str, name: str, path: Path, blurb: str) -> dict:
    exists = path.is_dir()
    count, size = _dir_stats(path) if exists else (0, 0)
    parts = [blurb]
    if exists and count:
        human = _human_size(size)
        parts.append(f"{count} item{'' if count == 1 else 's'}" + (f", {human}" if human else ""))
    elif not exists:
        parts.append("not present on this machine")
    return {
        "key": key,
        "name": name,
        "path": str(path),
        "detail": ". ".join(p for p in parts if p),
        "exists": exists,
    }


def _folders(config: ValarConfig) -> list[dict]:
    from . import journal as journal_api

    repo_root = config.persona_dir.parent
    engram = journal_api._engram_root(repo_root)
    rows = [
        _folder(
            "models",
            "Models",
            repo_root / "models",
            "Drop a GGUF in and it shows up in the picker",
        ),
        _folder(
            "generated",
            "Generated images",
            config.assets_dir / "generated",
            "Everything the imagery tool has made",
        ),
    ]
    # Session context. The Journal is the readable view of a conversation;
    # this is the raw material behind it -- one .scx per session plus the
    # dated ledger dirs. Surfaced because "where did that conversation go"
    # has no other answer until a resume or an SCX reader exists.
    sessions = repo_root / "sessions"
    if sessions.is_dir():
        scx = len(list(sessions.glob("*.scx")))
        rows.append(
            _folder(
                "sessions",
                "Conversations on disk",
                sessions,
                f"{scx} session context file{'' if scx == 1 else 's'} (.scx) "
                "and the dated ledgers behind the journal",
            )
        )
    if engram is not None:
        rows.append(
            _folder(
                "journal",
                "Journal and memory",
                engram,
                "Selene writes here: session pages, project notes, the nightly ledger",
            )
        )
    logs = repo_root / "Valar" / "logs"
    if logs.is_dir():
        rows.append(_folder("logs", "Logs", logs, "First stop when a turn misbehaves"))
    return rows


def _connections() -> list[dict]:
    from ..tools import ToolRegistry, tools_enabled

    if tools_enabled():
        try:
            registered = set(ToolRegistry.from_yaml().names())
        except Exception:  # noqa: BLE001 - a bad registry must not break the panel
            registered = set()
    else:
        registered = set()

    rows = []
    for spec in _CONNECTIONS:
        missing = [k for k in spec["requires"] if not os.environ.get(k, "").strip()]
        wants = spec["tools"]
        has_tool = (not wants) or bool(registered.intersection(wants))
        if missing:
            state, detail = "off", "Needs " + " and ".join(missing)
        elif not has_tool:
            state = "off"
            detail = "Tools are off" if not tools_enabled() else "Its tools are disabled"
        else:
            state = "live"
            detail = ""
            if spec["detail_env"]:
                key, fallback = spec["detail_env"]
                detail = os.environ.get(key, "").strip() or fallback
        rows.append(
            {
                "key": spec["key"],
                "name": spec["name"],
                "role": spec["role"],
                "state": state,
                "detail": detail,
            }
        )
    return rows


def _resolved(config: ValarConfig) -> list[dict]:
    """Flat label/value rows for the developer pane. `drift` marks a deployed
    value that differs from the code default, which is the whole reason the
    pane earns its place."""
    from ..tools import tools_enabled

    def row(label: str, value: str, drift: str = "") -> dict:
        return {"label": label, "value": value, "drift": drift}

    ctx_default = 32768
    tts_default = "neutts_air"
    return [
        row("brain", f"{config.brain.backend} -> {config.brain.base_url}"),
        row("model", config.brain.model or "(backend picks)"),
        row(
            "context",
            f"{config.context.max_context_tokens} tokens",
            f"code default {ctx_default}"
            if config.context.max_context_tokens != ctx_default
            else "",
        ),
        row(
            "tts",
            f"{config.voice.tts_service} ({config.voice.tts_backend})",
            f"code default {tts_default}"
            if config.voice.tts_service != tts_default
            else "",
        ),
        row("stt", f"whisper {config.voice.whisper_model}"),
        row("tools", "enabled" if tools_enabled() else "disabled"),
        row("memory", "enabled" if config.memory_enabled else "disabled"),
        row(
            "session idle",
            f"{config.session_idle_s}s" if config.session_idle_s else "never",
        ),
        row("persona dir", str(config.persona_dir)),
        row("listening on", f"{config.host}:{config.port}"),
    ]


def register(app: FastAPI, config: ValarConfig) -> None:
    @app.get("/settings/surface")
    async def settings_surface() -> JSONResponse:
        return JSONResponse(
            {
                "folders": _folders(config),
                "connections": _connections(),
                "resolved": _resolved(config),
                "server": {
                    "version": app.version,
                    "port": config.port,
                    "brain_backend": config.brain.backend,
                },
            }
        )
