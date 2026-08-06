#!/usr/bin/env bash
# Install + enable Valar as an always-on systemd --user service.
#
# Why this exists: Valar was being launched FOREGROUND via harness_run.sh, so it died
# with the terminal/session and :8700 went dark (the portproxy then resets on connect
# because nothing is listening behind it). This registers Valar as a user service so
# it is up whenever the WSL user manager is. Linger=yes is already set for `jones`
# (see memory valar_wsl_session_churn_brain_bounce), so the user manager - and thus
# Valar - survives logoff and starts at boot.
#
# Idempotent: safe to re-run. Run inside WSL as the `jones` user (NOT via sudo):
#   bash /mnt/d/Tools/Valinor/scripts/install_units.sh
set -euo pipefail

SRC_DIR=/mnt/d/Tools/Valinor/scripts/systemd
UNIT_DIR="$HOME/.config/systemd/user"
mkdir -p "$UNIT_DIR"

# Both units: valar-tts (persistent NeuTTS, 127.0.0.1:8701) and the gateway
# (HEARTH_TTS_BACKEND=remote default). The TTS service starts first (hearth-harness.service
# has After=/Wants=hearth-voice.service) so the gateway never reloads NeuTTS on its
# own restarts — the decoupling. The old service-load hang was the concurrent-load
# race fixed in valar/voice/tts.py (2026-06-03).
for unit in hearth-voice.service hearth-harness.service; do
  if [ ! -f "$SRC_DIR/$unit" ]; then
    echo "[valar-install] unit source missing: $SRC_DIR/$unit" >&2
    exit 1
  fi
  # CRLF-stripped (systemd rejects CRLF on DrvFs).
  sed 's/\r$//' "$SRC_DIR/$unit" > "$UNIT_DIR/$unit"
done

systemctl --user daemon-reload
systemctl --user enable hearth-voice.service hearth-harness.service
systemctl --user restart hearth-voice.service
systemctl --user restart hearth-harness.service

echo "[valar-install] enabled + (re)started hearth-voice.service + hearth-harness.service"
sleep 2
systemctl --user --no-pager status hearth-voice.service hearth-harness.service | head -n 40 || true
