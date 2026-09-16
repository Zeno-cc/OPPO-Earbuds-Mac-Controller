#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP=${1:-"$ROOT/OPPO Earbuds Mac Controller.app"}
REQUIRE_UPDATER=${2:-}
PLIST="$APP/Contents/Info.plist"
fail() { echo "Bundle validation failed: $*" >&2; exit 1; }
read_plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }
/usr/bin/plutil -lint "$PLIST" "$ROOT/Resources/Info.plist"
for KEY in CFBundleShortVersionString CFBundleVersion; do
    [[ "$(read_plist "$PLIST" "$KEY")" == "$(read_plist "$ROOT/Resources/Info.plist" "$KEY")" ]] || fail "$KEY mismatch"
done
[[ "$(read_plist "$PLIST" CFBundleIdentifier)" == com.aniketbudhwani.budsbar ]] || fail "bundle ID changed"
[[ "$(read_plist "$PLIST" LSMinimumSystemVersion)" == 26.0 ]] || fail "macOS target changed"
[[ "$(read_plist "$PLIST" CFBundleExecutable)" == BudsBar ]] || fail "executable changed"
[[ "$(read_plist "$PLIST" CFBundlePackageType)" == APPL ]] || fail "not an application"
BINARY="$APP/Contents/MacOS/BudsBar"
[[ -s "$BINARY" && -x "$BINARY" ]] || fail "missing executable"
/usr/bin/file -b "$BINARY" | /usr/bin/grep -q 'Mach-O.*executable' || fail "not Mach-O"
for ASSET in Assets.car AppIcon.icns Sparkle-LICENSE.txt; do
    [[ -s "$APP/Contents/Resources/$ASSET" ]] || fail "missing $ASSET"
done
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
[[ -L "$FRAMEWORK/Versions/Current" && -x "$FRAMEWORK/Sparkle" ]] || fail "damaged framework layout"
[[ "$(read_plist "$FRAMEWORK/Resources/Info.plist" CFBundleShortVersionString)" == 2.9.6 ]] || fail "wrong Sparkle version"
LINKS=$(/usr/bin/otool -L "$BINARY")
/usr/bin/grep -q '@rpath/Sparkle.framework/' <<< "$LINKS" || fail "missing relocatable Sparkle linkage"
RPATHS=$(/usr/bin/otool -l "$BINARY" | /usr/bin/awk '/cmd LC_RPATH/{r=1;next} r && /path /{sub(/^[[:space:]]*path /, ""); sub(/ \(offset [0-9]+\)$/, ""); print; r=0}')
/usr/bin/grep -qx '@executable_path/../Frameworks' <<< "$RPATHS" || fail "missing bundle rpath"
if /usr/bin/grep -E '/Users/|/\.build/|/private/tmp/' <<< "$LINKS"; then fail "development load path"; fi
if /usr/bin/grep -q '^/' <<< "$RPATHS"; then fail "absolute runtime search path"; fi
python3 - "$PLIST" "$REQUIRE_UPDATER" "$ROOT" <<'PY'
import importlib.util,pathlib,plistlib,sys
spec=importlib.util.spec_from_file_location('config',pathlib.Path(sys.argv[3])/'scripts/configure-updater.py')
config=importlib.util.module_from_spec(spec);spec.loader.exec_module(config)
info=plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())
release=sys.argv[2]=='--require-updater'
if release and ('BudsBarTestFeedURL' in info or 'NSAppTransportSecurity' in info):
    raise SystemExit('Release bundle contains a test network override')
config.configure(info,'release' if release else 'debug',info.get('SUPublicEDKey'),info.get('BudsBarUpdateTestBuild',False))
PY
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
SIGNATURE=$(/usr/bin/codesign --display --verbose=4 "$APP" 2>&1)
/usr/bin/grep -qx 'Signature=adhoc' <<< "$SIGNATURE" || fail "expected ad-hoc outer signature"
echo "Bundle validation passed."
