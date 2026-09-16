#!/bin/bash
# Real Sparkle installer test. Only an isolated GitHub CI workspace may run it.
set -euo pipefail
set +x
[[ "${CI:-}" == true && "${GITHUB_ACTIONS:-}" == true ]] || {
    echo 'This automated replacement test is CI-only; see docs/UPDATE_TESTING.md.' >&2; exit 1;
}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source scripts/sparkle-paths.sh
sparkle_paths "$ROOT"
[[ -x "$SPARKLE_BIN/sparkle" ]] || { echo 'Official Sparkle CLI missing' >&2; exit 1; }
export SPARKLE_ACCOUNT="com.aniketbudhwani.budsbar.install-test.$$.${RANDOM}"
WORK=$(mktemp -d /tmp/budsbar-install-test.XXXXXX)
cleanup() {
    /usr/bin/security delete-generic-password -a "$SPARKLE_ACCOUNT" -s https://sparkle-project.org >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT
"$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT"
export SPARKLE_PUBLIC_ED_KEY=$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p)
export BUDSBAR_UPDATE_TEST_BUILD=1
unset BUDSBAR_TEST_FEED_URL
bash build.sh release
APP='OPPO Earbuds Mac Controller.app'
mkdir "$WORK/client" "$WORK/server"
/usr/bin/ditto "$ROOT/$APP" "$WORK/client/$APP"
/usr/bin/ditto "$ROOT/$APP" "$WORK/server/$APP"
BASE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$WORK/client/$APP/Contents/Info.plist")
NEXT=$(python3 - "$BASE" <<'PY'
import re,sys
if not re.fullmatch(r'\d+\.\d+\.\d+',sys.argv[1]): raise SystemExit('Expected stable version')
a,b,c=map(int,sys.argv[1].split('.')); print(f'{a}.{b}.{c+1}')
PY
)
for KEY in CFBundleVersion CFBundleShortVersionString; do
    /usr/libexec/PlistBuddy -c "Set :$KEY $NEXT" "$WORK/server/$APP/Contents/Info.plist"
done
/usr/bin/codesign --force --sign - "$WORK/server/$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$WORK/server/$APP" "$WORK/server/BudsBar-$NEXT.zip"
rm -rf "$WORK/server/$APP"
PORT=$(python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(('127.0.0.1',0)); print(sock.getsockname()[1])
PY
)
"$SPARKLE_BIN/generate_appcast" --account "$SPARKLE_ACCOUNT" --maximum-deltas 0 --maximum-versions 1 \
    --download-url-prefix "http://localhost:$PORT/" "$WORK/server"
"$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$WORK/server/appcast.xml"
export DYLD_FRAMEWORK_PATH="$(dirname "$SPARKLE_FRAMEWORK")"
python3 - "$WORK" "$SPARKLE_BIN/sparkle" "$PORT" "$NEXT" <<'PY'
from functools import partial
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
from pathlib import Path
import plistlib,subprocess,sys,threading
root=Path(sys.argv[1]).resolve()
app=root/'client'/'OPPO Earbuds Mac Controller.app'
plist=app/'Contents'/'Info.plist'
info=plistlib.loads(plist.read_bytes())
assert info.get('BudsBarUpdateTestBuild') is True
old=info['CFBundleVersion']; new=sys.argv[4]
server=ThreadingHTTPServer(('127.0.0.1',int(sys.argv[3])),partial(SimpleHTTPRequestHandler,directory=str(root/'server')))
threading.Thread(target=server.serve_forever,daemon=True).start()
command=[sys.argv[2],'--check-immediately','--feed-url',f'http://localhost:{sys.argv[3]}/appcast.xml',
         '--user-agent-name','BudsBar isolated CI update test','--verbose',str(app)]
try:
    archive=root/'server'/f'BudsBar-{new}.zip'
    original=archive.read_bytes()
    archive.write_bytes(original+b'tampered')
    bad=subprocess.run(command,timeout=180)
    if bad.returncode==0 or plistlib.loads(plist.read_bytes())['CFBundleVersion']!=old:
        raise SystemExit('Tampered archive was not rejected safely')
    archive.write_bytes(original)
    subprocess.run(command,timeout=180,check=True)
    actual=plistlib.loads(plist.read_bytes())
    if actual['CFBundleVersion']!=new or actual['CFBundleIdentifier']!=info['CFBundleIdentifier']:
        raise SystemExit('Installer did not replace the intended App')
    subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(app)],check=True)
    print(f'REAL INSTALLER PASS: {old} -> {new}; tampering rejected; installed signature valid.')
    print('App was not running: GUI/Relaunch/Bluetooth/TCC still require manual QA.')
finally:
    server.shutdown()
PY
