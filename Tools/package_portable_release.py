#!/usr/bin/env python3
"""Sign and package a new candidate without overwriting an existing installer.

Notarization submission is a separate explicit command; this script prints the DMG path.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

from verify_public_release import validate_payload

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run(list(map(str, args)), check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("--identity", required=True)
    parser.add_argument("--name", required=True)
    args = parser.parse_args()
    info = validate_payload(args.app)
    signing_options = [] if args.identity == "-" else ["--timestamp", "--options", "runtime"]
    if Path(args.name).name != args.name or args.name in {".", ".."} or not args.name:
        raise SystemExit("name must be a filename, not a path")
    stage = ROOT / "Dist" / (args.name + "-stage")
    dmg = ROOT / "Dist" / (args.name + ".dmg")
    if stage.exists() or dmg.exists():
        raise SystemExit("Refusing to overwrite an existing staging folder or DMG")
    stage.mkdir(parents=True)
    app = stage / "拉片宝.app"
    shutil.copytree(args.app, app, symlinks=True)
    (stage / "Applications").symlink_to("/Applications")
    magics = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}
    machos = []
    for path in app.rglob("*"):
        if path.is_file() and not path.is_symlink():
            with path.open("rb") as stream:
                if stream.read(4) in magics:
                    machos.append(path)
    for path in sorted(machos, key=lambda p: len(p.parts), reverse=True):
        command = ["/usr/bin/codesign", "--force", "--sign", args.identity] + signing_options
        if path.name == "deno":
            command += ["--entitlements", str(ROOT / "Tools/deno-signing-entitlements.plist")]
        run(*command, path)
    # RuntimeTools.bundle is a resource directory without an Info.plist or bundle
    # executable. Its Mach-Os are signed above; the outer app seals its resources.
    run("/usr/bin/codesign", "--force", "--sign", args.identity, *signing_options, app)
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", app)
    evidence = ROOT / "Dist" / (args.name + "-evidence")
    evidence.mkdir()
    run(sys.executable, ROOT / "Tools/verify_download_runtime.py", app, "--report", evidence / "signed-runtime.json")
    run(sys.executable, ROOT / "Tools/check_download_pipeline.py", app, "--report", evidence / "signed-pipeline.json")
    run(sys.executable, ROOT / "Tools/verify_recognition_runtime.py", app, "--report", evidence / "signed-recognition.json")
    ui_report = subprocess.check_output([str(app / "Contents/MacOS/拉片宝"), "--lapianbao-ui-state-check"], text=True)
    (evidence / "ui-state.json").write_text(ui_report)
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    signature = subprocess.run(["/usr/bin/codesign", "-dvv", str(app)], capture_output=True, text=True, check=True).stderr
    signing = "Developer ID" if "Authority=Developer ID Application:" in signature else "local/development"
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip())
    record = {"version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
              "gitRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "includesUncommittedChanges": dirty, "signedMachOCount": len(machos),
              "signing": signing, "notarized": False,
              "status": "candidate; M4/macOS14 and full platform/manual acceptance pending"}
    (evidence / "build-record.json").write_text(json.dumps(record, indent=2) + "\n")
    run("/usr/bin/hdiutil", "create", "-volname", f"ShotPal Pro {info['CFBundleShortVersionString']}", "-srcfolder", stage,
        "-format", "UDZO", "-imagekey", "zlib-level=9", dmg)
    if args.identity != "-":
        run("/usr/bin/codesign", "--force", "--sign", args.identity, "--timestamp", dmg)
    print(f"Candidate DMG: {dmg}")
    print("Not ready for publication: notarize/staple, then run Tools/verify_public_release.py on the final DMG.")
    print(f"Pre-notarization SHA256: {hashlib.sha256(dmg.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    main()
