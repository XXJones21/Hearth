#!/usr/bin/env bash
# Launch the Valar harness in WSL against the local Rust brain.
#
# - Uses the Linux-native venv at /home/jones/valar-venv (built by
#   valar_wsl_env_build.sh) — NOT a /mnt/d venv.
# - PYTHONPATH includes the Valinor repo root (so `import Server.*` resolves) and
#   neutts-air/ (NeuTTS local package; Server/model_manager.py also auto-adds it).
# - Points the BrainProvider at llama-server's streaming OpenAI endpoint on
#   127.0.0.1:8080 (the Rust WS gateway :8765 does not serve HTTP chat). The brain
#   stays internal to WSL; only Valar :8700 is exposed to the LAN (via portproxy).
#
# Usage: valar_run.sh        (foreground; Ctrl-C to stop)
set -euo pipefail

VENV=/home/jones/valar-venv
REPO=/mnt/d/Tools/Valinor

if [ ! -x "$VENV/bin/python" ]; then
  echo "[valar-run] venv missing at $VENV — run scripts/valar_wsl_env_build.sh first" >&2
  exit 1
fi

export PYTHONPATH="$REPO:$REPO/neutts-air:${PYTHONPATH:-}"
export VALAR_BRAIN_BASE_URL="${VALAR_BRAIN_BASE_URL:-http://127.0.0.1:8080/v1}"
export VALAR_HOST="${VALAR_HOST:-0.0.0.0}"
export VALAR_PORT="${VALAR_PORT:-8700}"

# Single pipeline: Valar owns persona->model routing. The "router" backend streams
# from the data plane (VALAR_BRAIN_BASE_URL = llama-server :8080/v1 native SSE) and
# makes the right model resident via switch_persona on the Rust supervisor WS
# (control plane). Default persona = the always-resident fast daily model
# (valinor-daily -> gemma-4-E4B). Heavy personas swap in on demand.
export VALAR_BRAIN_BACKEND="${VALAR_BRAIN_BACKEND:-router}"

# CHOAM wallet bridge (2026-07-30): the wallet backend runs on WINDOWS
# loopback :8091; from WSL that address is a different loopback. Reach it
# via the Windows host = the WSL default gateway (resolved live so NAT
# subnet drift on reboot never breaks the URL). Requires the host-side
# scripts/choam_wallet_bridge.ps1 portproxy+firewall (WSL-subnet-scoped).
if [ -z "${CHOAM_WALLET_URL:-}" ] || [ -z "${VALAR_COMFY_URL:-}" ]; then
  _WIN_HOST="$(ip route show default 2>/dev/null | awk '{print $3; exit}')"
  if [ -n "$_WIN_HOST" ]; then
    export CHOAM_WALLET_URL="${CHOAM_WALLET_URL:-http://${_WIN_HOST}:8091/wallet/query}"
    # ComfyUI bridge (2026-07-31): scripts/comfy_bridge.ps1 host-side.
    export VALAR_COMFY_URL="${VALAR_COMFY_URL:-http://${_WIN_HOST}:8188}"
  fi
fi
export VALAR_BRAIN_SWITCH_WS_URL="${VALAR_BRAIN_SWITCH_WS_URL:-ws://127.0.0.1:8765}"
export VALAR_DEFAULT_PERSONA="${VALAR_DEFAULT_PERSONA:-Sulivan}"

# Sampling tuned for the Gemma 4 brain (its recommended defaults). Override by
# exporting these before launch for a different model family.
export VALAR_BRAIN_TEMPERATURE="${VALAR_BRAIN_TEMPERATURE:-1.0}"
export VALAR_BRAIN_TOP_P="${VALAR_BRAIN_TOP_P:-0.95}"
export VALAR_BRAIN_TOP_K="${VALAR_BRAIN_TOP_K:-64}"

# Keep Valar's prompt budget within the brain's loaded ctx (16384) so we never
# send a prompt longer than llama-server can hold. Leaves room for generation.
export VALAR_CTX_MAX_TOKENS="${VALAR_CTX_MAX_TOKENS:-16384}"
export VALAR_CTX_HISTORY_TOKENS="${VALAR_CTX_HISTORY_TOKENS:-9000}"

# Auto session-end: persist + clear an idle session after this many seconds (the
# home-pod QoL window, 2026-06-05: ~5 minutes; the code default stays 120). The
# Echo pairs this with its local idle host (+45s) and clears its chat there.
export VALAR_SESSION_IDLE_S="${VALAR_SESSION_IDLE_S:-300}"

# Single-GPU coexistence with the resident brain: pin the NeuTTS codec (~2GB fp32)
# to CPU so only the ~1GB GGUF backbone occupies VRAM. Measured cost: ~none
# (RTF 0.46x vs 0.40x with codec on GPU). The backbone itself stays on the GPU
# (CUDA llama-cpp-python) — that is the part that must be fast.
export VALAR_NEUTTS_CODEC_DEVICE="${VALAR_NEUTTS_CODEC_DEVICE:-cpu}"

# TTS backend. "remote" (default) talks to the persistent valar-tts service
# (127.0.0.1:8701) so a gateway restart costs NO GPU TTS reload — the decoupled
# end state. "local" loads NeuTTS in the gateway process (fallback; reloads the
# model on every gateway restart). The service "hang" was a concurrent-load race
# (warm-up vs first request both constructing NeuTTSAir -> meta-tensor failure),
# fixed by the sync lock in valar/voice/tts.py (2026-06-03).
export VALAR_TTS_BACKEND="${VALAR_TTS_BACKEND:-remote}"

# shellcheck disable=SC1091
source "$VENV/bin/activate"
cd "$REPO/Valar"

echo "[valar-run] starting Valar on ${VALAR_HOST}:${VALAR_PORT} -> brain ${VALAR_BRAIN_BASE_URL}"
exec python app.py
