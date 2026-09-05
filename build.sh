#!/bin/bash
# Builds OPPO Earbuds Mac Controller.app. Xcode 26 is required for both the SwiftUI
# macro plugin (see Package.swift) and the modern Icon Composer asset compiler.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG=${1:-release}
APP="OPPO Earbuds Mac Controller.app"
ICON_DOCUMENT="Resources/AppIcon.icon"

# The SwiftUI macro plugin is located in Package.swift so the editor works too.
swift build -c "$CONFIG"
BINARY=$(swift build -c "$CONFIG" --show-bin-path)/BudsBar

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/BudsBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Compile the modern macOS 26 icon document. actool emits both Assets.car (the
# appearance-aware source used by macOS) and AppIcon.icns (the legacy fallback).
ICON_WORK_DIR=$(/usr/bin/mktemp -d /tmp/oppo-earbuds-app-icon.XXXXXX)
trap 'rm -rf "$ICON_WORK_DIR"' EXIT
ACTOOL=$(/usr/bin/xcrun --find actool 2>/dev/null || true)
if [[ -z "$ACTOOL" || ! -x "$ACTOOL" ]]; then
    echo "Xcode 26 actool is required to compile $ICON_DOCUMENT" >&2
    exit 1
fi

"$ACTOOL" "$ICON_DOCUMENT" \
    --compile "$APP/Contents/Resources" \
    --output-format human-readable-text \
    --notices \
    --warnings \
    --output-partial-info-plist "$ICON_WORK_DIR/assetcatalog_generated_info.plist" \
    --app-icon AppIcon \
    --enable-on-demand-resources NO \
    --development-region en \
    --target-device mac \
    --minimum-deployment-target 26.0 \
    --platform macosx \
    --bundle-identifier com.aniketbudhwani.budsbar

for GENERATED_ICON in \
    "$APP/Contents/Resources/Assets.car" \
    "$APP/Contents/Resources/AppIcon.icns"; do
    if [[ ! -f "$GENERATED_ICON" ]]; then
        echo "actool did not generate $GENERATED_ICON" >&2
        exit 1
    fi
done

# Ad-hoc signature. The bundle identifier stays fixed across rebuilds so the granted
# Bluetooth permission survives; re-signing may still re-prompt once.
codesign --force --sign - "$APP"

echo "built $APP"
echo "run:  open \"$APP\"     (or: \"./$APP/Contents/MacOS/BudsBar\"  to see stderr)"
