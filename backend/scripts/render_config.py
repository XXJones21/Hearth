#!/usr/bin/env python3
"""Render hearth.env from the install record.

The client's setup flow scans the machine, plans a model against it, downloads
the weights, and writes hearth-install.json beside them. This turns that record
into the environment file the three systemd units read.

It is deliberately not wired to anything yet. M13's installer calls it; this
commit only makes the translation exist and be readable, so the seam between
the probe's plan and the backend's configuration can be reviewed as one thing.

Usage:
    render_config.py [--record PATH] [--out PATH] [--root PATH] [--print]

    --record  the hearth-install.json to read. Default: $HEARTH_MODELS, then
              $HEARTH_HOME/models, then ./hearth-install.json
    --out     where to write. Default: $HEARTH_HOME/config/hearth.env
    --root    the value to write for HEARTH_ROOT. Default: $HEARTH_ROOT, else
              this script's parent directory
    --print   write to stdout instead of a file

Every field it writes is documented in config/hearth.env.example, which names
the plan field each one comes from.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path, PurePosixPath

# Dictionary tier id to the identifier a persona manifest names. The dictionary
# numbers its tiers; personas want a name a human can read in a file. This is
# the one place the two vocabularies meet, and valar/models.py holds the same
# table for the resolver.
TIER_IDS = {
    0: "gemma-4-e2b",
    1: "gemma-4-e4b",
    2: "gemma-4-12b-qat",
    3: "gemma-4-26b-a4b",
}

# Hearth's own port block. Not the internal stack's, so a build that reaches a
# development machine finds nothing rather than finding the live house.
PORTS = {
    "HEARTH_PORT": 18700,
    "HEARTH_LLAMA_PORT": 18080,
    "HEARTH_RUST_WS_PORT": 18765,
    "HEARTH_RUST_ASSET_PORT": 18766,
    "HEARTH_TTS_PORT": 18702,
}


def find_record(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit).expanduser()
    home = Path(os.environ.get("HEARTH_HOME") or Path.home() / ".hearth").expanduser()
    models = Path(os.environ.get("HEARTH_MODELS") or home / "models").expanduser()
    for candidate in (models / "hearth-install.json", Path("hearth-install.json")):
        if candidate.is_file():
            return candidate
    raise SystemExit(
        f"no install record found. Looked in {models} and the working directory. "
        "Pass --record if it is elsewhere."
    )


def posix(value) -> str:
    """A path as the distro will see it.

    The renderer may run on Windows, beside the client that wrote the
    record, while everything it configures runs on the Linux side. Native
    path joining would emit backslashes into a file systemd reads.
    """
    return PurePosixPath(str(value).replace("\\", "/")).as_posix()


def render(record: dict, root, home) -> str:
    plan = record.get("plan") or {}
    machine = record.get("machine") or {}
    weights_dir = PurePosixPath(
        str(record.get("weights_dir") or f"{posix(home)}/models").replace("\\", "/")
    )

    model_file = plan.get("file")
    if not model_file:
        raise SystemExit("the install record has no plan.file; nothing to point the brain at")
    model_path = weights_dir / model_file

    tier = plan.get("tier")
    model_id = TIER_IDS.get(tier)
    if model_id is None:
        raise SystemExit(f"unknown model tier {tier!r} in the install record")

    gpu = machine.get("gpu") or {}
    lines: list[str] = [
        "# Written by scripts/render_config.py from hearth-install.json.",
        "# Edit the record and re-render rather than editing this file: an",
        "# upgrade reads the record, and a hand edit here is invisible to it.",
        "# Every field is documented in config/hearth.env.example.",
        "",
        "# Where things are",
        f"HEARTH_ROOT={posix(root)}",
        f"HEARTH_HOME={posix(home)}",
        f"HEARTH_MODELS={posix(weights_dir)}",
        f"HEARTH_ENGRAM={posix(home)}/engram",
        f"HEARTH_ENGRAM_MCP_PATH={posix(root)}/runtime/backend/vendor/engram-mcp",
        "",
        "# The model",
        f"HEARTH_DEEP_MODEL_OVERRIDE={posix(model_path)}",
        f"HEARTH_MODEL_ID={model_id}",
        f"HEARTH_LLAMA_CTX={plan.get('n_ctx', '')}",
        f"HEARTH_LLAMA_NGL={plan.get('n_gpu_layers', '')}",
        f"HEARTH_ACCEL={plan.get('backend') or gpu.get('backend') or 'cpu'}",
    ]
    cuda_arch = plan.get("cuda_arch")
    if cuda_arch:
        lines.append(f"HEARTH_CUDA_ARCH={cuda_arch}")
    lines += [
        f"HEARTH_COEXIST={1 if plan.get('coexist') else 0}",
        "",
        "# Behaviour. These three were systemd drop-ins on one machine and in no",
        "# repository, which is why a stranger's install was silent, tool-less",
        "# and unable to think.",
        f"HEARTH_TTS_SERVICE_URL=ws://127.0.0.1:{PORTS['HEARTH_TTS_PORT']}/tts",
        "HEARTH_TOOLS_ENABLED=1",
        "HEARTH_LLAMA_REASONING=auto",
        "",
        "# Ports",
    ]
    lines += [f"{name}={value}" for name, value in PORTS.items()]
    lines += [
        f"HEARTH_BRAIN_BASE_URL=http://127.0.0.1:{PORTS['HEARTH_LLAMA_PORT']}/v1",
        f"HEARTH_LLAMA_BASE_URL=http://127.0.0.1:{PORTS['HEARTH_LLAMA_PORT']}/v1",
        f"HEARTH_BRAIN_SWITCH_WS_URL=ws://127.0.0.1:{PORTS['HEARTH_RUST_WS_PORT']}",
        "",
        "# Voice and speech",
        "HEARTH_TTS_BACKEND=remote",
        "HEARTH_TTS_SERVICE=omnivoice",
        "HEARTH_WHISPER_MODEL=base",
    ]

    for warning in plan.get("warnings") or []:
        lines.append(f"# plan warning: {warning}")
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--record")
    ap.add_argument("--out")
    ap.add_argument("--root")
    ap.add_argument("--print", dest="to_stdout", action="store_true")
    args = ap.parse_args()

    record_path = find_record(args.record)
    try:
        record = json.loads(record_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise SystemExit(f"cannot read {record_path}: {exc}") from exc

    home = Path(os.environ.get("HEARTH_HOME") or Path.home() / ".hearth").expanduser()
    root = Path(
        args.root or os.environ.get("HEARTH_ROOT") or Path(__file__).resolve().parent.parent
    ).expanduser()

    body = render(record, root, home)
    if args.to_stdout:
        sys.stdout.write(body)
        return 0

    out = Path(args.out).expanduser() if args.out else home / "config" / "hearth.env"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(body, encoding="utf-8", newline="\n")
    print(f"wrote {out} from {record_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
