"""The Valar WS gateway — the single client entry point (universal voice protocol).

Implements the contract the rich clients already speak (mirrors the Echo/Desktop
ProtocolClient): client_info/client_info_ack handshake; text_query + binary audio
in with the STT fork (server Whisper+VAD vs client_transcription); streaming TTS
out (tts_chunk_* / play_wav_file -> speaking_complete); list_personas/switch_persona;
the IDLE->LISTENING->THINKING->SPEAKING state machine. Plus an HTTP assets endpoint.

This is the ONLY surface exposed to clients. It calls the Brain via BrainProvider
for tokens only; it never bundles inference.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import os
import time
import uuid

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, JSONResponse
from starlette.staticfiles import StaticFiles

from ..brain import BrainStreamResult, ChatMessage, ChatOptions, build_brain
from ..config import ValarConfig
from ..memory import EngramMemory
from ..persona import PersonaEngine, PersonaNotFound
from ..voice import EnergyVAD, SttUnavailable, WhisperSTT
from .session import Session, State
from .easel_watch import easel_watchdog
from .session_end import idle_watchdog
from .voice_loop import VoiceLoop
from ..models import resolve as resolve_model

logger = logging.getLogger("valar.gateway")

# Telegram/OpenAI "profile" -> Valar persona, for the HTTP /v1/chat/completions
# shim that lets the single pipeline also serve text gateways (Telegram, etc.).
# Mirrors the retired Hermes sidecar's map; unknown profiles fall through to a
# same-named persona so any persona is reachable by name.
PROFILE_TO_PERSONA: dict[str, str] = {
    # "daily" is the everyday driver = Sulivan on its main model (gemma-4-E4B).
    # There is no separate "valinor-daily" shell persona anymore.
    "daily": "Sulivan",
    "sulivan": "Sulivan",
    "selene": "Selene",
    "mentat": "Mentat",
    # Internal routing persona (gemma-4-E4B + JSON gate); not a conversational identity.
    "orchestrator": "valinor-orchestrate",
    # F1 (f1-principal / f1-vision) is deferred — it returns later as its own
    # client + persona. Intentionally out of the curated profile map for now
    # (still reachable by exact persona name if ever needed).
}


def create_app(config: ValarConfig) -> FastAPI:
    app = FastAPI(title="Valar Gateway", version="1.0.0")

    # Browser clients (hearth-client dev on localhost:1420, packaged Tauri on
    # tauri://localhost) read /health, /mentat/state, and persona assets
    # cross-origin; without CORS headers those fetches fail silently in the
    # webview while curl/PowerShell succeed. WS is not CORS-gated. Home-LAN
    # trust boundary; tighten to an origin list with the tailnet work (M7).
    from fastapi.middleware.cors import CORSMiddleware

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["GET", "POST"],
        allow_headers=["*"],
    )

    # --- read-only Journal API (Selene's room in the Hearth client) ------
    from valar.gateway import journal as journal_api

    journal_api.register(app, config.persona_dir.parent)

    # --- read-only settings surface (folders, connections, resolved config) ---
    from valar.gateway import settings_api

    settings_api.register(app, config)

    # --- read-only Apps surface (what the house is connected to) ----------
    from valar.gateway import apps_api

    apps_api.register(app, config)

    # --- the household: read and write persona.json -----------------------
    from valar.gateway import personas_api

    personas_api.register(app, config)

    # --- subsystems (built once, shared) ---------------------------------
    personas = PersonaEngine(config.persona_dir, config.default_persona)
    brain = build_brain(config.brain)
    memory = EngramMemory(
        config.persona_dir.parent,  # repo root
        enabled=config.memory_enabled,
        memory_token_budget=config.context.memory_token_budget,
    )
    # The gateway never loads a speech model itself. It talks to the voice
    # service, which holds one resident in its own process, so a gateway
    # restart costs no reload. The in-process alternative is gone rather
    # than defaulted off: the engine it loaded does not ship, so keeping the
    # branch would have meant an import guard with nothing behind it.
    if config.voice.tts_backend != "remote":
        raise ValueError(
            f"unknown TTS backend {config.voice.tts_backend!r}; Hearth talks to "
            "the voice service. Set HEARTH_TTS_BACKEND=remote."
        )
    from ..voice.tts_remote import RemoteVoiceStreamer

    tts = RemoteVoiceStreamer(config.voice.tts_service_url, config.voice.output_sample_rate)
    logger.info("voice service at %s", config.voice.tts_service_url)
    stt = WhisperSTT(config.voice.whisper_model, config.voice.input_sample_rate)
    voice_loop = VoiceLoop(config, brain, memory, tts, personas=personas)

    # Personas-as-subagents (2026-06-07): hand the shared seams to the subagent
    # runtime once, so standalone tool handlers (consult_memory -> Selene) can
    # invoke another persona in a fresh context window on the same resident
    # model. The handler contract stays pure; this is the EngramService idiom.
    from ..agents import configure_subagents

    configure_subagents(brain, personas, config)

    app.state.config = config
    app.state.personas = personas
    app.state.brain = brain

    # --- HTTP: health + assets -------------------------------------------
    @app.get("/health")
    async def health() -> JSONResponse:
        brain_ok = await brain.health()
        return JSONResponse(
            {
                "status": "ok",
                "brain_backend": config.brain.backend,
                "brain_ready": brain_ok,
                "current_persona": personas.current_name(),
                "personas": personas.list_personas(),
            }
        )

    @app.get("/voice/ready")
    async def voice_ready() -> JSONResponse:
        """Whether the voice can actually speak RIGHT NOW: the service's own
        /health, whose ready flag means backbone loaded and a voice encoded.
        The install's voice test waits on this instead of asking a cold
        engine to speak and apologising for the silence."""
        url = config.voice.tts_service_url
        health_url = url.replace("ws://", "http://").replace("wss://", "https://")
        if health_url.endswith("/tts"):
            health_url = health_url[: -len("/tts")] + "/health"
        try:
            import httpx

            async with httpx.AsyncClient(timeout=3.0) as client:
                resp = await client.get(health_url)
                body = resp.json()
                return JSONResponse(
                    {"ready": bool(body.get("ready")), "service": body.get("service", "")}
                )
        except Exception:  # noqa: BLE001 - not reachable IS the answer
            return JSONResponse({"ready": False, "service": ""})

    config.assets_dir.mkdir(parents=True, exist_ok=True)
    app.mount("/assets", StaticFiles(directory=str(config.assets_dir)), name="assets")

    @app.get("/persona/{name}/asset/{filename}")
    async def persona_asset(name: str, filename: str):
        path = config.persona_dir / name / filename
        if not path.exists() or not path.is_file():
            return JSONResponse({"error": "not found"}, status_code=404)
        return FileResponse(str(path))

    # Client persona config + GLB assets — the Echo/Quest contract, folded onto
    # Valar :8700 (was the old Rust assets surface :8766, which clients can no
    # longer reach through the portproxy). Without this the Echo hangs 30s on its
    # persona-config fetch and silently falls back to the bundled persona.
    @app.get("/personas/{name}/{filename}")
    async def persona_config_file(name: str, filename: str):
        path = config.persona_dir / name / filename
        if not path.exists() or not path.is_file():
            return JSONResponse({"error": "not found"}, status_code=404)
        return FileResponse(str(path))

    @app.get("/Persona/{asset_path:path}")
    async def persona_glb_asset(asset_path: str):
        # GLB/gltf + sidecars for glb_animated personas (Selene). Path-contained
        # to the Persona/ dir so a crafted ../ can't escape it.
        base = config.persona_dir.resolve()
        target = (config.persona_dir / asset_path).resolve()
        if base != target and base not in target.parents:
            return JSONResponse({"error": "forbidden"}, status_code=403)
        if not target.exists() or not target.is_file():
            return JSONResponse({"error": "not found"}, status_code=404)
        return FileResponse(str(target))

    # --- HTTP: OpenAI-compatible chat shim (text gateways: Telegram, etc.) ---
    # The single-pipeline front door for non-voice clients. Maps profile->persona,
    # injects the persona system prompt, routes through the same brain (so model
    # swap + idle watchdog apply), and returns a non-streaming OpenAI response.
    # This is what folds the Hermes sidecar's role into Valar.
    @app.post("/v1/chat/completions")
    async def chat_completions(payload: dict) -> JSONResponse:
        profile = str(payload.get("profile") or config.default_persona).strip().lower()
        persona_name = PROFILE_TO_PERSONA.get(profile, profile)
        try:
            persona = personas.load(persona_name)
        except PersonaNotFound:
            return JSONResponse(
                {"error": {"message": f"unknown profile/persona: {profile!r}"}},
                status_code=400,
            )

        # Merge system content: persona prompt first, then any caller system
        # messages (Qwen-style single-system-message safety, mirrors Hermes).
        caller_msgs = payload.get("messages") or []
        sys_parts: list[str] = []
        if persona.system_prompt:
            sys_parts.append(persona.system_prompt)
        non_system: list[ChatMessage] = []
        for m in caller_msgs:
            role = m.get("role", "user")
            content = m.get("content", "")
            if not isinstance(content, str):
                content = json.dumps(content)
            if role == "system":
                if content.strip():
                    sys_parts.append(content)
            else:
                non_system.append(ChatMessage(role=role, content=content))
        messages: list[ChatMessage] = []
        if sys_parts:
            messages.append(ChatMessage(role="system", content="\n\n".join(sys_parts)))
        messages.extend(non_system)

        dm = persona.config.get("deep_model") if isinstance(persona.config, dict) else None
        dm = dm if isinstance(dm, dict) else {}
        temp = payload.get("temperature")
        opts = ChatOptions(
            max_tokens=int(payload.get("max_tokens") or dm.get("max_tokens", config.brain.max_tokens)),
            temperature=float(temp if temp is not None else dm.get("temperature", config.brain.temperature)),
            top_p=float(dm.get("top_p", config.brain.top_p)),
            top_k=int(dm.get("top_k", config.brain.top_k)),
            model=config.brain.model,
            persona_name=persona.name,
            model_path=resolve_model(dm),
        )

        result = BrainStreamResult()
        parts: list[str] = []
        try:
            async for delta in brain.chat(messages, opts, result):
                parts.append(delta)
        except Exception as exc:  # noqa: BLE001 - surface as a gateway error
            logger.exception("chat_completions brain error")
            return JSONResponse({"error": {"message": str(exc)}}, status_code=502)
        text = "".join(parts).strip()
        return JSONResponse(
            {
                "id": f"valar-{uuid.uuid4().hex[:12]}",
                "object": "chat.completion",
                "model": result.model_used or persona_name,
                "choices": [
                    {
                        "index": 0,
                        "message": {"role": "assistant", "content": text},
                        "finish_reason": "stop",
                    }
                ],
                "usage": {
                    "prompt_tokens": result.usage.prompt_tokens,
                    "completion_tokens": result.usage.completion_tokens,
                    "total_tokens": result.usage.prompt_tokens + result.usage.completion_tokens,
                },
            }
        )

    # --- HTTP: Mentat run state (Phase 4 client panel) --------------------
    # Read-only mirror of the conductor's run-state file so the desktop
    # client's Mentat tab can poll it without a voice turn.
    @app.get("/mentat/state")
    async def mentat_state() -> JSONResponse:
        from pathlib import Path as _Path

        from ..tools.handlers.mentat import _resolve_last_run

        resolved = _resolve_last_run()
        if resolved is None:
            return JSONResponse({"run": None, "status": "none"})
        name, _cfg, state_path = resolved
        try:
            state = json.loads(_Path(state_path).read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001 - starting up or no state yet
            state = {"run": name, "status": "unknown"}
        return JSONResponse(state)

    # --- HTTP: delegated-agent run state ----------------------------------
    # The terminal card polls this while a run is in flight, so the card fills
    # in on its own instead of the operator having to ask "is it done yet".
    # Same read-only shape as /mentat/state.
    @app.get("/claude/state")
    async def claude_state() -> JSONResponse:
        from ..tools.handlers.claude_code import latest_state

        return JSONResponse(latest_state())

    # --- HTTP: the easel ---------------------------------------------------
    # The image card polls this while a drawing is in flight. Read-only: the
    # watcher thread in the handler is what actually collects the PNG, so a
    # drawing lands whether or not any client is looking.
    @app.get("/imagery/state")
    async def imagery_state() -> JSONResponse:
        from ..tools.handlers.imagery import latest_state

        return JSONResponse(latest_state())

    # The operator's answer to a permission request, from the card's Approve
    # or Deny button. Approving resumes the same session with a grant scoped
    # to the commands it asked for; the run never leaves the workspace it was
    # already allow-listed into, so this widens what it may RUN, never where.
    @app.post("/claude/decide")
    async def claude_decide(payload: dict) -> JSONResponse:
        from ..tools.handlers.claude_code import decide

        run_id = str(payload.get("run_id") or "")
        approve = bool(payload.get("approve"))
        if not run_id:
            return JSONResponse({"ok": False, "error": "run_id required"}, status_code=400)
        return JSONResponse(decide(run_id, approve))

    # --- HTTP: raw OpenAI pass-through (Phase 2.6) ------------------------
    # The single-doorway route for machine executors (the Mentat conductor's
    # Pi beats): a thin streaming reverse-proxy to the brain's own OpenAI
    # endpoint. tools / tool_calls / role:"tool" / SSE pass through natively
    # (llama-server speaks the full protocol) -- no persona injection, no
    # protocol reimplementation. This retires the "Pi -> :8080 direct"
    # exception: point Pi's baseUrl at http://<host>:8700/v1/raw and every
    # executor token flows through Valar's front door.
    import httpx as _httpx
    from fastapi.responses import Response, StreamingResponse

    _brain_http = config.brain.base_url.rstrip("/")

    @app.get("/v1/raw/models")
    async def raw_models() -> Response:
        try:
            async with _httpx.AsyncClient(timeout=10.0) as client:
                r = await client.get(f"{_brain_http}/models")
            return Response(
                content=r.content,
                status_code=r.status_code,
                media_type=r.headers.get("content-type", "application/json"),
            )
        except Exception as exc:  # noqa: BLE001 - surface as a gateway error
            return JSONResponse({"error": {"message": str(exc)}}, status_code=502)

    @app.post("/v1/raw/chat/completions")
    async def raw_chat(payload: dict) -> Response:
        n_msgs = len(payload.get("messages") or [])
        n_tools = len(payload.get("tools") or [])
        stream = bool(payload.get("stream"))
        logger.info(
            "raw pass-through: msgs=%d tools=%d stream=%s", n_msgs, n_tools, stream
        )
        url = f"{_brain_http}/chat/completions"
        if not stream:
            try:
                async with _httpx.AsyncClient(timeout=_httpx.Timeout(600.0, connect=10.0)) as client:
                    r = await client.post(url, json=payload)
                return Response(
                    content=r.content,
                    status_code=r.status_code,
                    media_type=r.headers.get("content-type", "application/json"),
                )
            except Exception as exc:  # noqa: BLE001
                return JSONResponse({"error": {"message": str(exc)}}, status_code=502)

        async def _relay():
            # Client lifetime is owned by the generator: FastAPI consumes it
            # after this handler returns, so the connection must not be closed
            # by a with-block scoped to the handler.
            client = _httpx.AsyncClient(timeout=_httpx.Timeout(600.0, connect=10.0))
            try:
                async with client.stream("POST", url, json=payload) as resp:
                    async for chunk in resp.aiter_bytes():
                        yield chunk
            finally:
                await client.aclose()

        return StreamingResponse(_relay(), media_type="text/event-stream")

    # --- WS: the universal voice protocol --------------------------------
    @app.websocket("/")
    @app.websocket("/ws")
    async def ws_endpoint(websocket: WebSocket) -> None:
        await websocket.accept()
        session = Session(session_id=str(uuid.uuid4()))
        vad = EnergyVAD(sample_rate=config.voice.input_sample_rate)
        logger.info("WS connect session=%s", session.session_id)

        async def emit(kind: str, payload: object) -> None:
            if isinstance(payload, (bytes, bytearray)):
                await websocket.send_bytes(bytes(payload))
            else:
                await websocket.send_text(json.dumps(payload))

        # Harness-owned auto session-end: after HEARTH_SESSION_IDLE_S with no
        # turns, persist (Engram diary + SCX continuity), emit session_ended,
        # and clear the history. Per-connection task; cancelled on disconnect.
        watchdog = asyncio.create_task(
            idle_watchdog(session, personas.current, brain, config, emit)
        )
        # A drawing outlives the turn that asked for it, so something has to
        # speak when it lands. Same per-connection shape as the idle watchdog,
        # which is why neither needs a broadcast registry.
        easel = asyncio.create_task(
            easel_watchdog(session, personas.current, voice_loop, emit)
        )

        try:
            while True:
                message = await websocket.receive()
                if message.get("type") == "websocket.disconnect":
                    break
                if "bytes" in message and message["bytes"] is not None:
                    await _handle_audio(
                        message["bytes"], session, vad, stt, personas, voice_loop, emit
                    )
                elif "text" in message and message["text"] is not None:
                    await _handle_command(
                        message["text"], session, personas, voice_loop, emit
                    )
        except WebSocketDisconnect:
            pass
        except Exception as exc:  # noqa: BLE001 - keep the server alive
            logger.exception("WS session error: %s", exc)
            try:
                await emit("error", {"action": "error", "message": str(exc)})
            except Exception:
                pass
        finally:
            watchdog.cancel()
            easel.cancel()
            # Cancel any in-flight turn task so it stops emitting into the dead
            # socket (the "Future exception was never retrieved" spam).
            task = session.turn_task
            if task is not None and not task.done():
                task.cancel()
            logger.info("WS disconnect session=%s", session.session_id)

    # --- startup: warm the heavy models in the background ----------------
    @app.on_event("startup")
    async def _warm_models() -> None:
        """Pre-load Whisper + NeuTTS backbone + the default persona's voice clone,
        and make the daily model resident, at boot. With the always-on stack the
        models should already be hot; lazy-loading them on the FIRST voice turn
        made turn 1 a ~20s wait. Runs as a background task so the server binds and
        accepts clients immediately — the warm-up just front-runs the first turn.
        Every step is best-effort: a failure logs and falls back to lazy-load."""

        async def _warm() -> None:
            loop = asyncio.get_running_loop()
            try:
                persona = personas.current()
            except Exception:  # noqa: BLE001 - warm-up never blocks startup
                persona = None
            # 1) Whisper STT model.
            try:
                await loop.run_in_executor(None, stt.warm)
            except Exception as exc:  # noqa: BLE001
                logger.warning("warm: STT load failed (will lazy-load): %s", exc)
            if persona is not None:
                # 2) NeuTTS backbone + persona voice-clone encode (GPU-heavy).
                try:
                    await loop.run_in_executor(
                        None,
                        tts.sync_persona_voice,
                        persona.voice_reference_audio,
                        persona.voice_reference_text,
                    )
                except Exception as exc:  # noqa: BLE001
                    logger.warning("warm: TTS/voice load failed (will lazy-load): %s", exc)
                # 3) Make the daily model resident on the brain (router backend).
                warm = getattr(brain, "warm", None)
                if warm is not None:
                    dm = (
                        persona.config.get("deep_model")
                        if isinstance(persona.config, dict)
                        else None
                    )
                    dm = dm if isinstance(dm, dict) else {}
                    opts = ChatOptions(
                        model=config.brain.model,
                        persona_name=persona.name,
                        model_path=resolve_model(dm),
                    )
                    try:
                        await warm(opts)
                    except Exception as exc:  # noqa: BLE001
                        logger.warning("warm: brain model warm failed: %s", exc)
            logger.info("warm: startup model warm-up complete")

        asyncio.create_task(_warm())

        # STT keep-warm (2026-06-06): the one-shot boot warm is not enough on
        # the shared GPU — WDDM pages Whisper out after idle minutes and the
        # next utterance pays 13-31s inline. A periodic tick keeps it resident;
        # the tick itself skips when a real inference ran within the interval.
        keepwarm_s = float(os.environ.get("HEARTH_STT_KEEPWARM_S", "90") or 0)
        if keepwarm_s > 0:

            async def _stt_keepwarm() -> None:
                loop = asyncio.get_running_loop()
                while True:
                    await asyncio.sleep(keepwarm_s)
                    try:
                        await loop.run_in_executor(None, stt.keep_warm, keepwarm_s)
                    except Exception as exc:  # noqa: BLE001 - never dies
                        logger.warning("stt keep-warm tick failed: %s", exc)

            asyncio.create_task(_stt_keepwarm())

    return app


def _merge_device_context(session, cmd: dict) -> None:
    """Merge any per-turn device_context (e.g. a refreshed location/timestamp) the
    client sent into the session's ambient context. No-op when absent."""
    dc = cmd.get("device_context")
    if isinstance(dc, dict):
        session.device_context.update(dc)


async def _run_text_turn(session, persona, text: str, voice_loop, emit) -> None:
    """Run a text-path turn (text_query / client_transcription) with the same
    failure bookkeeping the server-STT path gets from its turn wrapper.

    Phase 1b fix: these inline paths previously let exceptions bubble to the
    outer WS handler, which emitted an untyped error and NEVER announced the
    idle transition — an event-driven client (the Telegram-shim lineage) then
    hung on its THINKING watchdog. Failures are swallowed here (a turn never
    kills the WS); run_turn has already emitted the typed error event, so this
    wrapper only emits the generic one for failures that predate it.
    """

    async def _idle(reason: str) -> None:
        session.state = State.IDLE
        with contextlib.suppress(Exception):  # socket may already be gone
            await emit(
                "state_update",
                {"action": "state_update", "state": "idle", "stage": reason},
            )

    try:
        await voice_loop.run_turn(session, persona, text, emit)
    except asyncio.CancelledError:
        logger.info("text turn cancelled (reset/disconnect)")
        await _idle("cancelled")
        raise
    except Exception as exc:  # noqa: BLE001 - a turn never kills the WS
        logger.exception("text turn failed: %s", exc)
        if not getattr(exc, "_valar_error_emitted", False):
            with contextlib.suppress(Exception):
                await emit("error", {"action": "error", "message": str(exc)})
        await _idle("error")


async def _handle_command(raw: str, session, personas, voice_loop, emit) -> None:
    try:
        cmd = json.loads(raw)
    except json.JSONDecodeError:
        await emit("error", {"action": "error", "message": "invalid command JSON"})
        return
    action = cmd.get("action", "")

    if action == "client_info":
        session.platform = cmd.get("platform", "unknown")
        session.stt_mode = cmd.get("stt", "server")
        session.audio_format = cmd.get("audio_format", {})
        # Ambient device context (timezone, locale, units, location) from the
        # client OS -> injected into the prompt every turn. Merge so later per-turn
        # updates don't wipe the handshake values.
        dc = cmd.get("device_context")
        if isinstance(dc, dict):
            session.device_context.update(dc)
        # Client capabilities (ui_render, device_actions, spatial, ...) gate which
        # catalog tools are offered this session (see valar/tools tool-catalog).
        # A list of keys is accepted and coerced to truthy flags.
        caps = cmd.get("capabilities")
        if isinstance(caps, dict):
            session.capabilities.update(caps)
        elif isinstance(caps, (list, tuple)):
            session.capabilities.update({str(c): True for c in caps})
        await emit(
            "client_info_ack",
            {
                "action": "client_info_ack",
                "status": "received",
                "session_id": session.session_id,
                "server_capabilities": {
                    "audio_generation": True,
                    "voice_cloning": True,
                    "server_stt": True,
                    "spatial_support": False,
                },
            },
        )

    elif action == "text_query":
        text = (cmd.get("text") or "").strip()
        if not text:
            await emit("error", {"action": "error", "message": "empty text_query"})
            return
        _merge_device_context(session, cmd)
        persona = personas.current()
        await _run_text_turn(session, persona, text, voice_loop, emit)

    elif action == "client_transcription":
        # stt:"local" fork — client did STT on-device, sent the text.
        text = (cmd.get("text") or "").strip()
        if not text:
            return
        _merge_device_context(session, cmd)
        persona = personas.current()
        await _run_text_turn(session, persona, text, voice_loop, emit)

    elif action == "list_personas":
        await emit(
            "personas_list",
            {
                "action": "personas_list",
                # Client-aware: desktop sees Mentat (27B, desktop-only); the
                # lightweight clients (echo/ios/...) get the daily set only.
                "personas": personas.list_personas(session.platform),
                "current_persona": personas.current_name(),
            },
        )

    elif action == "switch_persona":
        # Both spellings arrive in the wild: the house clients send
        # persona_name; the setup flow sent bare name (found live 2026-08-08).
        name = cmd.get("persona_name") or cmd.get("name") or ""
        try:
            personas.switch(name)
            await emit(
                "persona_switched",
                {"action": "persona_switched", "persona_name": name, "status": "success"},
            )
        except PersonaNotFound as exc:
            await emit("error", {"action": "error", "message": str(exc)})

    elif action == "get_persona_config":
        name = cmd.get("persona_name", "")
        try:
            persona = personas.load(name)
            await emit(
                "persona_config",
                {
                    "action": "persona_config",
                    "persona_name": name,
                    "config": persona.public_config(),
                },
            )
        except PersonaNotFound as exc:
            await emit("error", {"action": "error", "message": str(exc)})

    elif action == "reset_vad":
        # The client abandoned the listening window (conversation timeout).
        # Cancel any in-flight turn task (Phase B: the turn runs concurrently,
        # so this command is no longer queued behind it) and bump the epoch so
        # an utterance still inside the STT executor is dropped on return.
        session.turn_epoch += 1
        task = session.turn_task
        if task is not None and not task.done():
            task.cancel()
            logger.info("reset_vad: cancelled in-flight turn task")
        session.reset_audio()
        session.state = State.IDLE

    elif action == "say":
        # Speak a short cue verbatim in the persona voice, no LLM turn (e.g. the
        # visionOS immersive-mode switch). Skipped if a turn is already in flight.
        text = (cmd.get("text") or "").strip()
        if not text:
            return
        if session.state in (State.THINKING, State.SPEAKING):
            return
        persona = personas.current()
        await voice_loop.say(session, persona, text, emit)

    elif action == "ping":
        await emit("pong", {"action": "pong", "status": "ok"})

    else:
        await emit("error", {"action": "error", "message": f"unknown command: {action}"})


async def _handle_audio(
    chunk: bytes, session, vad, stt, personas, voice_loop, emit
) -> None:
    """Server-side STT fork: buffer PCM, run VAD, transcribe on speech-end."""
    if session.stt_mode != "server":
        return  # local-STT clients should not stream audio; ignore defensively.

    # Half-duplex serialization: drop audio while a turn is in flight, so a client
    # whose mic stays open (THINKING/SPEAKING) can't re-trigger mid-turn or feed
    # its own TTS playback back into the VAD. One utterance -> one turn.
    if session.state in (State.THINKING, State.SPEAKING):
        return

    if session.state == State.IDLE:
        session.state = State.LISTENING
        session.reset_audio()
        vad.reset()

    session.audio_buffer.extend(chunk)
    event = vad.process_frame(chunk)
    if event.ended:
        utterance = bytes(session.audio_buffer)
        epoch = session.turn_epoch
        session.reset_audio()
        vad.reset()
        # Defensive: the THINKING/SPEAKING gate above makes a second VAD end
        # while a turn is in flight impossible, but never stack turn tasks.
        prior = session.turn_task
        if prior is not None and not prior.done():
            logger.warning("utterance while a turn task is in flight; dropped")
            return
        # Enter THINKING synchronously so the half-duplex gate drops further
        # mic audio while the turn task runs (the receive loop keeps going).
        session.state = State.THINKING
        # State-machine transition event (2026-06-06): announce the server's own
        # transition BEFORE the (potentially slow) STT so the client's state
        # machine follows the server instead of free-running a listen timeout
        # into IDLE mid-pipeline. Additive: clients ignore unknown actions.
        await emit(
            "state_update",
            {"action": "state_update", "state": "thinking", "stage": "transcribing"},
        )

        async def _emit_idle(reason: str) -> None:
            # A turn that dies WITHOUT output must still announce the idle
            # transition, or an event-driven client waits out its THINKING
            # watchdog (observed 2026-06-06: 30s hang on an empty turn).
            try:
                await emit(
                    "state_update",
                    {"action": "state_update", "state": "idle", "stage": reason},
                )
            except Exception:  # noqa: BLE001 - socket may already be gone
                pass

        async def _stt_and_turn() -> None:
            try:
                # Whisper is blocking + GPU-heavy; run it off the event loop so
                # the loop stays responsive. Timed here (STT happens BEFORE the
                # turn) and passed into run_turn so telemetry's stt_ms is real.
                loop = asyncio.get_running_loop()
                t_stt0 = time.monotonic()
                text = await loop.run_in_executor(None, stt.transcribe_pcm16, utterance)
                stt_ms = (time.monotonic() - t_stt0) * 1000.0
            except SttUnavailable as exc:
                await emit("error", {"action": "error", "message": str(exc)})
                session.state = State.IDLE
                await _emit_idle("error")
                return
            if session.turn_epoch != epoch:
                # The client reset (conversation timeout) while STT was in
                # flight: the user already left this exchange. Drop the stale
                # turn rather than speak into a window nobody is waiting on.
                logger.info(
                    "dropping stale turn (epoch %d -> %d): %r",
                    epoch, session.turn_epoch, text[:60],
                )
                session.state = State.IDLE
                await _emit_idle("cancelled")
                return
            if text.strip():
                await emit("transcription", {"action": "transcription", "text": text})
                persona = personas.current()
                await voice_loop.run_turn(session, persona, text, emit, stt_ms=stt_ms)
            else:
                session.state = State.IDLE
                await _emit_idle("no_speech")

        async def _turn_wrapper() -> None:
            # Phase B (2026-06-06): the STT+turn runs as a per-session TASK so
            # the WS receive loop stays responsive — reset_vad can cancel it,
            # and a disconnect cancels it instead of letting it emit into a
            # dead socket. Failures stay inside the wrapper (the old inline
            # path surfaced them through the WS loop's generic handler).
            try:
                await _stt_and_turn()
            except asyncio.CancelledError:
                logger.info("turn task cancelled (reset/disconnect)")
                session.state = State.IDLE
                await _emit_idle("cancelled")
                raise
            except Exception as exc:  # noqa: BLE001 - a turn never kills the WS
                logger.exception("turn task failed: %s", exc)
                # Phase 1b: run_turn emits ONE typed error event before
                # re-raising; only emit the generic one for failures that
                # happened before the turn body (e.g. persona load).
                if not getattr(exc, "_valar_error_emitted", False):
                    try:
                        await emit("error", {"action": "error", "message": str(exc)})
                    except Exception:  # noqa: BLE001 - socket may already be gone
                        pass
                session.state = State.IDLE
                await _emit_idle("error")

        session.turn_task = asyncio.create_task(_turn_wrapper())
