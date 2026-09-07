#!/bin/bash
# Validate build.sh's local/CI ad-hoc bundle without launching it.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP=${1:-"$ROOT/OPPO Earbuds Mac Controller.app"}
PLIST="$APP/Contents/Info.plist"
SOURCE_PLIST="$ROOT/Resources/Info.plist"

fail() {
    echo "Bundle validation failed: $*" >&2
    exit 1
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

/usr/bin/plutil -lint "$PLIST" "$SOURCE_PLIST"
for KEY in CFBundleShortVersionString CFBundleVersion; do
    EXPECTED=$(plist_value "$SOURCE_PLIST" "$KEY")
    [[ -n "$EXPECTED" && "$(plist_value "$PLIST" "$KEY")" == "$EXPECTED" ]] \
        || fail "$KEY must match Resources/Info.plist ($EXPECTED)"
done

[[ "$(plist_value "$PLIST" CFBundleIdentifier)" == "com.aniketbudhwani.budsbar" ]] \
    || fail "CFBundleIdentifier must preserve com.aniketbudhwani.budsbar"
[[ "$(plist_value "$PLIST" LSMinimumSystemVersion)" == "26.0" ]] \
    || fail "LSMinimumSystemVersion must be 26.0"
[[ "$(plist_value "$PLIST" CFBundleExecutable)" == "BudsBar" ]] \
    || fail "CFBundleExecutable must be BudsBar"
[[ "$(plist_value "$PLIST" CFBundlePackageType)" == "APPL" ]] \
    || fail "CFBundlePackageType must be APPL"

EXECUTABLE="$APP/Contents/MacOS/BudsBar"
[[ -s "$EXECUTABLE" && -x "$EXECUTABLE" ]] || fail "missing or non-executable BudsBar"
/usr/bin/file -b "$EXECUTABLE" | /usr/bin/grep -q 'Mach-O.*executable' \
    || fail "BudsBar must be a Mach-O executable"
for ASSET in Assets.car AppIcon.icns; do
    [[ -s "$APP/Contents/Resources/$ASSET" ]] || fail "missing or empty $ASSET"
done

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
SIGNATURE=$(/usr/bin/codesign --display --verbose=4 "$APP" 2>&1)
/usr/bin/grep -qx 'Signature=adhoc' <<< "$SIGNATURE" \
    || fail "expected build.sh's ad-hoc signature"
echo "Bundle validation passed: $APP"
