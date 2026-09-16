#!/bin/bash
# Build a local bundle only: never install, publish or modify /Applications.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$PWD
CONFIG=${1:-release}
case "$CONFIG" in debug|release) ;; *) echo "Usage: bash build.sh [debug|release]" >&2; exit 2;; esac
APP="$ROOT/OPPO Earbuds Mac Controller.app"
WORK=$(/usr/bin/mktemp -d "$ROOT/.build-app.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
STAGED="$WORK/OPPO Earbuds Mac Controller.app"
mkdir -p "$STAGED/Contents/MacOS" "$STAGED/Contents/Resources" "$STAGED/Contents/Frameworks"
cp Resources/Info.plist "$STAGED/Contents/Info.plist"
set -- "$STAGED/Contents/Info.plist" --configuration "$CONFIG" --public-key-file "$ROOT/Resources/SparklePublicKey.txt"
if [[ "${BUDSBAR_UPDATE_TEST_BUILD:-0}" == 1 ]]; then set -- "$@" --test-build; fi
if [[ -n "${BUDSBAR_TEST_FEED_URL:-}" ]]; then set -- "$@" --test-feed-url "$BUDSBAR_TEST_FEED_URL"; fi
python3 scripts/configure-updater.py "$@"

swift build -c "$CONFIG"
BIN_DIR=$(swift build -c "$CONFIG" --show-bin-path)
cp "$BIN_DIR/BudsBar" "$STAGED/Contents/MacOS/BudsBar"
source "$ROOT/scripts/sparkle-paths.sh"
sparkle_paths "$ROOT"
/usr/bin/ditto "$SPARKLE_FRAMEWORK" "$STAGED/Contents/Frameworks/Sparkle.framework"
SPARKLE_LICENSE="$ROOT/.build/checkouts/Sparkle/LICENSE"
if [[ ! -f "$SPARKLE_LICENSE" ]]; then SPARKLE_LICENSE="$ROOT/.build/checkouts/sparkle/LICENSE"; fi
[[ -f "$SPARKLE_LICENSE" ]] || { echo "Resolved Sparkle license not found" >&2; exit 1; }
cp "$SPARKLE_LICENSE" "$STAGED/Contents/Resources/Sparkle-LICENSE.txt"

# Remove development rpaths while preserving the bundle-relative runtime search path.
/usr/bin/otool -l "$STAGED/Contents/MacOS/BudsBar" | /usr/bin/awk '
/cmd LC_RPATH/{r=1;next}
r && /path /{sub(/^[[:space:]]*path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print; r=0}' > "$WORK/rpaths"
while IFS= read -r rpath; do
    case "$rpath" in /*) /usr/bin/install_name_tool -delete_rpath "$rpath" "$STAGED/Contents/MacOS/BudsBar";; esac
done < "$WORK/rpaths"
if ! /usr/bin/grep -qx '@executable_path/../Frameworks' "$WORK/rpaths"; then
    /usr/bin/install_name_tool -add_rpath '@executable_path/../Frameworks' "$STAGED/Contents/MacOS/BudsBar"
fi

# Resolve within the selected Xcode first: hosted macOS can have a broken xcrun cache.
# Do not reset global developer settings or modify the user's tool caches.
SELECTED_DEVELOPER_DIR=${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}
ACTOOL="$SELECTED_DEVELOPER_DIR/usr/bin/actool"
if [[ ! -x "$ACTOOL" ]]; then ACTOOL=$(/usr/bin/xcrun --find actool); fi
[[ -x "$ACTOOL" ]] || { echo "Xcode 26 actool is required" >&2; exit 1; }
echo "Compiling App icon with selected Xcode actool"
"$ACTOOL" Resources/AppIcon.icon --compile "$STAGED/Contents/Resources" \
    --output-format human-readable-text --notices --warnings \
    --output-partial-info-plist "$WORK/icon-info.plist" --app-icon AppIcon \
    --enable-on-demand-resources NO --development-region en --target-device mac \
    --minimum-deployment-target 26.0 --platform macosx \
    --bundle-identifier com.aniketbudhwani.budsbar
# Keep the signed nested Sparkle helpers intact; sign the outer App last.
/usr/bin/codesign --verify --deep --strict "$STAGED/Contents/Frameworks/Sparkle.framework"
/usr/bin/codesign --force --sign - "$STAGED"
if [[ "$CONFIG" == release ]]; then
    bash scripts/verify-app-bundle.sh "$STAGED" --require-updater
else
    bash scripts/verify-app-bundle.sh "$STAGED"
fi
rm -rf "$APP"
mv "$STAGED" "$APP"
echo "Built $APP ($CONFIG). The installed App has not been modified."
