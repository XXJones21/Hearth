"""generate_image / check_image -- the tier-2 imagery plumb (M10).

Submits a Flux job to the LOCAL ComfyUI (Windows-side :8189, reached on
:8188 over the comfy_bridge portproxy; the two ports MUST differ or IP
Helper squats the port and ComfyUI cannot bind) and, when it finishes,
pulls the PNG through ComfyUI's /view endpoint into Valar's served assets
dir so an image card can carry it to any client.

**The card arrives before the picture does.** generate_image returns an
`image_card` in the drawing state immediately, and a daemon thread watches
ComfyUI, collects the PNG, and fills the record in. Clients poll
`/imagery/state` and the card completes itself, which is the same shape
consult_claude uses for a delegated run. Before this the tool was
fire-and-forget: the drawing only reached the screen if the operator
happened to ask a second time AND the model happened to pick check_image,
and a turn that ended with "it should be ready" left nothing behind (live
on iOS, 2026-08-03). The worker is what makes the asset land even when no
client is watching; the poll only decides how fast anyone sees it.

check_image survives for the question a person actually asks out loud. It
reads the same record and never drives the generation itself.

One drawing at a time -- this is a companion drawing a picture, not a
render farm.

VRAM note: generation shares the 4080 with the resident brain; jobs run
slower under coexistence and may fail outright when VRAM is pinned. That is
reported honestly; the coexistence tuning is a known follow-up (same class
as CHOAM's trading-hours eviction).
"""

from __future__ import annotations

import json
import logging
import os
import re
import threading
import time
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

from ...config.settings import hearth_root
from ..spec import ToolResult

logger = logging.getLogger("valar.tools.imagery")

_COMFY_URL = os.environ.get("HEARTH_COMFY_URL", "http://127.0.0.1:8188").rstrip("/")
_ASSETS_DIR = hearth_root() / "harness" / "assets" / "generated"
_TIMEOUT_S = 15

# How long the watcher waits for a picture, and how often it looks. Flux at
# 20 steps is ~40s on a quiet card and several minutes when the brain is
# holding VRAM, so the ceiling is generous and the interval is cheap.
_POLL_S = 3
_GIVE_UP_S = 900

# One in-flight (or last finished) job. Mutated by the watcher thread and
# read by the event loop, so every write goes through _LOCK.
_JOB: dict = {}
_LOCK = threading.Lock()

_STYLE_SUFFIX = (
    " Warm palette of cream, amber, honey and terracotta, soft diffuse "
    "lighting, cozy storybook illustration style, high detail."
)


def _http_json(path: str, payload: dict | None = None, timeout: int = _TIMEOUT_S):
    url = f"{_COMFY_URL}{path}"
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        url, data=data,
        headers={"Content-Type": "application/json", "User-Agent": "Valar/1.0"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310
        return json.loads(resp.read().decode("utf-8"))


def _flux_graph(prompt: str, width: int, height: int, seed: int) -> dict:
    """The known-good local Flux graph (Q4 UNet + fp8 T5 + clip_l)."""
    return {
        "5": {"class_type": "EmptySD3LatentImage",
              "inputs": {"width": width, "height": height, "batch_size": 1}},
        "6": {"class_type": "CLIPTextEncode",
              "inputs": {"text": prompt, "clip": ["11", 0]}},
        "8": {"class_type": "VAEDecode",
              "inputs": {"samples": ["13", 0], "vae": ["10", 0]}},
        "9": {"class_type": "SaveImage",
              "inputs": {"filename_prefix": "hearth_gen", "images": ["8", 0]}},
        "10": {"class_type": "VAELoader", "inputs": {"vae_name": "flux_vae.safetensors"}},
        "11": {"class_type": "DualCLIPLoader",
               "inputs": {"clip_name1": "clip_l.safetensors",
                          "clip_name2": "t5xxl_fp8_e4m3fn.safetensors",
                          "type": "flux", "device": "default"}},
        "12": {"class_type": "UnetLoaderGGUF",
               "inputs": {"unet_name": "flux1-dev-Q4_K_S.gguf"}},
        "13": {"class_type": "KSampler",
               "inputs": {"seed": seed, "steps": 20, "cfg": 1,
                          "sampler_name": "euler", "scheduler": "simple",
                          "denoise": 1, "model": ["12", 0],
                          "positive": ["17", 0], "negative": ["16", 0],
                          "latent_image": ["5", 0]}},
        "16": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["6", 0]}},
        "17": {"class_type": "FluxGuidance",
               "inputs": {"guidance": 3.5, "conditioning": ["6", 0]}},
    }


def _card(job: dict) -> dict:
    """The image_card for a job in any state. The client re-renders this same
    card from /imagery/state, so the shape must not change between states."""
    return {
        "version": 1,
        "type": "image_card",
        "props": {
            "title": "From the easel",
            "prompt": job.get("prompt", ""),
            "status": job.get("status", "running"),
            "src": job.get("asset", ""),
            "note": job.get("note", ""),
            # Present while the drawing can still change; the card polls
            # /imagery/state until it settles.
            "job_id": job.get("id", ""),
        },
    }


def _snapshot() -> dict:
    with _LOCK:
        return dict(_JOB)


def _settle(job_id: str, **fields) -> None:
    """Write the outcome, but only if this job is still the current one. A
    second drawing started meanwhile owns the record; a late watcher must not
    overwrite it."""
    with _LOCK:
        if _JOB.get("id") != job_id:
            return
        _JOB.update(fields, finished=time.time())


def _collect(prompt_id: str, filename: str) -> str:
    """Pull the PNG out of ComfyUI into the served assets dir. Returns the
    client-facing relative path."""
    qs = urllib.parse.urlencode({"filename": filename, "type": "output"})
    req = urllib.request.Request(
        f"{_COMFY_URL}/view?{qs}", headers={"User-Agent": "Valar/1.0"}
    )
    with urllib.request.urlopen(req, timeout=30) as resp:  # noqa: S310
        blob = resp.read()
    _ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    safe = re.sub(r"[^\w.-]", "_", filename) or f"gen_{int(time.time())}.png"
    (_ASSETS_DIR / safe).write_bytes(blob)
    logger.info("imagery: collected %s (%d bytes) for %s", filename, len(blob), prompt_id)
    return f"assets/generated/{safe}"


def _watch(job_id: str) -> None:
    """Daemon: poll ComfyUI until the picture exists, then collect it.

    Runs whether or not anyone is looking, so the asset is on disk by the
    time the first client asks. Network hiccups are retried rather than
    treated as failure; only ComfyUI saying 'error' ends it early."""
    deadline = time.time() + _GIVE_UP_S
    while time.time() < deadline:
        time.sleep(_POLL_S)
        with _LOCK:
            if _JOB.get("id") != job_id:
                return  # superseded by a newer drawing
        try:
            hist = _http_json(f"/history/{job_id}", timeout=8)
        except Exception as exc:  # noqa: BLE001 - transient; keep watching
            logger.debug("imagery: history poll failed (%s), retrying", exc)
            continue
        entry = hist.get(job_id) or {}
        if (entry.get("status") or {}).get("status_str") == "error":
            _settle(job_id, status="error", note=(
                "the drawing failed on the easel, most often because the "
                "canvas ran out of room while the brain was thinking"
            ))
            logger.warning("imagery: job %s failed in ComfyUI", job_id)
            return
        images = ((entry.get("outputs") or {}).get("9") or {}).get("images") or []
        if not images:
            continue
        try:
            asset = _collect(job_id, images[0].get("filename", ""))
        except Exception as exc:  # noqa: BLE001
            logger.warning("imagery: collect failed: %s", exc)
            _settle(job_id, status="error", note=(
                "the drawing finished but could not be collected off the easel"
            ))
            return
        _settle(job_id, status="done", asset=asset, note="")
        return
    _settle(job_id, status="error", note=(
        "the drawing never finished; the studio may be stuck"
    ))
    logger.warning("imagery: job %s gave up after %ds", job_id, _GIVE_UP_S)


async def generate_image(args: dict) -> ToolResult:
    """args: {prompt: str, orientation?: landscape|portrait|square}. Submit a
    local image generation; the card lands now and fills itself in."""
    prompt = str(args.get("prompt") or "").strip()
    if not prompt:
        return ToolResult.error("what should I draw? Give me a description.")
    current = _snapshot()
    if current and current.get("status") == "running":
        return ToolResult.error(
            "one drawing is already on the easel -- let it finish before "
            "starting another."
        )
    orient = str(args.get("orientation") or "landscape").lower()
    width, height = {"portrait": (512, 768), "square": (640, 640)}.get(orient, (768, 512))
    seed = uuid.uuid4().int % 2_000_000_000
    try:
        res = _http_json("/prompt", {
            "prompt": _flux_graph(prompt + _STYLE_SUFFIX, width, height, seed),
            "client_id": "valar-imagery",
        })
    except Exception as exc:  # noqa: BLE001
        logger.warning("ComfyUI submit failed: %s", exc)
        return ToolResult.error(
            "the art studio is unreachable right now -- is ComfyUI running?"
        )
    prompt_id = str(res.get("prompt_id") or "")
    if not prompt_id:
        return ToolResult.error("the art studio refused the job.")

    with _LOCK:
        _JOB.clear()
        _JOB.update({
            "id": prompt_id, "prompt": prompt, "status": "running",
            "started": time.time(), "asset": "", "note": "",
        })
    threading.Thread(
        target=_watch, args=(prompt_id,), daemon=True,
        name=f"imagery-{prompt_id[:8]}",
    ).start()
    logger.info("imagery: submitted %s (%dx%d): %r", prompt_id, width, height, prompt[:80])

    # Kept short on purpose. A long instruction here survives into history and
    # the model can answer the NEXT drawing request by replaying it instead of
    # calling the tool again (live 2026-08-03: "now draw a lighthouse" got the
    # previous turn's sentence back and no tool call). State the fact, keep the
    # one guardrail that stops a fabricated completion, and stop talking.
    return ToolResult(
        content=(
            "This drawing is on the easel now and is already on the operator's "
            "screen, filling itself in as it renders. It is NOT finished yet."
        ),
        data={"ui_component": _card(_snapshot())},
    )


async def check_image(args: dict) -> ToolResult:
    """args: {}. What the easel is doing. The picture reaches the screen on
    its own; this answers the question when it is asked out loud."""
    job = _snapshot()
    if not job:
        return ToolResult.error("nothing is on the easel -- no drawing was started.")
    status = job.get("status")
    if status == "running":
        elapsed = int(time.time() - job.get("started", time.time()))
        return ToolResult(
            content=(
                f"Still drawing, about {elapsed} seconds in. It appears on the "
                "screen by itself when it is done; nothing needs fetching."
            ),
            data={"ui_component": _card(job)},
        )
    if status == "error":
        return ToolResult.error(job.get("note") or "the drawing did not finish.")
    return ToolResult(
        content="The drawing is finished and on the screen.",
        data={"ui_component": _card(job)},
    )


def latest_state() -> dict:
    """The current (or last) drawing, for the read-only HTTP route the cards
    poll. Same field names as the card props so the client can swap one for
    the other without translating."""
    job = _snapshot()
    if not job:
        return {"job_id": "", "status": "none"}
    return {
        "job_id": job.get("id", ""),
        "status": job.get("status", "running"),
        "prompt": job.get("prompt", ""),
        "src": job.get("asset", ""),
        "note": job.get("note", ""),
        "started": job.get("started"),
        "finished": job.get("finished"),
    }
