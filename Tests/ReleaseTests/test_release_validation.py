import base64
import importlib.util
import json
from pathlib import Path
import plistlib
import stat
import tempfile
import unittest
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
config = load('updater_config', 'scripts/configure-updater.py')
validation = load('release_validation', 'scripts/validate-release.py')

class ConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
        self.key = base64.b64encode(bytes(range(32))).decode()
    def test_release_requires_owner_key(self):
        with self.assertRaises(ValueError): config.configure(self.info, 'release', None)
    def test_debug_without_key_disables_network(self):
        output = config.configure(self.info, 'debug', None)
        self.assertNotIn('SUPublicEDKey', output)
        self.assertIs(output['SUEnableAutomaticChecks'], False)
    def test_key_is_only_in_output(self):
        output = config.configure(self.info, 'release', self.key)
        self.assertEqual(output['SUPublicEDKey'], self.key)
        self.assertNotIn('SUPublicEDKey', self.info)
    def test_invalid_keys(self):
        for key in ('TODO', 'not base64!', base64.b64encode(bytes(32)).decode()):
            with self.subTest(key=key), self.assertRaises(ValueError): config.public_key(key)
    def test_test_build_disables_scheduler(self):
        self.assertIs(config.configure(self.info, 'release', self.key, True)['SUEnableAutomaticChecks'], False)
    def test_unsafe_policies_rejected(self):
        for key, value in [('SURequireSignedFeed', False), ('SUVerifyUpdateBeforeExtraction', False),
                           ('SUSignedFeedFailureExpirationInterval', 1728000),
                           ('SUAllowsAutomaticUpdates', True), ('SUEnableJavaScript', True)]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                config.configure(dict(self.info, **{key: value}), 'release', self.key)
    def test_loopback_requires_marked_debug(self):
        feed = 'http://localhost:8765/appcast.xml'
        output = config.configure(self.info, 'debug', self.key, True, feed)
        self.assertEqual(output['BudsBarTestFeedURL'], feed)
        for configuration, marker in [('release', True), ('debug', False), ('release', False)]:
            with self.assertRaises(ValueError): config.configure(self.info, configuration, self.key, marker, feed)
    def test_arbitrary_hosts_rejected(self):
        for url in ['http://attacker.example:8765/appcast.xml', 'http://localhost:8765/wrong',
                    'http://user@localhost:8765/appcast.xml', 'https://localhost:8765/appcast.xml']:
            with self.assertRaises(ValueError): config.configure(self.info, 'debug', self.key, True, url)
    def test_release_strips_test_configuration(self):
        info = dict(self.info, BudsBarTestFeedURL='http://localhost:8765/appcast.xml',
                    NSAppTransportSecurity={'NSAllowsArbitraryLoads': True})
        output = config.configure(info, 'release', self.key)
        self.assertNotIn('BudsBarTestFeedURL', output)
        self.assertNotIn('NSAppTransportSecurity', output)

class ReleaseValidationTests(unittest.TestCase):
    """Synthetic signatures test structure only; macOS CI tests real EdDSA separately."""
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.version = '1.5.1'
        self.stem = 'OPPO-Earbuds-Mac-Controller-v1.5.1-macOS'
        self.archive = self.directory / (self.stem + '.zip')
        self.info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
        self.info.update(SUPublicEDKey=base64.b64encode(bytes(range(32))).decode(), BudsBarUpdateTestBuild=False)
        self.write_archive()
        (self.directory / (self.stem + '.dmg')).write_bytes(b'fixture DMG: not installable')
        self.xml = ET.Element('rss', version='2.0')
        self.item = ET.SubElement(ET.SubElement(self.xml, 'channel'), 'item')
        for key, value in [('version', self.version), ('shortVersionString', self.version), ('minimumSystemVersion', '26.0')]:
            ET.SubElement(self.item, validation.NS + key).text = value
        self.enclosure = ET.SubElement(self.item, 'enclosure', {
            'url': f'https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller/releases/download/v{self.version}/{self.stem}.zip',
            'length': str(self.archive.stat().st_size),
            validation.NS + 'edSignature': base64.b64encode(bytes(64)).decode()})
        self.write_feed()
    def write_archive(self, extra=None):
        with zipfile.ZipFile(self.archive, 'w') as archive:
            archive.writestr(validation.APP + '/Contents/Info.plist', plistlib.dumps(self.info))
            archive.writestr(validation.APP + '/Contents/MacOS/BudsBar', b'fixture')
            archive.writestr(validation.APP + '/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle', b'fixture')
            if extra: archive.writestr(*extra)
    def write_feed(self):
        (self.directory / 'appcast.xml').write_bytes(ET.tostring(self.xml))
        self.rehash()
    def rehash(self):
        names = [self.stem + '.zip', self.stem + '.dmg', 'appcast.xml']
        (self.directory / 'manifest.json').write_text(json.dumps({
            'version': self.version, 'sourceCommit': 'a' * 40, 'sparkleVersion': '2.9.6',
            'testBuild': self.info.get('BudsBarUpdateTestBuild', False),
            'sha256': {n: validation.sha256(self.directory / n) for n in names}}))
    def validate(self): return validation.validate(self.directory)
    def test_valid_structure(self): self.assertEqual(self.validate()['version'], '1.5.1')
    def test_tampered_archive(self):
        with self.archive.open('ab') as stream: stream.write(b'tampered')
        with self.assertRaises(ValueError): self.validate()
    def test_arbitrary_download_host(self):
        self.enclosure.set('url', 'https://example.com/evil.zip'); self.write_feed()
        with self.assertRaises(ValueError): self.validate()
    def test_feed_version_mismatch(self):
        self.item.find(validation.NS + 'version').text = '9.9.9'; self.write_feed()
        with self.assertRaises(ValueError): self.validate()
    def test_identity_mismatch(self):
        self.info['CFBundleIdentifier'] = 'other.app'; self.write_archive(); self.rehash()
        with self.assertRaises(ValueError): self.validate()
    def test_traversal(self):
        self.write_archive(('../evil', b'data')); self.rehash()
        with self.assertRaises(ValueError): self.validate()
    def test_escaping_symlink(self):
        link = zipfile.ZipInfo(validation.APP + '/Contents/Resources/bad')
        link.create_system = 3; link.external_attr = (stat.S_IFLNK | 0o777) << 16
        self.write_archive((link, '../../../../outside')); self.rehash()
        with self.assertRaises(ValueError): self.validate()
    def test_framework_relative_symlink_allowed(self):
        link = zipfile.ZipInfo(validation.APP + '/Contents/Frameworks/Sparkle.framework/Versions/Current')
        link.create_system = 3; link.external_attr = (stat.S_IFLNK | 0o777) << 16
        self.write_archive((link, 'B'))
        self.enclosure.set('length', str(self.archive.stat().st_size)); self.write_feed(); self.validate()
    def test_beta_rejected(self):
        ET.SubElement(self.item, validation.NS + 'channel').text = 'beta'; self.write_feed()
        with self.assertRaises(ValueError): self.validate()
    def test_test_build_cannot_publish(self):
        self.info['BudsBarUpdateTestBuild'] = True; self.write_archive()
        self.enclosure.set('length', str(self.archive.stat().st_size)); self.write_feed()
        with self.assertRaises(ValueError): self.validate()
        validation.validate(self.directory, allow_test_build=True)
    def test_missing_signature(self):
        self.enclosure.attrib.pop(validation.NS + 'edSignature'); self.write_feed()
        with self.assertRaises(ValueError): self.validate()
    def test_insecure_policy(self):
        self.info['SURequireSignedFeed'] = False; self.write_archive(); self.rehash()
        with self.assertRaises(ValueError): self.validate()
    def test_second_enclosure(self):
        ET.SubElement(self.item, 'enclosure'); self.write_feed()
        with self.assertRaises(ValueError): self.validate()
    def test_source_zip_is_not_update(self):
        self.enclosure.set('url', 'https://github.com/Zeno-cc/OPPO-Earbuds-Mac-Controller/archive/main.zip'); self.write_feed()
        with self.assertRaises(ValueError): self.validate()

if __name__ == '__main__': unittest.main()
