#!/usr/bin/env bash
# Pack the backend for the client bundle. Run before `tauri build`; the
# provisioner unpacks these into <root>/runtime on the user's machine.
#
#   resources/backend.tar.gz        harness, memory, personas, scripts,
#                                   config, manifest, and the model
#                                   dictionary at its root (the supervisor's
#                                   resolver looks there first)
#   resources/hearth-supervisor.exe the release binary
#
# What deliberately stays out: supervisor source (the binary ships), the dev
# venv and fetched binaries (.venv-win, .native), caches, session state, and
# the systemd units (testbed-only since the native decision).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
OUT="$REPO/desktop-client/src-tauri/resources"
# Per platform: the supervisor built on this machine is the one that ships
# from it. Windows bundles the .exe, macOS the bare binary.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) SUP_NAME="hearth-supervisor.exe"; TTS_NAME="tts-server.exe" ;;
  *) SUP_NAME="hearth-supervisor"; TTS_NAME="tts-server" ;;
esac
SUP="$REPO/backend/supervisor/target/release/$SUP_NAME"

[ -f "$SUP" ] || { echo "build the supervisor first: cargo build --release in backend/supervisor" >&2; exit 1; }

# A binary older than its sources is last week's supervisor wearing today's
# bundle. This exact staleness shipped an installer whose supervisor did not
# know HEARTH_DEEP_MODEL_FILE, and every install that planned a non-12B tier
# died at boot (2026-08-08). Copy-shipped artifacts get a freshness gate.
NEWEST_SRC="$(find "$REPO/backend/supervisor/src" -name '*.rs' -newer "$SUP" -print -quit)"
if [ -n "$NEWEST_SRC" ]; then
  echo "supervisor binary is OLDER than $NEWEST_SRC" >&2
  echo "rebuild it first: cargo build --release in backend/supervisor" >&2
  exit 1
fi

# The voice engine, built by scripts/build_omnivoice.sh into this same
# resources directory, so it is already in place and only needs checking.
# Absent is a warning rather than an error: house.rs treats the voice as
# optional and runs text-only without it, and that is the shape an install
# that skipped the voice row should keep.
if [ -f "$OUT/$TTS_NAME" ]; then
  echo "voice engine present: $TTS_NAME"
else
  echo "WARNING: no $TTS_NAME in resources; this bundle installs without a voice." >&2
  echo "         build it with: bash scripts/build_omnivoice.sh" >&2
fi

mkdir -p "$OUT"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/backend"
for d in harness memory personas scripts config; do
  cp -r "$REPO/backend/$d" "$STAGE/backend/"
done
cp "$REPO/backend/manifest.yaml" "$STAGE/backend/" 2>/dev/null || true
cp "$REPO/crates/hearth-probe/dictionary.yaml" "$STAGE/backend/dictionary.yaml"

# The second-brain memory client, vendored from its own repository into
# vendor/engram-mcp (the path REL_ENGRAM_MCP names and the rendered
# HEARTH_ENGRAM_MCP_PATH points at). First run establishes a brain for every
# new user, so a bundle without the client that reads it deeply is a memory
# regression shipping silently: hard error, like the supervisor gate above.
# The local transport is stdlib-only; the package directory is the whole need.
ENGRAM_MCP_SRC="${ENGRAM_MCP_SRC:-$REPO/../claude-marketplace/engram-mcp}"
if [ ! -d "$ENGRAM_MCP_SRC/engram_mcp" ]; then
  echo "no engram-mcp checkout at $ENGRAM_MCP_SRC" >&2
  echo "clone https://github.com/XXJones21/engram-mcp.git there, or set ENGRAM_MCP_SRC" >&2
  exit 1
fi
mkdir -p "$STAGE/backend/vendor/engram-mcp"
cp -r "$ENGRAM_MCP_SRC/engram_mcp" "$STAGE/backend/vendor/engram-mcp/"
cp "$ENGRAM_MCP_SRC/pyproject.toml" "$STAGE/backend/vendor/engram-mcp/" 2>/dev/null || true

find "$STAGE" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
rm -rf "$STAGE/backend/harness/sessions" 2>/dev/null || true

tar -C "$STAGE/backend" -czf "$OUT/backend.tar.gz" .
cp "$SUP" "$OUT/$SUP_NAME"

echo "packed:"
ls -la "$OUT"
