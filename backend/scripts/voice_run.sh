#!/usr/bin/env bash
# Launch the persistent Valar TTS service (NeuTTS-Air) in WSL.
#
# Holds NeuTTS resident on its own process so the Valar gateway (harness_run.sh) can
# restart without reloading the GPU TTS model. Internal only: binds 127.0.0.1:8701;
# the gateway connects over ws://127.0.0.1:8701/tts. Independent of the brain.
#
# Usage: voice_run.sh   (foreground; Ctrl-C to stop)
set -euo pipefail

# Venv is engine-dependent: NeuTTS runs in valar-venv; OmniVoice runs in the
# ISOLATED omnivoice-venv (its torch is newer than valar-venv's cu118 pin —
# never install omnivoice into valar-venv). Override with HEARTH_TTS_VENV.
if [ -z "${HEARTH_TTS_VENV:-}" ] && [ "${HEARTH_TTS_SERVICE:-}" = "omnivoice" ]; then
  HEARTH_TTS_VENV=/home/jones/omnivoice-venv
fi

# OmniVoice's PyTorch caching allocator over-reserves VRAM on the shared 4080:
# the warm-up diffusion high-water mark stays reserved-but-idle (~5.5GB process
# footprint for a ~2.2GB model). expandable_segments lets freed segments return
# to the driver, holding the process near its real footprint — the difference
# between fit and sysmem spillover on the single-GPU coexistence. Must be set
# before torch initializes CUDA, hence here rather than in Python.
if [ "${HEARTH_TTS_SERVICE:-}" = "omnivoice" ]; then
  export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}"
fi
VENV="${HEARTH_TTS_VENV:-/home/jones/valar-venv}"
REPO=/mnt/d/Tools/Valinor

if [ ! -x "$VENV/bin/python" ]; then
  echo "[valar-tts] venv missing at $VENV — run scripts/build_env.sh first" >&2
  exit 1
fi

export PYTHONPATH="$REPO:$REPO/neutts-air:${PYTHONPATH:-}"
export HEARTH_TTS_SERVICE="${HEARTH_TTS_SERVICE:-neutts_air}"
export HEARTH_TTS_PORT="${HEARTH_TTS_PORT:-8701}"
export HEARTH_TTS_SAMPLE_RATE="${HEARTH_TTS_SAMPLE_RATE:-48000}"
export HEARTH_DEFAULT_PERSONA="${HEARTH_DEFAULT_PERSONA:-Sulivan}"

# Single-GPU coexistence: pin the NeuTTS codec (~2GB fp32) to CPU so only the
# ~1GB GGUF backbone occupies VRAM (same as the gateway's local path used).
export HEARTH_NEUTTS_CODEC_DEVICE="${HEARTH_NEUTTS_CODEC_DEVICE:-cpu}"

# shellcheck disable=SC1091
source "$VENV/bin/activate"
cd "$REPO/Valar"

echo "[valar-tts] starting TTS service on 127.0.0.1:${HEARTH_TTS_PORT}"
exec python tts_app.py
