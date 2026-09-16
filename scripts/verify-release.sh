#!/bin/bash
# Verify final bytes, not a regenerated appcast.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIR=${1:?Usage: verify-release.sh directory [--allow-test-build]}
if [[ "${2:-}" == --allow-test-build ]]; then
    META=$(python3 "$ROOT/scripts/validate-release.py" "$DIR" --allow-test-build)
else
    META=$(python3 "$ROOT/scripts/validate-release.py" "$DIR")
fi
get() { printf '%s' "$META" | python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }
source "$ROOT/scripts/sparkle-paths.sh"
sparkle_paths "$ROOT"
sparkle_key_arguments
"$SPARKLE_BIN/sign_update" "${KEY_ARGS[@]}" --verify "$DIR/appcast.xml"
/usr/bin/swift "$ROOT/scripts/verify-update-signature.swift" "$(get archive)" "$(get signature)" "$(get publicKey)"
WORK=$(/usr/bin/mktemp -d /tmp/budsbar-verify-update.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
/usr/bin/ditto -x -k "$(get archive)" "$WORK"
/usr/bin/codesign --verify --deep --strict "$WORK/OPPO Earbuds Mac Controller.app"
echo "Release identity, signatures, layout and hashes verified."
