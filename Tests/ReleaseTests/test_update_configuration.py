"""Checks the local update trust boundary without requiring a published release."""
import base64
import importlib.util
from pathlib import Path
import plistlib
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "configure_updater", ROOT / "scripts" / "configure-updater.py"
)
CONFIG = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONFIG)


class UpdateConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.info = plistlib.loads((ROOT / "Resources" / "Info.plist").read_bytes())
        self.key = base64.b64encode(bytes(range(32))).decode("ascii")

    def test_release_requires_public_key(self):
        with self.assertRaises(ValueError):
            CONFIG.configure(self.info, "release", None)

    def test_debug_without_key_cannot_check_updates(self):
        result = CONFIG.configure(self.info, "debug", None)
        self.assertNotIn("SUPublicEDKey", result)
        self.assertIs(result["SUEnableAutomaticChecks"], False)

    def test_marked_debug_accepts_loopback_feed(self):
        feed = "http://localhost:8765/appcast.xml"
        result = CONFIG.configure(self.info, "debug", self.key, True, feed)
        self.assertEqual(result["BudsBarTestFeedURL"], feed)
        self.assertEqual(result["SUPublicEDKey"], self.key)
        self.assertIs(result["SUEnableAutomaticChecks"], False)

    def test_unmarked_or_release_build_rejects_loopback_feed(self):
        feed = "http://localhost:8765/appcast.xml"
        for configuration, marked in (("debug", False), ("release", True)):
            with self.subTest(configuration=configuration, marked=marked):
                with self.assertRaises(ValueError):
                    CONFIG.configure(self.info, configuration, self.key, marked, feed)

    def test_release_removes_test_network_configuration(self):
        info = dict(self.info, BudsBarTestFeedURL="http://localhost:8765/appcast.xml")
        info["NSAppTransportSecurity"] = {"NSAllowsArbitraryLoads": True}
        result = CONFIG.configure(info, "release", self.key)
        self.assertNotIn("BudsBarTestFeedURL", result)
        self.assertNotIn("NSAppTransportSecurity", result)

    def test_invalid_key_or_signature_policy_is_rejected(self):
        for key in ("invalid", base64.b64encode(bytes(32)).decode("ascii")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                CONFIG.public_key(key)
        with self.assertRaises(ValueError):
            CONFIG.configure(dict(self.info, SURequireSignedFeed=False), "release", self.key)


if __name__ == "__main__":
    unittest.main()
