#!/usr/bin/env python3
"""Configure a staged bundle only; release builds fail closed without an owner public key."""
import argparse
import base64
import os
from pathlib import Path
import plistlib
import sys
from urllib.parse import urlparse

FEED = "https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller/releases/latest/download/appcast.xml"
BUNDLE_ID = "com.aniketbudhwani.budsbar"


def public_key(value):
    value = value.strip()
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, base64.binascii.Error) as exc:
        raise ValueError("Invalid Sparkle public key encoding") from exc
    if len(decoded) != 32 or not any(decoded):
        raise ValueError("Sparkle public key must be a nonzero 32-byte Ed25519 key")
    return value


def configure(info, configuration, key, test_build=False, test_feed=None):
    result = dict(info)
    result.pop("BudsBarTestFeedURL", None)
    result.pop("NSAppTransportSecurity", None)
    if test_feed:
        parsed = urlparse(test_feed)
        if (configuration != "debug" or not test_build or parsed.scheme != "http"
                or parsed.hostname not in {"localhost", "127.0.0.1", "::1"}
                or not parsed.port or parsed.path != "/appcast.xml"
                or parsed.username or parsed.password or parsed.query or parsed.fragment):
            raise ValueError("Test feed requires a marked DEBUG build and loopback HTTP appcast URL")
        result["BudsBarTestFeedURL"] = test_feed
        result["NSAppTransportSecurity"] = {
            "NSAllowsLocalNetworking": True,
            "NSExceptionDomains": {"localhost": {"NSExceptionAllowsInsecureHTTPLoads": True}}
        }
    if result.get("CFBundleIdentifier") != BUNDLE_ID:
        raise ValueError("Bundle ID changed")
    if result.get("SUFeedURL") != FEED:
        raise ValueError("Release feed must be the fixed official stable feed")
    for name in ("SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction"):
        if result.get(name) is not True:
            raise ValueError(name + " must remain enabled")
    if result.get("SUSignedFeedFailureExpirationInterval") != 0:
        raise ValueError("Signed feed failures must not expire")
    for name in ("SUAutomaticallyUpdate", "SUAllowsAutomaticUpdates", "SUEnableSystemProfiling", "SUEnableJavaScript"):
        if result.get(name) is not False:
            raise ValueError(name + " must remain disabled")
    result.pop("SUPublicEDKey", None)
    if key:
        result["SUPublicEDKey"] = public_key(key)
    elif configuration == "release":
        raise ValueError("Release requires SPARKLE_PUBLIC_ED_KEY or Resources/SparklePublicKey.txt; see docs/RELEASING.md")
    if configuration == "debug" or test_build or not key:
        result["SUEnableAutomaticChecks"] = False
    result["BudsBarUpdateTestBuild"] = test_build
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plist", type=Path)
    parser.add_argument("--configuration", choices=["debug", "release"], required=True)
    parser.add_argument("--public-key-file", type=Path)
    parser.add_argument("--test-build", action="store_true")
    parser.add_argument("--test-feed-url")
    args = parser.parse_args()
    key = os.environ.get("SPARKLE_PUBLIC_ED_KEY")
    if not key and args.public_key_file and args.public_key_file.exists():
        key = args.public_key_file.read_text(encoding="utf-8").strip()
    updated = configure(plistlib.loads(args.plist.read_bytes()), args.configuration,
                        key, args.test_build, args.test_feed_url)
    temporary = args.plist.with_name(args.plist.name + ".tmp")
    temporary.write_bytes(plistlib.dumps(updated, sort_keys=False))
    temporary.replace(args.plist)
    print("Updater configuration: " + ("signed updates" if key else "disabled development build"))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, plistlib.InvalidFileException) as exc:
        print("Updater configuration failed: " + str(exc), file=sys.stderr)
        raise SystemExit(1)
