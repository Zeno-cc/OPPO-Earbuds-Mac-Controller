#!/bin/sh
# Downloads the latest release and installs it into /Applications.
#   curl -fsSL https://raw.githubusercontent.com/aniket-2308/Realme-TWS-Mac-Controller/main/install.sh | sh
set -e

APP="Realme TWS Mac Controller.app"
URL="https://github.com/aniket-2308/Realme-TWS-Mac-Controller/releases/latest/download/Realme-TWS-Mac-Controller.zip"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $APP…"
curl -fsSL "$URL" -o "$TMP/app.zip"
ditto -x -k "$TMP/app.zip" "$TMP/out"

rm -rf "/Applications/$APP"
mv "$TMP/out/$APP" "/Applications/$APP"

# The build is ad-hoc signed, so Gatekeeper would otherwise refuse a downloaded copy.
xattr -dr com.apple.quarantine "/Applications/$APP"

echo "Installed to /Applications. Launching…"
open "/Applications/$APP"
