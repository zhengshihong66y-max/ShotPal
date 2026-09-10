#!/usr/bin/env python3
"""Anonymous live extractor probes. They do not read browser cookies or certify all links."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile

SAMPLES = {
    "YouTube": "https://www.youtube.com/watch?v=YE7VzlLtp-4",
    "Bilibili": "https://www.bilibili.com/video/BV13x41117TL",
    "Douyin": "https://www.douyin.com/video/6961737553342991651",
    "Xiaohongshu": "https://www.xiaohongshu.com/explore/6411cf99000000001300b6d9",
    "Instagram": "https://www.instagram.com/reel/Chunk8-jurw/",
}


def run_bounded(command, *, env, cwd, timeout):
    """Confine timeout cleanup to this test's own new process group."""
    with subprocess.Popen(command, env=env, cwd=cwd, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, start_new_session=True) as process:
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            for sig in (signal.SIGTERM, signal.SIGKILL):
                try:
                    os.killpg(process.pid, sig)
                except ProcessLookupError:
                    pass
                try:
                    process.communicate(timeout=2)
                    # A descendant can close inherited pipes while still running.
                    # Ensure none survives merely because the parent exited first.
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    break
                except subprocess.TimeoutExpired:
                    continue
            raise
        return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--download-instagram", action="store_true")
    parser.add_argument("--download-platform", action="append", choices=list(SAMPLES), default=[],
                        help="Also test the real app download entry point for this sample")
    parser.add_argument("--download-timeout", type=int, default=240)
    args = parser.parse_args()
    tools = args.app.resolve() / "Contents/Resources/RuntimeTools.bundle/Contents/Resources/Tools"
    command = [str(tools / "python/cpython-3.11-aarch64-apple-darwin/bin/python3.11"), "-I", "-B", str(tools / "bin/yt-dlp"),
               "--ignore-config", "--no-plugin-dirs", "--no-js-runtimes", "--js-runtimes", f"deno:{tools / 'bin/deno'}",
               "--no-remote-components", "--ffmpeg-location", str(tools / "bin"), "--no-playlist",
               "--socket-timeout", "8", "--retries", "0", "--extractor-retries", "0",
               "--simulate", "--verbose", "--print", "%(extractor)s:%(id)s"]

    def probe(item):
        name, url = item
        with tempfile.TemporaryDirectory(prefix="LapianBao-platform-probe-") as temp:
            env = {"HOME": temp, "CFFIXED_USER_HOME": temp, "TMPDIR": temp,
                   "PATH": str(tools / "bin") + ":/usr/bin:/bin", "LANG": "en_US.UTF-8", "DENO_NO_UPDATE_CHECK": "1"}
            try:
                result = subprocess.run(command + [url], env=env, cwd=temp, capture_output=True, text=True, timeout=45)
                log = re.sub(r'https?://[^\s"<>]+', '[URL]', result.stderr)
                return {"platform": name, "sample": url, "status": "extraction-passed" if result.returncode == 0 else "failed",
                        "exitCode": result.returncode, "stdout": result.stdout, "diagnostic": log[-9000:],
                        "fullDownloadTested": False, "authentication": "anonymous; no user cookies accessed"}
            except subprocess.TimeoutExpired:
                return {"platform": name, "sample": url, "status": "timed-out", "fullDownloadTested": False}

    with ThreadPoolExecutor(max_workers=3) as executor:
        checks = list(executor.map(probe, SAMPLES.items()))
    report = {"scope": "Anonymous upstream test samples, current host/network, extraction only", "checks": checks}
    selected = list(dict.fromkeys(args.download_platform + (["Instagram"] if args.download_instagram else [])))
    for platform_name in selected:
        with tempfile.TemporaryDirectory(prefix="LapianBao-live-download-") as temp:
            env = {"HOME": temp, "CFFIXED_USER_HOME": temp, "TMPDIR": temp,
                   "PATH": "/nonexistent-host-tools", "LANG": "en_US.UTF-8"}
            executable = args.app.resolve() / "Contents/MacOS/拉片宝"
            try:
                result = run_bounded([str(executable), "--lapianbao-downloader-runtime-check", "--source", SAMPLES[platform_name],
                                         "--destination", str(Path(temp) / "library"),
                                         # HOME does not isolate cfprefsd. NSArgumentDomain
                                         # overrides saved settings without writing them.
                                         "-youtubeCookieFilePath", str(Path(temp) / "no-cookie-file.txt"),
                                         "-youtubeCookieFileBookmark", ""], env=env, cwd=temp,
                                        timeout=args.download_timeout)
                outcome = json.loads(result.stdout)
                outcome["exitCode"] = result.returncode
                outcome["authentication"] = "Saved cookie preferences overridden for this process; no browser export"
                if path := outcome.get("downloadedPath"):
                    outcome["downloadedBytes"] = Path(path).stat().st_size
                    outcome["mediaProbe"] = json.loads(subprocess.check_output([str(tools / "bin/ffprobe"), "-v", "error",
                        "-show_entries", "stream=codec_name,codec_type:format=duration,size", "-of", "json", path]))
                report.setdefault("fullAppDownloads", {})[platform_name] = outcome
            except (subprocess.TimeoutExpired, json.JSONDecodeError) as error:
                report.setdefault("fullAppDownloads", {})[platform_name] = {"status": "not-passed", "reason": str(error)}
    if "Instagram" in report.get("fullAppDownloads", {}):
        report["instagramFullAppDownload"] = report["fullAppDownloads"]["Instagram"]
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
