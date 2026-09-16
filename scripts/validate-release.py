#!/usr/bin/env python3
"""Offline structural checks. Cryptographic validation is performed by verify-release.sh."""
import argparse
import base64
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import sys
import xml.etree.ElementTree as ET
import zipfile

APP = "OPPO Earbuds Mac Controller.app"
BUNDLE_ID = "com.aniketbudhwani.budsbar"
FEED = "https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller/releases/latest/download/appcast.xml"
NS = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
MAX_UNPACKED_BYTES = 512 * 1024 * 1024


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def version_ok(version):
    return isinstance(version, str) and bool(re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version))


def archive_info(archive):
    with zipfile.ZipFile(archive) as bundle:
        names = set()
        total = 0
        for entry in bundle.infolist():
            path = PurePosixPath(entry.filename)
            require(not path.is_absolute() and ".." not in path.parts and "\\" not in entry.filename,
                    "Unsafe archive path")
            require(path.parts and path.parts[0] in (APP, "__MACOSX"), "Unexpected archive root")
            if path.parts[0] == "__MACOSX":
                require(len(path.parts) == 1 or path.parts[1] in (APP, "._" + APP), "Unexpected resource-fork metadata")
            require(entry.filename not in names, "Duplicate archive entry")
            names.add(entry.filename)
            require(not entry.flag_bits & 1, "Encrypted ZIP not supported")
            total += entry.file_size
            require(total <= MAX_UNPACKED_BYTES, "Archive unpacked size limit exceeded")
            kind = stat.S_IFMT(entry.external_attr >> 16)
            require(kind in (0, stat.S_IFREG, stat.S_IFDIR, stat.S_IFLNK), "Special file in archive")
            if kind == stat.S_IFLNK:
                require(entry.file_size <= 4096, "Oversized symlink")
                target = bundle.read(entry).decode("utf-8")
                require(target and not target.startswith("/") and "\\" not in target, "Unsafe symlink")
                resolved = list(path.parent.parts)
                for part in PurePosixPath(target).parts:
                    if part == "..":
                        require(len(resolved) > 1, "Symlink escapes App bundle")
                        resolved.pop()
                    elif part != ".":
                        resolved.append(part)
                require(resolved[0] == APP, "Symlink escapes App bundle")
        required = APP + "/Contents/Info.plist"
        require(required in names, "Missing App Info.plist")
        require(bundle.getinfo(required).file_size <= 1024 * 1024, "Oversized Info.plist")
        info = plistlib.loads(bundle.read(required))
        require(APP + "/Contents/MacOS/BudsBar" in names, "Missing BudsBar executable")
        require(any(name.startswith(APP + "/Contents/Frameworks/Sparkle.framework/") for name in names), "Sparkle not embedded")
        return info


def validate(directory, allow_test_build=False):
    directory = Path(directory)
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    version = manifest.get("version", "")
    require(version_ok(version), "Version must be stable X.Y.Z")
    stem = f"OPPO-Earbuds-Mac-Controller-v{version}-macOS"
    expected = {stem + ".zip", stem + ".dmg", "appcast.xml"}
    require(set(manifest.get("sha256", {})) == expected, "Artifact set mismatch")
    for name, digest in manifest["sha256"].items():
        path = directory / name
        require(path.is_file() and not path.is_symlink(), "Missing artifact or unexpected symlink")
        require(isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest), "Invalid digest")
        require(sha256(path) == digest, "Artifact changed after signing: " + name)
    require(manifest.get("sparkleVersion") == "2.9.6", "Unexpected Sparkle version")
    info = archive_info(directory / (stem + ".zip"))
    for key in ("CFBundleVersion", "CFBundleShortVersionString"):
        require(info.get(key) == version, "Archive " + key + " mismatch")
    require(info.get("CFBundleIdentifier") == BUNDLE_ID, "Bundle identity mismatch")
    require(info.get("CFBundleExecutable") == "BudsBar", "Executable identity mismatch")
    require(info.get("LSMinimumSystemVersion") == "26.0", "Minimum OS mismatch")
    require(info.get("SUFeedURL") == FEED, "Unexpected production feed")
    for key in ("SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction"):
        require(info.get(key) is True, "Signature verification disabled")
    require(info.get("SUSignedFeedFailureExpirationInterval") == 0, "Unsafe feed-failure expiry")
    require(info.get("SUAllowsAutomaticUpdates") is False and info.get("SUAutomaticallyUpdate") is False,
            "Unattended update policy changed")
    require("BudsBarTestFeedURL" not in info and "NSAppTransportSecurity" not in info, "Test feed in release archive")
    test = info.get("BudsBarUpdateTestBuild") is True
    require(manifest.get("testBuild") is test, "Test-build marker mismatch")
    require(allow_test_build or not test, "Test artifacts must never be published")
    key = info.get("SUPublicEDKey", "")
    require(isinstance(key, str), "Missing public key")
    public = base64.b64decode(key, validate=True)
    require(len(public) == 32 and any(public), "Invalid update trust anchor")

    xml = (directory / "appcast.xml").read_bytes()
    require(len(xml) <= 4 * 1024 * 1024, "Appcast too large")
    require(b"<!DOCTYPE" not in xml.upper() and b"<!ENTITY" not in xml.upper(), "DTD/entity not permitted")
    channel = ET.fromstring(xml).find("channel")
    require(channel is not None, "Missing RSS channel")
    items = channel.findall("item")
    require(len(items) == 1, "Bootstrap feed must contain one full update")
    item = items[0]
    require(item.find(NS + "channel") is None, "Pre-release channel in stable feed")
    require(item.find(NS + "deltas") is None, "Delta updates not enabled")
    require(item.findtext(NS + "minimumSystemVersion") == "26.0", "Appcast OS mismatch")
    enclosures = item.findall("enclosure")
    require(len(enclosures) == 1, "Expected one enclosure")
    enclosure = enclosures[0]
    for keyname in ("version", "shortVersionString"):
        require((item.findtext(NS + keyname) or enclosure.get(NS + keyname)) == version,
                "Appcast " + keyname + " mismatch")
    url = f"https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller/releases/download/v{version}/{stem}.zip"
    require(enclosure.get("url") == url, "Archive URL must be the exact versioned GitHub release URL")
    require(enclosure.get("length") == str((directory / (stem + ".zip")).stat().st_size), "Archive length mismatch")
    signature = enclosure.get(NS + "edSignature", "")
    require(len(base64.b64decode(signature, validate=True)) == 64, "Missing EdDSA archive signature")
    require(re.fullmatch(r"[0-9a-f]{40}", manifest.get("sourceCommit", "")) is not None, "Missing source commit")
    return {"version": version, "archive": str(directory / (stem + ".zip")),
            "publicKey": key, "signature": signature, "sourceCommit": manifest["sourceCommit"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--allow-test-build", action="store_true")
    args = parser.parse_args()
    try:
        print(json.dumps(validate(args.directory, args.allow_test_build), indent=2))
    except (ValueError, OSError, KeyError, TypeError, ET.ParseError, zipfile.BadZipFile) as exc:
        print("Release validation failed: " + str(exc), file=sys.stderr)
        raise SystemExit(1)
