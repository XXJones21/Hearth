#!/usr/bin/env bash
# Install the three Hearth systemd user units.
#
# A rewrite rather than a port. The Valinor script this replaces installed the
# retired speech engine's unit and never installed the one the harness declares
# in After=, so running it produced a stack ordered after a unit that did not
# exist. The enable list here is the set that actually runs:
#
#   hearth-supervisor.service   the model control plane, and llama-server
#   hearth-voice.service        the voice service on :8702
#   hearth-harness.service      the client entry point on :8700
#
# The units read $HEARTH_HOME/config/hearth.env, which the installer writes
# from the probe's plan. This script does not write it; render_config.py does.
# A missing file is not fatal here (EnvironmentFile=- in the units), but the
# stack will start with code defaults, which is worth knowing about, so it is
# reported rather than passed over.
#
# Idempotent. Run inside the distro as the product user, never with sudo:
#   bash "$HEARTH_ROOT/scripts/install_units.sh"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEARTH_ROOT="${HEARTH_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
HEARTH_HOME="${HEARTH_HOME:-$HOME/.hearth}"

SRC_DIR="$HEARTH_ROOT/systemd"
UNIT_DIR="$HOME/.config/systemd/user"
UNITS=(hearth-supervisor.service hearth-voice.service hearth-harness.service)

mkdir -p "$UNIT_DIR" "$HEARTH_HOME/config"

for unit in "${UNITS[@]}"; do
  if [ ! -f "$SRC_DIR/$unit" ]; then
    echo "[hearth-install] missing unit template: $SRC_DIR/$unit" >&2
    exit 1
  fi
  # The templates carry $HEARTH_ROOT as a literal so one file serves the image
  # and a checkout; substitute it on the way in. CRLF is stripped because a
  # Windows checkout on a mounted filesystem produces it and systemd rejects it.
  sed -e "s|@HEARTH_ROOT@|$HEARTH_ROOT|g" -e 's/\r$//' \
    "$SRC_DIR/$unit" > "$UNIT_DIR/$unit"
done

systemctl --user daemon-reload
systemctl --user enable "${UNITS[@]}"

if [ ! -f "$HEARTH_HOME/config/hearth.env" ]; then
  echo "[hearth-install] no $HEARTH_HOME/config/hearth.env yet." >&2
  echo "[hearth-install] the stack will start on code defaults, which is not a" >&2
  echo "[hearth-install] configured install. Write one with scripts/render_config.py." >&2
fi

# Ordering matters on a cold start: the supervisor makes a model resident, the
# voice service loads its own, and the harness dials both.
systemctl --user restart hearth-supervisor.service
systemctl --user restart hearth-voice.service
systemctl --user restart hearth-harness.service

echo "[hearth-install] installed and enabled: ${UNITS[*]}"
systemctl --user --no-pager status "${UNITS[@]}" | head -n 60 || true
