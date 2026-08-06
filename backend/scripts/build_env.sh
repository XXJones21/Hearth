#!/usr/bin/env bash
# Build the two Python environments the product runs on.
#
# This is a BUILD-TIME script. It runs on our builder, inside the image build,
# not on anyone's machine. That is what makes the constants below acceptable:
# the CUDA architecture and the host compiler pin are properties of the builder
# we chose, not guesses about a stranger's hardware. The runtime accelerator
# decision is a separate thing entirely and lives in hearth.env.
#
# Two environments, because the voice engine's torch is newer than the one the
# harness is pinned to and installing both in one tree resolves to neither:
#
#   $HEARTH_ROOT/venv         the harness: whisper, fastapi, the gateway
#   $HEARTH_ROOT/venv-voice   the voice service: OmniVoice and its torch
#
# Whether that split survives is an open question the image build has to settle
# with a real dependency resolve rather than an opinion.
#
# Idempotent: re-running rebuilds both in place.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEARTH_ROOT="${HEARTH_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
HEARTH_VENV="${HEARTH_VENV:-$HEARTH_ROOT/venv}"
HEARTH_VOICE_VENV="${HEARTH_VOICE_VENV:-$HEARTH_ROOT/venv-voice}"
PY="${HEARTH_PYTHON:-python3}"

# Keep pip's download cache and build temporary files off the distro's own
# virtual disk, which grows with anything written to it and never shrinks.
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-$HEARTH_ROOT/.pip-cache}"
export TMPDIR="${TMPDIR:-$HEARTH_ROOT/.tmp}"
mkdir -p "$PIP_CACHE_DIR" "$TMPDIR"

echo "==================================================================="
echo "Hearth environment build"
echo "  root       $HEARTH_ROOT"
echo "  harness    $HEARTH_VENV"
echo "  voice      $HEARTH_VOICE_VENV"
echo "  python     $($PY --version 2>&1)"
echo "==================================================================="

echo "--- [1/4] apt prerequisites ---"
# espeak-ng is deliberately absent: it belonged to the speech engine that was
# retired, and Hearth ships one voice.
REQ_PKGS="python3-venv python3-dev build-essential cmake git libsndfile1 ffmpeg curl"
MISSING=""
for p in $REQ_PKGS; do
  dpkg -s "$p" >/dev/null 2>&1 || MISSING="$MISSING$p "
done
if [ -n "$MISSING" ]; then
  echo "missing apt packages: $MISSING" >&2
  echo "install them in the image build stage, then re-run:" >&2
  echo "  apt-get install -y $MISSING" >&2
  exit 1
fi
echo "apt prerequisites present."

echo "--- [2/4] harness environment ---"
# Always from scratch. An interrupted run can leave a virtualenv whose pip
# exits zero and writes nothing, which is a build that reports success and
# produces a broken product.
rm -rf "$HEARTH_VENV"
"$PY" -m venv "$HEARTH_VENV"
# shellcheck disable=SC1091
source "$HEARTH_VENV/bin/activate"
python -m pip install --upgrade pip setuptools wheel
python -m pip install -r "$HEARTH_ROOT/harness/requirements.txt"
deactivate
echo "harness environment built."

echo "--- [3/4] voice environment ---"
rm -rf "$HEARTH_VOICE_VENV"
"$PY" -m venv "$HEARTH_VOICE_VENV"
# shellcheck disable=SC1091
source "$HEARTH_VOICE_VENV/bin/activate"
python -m pip install --upgrade pip setuptools wheel
python -m pip install torch torchaudio omnivoice soundfile numpy
deactivate
echo "voice environment built."

echo "--- [4/4] import verification ---"
"$HEARTH_VENV/bin/python" - <<'PYEOF'
import sys
print("harness python:", sys.version.split()[0])
import fastapi, uvicorn, httpx, websockets, yaml, whisper  # noqa: F401
print("harness imports ok (fastapi, uvicorn, httpx, websockets, pyyaml, whisper)")
PYEOF
"$HEARTH_VOICE_VENV/bin/python" - <<'PYEOF'
import sys
print("voice python:", sys.version.split()[0])
import torch, torchaudio  # noqa: F401
print("voice torch:", torch.__version__, "cuda:", torch.cuda.is_available())
PYEOF

echo "==================================================================="
echo "Hearth environment build complete."
echo "==================================================================="
