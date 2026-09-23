#!/bin/bash
SPARKLE_VERSION=2.9.6
SPARKLE_ACCOUNT=${SPARKLE_ACCOUNT:-com.aniketbudhwani.budsbar.updates}

sparkle_paths() {
    local root="$1" candidate version
    SPARKLE_FRAMEWORK=""
    while IFS= read -r candidate; do
        version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$candidate/Resources/Info.plist" 2>/dev/null || true)
        if [[ "$version" == "$SPARKLE_VERSION" ]]; then
            [[ -z "$SPARKLE_FRAMEWORK" ]] || { echo "Multiple Sparkle artifacts; clean .build/artifacts." >&2; return 1; }
            SPARKLE_FRAMEWORK="$candidate"
        fi
    done < <(/usr/bin/find "$root/.build/artifacts" -type d -name Sparkle.framework -prune 2>/dev/null)
    [[ -n "$SPARKLE_FRAMEWORK" ]] || { echo "Pinned Sparkle framework not found; run swift build." >&2; return 1; }
    SPARKLE_BIN=""
    while IFS= read -r candidate; do
        [[ -z "$SPARKLE_BIN" ]] || { echo "Multiple Sparkle tool directories." >&2; return 1; }
        SPARKLE_BIN=$(dirname "$candidate")
    done < <(/usr/bin/find "$root/.build/artifacts" -type f -path '*/bin/generate_appcast' 2>/dev/null)
    [[ -n "$SPARKLE_BIN" && -x "$SPARKLE_BIN/sign_update" && -x "$SPARKLE_BIN/generate_keys" ]] || {
        echo "Pinned SwiftPM artifact is missing its official release tools." >&2; return 1;
    }
}
