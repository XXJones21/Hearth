"""Valar single entry point (Odysseus-style FastAPI app).

Run:  python app.py            (uses HEARTH_HOST/HEARTH_PORT, defaults 0.0.0.0:8700)
  or: uvicorn app:app --host 0.0.0.0 --port 8700

This is the ONLY surface exposed to clients. It calls the Rust brain (via the
BrainProvider seam) for tokens; it does not host inference.
"""

from __future__ import annotations

import logging

from valar.config import load_config
from valar.gateway import create_app

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)

config = load_config()
app = create_app(config)


def main() -> None:
    import uvicorn

    logging.getLogger("valar").info(
        "starting Valar gateway on %s:%s (brain backend=%s -> %s)",
        config.host,
        config.port,
        config.brain.backend,
        config.brain.base_url,
    )
    # ws_ping_timeout=None: never tear down an in-flight voice turn for a late
    # pong. The loop can briefly stall on a cold model load or STT, during which
    # the websockets keepalive would otherwise fire 1011 mid-speech and drop the
    # client. We keep sending pings (NAT/idle keepalive) but do not require a
    # timely pong — client-side OkHttp pings + the clients' bounded reconnect
    # handle real liveness. (See the 15:42 keepalive-timeout disconnect.)
    uvicorn.run(
        app,
        host=config.host,
        port=config.port,
        log_level="info",
        ws_ping_interval=20.0,
        ws_ping_timeout=None,
    )


if __name__ == "__main__":
    main()
