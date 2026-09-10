#!/usr/bin/env python3
"""Negative build-gate fixtures. Never modify the real runtime tree."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from check_recognition_bundle_inputs import validate


class BundleInputTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="recognition-input-test-")
        self.addCleanup(self.temp.cleanup)
        self.tools = Path(self.temp.name)
        self.runtime = self.tools / "recognition"
        self.runtime.mkdir()
        self.model = self.runtime / "model.pth"
        self.model.write_bytes(b"x" * 1_000_001)
        self.license = self.runtime / "LICENSE"
        self.license.write_text("Synthetic test only")
        self.native = self.runtime / "core.so"
        self.native.write_bytes(b"synthetic unsigned native")
        self.lock = self.runtime / "recognition-wheels.lock.json"
        self.lock.write_text('{"requirements": {}}')
        self.manifest = {"architecture": "arm64", "python": "3.11", "models": ["model.pth"],
                         "lockSHA256": self.sha(self.lock), "files": {
                             p.name: {"sha256": self.sha(p), "native": p == self.native}
                             for p in [self.model, self.license, self.native]}}
        self.save()

    def sha(self, path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def save(self):
        (self.runtime / "manifest.json").write_text(json.dumps(self.manifest))

    def test_intact(self):
        validate(self.tools)

    def test_missing_model(self):
        self.model.unlink()
        with self.assertRaises(AssertionError):
            validate(self.tools)

    def test_corrupt_model(self):
        self.model.write_bytes(b"broken")
        with self.assertRaises(AssertionError):
            validate(self.tools, signed=True)

    def test_missing_native(self):
        self.native.unlink()
        with self.assertRaises(AssertionError):
            validate(self.tools, signed=True)

    def test_corrupt_unsigned_native(self):
        self.native.write_bytes(b"bad")
        with self.assertRaises(AssertionError):
            validate(self.tools)

    def test_signed_native_hash_may_change(self):
        self.native.write_bytes(b"synthetic signed native")
        validate(self.tools, signed=True)

    def test_corrupt_lock(self):
        self.lock.write_text("{}")
        with self.assertRaises(AssertionError):
            validate(self.tools)

    def test_escaping_path(self):
        self.manifest["files"]["../outside"] = {"sha256": "x", "native": False}
        self.save()
        with self.assertRaises(AssertionError):
            validate(self.tools)


if __name__ == "__main__":
    unittest.main()
