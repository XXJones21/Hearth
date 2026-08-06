#!/usr/bin/env bash
# Launch the persistent Hearth voice service (OmniVoice) on 127.0.0.1:8702.
#
# It holds the speech model resident in its own process so the harness can
# restart without reloading it. Internal only; the harness dials
# ws://127.0.0.1:8702/tts. Independent of the brain.
#
# Its virtualenv is separate from the harness's because its torch is newer than
# the one the rest of the stack is pinned to. That is a real constraint rather
# than tidiness, and it is why HEARTH_VOICE_VENV exists at all.
#
# Usage: voice_run.sh   (foreground; Ctrl-C to stop)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEARTH_ROOT="${HEARTH_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
HEARTH_HOME="${HEARTH_HOME:-$HOME/.hearth}"
HEARTH_VOICE_VENV="${HEARTH_VOICE_VENV:-$HEARTH_ROOT/venv-voice}"
export HEARTH_ROOT HEARTH_HOME

if [ ! -x "$HEARTH_VOICE_VENV/bin/python" ]; then
  echo "[hearth-voice] no python environment at $HEARTH_VOICE_VENV; run scripts/build_env.sh" >&2
  exit 1
fi

# OmniVoice's caching allocator over-reserves: the warm-up diffusion high-water
# mark stays reserved but idle, roughly 5.5 GB of process footprint for a 2.2 GB
# model. expandable_segments returns freed segments to the driver, which is the
# difference between fitting alongside the brain and spilling to system memory.
# It must be set before torch initialises CUDA, hence here rather than in Python.
export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}"

export PYTHONPATH="$HEARTH_ROOT:$HEARTH_ROOT/harness:${PYTHONPATH:-}"
export HEARTH_TTS_SERVICE="${HEARTH_TTS_SERVICE:-omnivoice}"
export HEARTH_TTS_PORT="${HEARTH_TTS_PORT:-8702}"
export HEARTH_TTS_SAMPLE_RATE="${HEARTH_TTS_SAMPLE_RATE:-48000}"
export HEARTH_DEFAULT_PERSONA="${HEARTH_DEFAULT_PERSONA:-Sulivan}"

# shellcheck disable=SC1091
source "$HEARTH_VOICE_VENV/bin/activate"
cd "$HEARTH_ROOT/harness"

echo "[hearth-voice] voice service on 127.0.0.1:${HEARTH_TTS_PORT} (root ${HEARTH_ROOT})"
exec python tts_app.py
