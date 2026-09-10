#!/usr/bin/env python3
"""Fail the build before copying an incomplete or unpinned downloader bundle."""
import hashlib
import json
from pathlib import Path
import zipfile

tools = Path(__file__).resolve().parents[1] / "LapianBao/RuntimeTools.bundle/Contents/Resources/Tools"
manifest = json.loads((tools / "downloader-manifest.json").read_text())
for name, asset in manifest["assets"].items():
    path = tools / asset["path"]
    assert path.is_file(), f"Required bundled {name} is missing; run Tools/prepare_download_runtime.py"
    assert hashlib.sha256(path.read_bytes()).hexdigest() == asset["unsignedSHA256"], f"Unverified bundled {name}"
for relative in ["bin/ffmpeg", "bin/ffprobe", "python/cpython-3.11-aarch64-apple-darwin/bin/python3.11",
                 "licenses/yt-dlp-Unlicense.txt", "licenses/yt-dlp-THIRD-PARTY.txt",
                 "licenses/deno-MIT.txt", "licenses/deno-THIRD-PARTY.txt"]:
    assert (tools / relative).is_file(), f"Required download runtime resource missing: {relative}"
with zipfile.ZipFile(tools / "bin/yt-dlp") as archive:
    assert any(n.startswith("yt_dlp_ejs/") and n.endswith(".js") for n in archive.namelist()), "EJS missing"
print("Pinned downloading runtime build inputs verified")
