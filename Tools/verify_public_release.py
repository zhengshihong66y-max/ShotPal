#!/usr/bin/env python3
"""Verify a finalized DMG; never sign, notarize, upload, or bypass Gatekeeper.

Creates a checksum only after trust, payload, and mounted-runtime checks pass.
This host check does not replace clean-machine/manual acceptance.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MODEL = 'RuntimeTools.bundle/Contents/Resources/Tools/whisper.cpp/models/ggml-large-v3-turbo-q5_0.bin'


def run(*command):
    return subprocess.check_output(list(map(str, command)), stderr=subprocess.STDOUT)


def require_developer_id(details):
    if 'Authority=Developer ID Application:' not in details or 'Signature=adhoc' in details:
        raise ValueError('Public distribution requires a Developer ID Application signature.')


def validate_payload(app):
    app = app.resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    resources = app / 'Contents/Resources'
    for language in ('en', 'zh-Hans'):
        for name in ('Localizable.strings', 'InfoPlist.strings'):
            path = resources / f'{language}.lproj' / name
            if not path.is_file() or not path.resolve().is_relative_to(app):
                raise ValueError(f'Missing or external localization: {path}')
    model = resources / MODEL
    if not model.is_file() or not model.resolve().is_relative_to(app) or model.stat().st_size < 100_000_000:
        raise ValueError('Bundled Whisper model is missing, external, or incomplete.')
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    if not executable.is_file() or not executable.resolve().is_relative_to(app):
        raise ValueError('App executable is missing or external.')
    return info


def verify(dmg):
    dmg = dmg.resolve(strict=True)
    if dmg.suffix.lower() != '.dmg':
        raise ValueError('Expected a finalized .dmg file.')
    require_developer_id(run('/usr/bin/codesign', '-dvv', dmg).decode())
    run('/usr/bin/codesign', '--verify', '--strict', dmg)
    run('/usr/bin/xcrun', 'stapler', 'validate', dmg)
    run('/usr/sbin/spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', dmg)
    with tempfile.TemporaryDirectory(prefix='shotpal-final-dmg-') as temp:
        mount = Path(temp) / 'mount'
        mount.mkdir()
        run('/usr/bin/hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mount, dmg)
        try:
            apps = list(mount.glob('*.app'))
            if len(apps) != 1:
                raise ValueError('Installer must contain exactly one top-level application.')
            app = apps[0]
            applications = mount / 'Applications'
            if not applications.is_symlink() or applications.resolve() != Path('/Applications'):
                raise ValueError('Installer must include a drag-to-Applications shortcut.')
            require_developer_id(run('/usr/bin/codesign', '-dvv', app).decode())
            run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
            run('/usr/sbin/spctl', '--assess', '--type', 'execute', app)
            info = validate_payload(app)
            executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
            for language in ('en', 'zh-Hans'):
                report = json.loads(run(executable, '--lapianbao-localization-check', '-AppleLanguages', f'({language})'))
                if report.get('status') != 'passed':
                    raise ValueError(f'Localization checks failed: {language}')
            for script in ('verify_download_runtime.py', 'verify_recognition_runtime.py'):
                run(sys.executable, ROOT / 'Tools' / script, app)
        finally:
            run('/usr/bin/hdiutil', 'detach', mount)
    digest = hashlib.sha256()
    with dmg.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    checksum = dmg.with_suffix('.dmg.sha256')
    checksum.write_text(f'{digest.hexdigest()}  {dmg.name}\n')
    print(f'Final installer checks passed: {dmg.name}')
    print(f'SHA-256: {checksum}')
    print('Clean-machine and manual acceptance remain separate release requirements.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dmg', type=Path)
    args = parser.parse_args()
    try:
        verify(args.dmg)
    except subprocess.CalledProcessError as error:
        raise SystemExit(f'Release verification failed:\n{error.output.decode(errors="replace")}') from error
    except (ValueError, OSError, KeyError) as error:
        raise SystemExit(f'Release verification failed: {error}') from error


if __name__ == '__main__':
    main()
