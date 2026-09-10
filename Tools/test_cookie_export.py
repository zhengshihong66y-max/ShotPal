#!/usr/bin/env python3
"""Exercise the production export script with bundled yt-dlp and synthetic cookies.

The browser extraction function is stubbed before the script runs. Network access
is denied in-process; no browser databases, Keychain items or credentials are read.
"""
import re
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "LapianBao/RuntimeTools.bundle/Contents/Resources/Tools"
SOURCE = (ROOT / "LapianBao/Stores/YouTubeCookieStore.swift").read_text()
SCRIPT = textwrap.dedent(re.search(r'cookieExportScript = """\n(.*?)\n    """', SOURCE, re.S).group(1))
PYTHON = TOOLS / "python/cpython-3.11-aarch64-apple-darwin/bin/python3.11"
ARCHIVE = TOOLS / "bin/yt-dlp"


class CookieExportTests(unittest.TestCase):
    def run_export(self, mode, destination):
        bootstrap = '''
import sys, socket
sys.path.insert(0, sys.argv[1])
import yt_dlp.cookies as cookies
from http.cookiejar import Cookie
def deny_network(*args, **kwargs):
    raise AssertionError("cookie export attempted network access")
socket.socket = deny_network
def fixture(browser, profile, logger, keyring=None, container=None):
    assert browser == "chrome" and profile is None
    if MODE == "failure":
        raise RuntimeError("fixture Keychain access denied")
    jar = cookies.YoutubeDLCookieJar()
    if MODE == "empty":
        logger.warning("fixture failed to decrypt cookies")
    else:
        jar.set_cookie(Cookie(0, "fixture", "synthetic", None, False, ".youtube.com", True, True,
                            "/", True, True, 4102444800, False, None, None, {}, False))
    return jar
cookies.extract_cookies_from_browser = fixture
exec(PRODUCTION_SCRIPT)
'''
        code = "MODE = " + repr(mode) + "\nPRODUCTION_SCRIPT = " + repr(SCRIPT) + "\n" + textwrap.dedent(bootstrap)
        return subprocess.run([str(PYTHON), "-I", "-B", "-c", code, str(ARCHIVE), "chrome", str(destination)],
                              capture_output=True, text=True, timeout=30)

    def test_export_without_network(self):
        with tempfile.TemporaryDirectory(prefix="lapianbao-cookie-fixture-") as temp:
            destination = Path(temp) / "export.txt"
            result = self.run_export("success", destination)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(".youtube.com", destination.read_text())
            self.assertEqual(destination.stat().st_mode & 0o777, 0o600)

    def test_decryption_warning_is_not_hidden(self):
        with tempfile.TemporaryDirectory(prefix="lapianbao-cookie-fixture-") as temp:
            destination = Path(temp) / "export.txt"
            result = self.run_export("empty", destination)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("failed to decrypt", result.stderr)
            self.assertNotIn("synthetic", destination.read_text())

    def test_failed_export_does_not_touch_existing_cookie_file(self):
        with tempfile.TemporaryDirectory(prefix="lapianbao-cookie-fixture-") as temp:
            saved = Path(temp) / "browser-cookies.txt"
            saved.write_text("existing synthetic fixture")
            result = self.run_export("failure", Path(temp) / "browser-cookies.txt.refresh")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Keychain access denied", result.stderr)
            self.assertEqual(saved.read_text(), "existing synthetic fixture")


if __name__ == "__main__":
    unittest.main()
