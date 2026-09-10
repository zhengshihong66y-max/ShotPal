#!/usr/bin/env python3
"""Fetch pinned official downloader assets at BUILD time, never on first launch."""
import hashlib
import io
import json
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "LapianBao/RuntimeTools.bundle/Contents/Resources/Tools"
ASSETS = {
    "yt-dlp": ("https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/download/2026.08.29.232711/yt-dlp",
               "e8bc4155d3af4fa4fa8efbb5146790f6e9da48266d103eea859de8a44ba194ad"),
    "deno": ("https://github.com/denoland/deno/releases/download/v2.9.6/deno-aarch64-apple-darwin.zip",
             "213a2f304f04d3c9cb5220669afad138f60a5aab1fe80962abdeb8f35807a472"),
}


def fetch(url):
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read()


def main():
    manifest = {"schemaVersion": 1, "architecture": "arm64", "firstLaunchDownloads": False,
                "ytDLPVersion": "2026.08.29.232711", "denoVersion": "2.9.6", "assets": {}}
    for name, (url, expected) in ASSETS.items():
        target = TOOLS / "bin" / name
        prepared_hash = "b3ac3bd206e48c26026cadd80c1367e96c149f9c66130952382a642b09fa8a71" if name == "deno" else expected
        data = target.read_bytes() if target.is_file() else b""
        if hashlib.sha256(data).hexdigest() != prepared_hash:
            data = fetch(url)
            if hashlib.sha256(data).hexdigest() != expected:
                raise SystemExit(f"SHA256 mismatch: {name}")
            if name == "deno":
                data = zipfile.ZipFile(io.BytesIO(data)).read("deno")
        if name == "yt-dlp":
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                assert any(n.startswith("yt_dlp_ejs/") for n in archive.namelist()), "EJS absent"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        target.chmod(0o755)
        manifest["assets"][name] = {"path": f"bin/{name}", "sourceURL": url,
                                    "downloadSHA256": expected, "unsignedSHA256": hashlib.sha256(data).hexdigest()}
        print(f"Verified and embedded {name}", flush=True)
    licenses = TOOLS / "licenses"
    licenses.mkdir(exist_ok=True)
    for name, url in {
        "yt-dlp-Unlicense.txt": "https://raw.githubusercontent.com/yt-dlp/yt-dlp/2f3929ba1a79996779deb4ad0d7b11368ca355ac/LICENSE",
        "yt-dlp-THIRD-PARTY.txt": "https://raw.githubusercontent.com/yt-dlp/yt-dlp/2f3929ba1a79996779deb4ad0d7b11368ca355ac/THIRD_PARTY_LICENSES.txt",
        "deno-MIT.txt": "https://raw.githubusercontent.com/denoland/deno/v2.9.6/LICENSE.md",
    }.items():
        (licenses / name).write_bytes(fetch(url))
    v8_urls = [
        "https://raw.githubusercontent.com/denoland/rusty_v8/v150.4.0/LICENSE",
        "https://raw.githubusercontent.com/denoland/v8/ac1e23989121713ca642f6650b34deff7b686896/LICENSE",
    ]
    (licenses / "deno-THIRD-PARTY.txt").write_bytes(b"\n\n".join(url.encode() + b"\n" + fetch(url) for url in v8_urls))
    (TOOLS / "downloader-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
