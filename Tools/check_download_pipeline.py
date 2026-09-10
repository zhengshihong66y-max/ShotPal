#!/usr/bin/env python3
"""Deterministic real HTTP download/merge/transcode through the built app.

Creates synthetic media in a temporary folder; never reads user cookies or libraries.
"""
import argparse
import functools
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    app = args.app.resolve()
    tools = app / "Contents/Resources/RuntimeTools.bundle/Contents/Resources/Tools"
    ffmpeg = tools / "bin/ffmpeg"
    ffprobe = tools / "bin/ffprobe"
    executable = app / "Contents/MacOS/拉片宝"
    checks = []
    with tempfile.TemporaryDirectory(prefix="LapianBao 下载验收 ") as directory:
        root = Path(directory)
        public = root / "server"
        public.mkdir()
        env = {"HOME": str(root / "home"), "CFFIXED_USER_HOME": str(root / "home"),
               "PATH": "/nonexistent-host-tools", "LANG": "en_US.UTF-8", "TMPDIR": directory,
               "DENO_NO_UPDATE_CHECK": "1", "NO_PROXY": "127.0.0.1,localhost",
               "HTTP_PROXY": "", "HTTPS_PROXY": "", "ALL_PROXY": ""}
        (root / "home").mkdir()
        common = [str(ffmpeg), "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24",
                  "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100", "-t", "2", "-threads", "2"]
        subprocess.run(common + ["-c:v", "libx264", "-c:a", "aac", str(public / "sample.mp4")], check=True, timeout=30)
        subprocess.run(common + ["-c:v", "libvpx-vp9", "-deadline", "realtime", "-c:a", "libopus", str(public / "sample.webm")], check=True, timeout=30)
        subprocess.run(common + ["-c:v", "libx264", "-c:a", "aac", "-f", "dash", str(public / "manifest.mpd")], check=True, timeout=30)

        class QuietHandler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *_):
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(QuietHandler, directory=str(public)))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            for fixture in ("sample.mp4", "sample.webm", "manifest.mpd"):
                url = f"http://127.0.0.1:{server.server_port}/{fixture}"
                result = subprocess.run([str(executable), "--lapianbao-downloader-runtime-check", "--source", url,
                                         "--destination", str(root / fixture.replace(".", "-"))],
                                        env=env, cwd=directory, capture_output=True, text=True, timeout=180)
                try:
                    report = json.loads(result.stdout)
                except json.JSONDecodeError:
                    report = {"status": "failed", "stdout": result.stdout, "stderr": result.stderr}
                if path := report.get("downloadedPath"):
                    probe = json.loads(subprocess.check_output([str(ffprobe), "-v", "error", "-show_streams", "-of", "json", path]))
                    report["streams"] = [{"type": s.get("codec_type"), "codec": s.get("codec_name")} for s in probe["streams"]]
                    report["downloadedBytes"] = Path(path).stat().st_size
                    if not any(s.get("codec_name") == "h264" for s in probe["streams"]):
                        report["status"] = "failed"
                        report.setdefault("failures", []).append("Output was not transcoded/retained as H264")
                    if not any(s.get("codec_type") == "audio" for s in probe["streams"]):
                        report["status"] = "failed"
                        report.setdefault("failures", []).append("Audio stream missing")
                checks.append({"fixture": fixture, "exitCode": result.returncode, "report": report})
        finally:
            server.shutdown()
            server.server_close()
    report = {"status": "passed" if all(c["exitCode"] == 0 and c["report"]["status"] == "passed" for c in checks) else "failed",
              "scope": "Synthetic HTTP fixtures on current host, not platform/M4 certification", "checks": checks}
    text = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.report:
        args.report.write_text(text)
    print(text)
    raise SystemExit(report["status"] != "passed")


if __name__ == "__main__":
    main()
