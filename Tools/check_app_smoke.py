#!/usr/bin/env python3
"""Run existing deterministic app checks with disposable settings and files."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("app", type=Path)
parser.add_argument("--report", type=Path, required=True)
args = parser.parse_args()
checks = []
for name in ["import-panel", "annotation-save", "scene-timeline", "scene-cache-restore", "drag-provider"]:
    with tempfile.TemporaryDirectory(prefix="LapianBao-smoke-") as temp:
        result = subprocess.run([str(args.app.resolve() / "Contents/MacOS/拉片宝"), f"--lapianbao-{name}-check"],
                                env={"HOME": temp, "CFFIXED_USER_HOME": temp, "TMPDIR": temp,
                                     "PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"},
                                cwd=temp, capture_output=True, text=True, timeout=60)
        checks.append({"name": name, "exitCode": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
report = {"status": "passed" if all(c["exitCode"] == 0 for c in checks) else "failed", "checks": checks,
          "scope": "Existing deterministic guards; not a full manual media-workflow acceptance"}
text = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
args.report.write_text(text)
print(text)
raise SystemExit(report["status"] != "passed")
