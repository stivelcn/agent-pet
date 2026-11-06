import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('mirror', Path(__file__).with_name('sync_release.py'))
mirror = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mirror)


class MirrorTests(unittest.TestCase):
    def setUp(self):
        self.payload = b'verified test DMG'
        self.tag = 'v0.2.6'
        self.name = 'LuMate-0.2.6-universal.dmg'
        self.release = {'tag_name': self.tag, 'draft': False, 'prerelease': False, 'body': 'notes', 'assets': [{
            'name': self.name, 'size': len(self.payload), 'digest': 'sha256:' + hashlib.sha256(self.payload).hexdigest(),
            'browser_download_url': mirror.DOWNLOAD + self.tag + '/' + self.name}]}

    def testRejectsUntrustedMetadataAndMissingChecksums(self):
        for key, value in [('digest', 'sha256:abc'), ('browser_download_url', 'https://evil.test/app.dmg'), ('size', -1)]:
            broken = copy.deepcopy(self.release)
            broken['assets'][0][key] = value
            with self.assertRaises(ValueError): mirror.validate_release(broken)
        for tag in ['../../bad', 'v0.2.6-beta', 'v0.2.6/other', '0.2.6']:
            with self.assertRaises(ValueError): mirror.version(tag)
        broken = copy.deepcopy(self.release)
        broken['prerelease'] = True
        with self.assertRaises(ValueError): mirror.validate_release(broken)

    def testPublishesOnlyCompleteVerifiedAssetsAndSkipsExistingBytes(self):
        seen = []
        def opener(url):
            seen.append(url)
            return io.BytesIO(json.dumps(self.release).encode() if url.startswith(mirror.API) else self.payload)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = mirror.sync(root, opener=opener)
            self.assertEqual(result['status'], 'synced')
            self.assertEqual((root / 'public' / self.tag / self.name).read_bytes(), self.payload)
            self.assertEqual(json.loads((root / 'public/latest.json').read_text())['tag_name'], self.tag)
            mirror.sync(root, opener=opener)
            self.assertEqual(sum(not url.startswith(mirror.API) for url in seen), 1)

    def testCorruptAssetDoesNotPublishMetadataOrReplacePreviousRelease(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            public = root / 'public'
            public.mkdir()
            previous = json.dumps({'tag_name': 'v0.2.5'})
            (public / 'latest.json').write_text(previous)
            def opener(url):
                return io.BytesIO(json.dumps(self.release).encode() if url.startswith(mirror.API) else b'bad')
            with self.assertRaises(ValueError): mirror.sync(root, opener=opener)
            self.assertEqual((public / 'latest.json').read_text(), previous)
            self.assertFalse((public / self.tag / self.name).exists())

    def testDelayedOlderWorkflowCannotDowngradeLatest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            public = root / 'public'
            public.mkdir()
            previous = json.dumps({'tag_name': 'v0.3.0'})
            (public / 'latest.json').write_text(previous)
            def opener(url):
                self.assertTrue(url.startswith(mirror.API))
                return io.BytesIO(json.dumps(self.release).encode())
            self.assertEqual(mirror.sync(root, self.tag, opener)['status'], 'ignored-older-release')
            self.assertEqual((public / 'latest.json').read_text(), previous)


if __name__ == '__main__': unittest.main()
