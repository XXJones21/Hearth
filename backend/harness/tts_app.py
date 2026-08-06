"""Valar TTS service entry point — the persistent NeuTTS-Air process.

Run:  python tts_app.py   (binds 127.0.0.1:HEARTH_TTS_PORT, default 8701)

Holds NeuTTS resident so the Valar gateway (app.py) can restart without reloading
the GPU TTS model. Internal only; the gateway connects over ws://127.0.0.1:8701/tts.
"""

from __future__ import annotations

import logging

from valar.config import load_config
from valar.persona import PersonaEngine
from valar.voice.tts_service import create_tts_app

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)

config = load_config()

# Resolve the default persona's voice so the service warms the right clone at boot.
_default_voice = None
try:
    _personas = PersonaEngine(config.persona_dir, config.default_persona)
    _persona = _personas.current()
    _default_voice = (_persona.voice_reference_audio, _persona.voice_reference_text)
except Exception as exc:  # noqa: BLE001 - warm is best-effort; serve anyway
    logging.getLogger("valar.tts_service").warning("default voice resolve failed: %s", exc)

app = create_tts_app(
    config.persona_dir.parent,
    service=config.voice.tts_service,
    sample_rate=config.voice.output_sample_rate,
    default_voice=_default_voice,
)


def main() -> None:
    import uvicorn

    logging.getLogger("valar.tts_service").info(
        "starting Valar TTS service on 127.0.0.1:%s (service=%s)",
        config.voice.tts_port,
        config.voice.tts_service,
    )
    uvicorn.run(app, host="127.0.0.1", port=config.voice.tts_port, log_level="info")


if __name__ == "__main__":
    main()
