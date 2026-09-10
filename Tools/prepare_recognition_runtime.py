#!/usr/bin/env python3
"""Build-time only: install hash-locked arm64 wheels into a relocatable vendor tree.

To refresh the reviewed lock, supply a pip --dry-run --ignore-installed --report
JSON produced by the bundled Python 3.11 using both requirements files. Normal
builds/downloads use the committed lock, never resolve newest dependencies.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "LapianBao/RuntimeTools.bundle/Contents/Resources/Tools"
LOCK = ROOT / "Tools/recognition-wheels.lock.json"
PYTHON = TOOLS / "python/cpython-3.11-aarch64-apple-darwin/bin/python3.11"
MAGICS = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock-from-report", type=Path)
    args = parser.parse_args()
    if args.lock_from_report:
        report = json.loads(args.lock_from_report.read_text())
        assert report["environment"]["platform_machine"] == "arm64"
        assert report["environment"]["python_version"] == "3.11"
        packages = []
        for item in report["install"]:
            info, meta = item["download_info"], item["metadata"]
            assert info["url"].endswith(".whl")
            packages.append({"name": meta["name"], "version": meta["version"],
                             "url": info["url"], "sha256": info["archive_info"]["hashes"]["sha256"]})
        lock = {"python": "3.11", "architecture": "arm64", "minimumMacOS": "14.0",
                "requirements": {p.name: sha(p) for p in [ROOT / "Tools/requirements-music.txt", ROOT / "Tools/requirements-transnet.txt"]},
                "packages": sorted(packages, key=lambda p: p["name"].lower())}
        LOCK.write_text(json.dumps(lock, indent=2) + "\n")
    lock = json.loads(LOCK.read_text())
    assert platform.machine() == "arm64", "Build on Apple Silicon with the bundled Python"
    for name, digest in lock["requirements"].items():
        assert sha(ROOT / "Tools" / name) == digest, "Requirements changed; resolve and review a new lock"
    destination = TOOLS / "recognition"
    if (destination / "site-packages").exists():
        raise SystemExit("Recognition assets already exist; refusing to overwrite them")
    with tempfile.TemporaryDirectory(prefix="lapianbao-recognition-build-") as temp:
        work = Path(temp)
        wheels = work / "wheels"
        wheels.mkdir()

        def download(package):
            target = wheels / package["url"].rsplit("/", 1)[1]
            with urllib.request.urlopen(package["url"], timeout=120) as response, target.open("wb") as stream:
                shutil.copyfileobj(response, stream)
            assert sha(target) == package["sha256"], f"Wheel digest mismatch: {target.name}"
            return target

        with ThreadPoolExecutor(max_workers=6) as pool:
            downloaded = list(pool.map(download, lock["packages"]))
        requirements = work / "locked.txt"
        requirements.write_text("\n".join(f'{p["name"]}=={p["version"]} --hash=sha256:{p["sha256"]}' for p in lock["packages"]) + "\n")
        staged = work / "recognition"
        site = staged / "site-packages"
        subprocess.run([str(PYTHON), "-I", "-B", "-m", "pip", "--isolated", "install", "--no-index",
                        "--find-links", str(wheels), "--no-deps", "--require-hashes", "--no-compile",
                        "--target", str(site), "-r", str(requirements)], check=True)
        # Generated console-script launchers contain a build-machine shebang. The
        # app only uses its explicit Python/bootstrap entry point; do not ship them.
        if (site / "bin").exists():
            shutil.rmtree(site / "bin")
        inventory = {}
        for path in sorted(site.rglob("*")):
            if path.is_file():
                with path.open("rb") as stream:
                    native = stream.read(4) in MAGICS
                inventory[str(path.relative_to(staged))] = {"sha256": sha(path), "native": native}
        weights = [p for p in site.rglob("*.pth") if p.stat().st_size > 1_000_000]
        assert weights, "TransNet model weights absent from dependency closure"
        manifest = {"schema": 1, "lockSHA256": sha(LOCK), "architecture": "arm64", "python": "3.11",
                    "packages": lock["packages"], "models": [str(p.relative_to(staged)) for p in weights],
                    "files": inventory}
        (staged / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        shutil.copy2(LOCK, staged / LOCK.name)
        shutil.copytree(staged, destination, dirs_exist_ok=True)
        print(f"Bundled {len(downloaded)} wheels, {len(inventory)} files, models: {manifest['models']}")


if __name__ == "__main__":
    main()
