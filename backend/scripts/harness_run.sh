#!/usr/bin/env bash
# Launch the Hearth harness, the single client entry point (:8700).
#
# Where things are is derived, never declared. HEARTH_ROOT is this script's
# parent directory, which is /opt/hearth in the shipped image and the checkout's
# backend/ in a working tree. Set HEARTH_ROOT to override for a third location.
#
# What varies per machine (the model, the context, the accelerator, the voice
# endpoint) is NOT here. It arrives through $HEARTH_HOME/config/hearth.env,
# written at install time from the probe's plan and read by the systemd unit.
# See config/hearth.env.example.
#
# Usage: harness_run.sh        (foreground; Ctrl-C to stop)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEARTH_ROOT="${HEARTH_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
HEARTH_HOME="${HEARTH_HOME:-$HOME/.hearth}"
HEARTH_VENV="${HEARTH_VENV:-$HEARTH_ROOT/venv}"
export HEARTH_ROOT HEARTH_HOME

if [ ! -x "$HEARTH_VENV/bin/python" ]; then
  echo "[hearth] no python environment at $HEARTH_VENV; run scripts/build_env.sh" >&2
  exit 1
fi

# The harness package lives at $HEARTH_ROOT/harness, the memory modules at
# $HEARTH_ROOT/memory, so both roots go on the path.
export PYTHONPATH="$HEARTH_ROOT:$HEARTH_ROOT/harness:${PYTHONPATH:-}"

export HEARTH_BRAIN_BASE_URL="${HEARTH_BRAIN_BASE_URL:-http://127.0.0.1:8080/v1}"
export HEARTH_HOST="${HEARTH_HOST:-0.0.0.0}"
export HEARTH_PORT="${HEARTH_PORT:-8700}"

# Single pipeline: the harness owns persona-to-model routing. The "router"
# backend streams from the data plane (HEARTH_BRAIN_BASE_URL = llama-server
# :8080/v1 native SSE) and makes the right model resident via switch_persona on
# the supervisor's WebSocket (control plane). The code default is "rust", which
# is the wrong plane, so it is set here rather than left to fall through.
export HEARTH_BRAIN_BACKEND="${HEARTH_BRAIN_BACKEND:-router}"
export HEARTH_BRAIN_SWITCH_WS_URL="${HEARTH_BRAIN_SWITCH_WS_URL:-ws://127.0.0.1:8765}"
export HEARTH_DEFAULT_PERSONA="${HEARTH_DEFAULT_PERSONA:-Sulivan}"

# Auto session-end: persist and clear an idle session after this many seconds.
# Five minutes is the home-pod window; the code default of 120 is too eager for
# a device someone talks to across a room.
export HEARTH_SESSION_IDLE_S="${HEARTH_SESSION_IDLE_S:-300}"

# Talk to the persistent voice service rather than loading a speech model in
# this process, so a harness restart costs no GPU reload. The code default is
# "local", which is the fallback, not the shipped arrangement.
export HEARTH_TTS_BACKEND="${HEARTH_TTS_BACKEND:-remote}"

# shellcheck disable=SC1091
source "$HEARTH_VENV/bin/activate"
cd "$HEARTH_ROOT/harness"

echo "[hearth] harness on ${HEARTH_HOST}:${HEARTH_PORT} -> brain ${HEARTH_BRAIN_BASE_URL} (root ${HEARTH_ROOT})"
exec python app.py
