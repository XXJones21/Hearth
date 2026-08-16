"""What the house is doing, and which mind is in it.

The client's Settings panel can already show most of this. The persona could
not, which meant the one participant in the conversation who knows why an
answer took forty seconds was the only one unable to say so.

Everything here is OBSERVED rather than assumed. A model path in a config
file is a plan; what is answering on the brain port is a fact, and these
report the second. Where something cannot be observed, it is left out rather
than guessed at.
"""

from __future__ import annotations

import logging
import os
import platform
import subprocess
import time

from ..spec import ToolResult

logger = logging.getLogger("valar.tools.house")

_STARTED = time.time()
_PROBE_TIMEOUT_S = 4.0


def _fmt_uptime(seconds: float) -> str:
    s = int(max(0, seconds))
    if s < 90:
        return f"{s} seconds"
    if s < 5400:
        return f"{s // 60} minutes"
    hours = s / 3600
    if hours < 48:
        return f"{hours:.1f} hours"
    return f"{hours / 24:.1f} days"


def _brain_base() -> str:
    from ...config.settings import BrainConfig

    return BrainConfig().base_url.rstrip("/")


def _resident_model() -> tuple[str, str]:
    """(model name, error). Asks the brain what it is holding right now."""
    import httpx

    url = _brain_base() + "/models"
    try:
        with httpx.Client(timeout=_PROBE_TIMEOUT_S) as client:
            resp = client.get(url)
            if resp.status_code != 200:
                return "", f"the brain answered {resp.status_code}"
            data = resp.json()
    except Exception as exc:  # noqa: BLE001 - not answering IS the answer
        return "", f"the brain is not answering ({type(exc).__name__})"
    items = data.get("data") or []
    if not items:
        return "", "the brain reports no model loaded"
    name = str(items[0].get("id") or "").strip()
    return (os.path.basename(name) or name), ""


def _gpu_lines() -> list[str]:
    """Whatever nvidia-smi will say, or nothing. Never an error: a machine
    without an NVIDIA card is not a machine with a problem."""
    try:
        proc = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=name,memory.used,memory.total,utilization.gpu",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            timeout=_PROBE_TIMEOUT_S,
            check=False,
        )
    except Exception:  # noqa: BLE001
        return []
    if proc.returncode != 0:
        return []
    out: list[str] = []
    for line in (proc.stdout or "").strip().splitlines():
        parts = [p.strip() for p in line.split(",")]
        if len(parts) >= 4:
            used, total = parts[1], parts[2]
            free = ""
            try:
                free = f", {int(total) - int(used)} MB free"
            except ValueError:
                pass
            out.append(f"{parts[0]}: {used} of {total} MB used{free}, {parts[3]}% busy")
    return out


def house_status(args: dict) -> ToolResult:
    """How the house is running, in terms the operator can act on."""
    lines: list[str] = []

    model, err = _resident_model()
    if model:
        lines.append(f"Mind: {model} is loaded and answering.")
    else:
        lines.append(f"Mind: not available right now ({err}).")

    for gpu in _gpu_lines():
        lines.append(f"Graphics: {gpu}")

    lines.append(f"This house has been up {_fmt_uptime(time.time() - _STARTED)}.")
    lines.append(f"Running on {platform.system()} {platform.release()}.")

    try:
        from ...memory.journal_sync import engram_root

        root = engram_root()
        lines.append(
            f"Memory tree: {root}" if root else "Memory tree: none connected."
        )
    except Exception:  # noqa: BLE001
        pass

    try:
        from ...memory.session_record import list_records

        records = list_records(limit=200)
        unsynced = sum(1 for r in records if not r.get("synced"))
        lines.append(
            f"Conversations kept: {len(records)}"
            + (f", {unsynced} not yet written up" if unsynced else "")
        )
    except Exception:  # noqa: BLE001
        pass

    logger.info("house_status reported")
    return ToolResult(
        content="\n".join(lines)
        + "\nAnswer in plain language. Do not read the numbers out verbatim "
        "unless they asked for them.",
        data={"model": model, "up_seconds": int(time.time() - _STARTED)},
    )


def list_models(args: dict) -> ToolResult:
    """The models on this machine, so a switch names a real one."""
    try:
        from ...config.settings import hearth_models

        folder = hearth_models()
    except Exception:  # noqa: BLE001
        from ...config.settings import REPO_ROOT  # type: ignore

        folder = REPO_ROOT / "models"
    if not folder.is_dir():
        return ToolResult.error(f"There is no models folder at {folder}.")
    found = sorted(p.name for p in folder.glob("*.gguf"))
    if not found:
        return ToolResult.error(f"No models are installed in {folder}.")
    resident, _err = _resident_model()
    lines = [f"Models on this machine: {len(found)}"]
    for name in found[:30]:
        lines.append(f"- {name}" + ("  (loaded)" if resident and resident in name else ""))
    return ToolResult(content="\n".join(lines), data={"models": found, "loaded": resident})


async def switch_model(args: dict) -> ToolResult:
    """args: {model: str}. Make a different model resident for the next turn.

    The supervisor has done this since the router was written; it had no
    conversational door. Loading is not instant and the tool says so, because
    a silent forty-second pause reads as a broken house.
    """
    want = str((args or {}).get("model") or "").strip()
    if not want:
        return ToolResult.error("Which model? Call list_models first; never guess a filename.")

    from ..context import turn_context

    ctx = turn_context()
    brain = ctx.get("brain")
    if brain is None or not hasattr(brain, "_ensure_model"):
        return ToolResult.error(
            "This house does not route between models: it runs the one it was "
            "started with. Say so plainly."
        )

    try:
        from ...config.settings import hearth_models

        folder = hearth_models()
    except Exception:  # noqa: BLE001
        folder = None
    match = ""
    if folder and folder.is_dir():
        names = sorted(p.name for p in folder.glob("*.gguf"))
        exact = [n for n in names if n.lower() == want.lower()]
        loose = [n for n in names if want.lower() in n.lower()]
        if exact:
            match = exact[0]
        elif len(loose) == 1:
            match = loose[0]
        elif len(loose) > 1:
            return ToolResult.error(
                f"{want!r} matches several models: {', '.join(loose[:5])}. Ask which."
            )
        else:
            return ToolResult.error(
                f"No model here is called {want!r}. Call list_models and offer what exists."
            )
        target = str(folder / match)
    else:
        target = want

    from ...brain import ChatOptions

    opts = ChatOptions(model_path=target, persona_name=str((ctx.get("persona") and ctx["persona"].name) or ""))
    try:
        await brain._ensure_model(opts)  # noqa: SLF001 - the switch seam is private by habit, not by design
    except Exception as exc:  # noqa: BLE001
        logger.warning("switch_model failed %s: %s", target, exc)
        return ToolResult.error(f"That model could not be loaded: {exc}")

    logger.info("switch_model -> %s", target)
    return ToolResult(
        content=(
            f"Loaded: {match or target}. It answers from the next thing they say.\n"
            "Tell them which model is in, and that the first reply after a swap "
            "is slower while it settles."
        ),
        data={"model": match or target},
    )
