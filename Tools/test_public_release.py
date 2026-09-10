#!/usr/bin/env python3
"""Exercise release failures without modifying signing keys or mounting real disks."""
import hashlib
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import verify_public_release as release


class ReleaseTests(unittest.TestCase):
    def make_app(self, base):
        app = base / 'ShotPal Pro.app'
        resources = app / 'Contents/Resources'
        executable = app / 'Contents/MacOS/拉片宝'
        executable.parent.mkdir(parents=True)
        executable.write_bytes(b'fixture')
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': '拉片宝'}))
        for language in ('en', 'zh-Hans'):
            folder = resources / f'{language}.lproj'
            folder.mkdir(parents=True)
            for name in ('Localizable.strings', 'InfoPlist.strings'):
                (folder / name).write_text('"fixture" = "fixture";')
        model = resources / release.MODEL
        model.parent.mkdir(parents=True)
        with model.open('wb') as stream:
            stream.truncate(100_000_000)
        return app

    def test_reject_non_distribution_identity(self):
        for signature in ('Signature=adhoc', 'Authority=Apple Development: Test', ''):
            with self.subTest(signature=signature), self.assertRaises(ValueError):
                release.require_developer_id(signature)
        release.require_developer_id('Authority=Developer ID Application: Test')

    def test_missing_english_and_incomplete_model(self):
        with tempfile.TemporaryDirectory() as temp:
            app = self.make_app(Path(temp))
            self.assertEqual(release.validate_payload(app)['CFBundleExecutable'], '拉片宝')
            en = app / 'Contents/Resources/en.lproj/Localizable.strings'
            en.unlink()
            with self.assertRaisesRegex(ValueError, 'localization'):
                release.validate_payload(app)
            en.write_text('fixture')
            (app / 'Contents/Resources' / release.MODEL).write_bytes(b'truncated')
            with self.assertRaisesRegex(ValueError, 'model'):
                release.validate_payload(app)

    def test_external_model_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            app = self.make_app(base)
            model = app / 'Contents/Resources' / release.MODEL
            external = base / 'external.bin'
            model.rename(external)
            model.symlink_to(external)
            with self.assertRaisesRegex(ValueError, 'model'):
                release.validate_payload(app)

    def test_final_checksum_and_failure_cleanup(self):
        for fail_runtime in (False, True):
            with self.subTest(fail_runtime=fail_runtime), tempfile.TemporaryDirectory() as temp:
                dmg = Path(temp) / 'ShotPal.dmg'
                dmg.write_bytes(b'final stapled image')
                calls = []
                def command(*args):
                    args = tuple(map(str, args)); calls.append(args)
                    if '-dvv' in args:
                        return b'Authority=Developer ID Application: Test'
                    if 'attach' in args:
                        mount = Path(args[args.index('-mountpoint') + 1])
                        self.make_app(mount)
                        (mount / 'Applications').symlink_to('/Applications')
                    if '--lapianbao-localization-check' in args:
                        return json.dumps({'status': 'passed'}).encode()
                    if fail_runtime and any('verify_recognition_runtime.py' in a for a in args):
                        raise ValueError('runtime failed')
                    return b''
                with patch.object(release, 'run', side_effect=command):
                    if fail_runtime:
                        with self.assertRaisesRegex(ValueError, 'runtime failed'):
                            release.verify(dmg)
                    else:
                        release.verify(dmg)
                self.assertTrue(any('detach' in c for c in calls))
                checksum = dmg.with_suffix('.dmg.sha256')
                self.assertEqual(checksum.exists(), not fail_runtime)
                if checksum.exists():
                    self.assertEqual(checksum.read_text(), hashlib.sha256(dmg.read_bytes()).hexdigest() + '  ShotPal.dmg\n')


if __name__ == '__main__':
    unittest.main()
