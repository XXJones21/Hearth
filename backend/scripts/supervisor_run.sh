#!/usr/bin/env bash
# Launch the Hearth supervisor, the model control plane.
#
# It owns which GGUF is resident, spawns and supervises llama-server on :8080,
# and serves the WebSocket control plane on :8765 plus persona assets on :8766.
# All three are internal; only the harness on :8700 faces the LAN.
#
# HEARTH_ROOT is derived from this script's own location. Everything that
# varies per machine arrives through $HEARTH_HOME/config/hearth.env, which the
# systemd unit reads before this runs.
#
# Usage: supervisor_run.sh          (foreground)
#        supervisor_run.sh --stop   (stop the supervisor and llama-server)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEARTH_ROOT="${HEARTH_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
HEARTH_HOME="${HEARTH_HOME:-$HOME/.hearth}"
export HEARTH_ROOT HEARTH_HOME

# The release binary, built once at image build time. There is no Rust
# toolchain in the shipped image; a checkout can point at its own build with
# HEARTH_SUPERVISOR_BIN, or fall back to target/release below.
SUPERVISOR_BIN="${HEARTH_SUPERVISOR_BIN:-$HEARTH_ROOT/bin/hearth-supervisor}"
if [ ! -x "$SUPERVISOR_BIN" ] && [ -x "$HEARTH_ROOT/supervisor/target/release/hearth-supervisor" ]; then
  SUPERVISOR_BIN="$HEARTH_ROOT/supervisor/target/release/hearth-supervisor"
fi

export HEARTH_DEEPAGENT_PERSONA="${HEARTH_DEEPAGENT_PERSONA:-Sulivan}"
export HEARTH_KV_CACHE_TYPE="${HEARTH_KV_CACHE_TYPE:-q4_0}"
export HEARTH_LLAMA_PARALLEL="${HEARTH_LLAMA_PARALLEL:-1}"
export HEARTH_LLAMA_HOST="${HEARTH_LLAMA_HOST:-127.0.0.1}"
export HEARTH_LLAMA_PORT="${HEARTH_LLAMA_PORT:-8080}"
export HEARTH_LLAMA_NO_WARMUP="${HEARTH_LLAMA_NO_WARMUP:-1}"
# GGML CUDA unified memory spills VRAM into system RAM. Opt-in: some WSL and
# NVIDIA build combinations stall or return 503 for a long time with it on.
export HEARTH_LLAMA_CUDA_UNIFIED_MEMORY="${HEARTH_LLAMA_CUDA_UNIFIED_MEMORY:-0}"
export HEARTH_LLAMA_HEALTH_TIMEOUT_S="${HEARTH_LLAMA_HEALTH_TIMEOUT_S:-600}"
# Per-request generation timeout. A long answer on a large model can take two
# to three minutes end to end including prompt prefill, so the 45 second code
# default aborts genuine work mid-stream.
export HEARTH_RUST_DIRECT_TIMEOUT_S="${HEARTH_RUST_DIRECT_TIMEOUT_S:-240}"
export HEARTH_RUST_DIRECT_MAX_TOKENS="${HEARTH_RUST_DIRECT_MAX_TOKENS:-2048}"
export HEARTH_RUST_GENERIC_MAX_TOKENS="${HEARTH_RUST_GENERIC_MAX_TOKENS:-4096}"
export HEARTH_LLAMA_BASE_URL="${HEARTH_LLAMA_BASE_URL:-http://127.0.0.1:8080/v1}"
export HEARTH_LLAMA_SERVER_BIN="${HEARTH_LLAMA_SERVER_BIN:-/usr/local/bin/llama-server}"
export HEARTH_RUST_PYTHON_BIN="${HEARTH_RUST_PYTHON_BIN:-python3}"

if [[ "${1:-}" == "--stop" ]]; then
  echo "[hearth] stopping the supervisor and llama-server"
  pkill -f "hearth-supervisor" 2>/dev/null || true
  pkill -f "${HEARTH_LLAMA_SERVER_BIN}" 2>/dev/null || true
  exit 0
fi

if [ ! -x "$SUPERVISOR_BIN" ]; then
  echo "[hearth] no supervisor binary at $SUPERVISOR_BIN" >&2
  echo "[hearth] build one with: cargo build --release --manifest-path $HEARTH_ROOT/supervisor/Cargo.toml" >&2
  exit 127
fi

if [[ "${1:-}" == "--dry-run" || "${HEARTH_RUST_DRY_RUN:-0}" == "1" ]]; then
  export HEARTH_RUST_DRY_RUN=1
  exec "$SUPERVISOR_BIN" --print-config
fi

if [[ "${1:-}" == "--probe-runtime" ]]; then
  exec "$SUPERVISOR_BIN" --probe-runtime
fi

# A llama-server that holds the port but does not answer /health is an orphan
# from a previous run. Clear it, or the supervisor fails on a port conflict
# instead of starting a fresh one.
LLAMA_PORT_CHECK="${HEARTH_LLAMA_PORT}"
if command -v ss >/dev/null 2>&1 && ss -tln 2>/dev/null | grep -q ":${LLAMA_PORT_CHECK} "; then
  if curl -s --max-time 5 "http://127.0.0.1:${LLAMA_PORT_CHECK}/health" >/dev/null 2>&1; then
    echo "[hearth] adopting the healthy llama-server already on :${LLAMA_PORT_CHECK}"
  else
    echo "[hearth] stale llama-server on :${LLAMA_PORT_CHECK} with no /health; clearing it"
    pkill -f "${HEARTH_LLAMA_SERVER_BIN}" 2>/dev/null || true
    sleep 2
    if ss -tln 2>/dev/null | grep -q ":${LLAMA_PORT_CHECK} "; then
      echo "[hearth] port ${LLAMA_PORT_CHECK} is still bound; clear it by hand" >&2
    fi
  fi
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  GPU_STATE="$(nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)"
  [[ -n "${GPU_STATE}" ]] && echo "[hearth] GPU before model load (used / free / total MiB): ${GPU_STATE}"
fi

echo "[hearth] supervisor from ${SUPERVISOR_BIN} (root ${HEARTH_ROOT})"
echo "[hearth] control plane ${HEARTH_RUST_WS_HOST:-0.0.0.0}:${HEARTH_RUST_WS_PORT:-8765}, assets ${HEARTH_RUST_ASSET_HOST:-0.0.0.0}:${HEARTH_RUST_ASSET_PORT:-8766}"
echo "[hearth] data plane ${HEARTH_LLAMA_BASE_URL}"
exec "$SUPERVISOR_BIN"
