#!/usr/bin/env python3
"""Inspect/test the actual app, offline and with external tool execution denied.

This is a host-local isolation test, NOT a clean macOS/M4 compatibility claim.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import subprocess
import tempfile
import zipfile


def dylib_dependencies(load_commands):
    """LC_ID_DYLIB names the library itself; it is not a runtime dependency.

    Wheel builders may retain a build-prefix ID while consumers correctly use
    @loader_path. Only actual load/re-export commands describe required files.
    """
    command = None
    for line in load_commands.splitlines():
        line = line.strip()
        if line.startswith("cmd "):
            command = line.split()[1]
        elif line.startswith("name ") and command in {
            "LC_LOAD_DYLIB", "LC_LOAD_WEAK_DYLIB", "LC_REEXPORT_DYLIB",
            "LC_LAZY_LOAD_DYLIB", "LC_LOAD_UPWARD_DYLIB",
        }:
            yield line[5:].rsplit(" (offset ", 1)[0]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    app = args.app.resolve()
    tools = app / "Contents/Resources/RuntimeTools.bundle/Contents/Resources/Tools"
    manifest = json.loads((tools / "downloader-manifest.json").read_text())
    checks = []
    failures = []
    paths = {name: tools / f"bin/{name}" for name in ("yt-dlp", "deno", "ffmpeg", "ffprobe")}
    paths["python"] = tools / "python/cpython-3.11-aarch64-apple-darwin/bin/python3.11"
    for name, path in paths.items():
        if not path.is_file() or not os.access(path, os.X_OK):
            failures.append(f"Missing/non-executable bundled {name}: {path}")
        elif not path.resolve().is_relative_to(app):
            failures.append(f"Bundled {name} symlink escapes app")
    if failures:
        raise SystemExit("\n".join(failures))
    archive_hash = hashlib.sha256(paths["yt-dlp"].read_bytes()).hexdigest()
    if archive_hash != manifest["assets"]["yt-dlp"]["unsignedSHA256"]:
        failures.append("yt-dlp archive checksum differs from pinned release")
    with zipfile.ZipFile(paths["yt-dlp"]) as archive:
        if not any(n.startswith("yt_dlp_ejs/") and n.endswith(".js") for n in archive.namelist()):
            failures.append("Bundled EJS scripts absent")
        else:
            checks.append({"name": "embedded-EJS", "passed": True})

    # Deny every executable outside the app, plus network and common developer runtimes.
    # JSON quoting also escapes spaces/Chinese characters safely in the sandbox profile.
    quoted_app = json.dumps(str(app), ensure_ascii=False)
    profile = f'''(version 1) (allow default)
      (deny network*)
      (deny process-exec (require-not (subpath {quoted_app})))
      (deny file-read* (subpath "/opt/homebrew") (subpath "/usr/local")
                       (subpath "/Applications/Xcode.app") (subpath "/Library/Developer"))'''
    with tempfile.TemporaryDirectory(prefix="LapianBao-runtime-check-") as temp:
        env = {"HOME": temp, "CFFIXED_USER_HOME": temp, "TMPDIR": temp,
               "PATH": "/nonexistent-lapianbao-host-tools", "LANG": "en_US.UTF-8",
               "PYTHONHOME": "/nonexistent-poison-python", "PYTHONPATH": "/nonexistent-poison-modules",
               "DENO_NO_UPDATE_CHECK": "1"}

        def run(name, command, expected=None, timeout=60):
            try:
                result = subprocess.run(["/usr/bin/sandbox-exec", "-p", profile] + list(map(str, command)),
                                        env=env, cwd=temp, capture_output=True, text=True, timeout=timeout)
                passed = result.returncode == 0 and (expected is None or expected in result.stdout)
                checks.append({"name": name, "passed": passed, "exitCode": result.returncode,
                               "stdout": result.stdout[-12000:], "stderr": result.stderr[-3000:]})
                if not passed:
                    failures.append(name)
                return result
            except subprocess.TimeoutExpired:
                failures.append(name + " timed out")
                checks.append({"name": name, "passed": False, "timedOut": True})

        run("bundled-python+yt-dlp", [paths["python"], "-I", "-B", paths["yt-dlp"],
                                    "--ignore-config", "--version"], manifest["ytDLPVersion"])
        run("bundled-deno-real-JS", [paths["deno"], "eval", "--no-config", "--no-lock",
                                    "console.log(Array.from({length: 1000}, (_, i) => i).reduce((a,b) => a+b, 0))"], "499500")
        run("bundled-ffmpeg", [paths["ffmpeg"], "-version"], "ffmpeg version")
        run("bundled-ffprobe", [paths["ffprobe"], "-version"], "ffprobe version")
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
        result = run("app-offline-self-check", [executable, "--lapianbao-self-check"], '"succeeded"')
        if result and result.returncode == 0:
            report = json.loads(result.stdout)
            if Path(report.get("ytdlpPath", "/missing")) != paths["yt-dlp"]:
                failures.append("App selected a non-bundled downloader")
        run("app-progress-regression", [executable, "--lapianbao-download-progress-check"], '"succeeded"')
        if (Path(temp) / "Library/Application Support/LapianBao/Tools/yt-dlp").exists():
            failures.append("First-launch bootstrap unexpectedly installed yt-dlp")
        managed = Path(temp) / "Library/Application Support/LapianBao/Tools/yt-dlp"
        managed.parent.mkdir(parents=True, exist_ok=True)
        managed.write_bytes(b"broken update archive")
        managed.chmod(0o755)
        receipt = managed.with_name("yt-dlp.verified.json")
        for name, digest in [
            ("interrupted-update-receipt-mismatch", "0" * 64),
            ("incompatible-verified-update", hashlib.sha256(managed.read_bytes()).hexdigest()),
        ]:
            receipt.write_text(json.dumps({"version": "2099.01.01", "sha256": digest}))
            result = run(name, [executable, "--lapianbao-self-check"], '"succeeded"')
            if result and result.returncode == 0 and Path(json.loads(result.stdout).get("ytdlpPath", "/missing")) != paths["yt-dlp"]:
                failures.append(name + " did not fall back to bundled runtime")

    # Verify the dynamic-library closure of every embedded Mach-O, not just its entry point.
    macho_magics = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}
    macho_count = 0
    for path in tools.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        with path.open("rb") as stream:
            if stream.read(4) not in macho_magics:
                continue
        macho_count += 1
        linked = subprocess.check_output(["/usr/bin/otool", "-l", str(path)], text=True)
        for dependency in dylib_dependencies(linked):
            if dependency.startswith("/") and not dependency.startswith(("/usr/lib/", "/System/Library/")):
                failures.append(f"External dylib: {path.relative_to(app)} -> {dependency}")
    checks.append({"name": "embedded-MachO-system-only-dylibs", "count": macho_count})
    report = {"status": "failed" if failures else "passed", "app": str(app),
              "host": platform.platform(), "machine": platform.machine(),
              "scope": "Offline sandbox test on this host; not clean macOS or M4 certification",
              "checks": checks, "failures": failures,
              "packagedSHA256": {k: hashlib.sha256(v.read_bytes()).hexdigest() for k, v in paths.items()}}
    encoded = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.report:
        args.report.write_text(encoded)
    print(encoded)
    raise SystemExit(bool(failures))


if __name__ == "__main__":
    main()
