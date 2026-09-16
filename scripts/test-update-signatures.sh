#!/bin/bash
# Disposable CI identity, no production secrets and no public release.
set -euo pipefail
set +x
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source scripts/sparkle-paths.sh
sparkle_paths "$ROOT"
export SPARKLE_ACCOUNT="com.aniketbudhwani.budsbar.ci.$$.${RANDOM}"
WORK=$(mktemp -d /tmp/budsbar-signature-tests.XXXXXX)
cleanup() {
    /usr/bin/security delete-generic-password -a "$SPARKLE_ACCOUNT" -s https://sparkle-project.org >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT
"$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT"
export SPARKLE_PUBLIC_ED_KEY=$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p)
export BUDSBAR_UPDATE_TEST_BUILD=1
bash build.sh release
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)
STEM="OPPO-Earbuds-Mac-Controller-v$VERSION-macOS"
mkdir "$WORK/updates"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$ROOT/OPPO Earbuds Mac Controller.app" "$WORK/updates/$STEM.zip"
"$SPARKLE_BIN/generate_appcast" --account "$SPARKLE_ACCOUNT" --maximum-deltas 0 --maximum-versions 1 \
    --download-url-prefix "https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller/releases/download/v$VERSION/" "$WORK/updates"
"$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$WORK/updates/appcast.xml"
SIGNATURE=$(python3 - "$WORK/updates/appcast.xml" <<'PY'
import sys,xml.etree.ElementTree as ET
print(ET.parse(sys.argv[1]).getroot().find('channel/item/enclosure').get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'))
PY
)
/usr/bin/swift scripts/verify-update-signature.swift "$WORK/updates/$STEM.zip" "$SIGNATURE" "$SPARKLE_PUBLIC_ED_KEY"
cp "$WORK/updates/$STEM.zip" "$WORK/tampered.zip"
printf 'tampered' >> "$WORK/tampered.zip"
if /usr/bin/swift scripts/verify-update-signature.swift "$WORK/tampered.zip" "$SIGNATURE" "$SPARKLE_PUBLIC_ED_KEY"; then
    echo 'FAIL: modified archive accepted' >&2; exit 1
fi
cp "$WORK/updates/appcast.xml" "$WORK/tampered.xml"
printf '\n<!-- tampered -->\n' >> "$WORK/tampered.xml"
if "$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$WORK/tampered.xml"; then
    echo 'FAIL: modified feed accepted' >&2; exit 1
fi
echo 'Real EdDSA checks passed; altered ZIP and feed rejected.'
