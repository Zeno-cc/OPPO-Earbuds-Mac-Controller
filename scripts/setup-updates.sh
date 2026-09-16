#!/bin/bash
# One-time owner action, never invoked by build.sh/CI. No private key is exported.
set -euo pipefail
set +x
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[[ "$(uname -s)" == Darwin && -t 0 ]] || { echo 'Run interactively on your persistent Mac.' >&2; exit 1; }
cd "$ROOT"
swift package resolve
source scripts/sparkle-paths.sh
sparkle_paths "$ROOT"
echo 'Private update key will remain in this Mac login Keychain. Make your own secure backup.'
read -r -p 'Type PERSISTENT to continue: ' consent
[[ "$consent" == PERSISTENT ]] || exit 1
"$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT"
PUBLIC=$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p)
python3 - "$PUBLIC" "$ROOT/Resources/SparklePublicKey.txt" <<'PY'
import base64,pathlib,sys
key=sys.argv[1].strip()
if len(base64.b64decode(key,validate=True))!=32: raise SystemExit('Invalid generated public key')
p=pathlib.Path(sys.argv[2])
if p.exists() and p.read_text().strip()!=key: raise SystemExit('Existing public key differs; reviewed key rotation required')
p.write_text(key+'\n')
PY
echo 'Commit Resources/SparklePublicKey.txt (public only). Private key was not exported.'
