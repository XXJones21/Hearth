#!/usr/bin/env bash
# Valar WSL CUDA Python environment — one-pass build.
# Mirrors the known-good Windows reference env (D:\Tools\Valinor\.venv, Python 3.13.1)
# onto WSL Ubuntu-24.04 / Python 3.12.
#
# Run via PowerShell (NOT the MSYS2 Bash tool):
#   wsl -d Ubuntu-24.04 bash /mnt/d/Tools/Valinor/scripts/build_env.sh
#
# Idempotent: re-running upgrades/repairs the venv in place.
set -euo pipefail

VENV="/home/jones/valar-venv"          # Linux-native path (NOT /mnt/d — avoids slow mount I/O)
REPO="/mnt/d/Tools/Valinor"
CU_INDEX="https://download.pytorch.org/whl/cu118"
PY="python3"

# llama-cpp-python CUDA source-build settings. We DO NOT use a prebuilt wheel index:
# the old abetlen cu118 index (https://abetlen.github.io/llama-cpp-python/whl/cu118)
# returns HTTP 404, so `pip --extra-index-url <404>` silently resolves the CPU-only
# PyPI wheel and "succeeds" — which is exactly how this env ended up with a backbone
# stuck on CPU (llama_supports_gpu_offload()==False, NeuTTS synthesis at RTF ~4.4x).
# We always build from source with CUDA on. nvcc here is CUDA 12.0, which rejects
# gcc>12, so we pin the CUDA host compiler to g++-12. The RTX 4080 is Ada -> sm_89.
LLAMA_CUDA_HOST_CXX="/usr/bin/g++-12"
LLAMA_CUDA_ARCH="89"

# Keep pip's download cache + build temp OFF the cramped C: WSL-vdisk. The vdisk is
# a sparse vhdx on C: (only ~37GB physical free); writing multi-GB wheels/temp there
# can wedge the whole VM. D: has ~1TB. Only the final ~8GB venv lands on C:.
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-$REPO/.pip-cache}"
export TMPDIR="${TMPDIR:-$REPO/.tmp}"
mkdir -p "$PIP_CACHE_DIR" "$TMPDIR"

echo "==================================================================="
echo "Valar WSL env build — venv=$VENV  python=$($PY --version 2>&1)"
echo "==================================================================="

# --- 1. System build prerequisites ----------------------------------------
# Non-interactive safe: only sudo if something is actually missing (sudo needs a
# TTY, which a background run does not have). All these are normally pre-installed.
echo "--- [1/6] apt prerequisites ---"
REQ_PKGS="python3-venv python3-dev build-essential cmake git libsndfile1 ffmpeg espeak-ng"
MISSING=""
for p in $REQ_PKGS; do
  dpkg -s "$p" >/dev/null 2>&1 || MISSING="$MISSING$p "
done
if [ -n "$MISSING" ]; then
  echo "Missing apt packages: $MISSING"
  echo "Run once (needs sudo), then re-run this script:"
  echo "  sudo apt-get install -y $MISSING"
  exit 1
fi
echo "apt prerequisites already present (espeak-ng/libsndfile1/ffmpeg/build tools) — skipping sudo."

# --- 2. venv ---------------------------------------------------------------
# Always recreate fresh. A prior interrupted/wedged run can leave a corrupt ~1MB venv
# whose pip exits 0 but silently no-ops (install reports success, writes nothing) —
# and that masquerades as a successful build. venv creation is cheap (~16MB, seconds)
# and wheels are cached on D:, so a clean slate each run is the robust choice.
echo "--- [2/6] create fresh venv ---"
rm -rf "$VENV"
"$PY" -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
# Pin setuptools<81: perth_net (NeuTTS watermarker dep) imports pkg_resources, which
# setuptools removed in >=81. Newer setuptools silently breaks NeuTTS at load time.
python -m pip install --upgrade pip "setuptools<81" wheel
# Prove pip actually works (a real op, not just --version which a broken pip can fake).
python -m pip install --dry-run --no-deps pip >/dev/null 2>&1 || { echo "FATAL: venv pip nonfunctional" >&2; exit 1; }
echo "venv ready: $(python --version)  pip $(python -m pip --version | awk '{print $2}')"

# --- 3. torch CUDA stack (cu118, mirrors reference) -----------------------
echo "--- [3/6] torch/torchaudio/torchvision cu118 ---"
pip install -q \
  --index-url "$CU_INDEX" \
  torch==2.7.1+cu118 torchaudio==2.7.1+cu118 torchvision==0.22.1+cu118
echo "torch stack installed."

# --- 4. llama-cpp-python CUDA build (backbone for neutts-air-q4-gguf) ------
# ALWAYS source-build with CUDA. A CPU-only llama_cpp loads fine but runs the NeuTTS
# autoregressive backbone on CPU (RTF ~4.4x, unusable for real-time). We force the
# GPU build and then HARD-VERIFY llama_supports_gpu_offload()==True so a silent CPU
# fallthrough can never masquerade as success again.
echo "--- [4/6] llama-cpp-python 0.3.9 (CUDA source build) ---"
if ! python -c "import llama_cpp, sys; from llama_cpp import llama_cpp as L; sys.exit(0 if L.llama_supports_gpu_offload() else 1)" 2>/dev/null; then
  echo "  building llama-cpp-python==0.3.9 from source with -DGGML_CUDA=on (host cxx $LLAMA_CUDA_HOST_CXX, arch sm_$LLAMA_CUDA_ARCH)"
  CMAKE_ARGS="-DGGML_CUDA=on -DCMAKE_CUDA_HOST_COMPILER=$LLAMA_CUDA_HOST_CXX -DCMAKE_CUDA_ARCHITECTURES=$LLAMA_CUDA_ARCH" \
    pip install --no-cache-dir --force-reinstall --no-binary llama-cpp-python llama-cpp-python==0.3.9
else
  echo "  llama-cpp-python already CUDA-capable (gpu_offload=True) — skipping rebuild."
fi
# Hard gate: refuse to proceed on a CPU-only build.
python -c "from llama_cpp import llama_cpp as L; assert L.llama_supports_gpu_offload(), 'FATAL: llama-cpp-python has no GPU offload (CPU-only build)'" \
  && echo "llama-cpp-python CUDA build verified (gpu_offload=True)."

# --- 5. NeuTTS-Air closure + whisper + audio + gateway --------------------
echo "--- [5/6] neutts/whisper/audio/gateway deps ---"
# NeuTTS-Air local package deps (neutts-air/requirements.txt closure) + STT + gateway.
pip install -q \
  "numpy==2.2.6" \
  "transformers==4.52.3" \
  "neucodec==0.0.4" \
  "resemble-perth==1.0.1" \
  "phonemizer==3.3.0" \
  "soundfile==0.13.1" \
  "librosa==0.11.0" \
  "openai-whisper==20250625" \
  "fastapi==0.136.3" \
  "uvicorn[standard]==0.48.0" \
  "httpx==0.28.1" \
  "websockets==15.0.1"
echo "neutts/whisper/audio/gateway deps installed."

# --- 6. Import verification ------------------------------------------------
echo "--- [6/6] import verification ---"
export PYTHONPATH="$REPO:$REPO/neutts-air:${PYTHONPATH:-}"
python - <<'PYEOF'
import sys
print("python:", sys.version.split()[0])

import torch
print("torch:", torch.__version__, "cuda_available:", torch.cuda.is_available(),
      "cuda_ver:", torch.version.cuda)
assert torch.cuda.is_available(), "FATAL: torch.cuda.is_available() is False"

import llama_cpp
from llama_cpp import llama_cpp as _L
print("llama_cpp:", llama_cpp.__version__, "gpu_offload:", _L.llama_supports_gpu_offload())

import whisper
m = whisper.load_model("base")
print("whisper: base model loaded ok")

import neucodec, soundfile, librosa, numpy, transformers
print("neucodec:", neucodec.__version__ if hasattr(neucodec,'__version__') else 'ok',
      "| soundfile/librosa/numpy/transformers import ok")

# NeuTTS-Air local package (added to path above)
import importlib
neuttsair = importlib.import_module("neuttsair.neutts")
print("neuttsair.neutts import ok")

print("ALL IMPORTS OK")
PYEOF
echo "==================================================================="
echo "Valar WSL env build COMPLETE."
echo "==================================================================="
