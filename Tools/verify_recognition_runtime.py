#!/usr/bin/env python3
"""Verify actual app recognition assets/workers, offline and without host tools.

This proves local isolation, not physical M4/macOS14 or online song matching.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import plistlib
import subprocess
import tempfile
import time
from check_recognition_bundle_inputs import validate


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    app = args.app.resolve()
    tools = app / "Contents/Resources/RuntimeTools.bundle/Contents/Resources/Tools"
    manifest = validate(tools, signed=True)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    python = tools / "python/cpython-3.11-aarch64-apple-darwin/bin/python3.11"
    bootstrap = [python, "-I", "-B", "-u", tools / "recognition_bootstrap.py"]
    quote = lambda p: json.dumps(str(p), ensure_ascii=False)
    checks = []
    profile = f'''(version 1) (allow default)
      (deny network*)
      (deny process-exec (require-not (subpath {quote(app)})))
      (deny file-read* (subpath "/opt/homebrew") (subpath "/usr/local")
                       (subpath "/Applications/Xcode.app") (subpath "/Library/Developer")
                       (require-all (subpath {quote(Path.home())}) (require-not (subpath {quote(app)}))))
      (deny file-write* (subpath {quote(Path.home())}))'''
    with tempfile.TemporaryDirectory(prefix="lapianbao-recognition-verify-") as temp:
        env = {"HOME": temp, "CFFIXED_USER_HOME": temp, "TMPDIR": temp, "LANG": "en_US.UTF-8",
               "PATH": str(tools / "bin") + ":/nonexistent-host-tools",
               "PYTHONHOME": "/nonexistent-poison", "PYTHONPATH": "/nonexistent-poison",
               "OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1", "MKL_NUM_THREADS": "1",
               "VECLIB_MAXIMUM_THREADS": "1", "LAPIANBAO_SCENE_DEVICE": "cpu",
               "LAPIANBAO_MUSIC_MAX_SEGMENTS": "1", "LAPIANBAO_MUSIC_RECOGNIZE_TIMEOUT": "2"}

        def run(name, command, expected_code=0, timeout=120):
            start = time.monotonic()
            try:
                result = subprocess.run(["/usr/bin/sandbox-exec", "-p", profile] + list(map(str, command)),
                                        env=env, cwd=temp, capture_output=True, text=True, timeout=timeout)
                check = {"name": name, "passed": result.returncode == expected_code,
                         "exitCode": result.returncode, "seconds": round(time.monotonic()-start, 3),
                         "stdout": result.stdout[-16000:], "stderr": result.stderr[-5000:]}
            except subprocess.TimeoutExpired:
                check = {"name": name, "passed": False, "timedOut": True}
            checks.append(check)
            return check

        run("app-music-native-fingerprint-offline", [executable, "--lapianbao-music-runtime-check"])
        run("app-scene-model-offline", [executable, "--lapianbao-scene-runtime-check"])
        video = Path(temp) / "three-shots.mp4"
        fixture = run("make-synthetic-shots", [tools / "bin/ffmpeg", "-v", "error", "-y",
            "-f", "lavfi", "-i", "color=red:s=320x180:r=25:d=2",
            "-f", "lavfi", "-i", "color=blue:s=320x180:r=25:d=2",
            "-f", "lavfi", "-i", "color=green:s=320x180:r=25:d=2",
            "-filter_complex", "[0:v][1:v][2:v]concat=n=3:v=1:a=0[v]", "-map", "[v]",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", video])
        if fixture["passed"]:
            inference = run("app-actual-scene-inference-cpu", [executable, "--lapianbao-scene-runtime-check", video])
            if inference["passed"]:
                cuts = json.loads(inference["stdout"])["cutTimes"]
                inference["passed"] = all(any(abs(cut - expected) <= .15 for cut in cuts) for expected in [0, 2, 4])
            automatic = run("actual-scene-inference-auto", bootstrap + ["scene", video, "--device", "auto"])
            if automatic["passed"]:
                payload = json.loads(automatic["stdout"])
                automatic["device"] = payload["device"]
                automatic["passed"] = all(any(abs(cut - expected) <= .15 for cut in payload["cut_times"]) for expected in [0, 2, 4])
        audio = Path(temp) / "synthetic-tone.wav"
        fixture = run("make-synthetic-audio", [tools / "bin/ffmpeg", "-v", "error", "-y", "-f", "lavfi",
                    "-i", "sine=frequency=440:duration=12", "-ac", "1", audio])
        if fixture["passed"]:
            failure = run("blocked-music-service-is-error-not-no-match", bootstrap + ["music", audio], expected_code=1, timeout=45)
            if failure["passed"]:
                events = [json.loads(line) for line in failure["stdout"].splitlines() if line.startswith("{")]
                failure["passed"] = any(e.get("code") == "recognition_incomplete" for e in events) and not any(e.get("type") == "done" for e in events)
            failure = run("app-blocked-music-service-is-error", [executable, "--lapianbao-music-runtime-check", audio], expected_code=1, timeout=45)
            if failure["passed"]:
                failure["passed"] = json.loads(failure["stdout"]).get("status") == "failed" and "服务" in failure["stdout"]
        assert not (Path(temp) / "Library/Application Support/LapianBao/PythonRuntimes").exists(), "Unexpected runtime installation"
    report = {"app": str(app), "build": info["CFBundleVersion"], "host": platform.platform(),
              "packages": len(manifest["packages"]), "files": len(manifest["files"]),
              "models": manifest["models"], "networkDenied": True, "externalExecutablesDenied": True,
              "realHomeReadsOutsideAppDenied": True, "checks": checks,
              "passed": all(c["passed"] for c in checks),
              "notTested": ["physical M4 Mac mini", "macOS 14 host", "online song match", "manual feature UI"]}
    if args.report:
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
