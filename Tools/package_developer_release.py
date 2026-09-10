#!/usr/bin/env python3
"""Archive committed source plus complete local runtime; never upload credentials."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]


def git(*args, cwd=ROOT):
    return subprocess.check_output(["git", *args], cwd=cwd)


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        raise SystemExit("Refusing to overwrite an existing archive")
    if git("status", "--porcelain").strip():
        raise SystemExit("Commit the intended source changes before packaging")
    revision = git("rev-parse", "HEAD").decode().strip()
    paths = {ROOT / os.fsdecode(p) for p in git("ls-files", "-z").split(b"\0") if p}
    submodule = ROOT / "Tools/whisper.cpp"
    subrevision = git("rev-parse", "HEAD", cwd=submodule).decode().strip()
    if git("status", "--porcelain", cwd=submodule).strip():
        raise SystemExit("Whisper submodule contains uncommitted changes")
    paths.discard(submodule)
    paths.update(submodule / os.fsdecode(p) for p in git("ls-files", "-z", cwd=submodule).split(b"\0") if p)
    runtime = ROOT / "LapianBao/RuntimeTools.bundle"
    paths.update(p for p in runtime.rglob("*") if p.is_file() or p.is_symlink())
    paths = sorted(p for p in paths if not any(
        part in {".git", ".DS_Store", "__pycache__"} for part in p.relative_to(ROOT).parts
    ) and p.suffix not in {".pyc", ".pyo"})
    records = {}
    for path in paths:
        relative = str(path.relative_to(ROOT))
        if path.is_symlink():
            if not path.resolve().is_relative_to(ROOT):
                raise SystemExit(f"External symlink cannot be packaged: {relative}")
            records[relative] = {"symlink": os.readlink(path)}
        elif path.is_file():
            records[relative] = {"bytes": path.stat().st_size, "sha256": sha(path)}
        else:
            raise SystemExit(f"Expected source file is missing: {relative}")
    manifest = {"schema": 1, "gitRevision": revision, "whisperRevision": subrevision,
                "purpose": "Complete developer source and prepared runtime; no signing credentials",
                "files": records}
    output.parent.mkdir(parents=True, exist_ok=True)
    partial = output.with_name(output.name + ".partial")
    if partial.exists():
        raise SystemExit("Partial archive exists; inspect it before retrying")
    prefix = output.name.removesuffix(".tar.gz")
    with tarfile.open(partial, "w:gz", compresslevel=6, dereference=False) as archive:
        for path in paths:
            archive.add(path, arcname=f"{prefix}/{path.relative_to(ROOT)}", recursive=False)
        content = (json.dumps(manifest, indent=2) + "\n").encode()
        entry = tarfile.TarInfo(f"{prefix}/PACKAGE-MANIFEST.json")
        entry.size = len(content)
        entry.mode = 0o644
        archive.addfile(entry, io.BytesIO(content))
    if partial.stat().st_size >= 2 * 1024 ** 3:
        raise SystemExit("Archive exceeds GitHub's per-asset limit; partial retained for inspection")
    partial.rename(output)
    print(json.dumps({"archive": str(output), "bytes": output.stat().st_size,
                      "sha256": sha(output), "files": len(records), "gitRevision": revision}, indent=2))


if __name__ == "__main__":
    main()
