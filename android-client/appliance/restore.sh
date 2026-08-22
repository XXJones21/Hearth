#!/usr/bin/env bash
# Reverse the strip, per tier or per package, without a reset.
# `pm uninstall --user 0` only parks a preinstalled package;
# `cmd package install-existing` un-parks it.
#
#   ./restore.sh <0|1|2|3|late|package.name> [adb-serial]
set -euo pipefail
cd "$(dirname "$0")"
source ./tiers.sh

TARGET="${1:?usage: ./restore.sh <0|1|2|3|late|package.name> [adb-serial]}"
SERIAL="${2:-}"
ADB=(adb)
[ -n "$SERIAL" ] && ADB=(adb -s "$SERIAL")
LOG="strip-log.txt"

restore_one() {
    local pkg="$1"
    if "${ADB[@]}" shell cmd package install-existing "$pkg" >/dev/null 2>&1; then
        echo "restored $pkg"
        echo "$(date -Iseconds) restored $pkg" >> "$LOG"
    else
        echo "FAILED   $pkg (was it ever preinstalled? sideloads need their APK back)"
    fi
}

case "$TARGET" in
    0) TIER=("${TIER0[@]}") ;;
    1) TIER=("${TIER1[@]}") ;;
    2) TIER=("${TIER2[@]}") ;;
    3) TIER=("${TIER3[@]}") ;;
    late) TIER=("${TIER_LATE[@]}") ;;
    *) restore_one "$TARGET"; exit 0 ;;
esac

echo "== restoring tier $TARGET =="
for entry in "${TIER[@]}"; do
    restore_one "${entry%%|*}"
done

if [ "$TARGET" = "2" ]; then
    # The prefix sweep is not enumerable once stripped; restore the base
    # package and pull the rest from the log.
    while read -r line; do
        pkg="$(sed -n 's/.* removed \([^ ]*\) --.*/\1/p' <<<"$line")"
        case "$pkg" in
            com.motorola.livewallpaper3*) restore_one "$pkg" ;;
        esac
    done < "$LOG"
fi

echo "== done =="
