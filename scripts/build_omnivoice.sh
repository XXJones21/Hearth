#!/usr/bin/env bash
# Build the voice engine, from a pinned upstream plus our patches.
#
# omnivoice.cpp is the C++/GGML implementation of OmniVoice. It replaces the
# torch voice on every platform, and on macOS it is the only one that works at
# all: the torch path selects "cuda:0 if available else cpu", so on Apple
# Silicon it lands on the CPU and synthesises at about 7.6x realtime. This one
# has a Metal backend and clears realtime.
#
# The build machine produces the binary and `pack_backend.sh` ships it, exactly
# as it already does for hearth-supervisor. Nothing is cloned or compiled on a
# user's machine, and there is no standalone install for anyone to satisfy.
#
# Our patches live in vendor/omnivoice/patches and are applied to a pinned
# commit, so this is reproducible and the delta from upstream stays legible.
# The named-voice patch is worth upstreaming; until it lands, it lives here.
#
#   Usage: bash scripts/build_omnivoice.sh [--clean]
#   Output: desktop-client/src-tauri/resources/tts-server
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
WORK="$REPO/.build/omnivoice"
OUT="$REPO/desktop-client/src-tauri/resources"

UPSTREAM="https://github.com/ServeurpersoCom/omnivoice.cpp.git"
# Pinned. Bump deliberately, re-run, and re-check the patches still apply.
PIN="4f33af825d66e6ef1cb185e87b4589cacf747291"

case "$(uname -s)" in
  Darwin) BACKEND_FLAG="-DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON"; BIN_NAME="tts-server" ;;
  MINGW*|MSYS*|CYGWIN*) BACKEND_FLAG="-DGGML_CUDA=ON"; BIN_NAME="tts-server.exe" ;;
  *) BACKEND_FLAG="-DGGML_VULKAN=ON"; BIN_NAME="tts-server" ;;
esac

# One file, not six. A default ggml build emits libggml{,-base,-cpu,-blas,
# -metal}.dylib and links them by @rpath, which inside a relocatable .app means
# shipping five more files and rewriting install names. Static linking, plus
# embedding the Metal shader library into the binary rather than loading a
# .metallib beside it, makes the thing the provisioner unpacks self-contained.
STATIC_FLAGS="-DBUILD_SHARED_LIBS=OFF"

# macOS ships no cmake and the upstream build scripts assume nproc, which does
# not exist here. Both are why there is no buildmetal.sh to call instead.
CMAKE="$(command -v cmake || echo /opt/homebrew/bin/cmake)"
[ -x "$CMAKE" ] || { echo "cmake not found. brew install cmake" >&2; exit 1; }

if [ "${1:-}" = "--clean" ]; then rm -rf "$WORK"; fi

if [ ! -d "$WORK/.git" ]; then
  mkdir -p "$(dirname "$WORK")"
  git clone --recurse-submodules "$UPSTREAM" "$WORK"
fi

cd "$WORK"
git fetch --all --tags --quiet || true
# Discard any previous patch application before re-applying, so a re-run is
# idempotent rather than a second copy of the same hunks.
git checkout --quiet --force "$PIN"
git submodule update --init --recursive --quiet
git clean -fdq -e build

for p in "$REPO"/vendor/omnivoice/patches/*.patch; do
  [ -e "$p" ] || continue
  echo "applying $(basename "$p")"
  git apply --check "$p" || { echo "patch does not apply to $PIN: $p" >&2; exit 1; }
  git apply "$p"
done

mkdir -p build && cd build
"$CMAKE" .. $BACKEND_FLAG $STATIC_FLAGS -DCMAKE_BUILD_TYPE=Release
"$CMAKE" --build . --config Release -j "$(sysctl -n hw.ncpu 2>/dev/null || nproc)" --target tts-server

mkdir -p "$OUT"
cp "$WORK/build/tts-server" "$OUT/$BIN_NAME"
echo "built: $OUT/$BIN_NAME"
ls -la "$OUT/$BIN_NAME"
