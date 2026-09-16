#!/bin/bash
# Generates artifacts only. Never changes source versions, tags, or public releases.
set -euo pipefail
set +x
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
VERSION=${1:?Usage: bash scripts/release.sh X.Y.Z [--test-build]}
TEST_BUILD=0
if [[ "${2:-}" == --test-build ]]; then TEST_BUILD=1; elif [[ -n "${2:-}" ]]; then exit 2; fi
python3 - "$VERSION" Resources/Info.plist <<'PY'
import plistlib,re,sys
v=sys.argv[1]
if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)',v): raise SystemExit('Expected stable X.Y.Z')
with open(sys.argv[2],'rb') as stream: info=plistlib.load(stream)
if info['CFBundleVersion']!=v or info['CFBundleShortVersionString']!=v: raise SystemExit('Version does not match committed Info.plist')
PY
[[ -z "$(git status --porcelain)" ]] || { echo "Commit source changes before generating release artifacts." >&2; exit 1; }
DIST="$ROOT/dist/v$VERSION"
[[ ! -e "$DIST" ]] || { echo "Refusing to overwrite existing signed artifacts." >&2; exit 1; }
mkdir -p "$ROOT/dist"
WORK=$(/usr/bin/mktemp -d "$ROOT/dist/.release.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export BUDSBAR_UPDATE_TEST_BUILD="$TEST_BUILD"
unset BUDSBAR_TEST_FEED_URL
swift test
swift test -c release
bash build.sh release
APP="$ROOT/OPPO Earbuds Mac Controller.app"
bash scripts/verify-app-bundle.sh "$APP" --require-updater
source scripts/sparkle-paths.sh
sparkle_paths "$ROOT"
sparkle_key_arguments
STEM="OPPO-Earbuds-Mac-Controller-v$VERSION-macOS"
mkdir -p "$WORK/updates" "$WORK/dmg" "$WORK/final"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/updates/$STEM.zip"
if [[ -f "docs/release-notes/$VERSION.html" ]]; then cp "docs/release-notes/$VERSION.html" "$WORK/updates/$STEM.html"; fi
"$SPARKLE_BIN/generate_appcast" "${KEY_ARGS[@]}" --maximum-deltas 0 --maximum-versions 1 \
    --embed-release-notes --download-url-prefix "https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller/releases/download/v$VERSION/" "$WORK/updates"
/usr/bin/ditto "$APP" "$WORK/dmg/OPPO Earbuds Mac Controller.app"
ln -s /Applications "$WORK/dmg/Applications"
/usr/bin/hdiutil create -quiet -volname 'OPPO Earbuds Mac Controller' -srcfolder "$WORK/dmg" \
    -ov -format UDZO "$WORK/$STEM.dmg"
mv "$WORK/updates/$STEM.zip" "$WORK/updates/appcast.xml" "$WORK/$STEM.dmg" "$WORK/final/"
python3 - "$WORK/final" "$VERSION" "$(git rev-parse HEAD)" "$TEST_BUILD" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1])
hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.iterdir())}
(root/'manifest.json').write_text(json.dumps({'version':sys.argv[2],'sourceCommit':sys.argv[3],
    'testBuild':sys.argv[4]=='1','sparkleVersion':'2.9.6','sha256':hashes},indent=2)+'\n')
PY
if [[ "$TEST_BUILD" == 1 ]]; then
    bash scripts/verify-release.sh "$WORK/final" --allow-test-build
else
    bash scripts/verify-release.sh "$WORK/final"
fi
mv "$WORK/final" "$DIST"
echo "Verified artifacts: $DIST. Nothing was installed, tagged, or published."
