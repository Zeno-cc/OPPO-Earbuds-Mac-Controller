#!/bin/bash
# Build local v1.5.1 assets. Does not install, tag, push, or upload.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
VERSION=${1:?Usage: bash scripts/prepare-release.sh 1.5.1}
[[ "$VERSION" == 1.5.1 ]] || { echo 'This release task only prepares v1.5.1' >&2; exit 2; }
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || {
    echo 'Commit the exact candidate before preparing release assets.' >&2; exit 1;
}
[[ -z "${SPARKLE_PUBLIC_ED_KEY:-}" && -z "${BUDSBAR_TEST_FEED_URL:-}" && "${BUDSBAR_UPDATE_TEST_BUILD:-0}" == 0 ]] || {
    echo 'Release preparation does not accept test or public-key overrides.' >&2; exit 1;
}
DIST="$ROOT/dist/v$VERSION"
[[ ! -e "$DIST" ]] || { echo "Refusing to overwrite $DIST" >&2; exit 1; }
mkdir -p "$ROOT/dist"
source "$ROOT/scripts/sparkle-paths.sh"
sparkle_paths "$ROOT"
KEY=$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p)
[[ "$KEY" == "$(tr -d '\r\n' < "$ROOT/Resources/SparklePublicKey.txt")" ]] || {
    echo 'Keychain key does not match committed public key.' >&2; exit 1;
}
bash "$ROOT/build.sh" release
APP="$ROOT/OPPO Earbuds Mac Controller.app"
STAGED=$(/usr/bin/mktemp -d "$ROOT/dist/.v1.5.1.XXXXXX")
trap 'rm -rf "$STAGED"' EXIT
mkdir -p "$STAGED/package" "$STAGED/dmg"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGED/package/BudsBar-$VERSION.zip"
"$SPARKLE_BIN/generate_appcast" --account "$SPARKLE_ACCOUNT" --maximum-deltas 0 --maximum-versions 1 \
    --download-url-prefix "https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller/releases/download/v$VERSION/" \
    "$STAGED/package"
/usr/bin/ditto "$APP" "$STAGED/dmg/OPPO Earbuds Mac Controller.app"
ln -s /Applications "$STAGED/dmg/Applications"
/usr/bin/hdiutil create -quiet -volname 'OPPO Earbuds Mac Controller' -srcfolder "$STAGED/dmg" \
    -format UDZO "$STAGED/package/OPPO-Earbuds-Mac-Controller-v$VERSION-macOS.dmg"
bash "$ROOT/scripts/verify-release.sh" "$VERSION" "$STAGED/package"
mv "$STAGED/package" "$DIST"
echo "Local release assets ready: $DIST (source $(git rev-parse --short HEAD)). Nothing was installed or uploaded."
