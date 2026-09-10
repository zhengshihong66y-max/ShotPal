#!/usr/bin/env python3
"""Explicit online acceptance using ShazamIO's public Gloria fixture, not user media."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument("app", type=Path)
parser.add_argument("fixture", type=Path)
parser.add_argument("--report", type=Path, required=True)
args = parser.parse_args()
app = args.app.resolve()
fixture = args.fixture.resolve()
quote = lambda p: json.dumps(str(p), ensure_ascii=False)
profile = f'''(version 1) (allow default)
 (deny process-exec (require-not (subpath {quote(app)})))
 (deny file-read* (subpath "/opt/homebrew") (subpath "/usr/local")
  (require-all (subpath {quote(Path.home())}) (require-not (subpath {quote(app)}))))
 (deny file-write* (subpath {quote(Path.home())}))'''
with tempfile.TemporaryDirectory(prefix="lapianbao-public-song-") as temp:
    env = {"HOME": temp, "CFFIXED_USER_HOME": temp, "TMPDIR": temp, "PATH": "/nonexistent",
           "LANG": "en_US.UTF-8", "PYTHONHOME": "/nonexistent", "PYTHONPATH": "/nonexistent",
           "LAPIANBAO_MUSIC_MAX_SEGMENTS": "1", "LAPIANBAO_MUSIC_RECOGNIZE_TIMEOUT": "20"}
    start = time.monotonic()
    result = subprocess.run(["/usr/bin/sandbox-exec", "-p", profile,
                             str(app / "Contents/MacOS/拉片宝"), "--lapianbao-music-runtime-check", str(fixture)],
                            env=env, cwd=temp, capture_output=True, text=True, timeout=90)
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        payload = {"status": "failed", "output": result.stdout}
    passed = result.returncode == 0 and payload.get("status") == "succeeded" and any(
        s.get("title") == "I Will Survive" and s.get("artist") == "Gloria Gaynor" for s in payload.get("songs", []))
    report = {"passed": passed, "app": str(app), "seconds": round(time.monotonic()-start, 3),
              "fixture": "https://github.com/shazamio/ShazamIO/blob/b5321b5c15d88ed98663420e63916704c6537512/examples/data/Gloria.ogg",
              "fixtureSHA256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
              "exitCode": result.returncode, "result": payload, "stderr": result.stderr,
              "userMediaUsed": False, "externalExecutablesDenied": True, "realHomeReadsOutsideAppDenied": True}
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    raise SystemExit(0 if passed else 1)
