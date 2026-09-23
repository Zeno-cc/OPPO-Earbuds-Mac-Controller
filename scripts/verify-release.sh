#!/bin/bash
# Recheck one locally prepared release with the production Keychain identity.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${1:?Usage: bash scripts/verify-release.sh 1.5.1 [asset-directory]}
DIR=${2:-"$ROOT/dist/v$VERSION"}
[[ "$VERSION" == 1.5.1 ]] || { echo 'Unexpected release version' >&2; exit 2; }
ZIP="$DIR/BudsBar-$VERSION.zip"
DMG="$DIR/OPPO-Earbuds-Mac-Controller-v$VERSION-macOS.dmg"
FEED="$DIR/appcast.xml"
[[ -s "$ZIP" && -s "$DMG" && -s "$FEED" ]] || { echo 'Missing release asset' >&2; exit 1; }
source "$ROOT/scripts/sparkle-paths.sh"
sparkle_paths "$ROOT"
KEY=$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p)
[[ "$KEY" == "$(tr -d '\r\n' < "$ROOT/Resources/SparklePublicKey.txt")" ]] || {
    echo 'Production public key mismatch' >&2; exit 1;
}
"$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$FEED"
SIGNATURE=$(python3 - "$FEED" "$ZIP" "$VERSION" "$KEY" <<'PY'
import plistlib
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
import zipfile

feed, archive, version, public_key = sys.argv[1:]
namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = ET.parse(feed).getroot().findall('channel/item')
if len(items) != 1:
    raise SystemExit('Expected exactly one update in appcast')
item = items[0]
enclosure = item.find('enclosure')
expected_url = (f'https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller/'
                f'releases/download/v{version}/BudsBar-{version}.zip')
if enclosure is None or enclosure.get('url') != expected_url:
    raise SystemExit('Appcast download URL mismatch')
if enclosure.get('length') != str(Path(archive).stat().st_size):
    raise SystemExit('Appcast archive length mismatch')
if (item.findtext(namespace + 'version') or enclosure.get(namespace + 'version')) != version:
    raise SystemExit('Appcast version mismatch')
signature = enclosure.get(namespace + 'edSignature')
if not signature:
    raise SystemExit('Missing archive signature')
with zipfile.ZipFile(archive) as zipped:
    info = plistlib.loads(zipped.read('OPPO Earbuds Mac Controller.app/Contents/Info.plist'))
for field in ('CFBundleVersion', 'CFBundleShortVersionString'):
    if info.get(field) != version:
        raise SystemExit('Archive version mismatch: ' + field)
if info.get('SUPublicEDKey') != public_key:
    raise SystemExit('Archive public key mismatch')
if info.get('BudsBarUpdateTestBuild') or info.get('BudsBarTestFeedURL'):
    raise SystemExit('Test configuration in release archive')
if info.get('LSMinimumSystemVersion') != '26.0':
    raise SystemExit('Minimum macOS changed')
print(signature)
PY
)
"$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$ZIP" "$SIGNATURE"
/usr/bin/hdiutil verify "$DMG" >/dev/null
echo 'Release DMG, signed ZIP and signed appcast verified.'
