#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export VALINOR_RUST_REPO_ROOT="${VALINOR_RUST_REPO_ROOT:-/mnt/d/Tools/Valinor}"
export VALINOR_STACK_SERVER="${VALINOR_STACK_SERVER:-rust}"
export VALINOR_DEEPAGENT_PERSONA="${VALINOR_DEEPAGENT_PERSONA:-valinor-orchestrate}"
export VALINOR_MENTAT_MODE="${VALINOR_MENTAT_MODE:-agent}"
export VALINOR_MENTAT_HARNESS="${VALINOR_MENTAT_HARNESS:-hermes}"
export VALINOR_MENTAT_WORKSPACE_ROOT="${VALINOR_MENTAT_WORKSPACE_ROOT:-/mnt/d/Tools/mentat-workspace}"
export VALINOR_MENTAT_PROJECT_SLUG="${VALINOR_MENTAT_PROJECT_SLUG:-valinor-webapp}"
export VALINOR_KV_CACHE_TYPE="${VALINOR_KV_CACHE_TYPE:-q4_0}"
export VALINOR_LLAMA_PARALLEL="${VALINOR_LLAMA_PARALLEL:-1}"
export VALINOR_LLAMA_HOST="${VALINOR_LLAMA_HOST:-127.0.0.1}"
export VALINOR_LLAMA_PORT="${VALINOR_LLAMA_PORT:-8080}"
export VALINOR_LLAMA_NO_WARMUP="${VALINOR_LLAMA_NO_WARMUP:-1}"
# llama.cpp GGML CUDA: set to 1 to pass GGML_CUDA_ENABLE_UNIFIED_MEMORY=1 to llama-server (VRAM spill to system RAM). Default 0: opt-in, some WSL/NVIDIA builds stall or 503 for a long time with UM; enable only when you need it and have verified stability.
export VALINOR_LLAMA_CUDA_UNIFIED_MEMORY="${VALINOR_LLAMA_CUDA_UNIFIED_MEMORY:-0}"
export VALINOR_LLAMA_HEALTH_TIMEOUT_S="${VALINOR_LLAMA_HEALTH_TIMEOUT_S:-600}"
# Per-request chat-completion timeout. Default in config.rs is 45s, sized for
# snappy Telegram replies. Long-form briefings on the 35B (F1 AI Team
# Principal, deep-think escalations) can take 60-180s end-to-end including
# prompt prefill. Bump to 240s so genuine generation isn't aborted mid-stream.
export VALINOR_RUST_DIRECT_TIMEOUT_S="${VALINOR_RUST_DIRECT_TIMEOUT_S:-240}"
# Per-request output token cap on the direct-model path (text_query). Default
# in ws.rs:direct_max_tokens_cap is 256 — way too short for long-form
# briefings. F1 AI Team Principal needs ~1,400 tokens to produce all four
# sections (Season Read, Driver Breakdown, Next Race Priorities, Watch Items).
# 2048 matches the f1-principal persona's max_tokens and is generous for
# Telegram /deep escalations too.
export VALINOR_RUST_DIRECT_MAX_TOKENS="${VALINOR_RUST_DIRECT_MAX_TOKENS:-2048}"
# Per-request output token cap on the GENERIC/gateway chat path (Hermes gateway
# -> Rust /v1/chat/completions, clamped in ws.rs via generic_llm_max_output_tokens;
# config.rs default is 512). CHOAM/Liara needs full ORDER JSON (incl. risk_check)
# and multi-stage Fennec-loop output, which truncate badly at 512. This is a
# ceiling, not a target: voice callers (Sulivan/Selene) send their own small
# max_tokens and are unaffected; only callers that explicitly request more get more.
export VALINOR_RUST_GENERIC_MAX_TOKENS="${VALINOR_RUST_GENERIC_MAX_TOKENS:-4096}"
export VALINOR_LLAMA_BASE_URL="${VALINOR_LLAMA_BASE_URL:-http://127.0.0.1:8080/v1}"
export VALINOR_LLAMA_SERVER_BIN="${VALINOR_LLAMA_SERVER_BIN:-/usr/local/bin/llama-server}"
# NO heavy-model auto-override. The boot persona's deep_model.path drives the
# resident model (single pipeline: personas point at ext4 copies directly), and
# Valar's router swaps heavy models in/out on demand. The removed band-aid here
# auto-pinned the 27B/35B from ~/models/valinor when VALINOR_DEEP_MODEL_OVERRIDE
# was unset, which kept resurrecting the VRAM crash-loop after reboots. An
# explicit `export VALINOR_DEEP_MODEL_OVERRIDE=<path>` before launch still works
# (rust/valinor-server/src/llama.rs honors it) for one-off experiments.
# Speculative decoding: only auto-enable when the GPU has enough VRAM headroom.
# Qwen3.6-27B Q3_K_M fills a 16 GB RTX 4080 entirely; the 1.7B draft model needs
# ~1.2 GB that does not exist after loading the main model at 65536 context.
# On 24+ GB cards (e.g. RTX 4090 with Q4_K_M) spec-dec works at 154 tok/s (85% acceptance).
# To force spec-dec regardless: export VALINOR_SPEC_DRAFT_MODEL=<path> before running.
# To force spec-dec off:        export VALINOR_SPEC_DRAFT_MODEL=""
_SPEC_DEC_MIN_VRAM_MIB=20000
_GPU_TOTAL_MIB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
if [[ -z "${VALINOR_SPEC_DRAFT_MODEL:-}" ]]; then
  if [[ -n "$_GPU_TOTAL_MIB" && "$_GPU_TOTAL_MIB" -ge "$_SPEC_DEC_MIN_VRAM_MIB" ]]; then
    if [[ -f "$HOME/models/valinor/Qwen3-1.7B-Q4_K_M.gguf" ]]; then
      export VALINOR_SPEC_DRAFT_MODEL="$HOME/models/valinor/Qwen3-1.7B-Q4_K_M.gguf"
    elif [[ -f "/mnt/d/Tools/Valinor/models/Qwen3-1.7B-Q4_K_M.gguf" ]]; then
      export VALINOR_SPEC_DRAFT_MODEL="/mnt/d/Tools/Valinor/models/Qwen3-1.7B-Q4_K_M.gguf"
    fi
  fi
fi
unset _SPEC_DEC_MIN_VRAM_MIB _GPU_TOTAL_MIB
export VALINOR_RUST_PYTHON_BIN="${VALINOR_RUST_PYTHON_BIN:-python3}"

export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

VALINOR_WEBAPP_DIR="${VALINOR_MENTAT_WORKSPACE_ROOT}/${VALINOR_MENTAT_PROJECT_SLUG}"
MENTAT_JSON="${VALINOR_RUST_REPO_ROOT}/Persona/Mentat/mentat.json"

VALINOR_WSL_CLIENT_HOST="${VALINOR_WSL_CLIENT_HOST:-$(hostname -I | awk '{print $1}')}"
VALINOR_CLIENT_WS_URL="${VALINOR_CLIENT_WS_URL:-ws://${VALINOR_WSL_CLIENT_HOST}:${VALINOR_RUST_WS_PORT:-8765}}"
VALINOR_CLIENT_HTTP_ORIGIN="${VALINOR_CLIENT_HTTP_ORIGIN:-http://${VALINOR_WSL_CLIENT_HOST}:${VALINOR_RUST_ASSET_PORT:-8766}}"

if [[ "${1:-}" == "--stop" ]]; then
  echo "[VALINOR-RUST] Stopping Rust backend and llama-server"
  pkill -f "rust/valinor-server/target/debug/valinor-server" 2>/dev/null || true
  pkill -f "/usr/local/bin/llama-server" 2>/dev/null || true
  exit 0
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "[VALINOR-RUST] Missing cargo in WSL. Install the Rust toolchain in Ubuntu-24.04 before launching this profile." >&2
  exit 127
fi

if [[ "${1:-}" == "--dry-run" || "${VALINOR_RUST_DRY_RUN:-0}" == "1" ]]; then
  export VALINOR_RUST_DRY_RUN=1
  cargo run --manifest-path "$VALINOR_RUST_REPO_ROOT/rust/valinor-server/Cargo.toml" -- --print-config
  exit $?
fi

if [[ "${1:-}" == "--probe-runtime" ]]; then
  cargo run --manifest-path "$VALINOR_RUST_REPO_ROOT/rust/valinor-server/Cargo.toml" -- --probe-runtime
  exit $?
fi

# Pre-flight: detect and clean up stale llama-server. If port is bound but /health does not respond,
# kill the orphan so the supervisor can start a fresh one instead of erroring on port conflict.
LLAMA_PORT_CHECK="${VALINOR_LLAMA_PORT:-8080}"
if command -v ss >/dev/null 2>&1 && ss -tlnp 2>/dev/null | grep -q ":${LLAMA_PORT_CHECK} "; then
  if curl -s --max-time 5 "http://127.0.0.1:${LLAMA_PORT_CHECK}/health" >/dev/null 2>&1; then
    echo "[VALINOR-RUST] Found healthy existing llama-server on :${LLAMA_PORT_CHECK} (Rust will adopt it)."
  else
    echo "[VALINOR-RUST] Stale llama-server detected on :${LLAMA_PORT_CHECK} (no /health response). Killing before restart."
    pkill -f "/usr/local/bin/llama-server" 2>/dev/null || true
    sleep 2
    if ss -tlnp 2>/dev/null | grep -q ":${LLAMA_PORT_CHECK} "; then
      echo "[VALINOR-RUST] WARNING: port ${LLAMA_PORT_CHECK} still bound after pkill. Manual cleanup may be required." >&2
    fi
  fi
fi

# Pre-flight: GPU state snapshot for diagnostics on slow loads.
if command -v nvidia-smi >/dev/null 2>&1; then
  GPU_STATE="$(nvidia-smi --query-gpu=memory.used,memory.free,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)"
  if [[ -n "${GPU_STATE}" ]]; then
    echo "[VALINOR-RUST] GPU memory before model load (used / free / total MiB): ${GPU_STATE}"
  fi
fi

echo "[VALINOR-RUST] Starting full Rust backend stack"
echo "[VALINOR-RUST] Valinor repo (Rust + llama harness profile): ${VALINOR_RUST_REPO_ROOT}"
echo "[VALINOR-RUST] llama model profile file: ${MENTAT_JSON}"
if [[ ! -f "${MENTAT_JSON}" ]]; then
  echo "[VALINOR-RUST] WARNING: mentat.json missing; llama-server args come from Persona/Mentat/mentat.json in the Valinor repo." >&2
fi
echo "[VALINOR-RUST] Rust WebSocket: ${VALINOR_RUST_WS_HOST:-0.0.0.0}:${VALINOR_RUST_WS_PORT:-8765}"
echo "[VALINOR-RUST] Rust assets: ${VALINOR_RUST_ASSET_HOST:-0.0.0.0}:${VALINOR_RUST_ASSET_PORT:-8766}"
if [[ -d "$VALINOR_WEBAPP_DIR" ]]; then
  ENV_FILE="$VALINOR_WEBAPP_DIR/.env.local"
  TMP_ENV_FILE="$(mktemp)"
  if [[ -f "$ENV_FILE" ]]; then
    grep -v -E '^(VITE_VALINOR_WS|VITE_VALINOR_HTTP_ORIGIN)=' "$ENV_FILE" > "$TMP_ENV_FILE" || true
  fi
  {
    cat "$TMP_ENV_FILE"
    echo "VITE_VALINOR_WS=${VALINOR_CLIENT_WS_URL}"
    echo "VITE_VALINOR_HTTP_ORIGIN=${VALINOR_CLIENT_HTTP_ORIGIN}"
  } > "$ENV_FILE"
  rm -f "$TMP_ENV_FILE"
  echo "[VALINOR-RUST] Vite dev env: ${ENV_FILE}"
fi
echo "[VALINOR-RUST] Vite WebSocket: ${VALINOR_CLIENT_WS_URL}"
echo "[VALINOR-RUST] Vite assets: ${VALINOR_CLIENT_HTTP_ORIGIN}"
echo "[VALINOR-RUST] llama-server: ${VALINOR_LLAMA_BASE_URL} (CUDA unified memory: ${VALINOR_LLAMA_CUDA_UNIFIED_MEMORY})"
if [[ -n "${VALINOR_SPEC_DRAFT_MODEL:-}" ]]; then
  echo "[VALINOR-RUST] spec-dec draft model: ${VALINOR_SPEC_DRAFT_MODEL}"
else
  echo "[VALINOR-RUST] spec-dec draft model: not configured (set VALINOR_SPEC_DRAFT_MODEL or copy model to ~/models/valinor/)"
fi
echo "[VALINOR-RUST] Rust will supervise llama-server for this profile."

cargo run --manifest-path "$VALINOR_RUST_REPO_ROOT/rust/valinor-server/Cargo.toml"
