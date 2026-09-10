#!/usr/bin/env python3
"""Check the complete unsigned vendor inventory before Xcode copies resources."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "LapianBao/RuntimeTools.bundle/Contents/Resources/Tools"


def validate(tools, signed=False):
    runtime = tools / "recognition"
    manifest = json.loads((runtime / "manifest.json").read_text())
    lock = runtime / "recognition-wheels.lock.json"
    assert hashlib.sha256(lock.read_bytes()).hexdigest() == manifest["lockSHA256"], "Recognition lock mismatch"
    assert manifest["architecture"] == "arm64" and manifest["python"] == "3.11"
    for path, record in manifest["files"].items():
        target = runtime / path
        assert target.resolve().is_relative_to(runtime.resolve()), f"Escaping recognition path: {path}"
        assert target.is_file(), f"Missing recognition dependency: {path}"
        if not (signed and record["native"]):
            assert hashlib.sha256(target.read_bytes()).hexdigest() == record["sha256"], f"Corrupt recognition dependency: {path}"
    assert manifest["models"], "Missing recognition model declaration"
    for model in manifest["models"]:
        assert model in manifest["files"] and (runtime / model).stat().st_size > 1_000_000
    assert any("license" in p.lower() for p in manifest["files"]), "Third-party licenses missing"
    for name, digest in json.loads(lock.read_text())["requirements"].items():
        assert hashlib.sha256((tools / name).read_bytes()).hexdigest() == digest, f"Stale requirements: {name}"
    return manifest


def main():
    manifest = validate(TOOLS)
    assert (ROOT / "Tools/recognition-wheels.lock.json").read_bytes() == (TOOLS / "recognition/recognition-wheels.lock.json").read_bytes()
    for name in ["recognition_bootstrap.py", "detect_music.py", "detect_scene_cuts_transnet.py"]:
        assert (ROOT / "Tools" / name).read_bytes() == (TOOLS / name).read_bytes(), f"Bundled script out of sync: {name}"
    print(f"Pinned recognition inputs verified: {len(manifest['packages'])} wheels, {len(manifest['files'])} files")


if __name__ == "__main__":
    main()
