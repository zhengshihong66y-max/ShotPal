#!/usr/bin/env python3
"""Deterministic service/no-match classification tests; no requests/user media."""
import asyncio
import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

TOOLS = Path(sys.argv.pop(1)).resolve()
sys.path.insert(0, str(TOOLS / "recognition/site-packages"))
spec = importlib.util.spec_from_file_location("detect_music", TOOLS / "detect_music.py")
music = importlib.util.module_from_spec(spec)
spec.loader.exec_module(music)


class FakeShazam:
    def __init__(self, result=None, error=None):
        self.result, self.error = result, error

    async def recognize(self, _):
        if self.error:
            raise self.error
        return self.result


class RecognitionTests(unittest.IsolatedAsyncioTestCase):
    async def test_real_no_match(self):
        self.assertIsNone(await music.recognize(FakeShazam({"matches": []}), "synthetic"))

    async def test_connection_error_is_not_no_match(self):
        with self.assertRaises(music.RecognitionServiceError):
            await music.recognize(FakeShazam(error=ConnectionError("secret URL")), "synthetic")

    async def test_timeout_is_not_no_match(self):
        with self.assertRaises(music.RecognitionServiceError):
            await music.recognize(FakeShazam(error=asyncio.TimeoutError()), "synthetic")

    async def test_invalid_response_is_not_no_match(self):
        for result in [{"error": "unavailable"}, None, "bad"]:
            with self.assertRaises(music.RecognitionServiceError):
                await music.recognize(FakeShazam(result), "synthetic")

    async def test_match(self):
        result = await music.recognize(FakeShazam({"track": {"title": "Fixture", "subtitle": "Test"}}), "synthetic")
        self.assertEqual(result["title"], "Fixture")

    async def run_main(self, shazam, extraction=True):
        events = []
        with patch.object(music, "Shazam", return_value=shazam), patch.object(music, "get_duration", return_value=12), \
             patch.object(music, "extract_segment", return_value=extraction), patch.object(music, "emit", side_effect=events.append), \
             patch.object(sys, "argv", ["detect_music.py", __file__]):
            code = 0
            try:
                await music.main()
            except SystemExit as error:
                code = error.code
        return code, events

    async def test_main_all_service_errors_fail(self):
        code, events = await self.run_main(FakeShazam(error=ConnectionError()))
        self.assertEqual(code, 1)
        self.assertEqual(events[-1]["type"], "error")
        self.assertFalse(any(e["type"] == "done" for e in events))

    async def test_main_no_match_succeeds(self):
        code, events = await self.run_main(FakeShazam({"matches": []}))
        self.assertEqual(code, 0)
        self.assertEqual(events[-1], {"type": "done", "songs": []})

    async def test_no_audio_fails(self):
        code, events = await self.run_main(FakeShazam({"matches": []}), extraction=False)
        self.assertEqual(code, 1)
        self.assertEqual(events[-1]["type"], "error")

    async def test_partial_match_then_failure_is_incomplete(self):
        events = []
        results = [{"title": "Fixture", "artist": "Test", "artwork_url": "", "apple_music_url": "", "genre": ""},
                   music.RecognitionServiceError("service unavailable")]
        async def recognize(*args, **kwargs):
            result = results.pop(0)
            if isinstance(result, Exception):
                raise result
            return result
        with patch.object(music, "Shazam", return_value=FakeShazam()), patch.object(music, "get_duration", return_value=36), \
             patch.object(music, "MAX_SEGMENTS", 2), patch.object(music, "extract_segment", return_value=True), \
             patch.object(music, "recognize", side_effect=recognize), patch.object(music, "itunes_enrich", return_value={}), \
             patch.object(music, "emit", side_effect=events.append), patch.object(sys, "argv", ["detect_music.py", __file__]):
            with self.assertRaises(SystemExit):
                await music.main()
        self.assertEqual(len([e for e in events if e["type"] == "found"]), 1)
        self.assertEqual(events[-1]["type"], "error")
        self.assertEqual(events[-1]["completed_requests"], 1)


if __name__ == "__main__":
    unittest.main()
