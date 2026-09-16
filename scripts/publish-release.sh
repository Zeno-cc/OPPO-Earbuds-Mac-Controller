#!/bin/bash
# Explicit operator action: upload a DRAFT, never publish or merge.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
VERSION=${1:?Usage: bash scripts/publish-release.sh X.Y.Z}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
DIR="$ROOT/dist/v$VERSION"
bash scripts/verify-release.sh "$DIR"
COMMIT=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["sourceCommit"])' "$DIR/manifest.json")
[[ "$(git rev-parse HEAD)" == "$COMMIT" && -z "$(git status --porcelain)" ]] || { echo "Source differs from verified artifacts." >&2; exit 1; }
REPO=Zeno-cc/OPPO-Earbuds-Mac-Controller
# Existing tags must identify the exact build source, including annotated tags.
TAG_SHA=$(gh api "repos/$REPO/commits/v$VERSION" --jq .sha 2>/dev/null || true)
[[ -z "$TAG_SHA" || "$TAG_SHA" == "$COMMIT" ]] || { echo "Existing tag points to different source." >&2; exit 1; }
if gh release view "v$VERSION" --repo "$REPO" --json isDraft >/dev/null 2>&1; then
    [[ "$(gh release view "v$VERSION" --repo "$REPO" --json isDraft --jq .isDraft)" == true ]] || {
        echo "Refusing to modify a published release." >&2; exit 1;
    }
else
    gh release create "v$VERSION" --repo "$REPO" --target "$COMMIT" --draft \
        --title "OPPO Earbuds Mac Controller v$VERSION" \
        --notes 'Signed in-app update. Review docs/RELEASING.md before publication.'
fi
gh release upload "v$VERSION" --repo "$REPO" --clobber \
    "$DIR"/*.zip "$DIR"/*.dmg "$DIR/appcast.xml" "$DIR/manifest.json"
WORK=$(/usr/bin/mktemp -d /tmp/budsbar-draft-check.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
gh release download "v$VERSION" --repo "$REPO" --dir "$WORK"
python3 - "$DIR" "$WORK" <<'PY'
import hashlib,json,pathlib,sys
manifest=json.loads((pathlib.Path(sys.argv[1])/'manifest.json').read_text())
for name,digest in manifest['sha256'].items():
    p=pathlib.Path(sys.argv[2])/name
    if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=digest: raise SystemExit('Uploaded draft differs from verified artifacts')
PY
echo 'Draft uploaded and downloaded bytes verified. Review and publish manually.'
echo 'Public asset URLs are expected to be unavailable until the draft is published.'
