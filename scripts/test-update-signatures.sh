#!/bin/bash
# Exercise Sparkle's real signing tools with a disposable local identity.
set -euo pipefail
set +x
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/scripts/sparkle-paths.sh"
sparkle_paths "$ROOT"

TEST_WORK=$(/usr/bin/mktemp -d /tmp/budsbar-signature-tests.XXXXXX)
cleanup() {
    /bin/rm -rf "$TEST_WORK"
}
trap cleanup EXIT

TEST_KEY_FILE="$TEST_WORK/disposable.private-key"
TEST_PUBLIC_KEY=$(/usr/bin/swift -e '
import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedString().write(
    to: URL(fileURLWithPath: CommandLine.arguments[1]), atomically: true, encoding: .utf8)
print(key.publicKey.rawRepresentation.base64EncodedString())
' "$TEST_KEY_FILE")
/bin/chmod 600 "$TEST_KEY_FILE"
/bin/mkdir -p "$TEST_WORK/updates"
TEST_APP="$TEST_WORK/OPPO Earbuds Mac Controller.app"
/usr/bin/ditto "$ROOT/OPPO Earbuds Mac Controller.app" "$TEST_APP"
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $TEST_PUBLIC_KEY" "$TEST_APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$TEST_APP" >/dev/null

TEST_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$TEST_APP/Contents/Info.plist")
TEST_ZIP="$TEST_WORK/updates/BudsBar-$TEST_VERSION.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$TEST_APP" "$TEST_ZIP"
"$SPARKLE_BIN/generate_appcast" --ed-key-file "$TEST_KEY_FILE" --maximum-deltas 0 --maximum-versions 1 \
    --download-url-prefix 'http://localhost:8765/' "$TEST_WORK/updates"
TEST_FEED="$TEST_WORK/updates/appcast.xml"
[[ -s "$TEST_FEED" ]] || { echo 'FAIL: signed appcast missing' >&2; exit 1; }
"$SPARKLE_BIN/sign_update" --ed-key-file "$TEST_KEY_FILE" --verify "$TEST_FEED"

TEST_SIGNATURE=$(python3 - "$TEST_FEED" <<'PY'
import sys
import xml.etree.ElementTree as ET
enclosure = ET.parse(sys.argv[1]).getroot().find('channel/item/enclosure')
if enclosure is None:
    raise SystemExit('FAIL: appcast enclosure missing')
signature = enclosure.get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature')
if not signature:
    raise SystemExit('FAIL: archive signature missing')
print(signature)
PY
)
"$SPARKLE_BIN/sign_update" --ed-key-file "$TEST_KEY_FILE" --verify "$TEST_ZIP" "$TEST_SIGNATURE"

/bin/cp "$TEST_ZIP" "$TEST_WORK/tampered.zip"
printf 'tampered' >> "$TEST_WORK/tampered.zip"
if "$SPARKLE_BIN/sign_update" --ed-key-file "$TEST_KEY_FILE" --verify "$TEST_WORK/tampered.zip" "$TEST_SIGNATURE"; then
    echo 'FAIL: modified ZIP accepted' >&2
    exit 1
fi

/bin/cp "$TEST_FEED" "$TEST_WORK/tampered.xml"
python3 - "$TEST_WORK/tampered.xml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
original = path.read_bytes()
changed = original.replace(b'http://localhost:8765/', b'http://localhost:8766/', 1)
if changed == original:
    raise SystemExit('FAIL: appcast download URL not found')
path.write_bytes(changed)
PY
if "$SPARKLE_BIN/sign_update" --ed-key-file "$TEST_KEY_FILE" --verify "$TEST_WORK/tampered.xml"; then
    echo 'FAIL: modified appcast accepted' >&2
    exit 1
fi
echo 'Sparkle EdDSA checks passed; modified ZIP and appcast rejected.'
