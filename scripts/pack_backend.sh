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
SUP="$REPO/backend/supervisor/target/release/hearth-supervisor.exe"

[ -f "$SUP" ] || { echo "build the supervisor first: cargo build --release in backend/supervisor" >&2; exit 1; }

mkdir -p "$OUT"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/backend"
for d in harness memory personas scripts config; do
  cp -r "$REPO/backend/$d" "$STAGE/backend/"
done
cp "$REPO/backend/manifest.yaml" "$STAGE/backend/" 2>/dev/null || true
cp "$REPO/crates/hearth-probe/dictionary.yaml" "$STAGE/backend/dictionary.yaml"

find "$STAGE" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
rm -rf "$STAGE/backend/harness/sessions" 2>/dev/null || true

tar -C "$STAGE/backend" -czf "$OUT/backend.tar.gz" .
cp "$SUP" "$OUT/hearth-supervisor.exe"

echo "packed:"
ls -la "$OUT"
