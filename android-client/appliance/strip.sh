#!/usr/bin/env bash
# Strip one tier from the appliance. Reversible: everything here is
# `pm uninstall --user 0`, which parks the package rather than deleting it;
# restore.sh brings any of it back without a reset.
#
#   ./strip.sh <0|1|2|3|late> [adb-serial]
#
# Run tiers in order, verify between them (runbook.md carries the per-tier
# verify steps), and stop the moment something looks wrong.
set -euo pipefail
cd "$(dirname "$0")"
source ./tiers.sh

TIER_NAME="${1:?usage: ./strip.sh <0|1|2|3|late> [adb-serial]}"
SERIAL="${2:-}"
ADB=(adb)
[ -n "$SERIAL" ] && ADB=(adb -s "$SERIAL")
LOG="strip-log.txt"

case "$TIER_NAME" in
    0) TIER=("${TIER0[@]}") ;;
    1) TIER=("${TIER1[@]}") ;;
    2) TIER=("${TIER2[@]}") ;;
    3) TIER=("${TIER3[@]}") ;;
    late) TIER=("${TIER_LATE[@]}") ;;
    *) echo "unknown tier: $TIER_NAME" >&2; exit 1 ;;
esac

INSTALLED="$("${ADB[@]}" shell pm list packages | tr -d '\r')"

on_allowlist() {
    local pkg="$1" a
    for a in "${ALLOWLIST[@]}"; do
        [ "$a" = "$pkg" ] && return 0
    done
    return 1
}

strip_one() {
    local pkg="$1" reason="$2"
    if on_allowlist "$pkg"; then
        echo "REFUSED  $pkg is on the do-not-touch allowlist"
        return
    fi
    if ! grep -Fxq "package:$pkg" <<<"$INSTALLED"; then
        echo "absent   $pkg"
        return
    fi
    # </dev/null: adb inside a while-read loop otherwise swallows the rest
    # of the piped package list, which is how the first tier 2 run stripped
    # exactly one wallpaper and declared victory.
    if "${ADB[@]}" shell pm uninstall --user 0 "$pkg" </dev/null >/dev/null 2>&1; then
        echo "removed  $pkg  ($reason)"
        echo "$(date -Iseconds) TIER$TIER_NAME removed $pkg -- $reason" >> "$LOG"
    else
        echo "FAILED   $pkg  (protected or already gone; fine, move on)"
    fi
}

echo "== tier $TIER_NAME =="
for entry in "${TIER[@]}"; do
    strip_one "${entry%%|*}" "${entry#*|}"
done

# Prefix sweeps, tier 2 only.
if [ "$TIER_NAME" = "2" ]; then
    for entry in "${TIER2_PREFIXES[@]}"; do
        prefix="${entry%%|*}"; reason="${entry#*|}"
        while read -r pkg; do
            [ -n "$pkg" ] && strip_one "$pkg" "$reason"
        done < <(grep -o "^package:$prefix[^ ]*" <<<"$INSTALLED" | sed 's/^package://')
    done
fi

echo "== tier $TIER_NAME done; log in $LOG. Verify per runbook.md before the next tier. =="
