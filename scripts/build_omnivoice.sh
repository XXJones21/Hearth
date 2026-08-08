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
#           desktop-client/src-tauri/resources/omnivoice-tts
#
# TWO binaries, and the second one is the whole of voice design.
#
# tts-server streams cloned speech and is what the house talks to every turn.
# It cannot design a voice: its /v1/audio/speech validates `voice` against the
# names loaded at startup and 400s on anything else, so instruct attributes
# have no way in. That is a property of the SERVER, not the engine -- the
# library underneath has the whole voice-design path, vocabulary validation and
# all, which is why the shipped binary already contains strings like
# "instruct '%s' could not be resolved against the voice-design vocabulary".
#
# omnivoice-tts is the CLI that reaches it: `--instruct <str>`, resolved
# through pipeline_tts_resolve_instruct. Design runs exactly once per persona,
# at creation, and its output becomes the reference clip every later sentence
# clones from -- so a one-shot process is the right shape and the streaming
# server stays a streaming server.
#
# Found 2026-08-08, after a made persona spoke in Sulivan's voice because
# design 500'd on an engine that could do it all along.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
WORK="$REPO/.build/omnivoice"
OUT="$REPO/desktop-client/src-tauri/resources"

UPSTREAM="https://github.com/ServeurpersoCom/omnivoice.cpp.git"
# Pinned. Bump deliberately, re-run, and re-check the patches still apply.
PIN="4f33af825d66e6ef1cb185e87b4589cacf747291"

case "$(uname -s)" in
  Darwin) BACKEND_FLAG="-DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON"; EXE="" ;;
  MINGW*|MSYS*|CYGWIN*) BACKEND_FLAG="-DGGML_CUDA=ON"; EXE=".exe" ;;
  *) BACKEND_FLAG="-DGGML_VULKAN=ON"; EXE="" ;;
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
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
"$CMAKE" --build . --config Release -j "$JOBS" --target tts-server
"$CMAKE" --build . --config Release -j "$JOBS" --target omnivoice-tts

mkdir -p "$OUT"
for b in tts-server omnivoice-tts; do
  # cmake puts tools in build/ or build/bin/ depending on generator.
  src="$WORK/build/$b"; [ -f "$src" ] || src="$WORK/build/bin/$b"
  [ -f "$src" ] || { echo "missing build output: $b" >&2; exit 1; }
  cp "$src" "$OUT/$b$EXE"
  chmod +x "$OUT/$b$EXE"
  echo "built: $OUT/$b$EXE"
done
ls -la "$OUT"/tts-server$EXE "$OUT"/omnivoice-tts$EXE
