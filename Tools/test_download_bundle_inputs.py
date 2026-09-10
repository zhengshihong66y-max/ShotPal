#!/usr/bin/env python3
"""Negative packaging tests in a disposable tree; do not mutate real assets."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source_tools = root / "LapianBao/RuntimeTools.bundle/Contents/Resources/Tools"
with tempfile.TemporaryDirectory(prefix="LapianBao-negative-package-") as directory:
    fixture = Path(directory)
    (fixture / "Tools").mkdir()
    script = fixture / "Tools/check_download_bundle_inputs.py"
    shutil.copy2(root / "Tools/check_download_bundle_inputs.py", script)
    resources = fixture / "LapianBao/RuntimeTools.bundle/Contents/Resources/Tools"
    (resources / "bin").mkdir(parents=True)
    shutil.copy2(source_tools / "downloader-manifest.json", resources / "downloader-manifest.json")

    def must_fail(message):
        result = subprocess.run([sys.executable, str(script)], capture_output=True, text=True)
        assert result.returncode != 0 and message in result.stderr, result.stderr
        return {"expectedFailure": message, "passed": True}

    checks = [must_fail("Required bundled yt-dlp is missing")]
    (resources / "bin/yt-dlp").write_bytes(b"invalid archive")
    checks.append(must_fail("Unverified bundled yt-dlp"))
    shutil.copy2(source_tools / "bin/yt-dlp", resources / "bin/yt-dlp")
    checks.append(must_fail("Required bundled deno is missing"))
    (resources / "bin/deno").write_bytes(b"invalid Deno")
    checks.append(must_fail("Unverified bundled deno"))
    print(json.dumps({"status": "passed", "checks": checks}, indent=2))
