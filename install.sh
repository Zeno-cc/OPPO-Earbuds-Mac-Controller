#!/bin/sh
# Downloads the latest DMG release and installs it into /Applications.
#   curl -fsSL https://raw.githubusercontent.com/Zeno-cc/OPPO-Earbuds-Mac-Controller/main/install.sh | sh
set -e

APP="OPPO Earbuds Mac Controller.app"
URL="https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller/releases/latest/download/OPPO-Earbuds-Mac-Controller-v1.2.1-macOS.dmg"

TMP=$(mktemp -d)
MOUNT="$TMP/mount"
mkdir -p "$MOUNT"
trap 'hdiutil detach "$MOUNT" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

echo "Downloading $APP…"
curl -fsSL "$URL" -o "$TMP/app.dmg"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$TMP/app.dmg" >/dev/null

rm -rf "/Applications/$APP"
ditto "$MOUNT/$APP" "/Applications/$APP"

# The build is ad-hoc signed, so Gatekeeper would otherwise refuse a downloaded copy.
xattr -dr com.apple.quarantine "/Applications/$APP"

echo "Installed to /Applications. Launching…"
open "/Applications/$APP"
