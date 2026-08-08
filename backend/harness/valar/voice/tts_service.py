"""Persistent NeuTTS-Air TTS service.

Holds the GPU-heavy NeuTTS backbone + per-persona voice encoding RESIDENT in its
own process so Valar's gateway can restart its code without reloading the model
(the NeuTTS-reload / VRAM-churn the gateway hit on every restart). This mirrors the
Brain decoupling: TTS is a separate process Valar talks to over a socket, not an
in-process model.

Protocol (WS ``/tts``, one request streams one sentence):
  client -> {"text": "...", "ref_audio": "/abs/path.wav", "ref_text": "..."}
  server -> binary float32 PCM frames ... then {"action": "tts_done"}
            (or {"action": "tts_error", "message": "..."})

The voice reference is encoded + cached HERE (server-side), so a persona switch
costs the encode once on the service, never in Valar. Binds 127.0.0.1 (internal,
like the brain); only Valar :8700 faces clients.
"""

from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path
from typing import Optional, Tuple

from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse, Response

logger = logging.getLogger("valar.tts_service")


def create_tts_app(
    repo_root: Path,
    service: str = "omnivoice",
    sample_rate: int = 48000,
    default_voice: Optional[Tuple[Optional[Path], Optional[str]]] = None,
) -> FastAPI:
    app = FastAPI(title="Valar TTS Service", version="1.0.0")
    # Engine fork on HEARTH_TTS_SERVICE. Both are the same k2-fsa model and
    # both implement the same streamer interface, so everything below — and the
    # gateway, and the clients — is engine-agnostic (the TTS seam).
    #
    #   "omnivoice-cpp"  omnivoice.cpp over HTTP. Metal on Apple Silicon, CUDA
    #                    and Vulkan elsewhere; the weights live in a separate
    #                    shipped binary, so this side costs a socket.
    #   "omnivoice"      the torch build in its own venv. CUDA or CPU only:
    #                    it has no MPS path, so on any Mac it runs on the
    #                    processor at roughly 7.6x realtime.
    if service == "omnivoice-cpp":
        from .tts_cpp import OmniVoiceCppStreamer

        tts = OmniVoiceCppStreamer(repo_root, service=service, sample_rate=sample_rate)
    elif service == "omnivoice":
        from .tts_omnivoice import OmniVoiceStreamer

        tts = OmniVoiceStreamer(repo_root, service=service, sample_rate=sample_rate)
    else:
        raise ValueError(
            f"unknown voice engine {service!r}; Hearth ships omnivoice-cpp and omnivoice. "
            "Set HEARTH_TTS_SERVICE=omnivoice-cpp."
        )
    app.state.tts = tts

    @app.get("/health")
    async def health() -> JSONResponse:
        # READY means the backbone is loaded AND a voice is encoded (the warm
        # completed), not merely that the module imported. (_loaded was the import
        # flag and lied — the gateway hit the service before NeuTTS finished loading
        # and got 0 frames.) _ref_codes is set only after a successful encode.
        ready = getattr(tts, "_ref_codes", None) is not None
        return JSONResponse(
            {"status": "ok", "ready": ready, "imported": bool(tts._loaded), "service": service}
        )

    @app.post("/design")
    async def design(request: Request) -> Response:
        """Voice design: synthesize a sample in a voice described by instruct
        attributes. Runs once per persona, at creation; the WAV returned
        becomes the persona's reference clip and runtime stays pure cloning.
        Body: {"text": "...", "attributes": ["male", "low pitch", ...]}."""
        try:
            body = await request.json()
        except Exception:
            return JSONResponse({"error": "body must be JSON"}, status_code=400)
        text = str(body.get("text") or "").strip()
        attributes = body.get("attributes") or []
        if not text:
            return JSONResponse({"error": "text is required"}, status_code=400)
        if not isinstance(attributes, list):
            return JSONResponse({"error": "attributes must be a list"}, status_code=400)
        loop = asyncio.get_running_loop()
        try:
            wav = await loop.run_in_executor(
                None, tts.design_sample, text, [str(a) for a in attributes]
            )
        except Exception as exc:  # noqa: BLE001 - the caller needs the reason
            logger.warning("voice design failed: %s", exc)
            return JSONResponse({"error": str(exc)}, status_code=500)
        return Response(content=wav, media_type="audio/wav")

    @app.on_event("startup")
    async def _warm() -> None:
        """Load NeuTTS + encode the default persona voice once, at the service's
        own startup. Best-effort; lazy-loads on first request otherwise."""

        async def _w() -> None:
            if not default_voice:
                return
            ref_audio, ref_text = default_voice
            loop = asyncio.get_running_loop()
            try:
                await loop.run_in_executor(None, tts.sync_persona_voice, ref_audio, ref_text)
                logger.info("TTS service warm: default voice encoded (%s)", ref_audio)
            except Exception as exc:  # noqa: BLE001 - warm never blocks startup
                logger.warning("TTS service warm failed (will lazy-load): %s", exc)

        asyncio.create_task(_w())

    @app.websocket("/tts")
    async def tts_ws(ws: WebSocket) -> None:
        await ws.accept()
        loop = asyncio.get_running_loop()
        try:
            while True:
                req = json.loads(await ws.receive_text())
                text = (req.get("text") or "").strip()
                if not text:
                    await ws.send_text(json.dumps({"action": "tts_done"}))
                    continue
                ref_audio = req.get("ref_audio")
                ref_text = req.get("ref_text")
                import time as _time

                t_req = _time.monotonic()
                # Ensure the requested persona voice is encoded (cached server-side).
                #
                # A persona with NO reference clip used to skip this entirely,
                # which is how a newly made persona spoke in Sulivan's voice on
                # 2026-08-08: sync was never called, the streamer kept the last
                # voice it resolved, and every sentence went out under that
                # name. tts_cpp's own docstring had already called it -- "a
                # persona silently speaking in the default voice is worse than
                # an error, nothing downstream can tell it happened" -- and the
                # guard that says so lives INSIDE the call being skipped.
                #
                # So the no-clip case is now explicit: clear the voice and let
                # the engine refuse. Better a turn that fails loudly than a
                # house that quietly puts words in the wrong mouth.
                if ref_audio:
                    await loop.run_in_executor(
                        None, tts.sync_persona_voice, Path(ref_audio), ref_text
                    )
                else:
                    await loop.run_in_executor(
                        None, tts.sync_persona_voice, None, None
                    )
                t_sync = _time.monotonic()
                try:
                    frames = 0
                    nbytes = 0
                    async for pcm in tts.stream_sentence(text):
                        await ws.send_bytes(pcm)
                        frames += 1
                        nbytes += len(pcm)
                    await ws.send_text(json.dumps({"action": "tts_done"}))
                    t_done = _time.monotonic()
                    logger.info(
                        "TTS served %d frames (%d bytes) for %r [sync %.2fs synth+stream %.2fs]",
                        frames,
                        nbytes,
                        text[:40],
                        t_sync - t_req,
                        t_done - t_sync,
                    )
                except Exception as exc:  # noqa: BLE001 - one bad sentence != drop the conn
                    logger.error("TTS generate failed: %s", exc)
                    await ws.send_text(json.dumps({"action": "tts_error", "message": str(exc)}))
        except WebSocketDisconnect:
            pass
        except Exception as exc:  # noqa: BLE001 - keep the service alive
            logger.exception("TTS WS session error: %s", exc)

    return app
