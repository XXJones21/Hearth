#!/bin/bash
# Migration plan F1, over the working tree rather than over one scrub run.
#
# Comments are excluded for the same reason apple-scrub.py excludes them: the
# gates hunt couplings, not prose, and a comment explaining why the port is
# 18700 and not 8700 is the most valuable line in the file.
#
# NUL-delimited on purpose. Two of the three target folders are "Hearth Vision"
# and "Hearth Widget", and a word-split loop silently skipped all twelve of
# their files while printing ok -- a gate that passes by not looking is worse
# than no gate.
#
# Usage: tools/apple-gates.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
fail=0

# `mapfile` is bash 4; macOS ships bash 3.2 as /bin/bash. Read NUL-delimited.
#
# TRACKED **AND UNTRACKED**, with --exclude-standard so .gitignore still wins.
# `git ls-files` alone lists only tracked files, which made the gate blind in
# exactly the situation it exists for: an area lands a dozen brand-new files,
# the gate is run before staging, and it reports ok because it cannot see them.
# Area 4 shipped an RFC1918 literal through that hole and was caught only once
# the files happened to be staged. A gate that passes by not looking is worse
# than no gate -- the same reason this loop is NUL-delimited.
FILES=()
while IFS= read -r -d '' f; do
    if [[ $f == *.swift || $f == *.plist || $f == *.entitlements || $f == *.xcconfig ]]; then
        FILES+=("$f")
    fi
done < <(git ls-files -z --cached --others --exclude-standard apple-client)

check() {
    local label=$1 pattern=$2 out="" hit
    for f in "${FILES[@]}"; do
        hit=$(sed -e 's://.*::' "$f" | grep -inE "$pattern" | sed "s|^|  $f:|")
        [[ -n $hit ]] && out+="$hit"$'\n'
    done
    if [[ -n $out ]]; then printf '  FAIL  %s\n%s' "$label" "$out"; fail=1
    else printf '  ok    %s\n' "$label"; fi
}

echo "F1 -- the move   (${#FILES[@]} source files checked)"
check "no valinor"          'valinor'
check "no RFC1918 literal"  '\b10\.[0-9]+\.[0-9]+\.[0-9]+\b|\b192\.168\.'
check "no old ports"        ':(8700|8765|8766|8080|8702)\b'
check "no absolute paths"   'D:/Tools|/Users/jones/Valinor'
check "no SwiftData"        'SwiftData'

if git grep -q AS9PH6XDN4 -- apple-client/ ':!apple-client/manifest.yaml' 2>/dev/null; then
    echo "  FAIL  DEVELOPMENT_TEAM is tracked"; fail=1
else
    echo "  ok    DEVELOPMENT_TEAM only in the gitignored Local.xcconfig"
fi

printf '\n  tracked under apple-client: %s\n' "$(git ls-files apple-client | wc -l | tr -d ' ')"
exit $fail
