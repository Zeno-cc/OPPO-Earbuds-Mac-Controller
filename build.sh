#!/bin/bash
# Builds OPPO Earbuds Mac Controller.app. Compiles with the Command Line Tools; an installed Xcode.app is
# needed only for its SwiftUI macro plugin (see Package.swift). Xcode need not be selected
# with xcode-select.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG=${1:-release}
APP="OPPO Earbuds Mac Controller.app"

# The SwiftUI macro plugin is located in Package.swift so the editor works too.
swift build -c "$CONFIG"
BINARY=$(swift build -c "$CONFIG" --show-bin-path)/BudsBar

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/BudsBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature. The bundle identifier stays fixed across rebuilds so the granted
# Bluetooth permission survives; re-signing may still re-prompt once.
codesign --force --sign - "$APP"

echo "built $APP"
echo "run:  open \"$APP\"     (or: \"./$APP/Contents/MacOS/BudsBar\"  to see stderr)"
