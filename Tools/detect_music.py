#!/usr/bin/env python3
"""
detect_music.py — Recognize songs in a media file using Shazam.

Setup (one-time, run from repo root):
    python3 -m venv Tools/music-env
    Tools/music-env/bin/pip install shazamio aiohttp requests

Usage:
    python detect_music.py <media_path>

Output (NDJSON, one JSON object per line):
    {"type": "progress", "value": 0.3, "message": "3/10"}
    {"type": "found", "song": {"title": "...", "artist": "...", ...}}
    {"type": "done", "songs": [...]}
    {"type": "error", "message": "..."}
"""

import asyncio
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

try:
    from shazamio import Shazam
    import requests
except ImportError:
    print(json.dumps({
        "type": "error",
        "message": "缺少依赖，请运行：\npython3 -m venv Tools/music-env\nTools/music-env/bin/pip install shazamio aiohttp requests"
    }), flush=True)
    sys.exit(1)

# Seconds per recognition window (Shazam needs ~10–12s for reliable match)
SEGMENT_DURATION = float(os.environ.get("LAPIANBAO_MUSIC_SEGMENT_DURATION", "12"))
# How often to sample the timeline. Use overlapping-ish probes so videos with
# multiple tracks are less likely to miss a transition.
STEP_INTERVAL = float(os.environ.get("LAPIANBAO_MUSIC_STEP_INTERVAL", "18"))
# Per-window network timeout. Without this, one slow Shazam request can make the
# whole app look stuck even though the Python process is still alive.
RECOGNIZE_TIMEOUT = float(os.environ.get("LAPIANBAO_MUSIC_RECOGNIZE_TIMEOUT", "10"))
ITUNES_TIMEOUT = float(os.environ.get("LAPIANBAO_MUSIC_ITUNES_TIMEOUT", "3"))
FFPROBE_TIMEOUT = float(os.environ.get("LAPIANBAO_MUSIC_FFPROBE_TIMEOUT", "12"))
FFMPEG_TIMEOUT = float(os.environ.get("LAPIANBAO_MUSIC_FFMPEG_TIMEOUT", "12"))
TOTAL_TIMEOUT = float(os.environ.get("LAPIANBAO_MUSIC_TOTAL_TIMEOUT", "120"))
# Keep the feature interactive. This is a recognition aid, not an offline batch
# analyzer; very long videos should not enqueue hundreds of network probes.
MAX_SEGMENTS = max(1, int(os.environ.get("LAPIANBAO_MUSIC_MAX_SEGMENTS", "12")))


def find_tool(name: str) -> str:
    """Find ffmpeg/ffprobe even when the macOS app has a minimal PATH."""
    for path in (
        shutil.which(name),
        f"/opt/homebrew/bin/{name}",
        f"/usr/local/bin/{name}",
        f"/usr/bin/{name}",
    ):
        if path and os.path.exists(path) and os.access(path, os.X_OK):
            return path
    return name


def emit(obj: dict) -> None:
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def get_duration(media_path: str) -> float:
    cmd = [
        find_tool("ffprobe"), "-v", "quiet",
        "-print_format", "json",
        "-show_format",
        "-show_streams",
        media_path,
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=FFPROBE_TIMEOUT)
        if result.returncode != 0:
            return 0.0
        data = json.loads(result.stdout)
        candidates = [data.get("format", {}).get("duration")]
        candidates.extend(stream.get("duration") for stream in data.get("streams", []))
        for value in candidates:
            try:
                seconds = float(value)
                if seconds > 0:
                    return seconds
            except (TypeError, ValueError):
                continue
    except Exception:
        pass
    return 0.0


def extract_segment(media_path: str, start: float, duration: float, out_path: str) -> bool:
    """Extract a mono 44.1kHz WAV segment from a media file."""
    cmd = [
        find_tool("ffmpeg"), "-y",
        "-ss", str(start),
        "-i", media_path,
        "-t", str(duration),
        "-vn",           # no video
        "-ar", "44100",
        "-ac", "1",
        "-f", "wav",
        out_path,
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, timeout=FFMPEG_TIMEOUT)
        return (
            result.returncode == 0
            and os.path.exists(out_path)
            and os.path.getsize(out_path) > 4096
        )
    except Exception:
        return False


def itunes_enrich(title: str, artist: str) -> dict:
    """
    Query iTunes Search API for Apple Music URL, high-res artwork, and genre.
    Returns {} on failure.
    """
    try:
        resp = requests.get(
            "https://itunes.apple.com/search",
            params={"term": f"{artist} {title}", "media": "music", "entity": "song", "limit": 5},
            timeout=ITUNES_TIMEOUT,
        )
        for r in resp.json().get("results", []):
            if r.get("kind") == "song":
                artwork = normalize_itunes_artwork_url(r.get("artworkUrl100", ""))
                duration_ms = float(r.get("trackTimeMillis") or 0)
                return {
                    "apple_music_url": r.get("trackViewUrl", ""),
                    "artwork_url": artwork,
                    "artist": r.get("artistName", ""),
                    "genre": r.get("primaryGenreName", ""),
                    "duration": duration_ms / 1000 if duration_ms > 0 else 0,
                }
    except Exception:
        pass
    return {}


def normalize_itunes_artwork_url(url: str) -> str:
    """Promote iTunes artwork URLs to a stable square size."""
    artwork = str(url or "").strip()
    if not artwork:
        return ""
    artwork = artwork.replace("100x100", "600x600")
    return re.sub(r"\d+x\d+bb", "600x600bb", artwork)


def clean_music_tags(*values: str) -> list[str]:
    tags: list[str] = []
    seen: set[str] = set()
    for value in values:
        tag = " ".join(str(value or "").replace("/", " / ").split()).strip()
        if not tag or tag.casefold() in seen:
            continue
        seen.add(tag.casefold())
        tags.append(tag)
    return sorted(tags)


def shazam_genre(track: dict) -> str:
    genres = track.get("genres", {})
    if isinstance(genres, dict):
        primary = genres.get("primary")
        if primary:
            return str(primary)
    return ""


def parse_apple_music_url(track: dict) -> str:
    """Extract Apple Music URL from a Shazam track object."""
    hub = track.get("hub", {})
    for option in hub.get("options", []):
        for action in option.get("actions", []):
            uri = action.get("uri", "")
            if "music.apple.com" in uri or "itunes.apple.com" in uri:
                return uri
    for action in hub.get("actions", []):
        uri = action.get("uri", "")
        if "music.apple.com" in uri or "itunes.apple.com" in uri:
            return uri
    return ""


async def recognize(shazam: Shazam, seg_path: str, timeout: float = RECOGNIZE_TIMEOUT) -> dict | None:
    try:
        result = await asyncio.wait_for(shazam.recognize(seg_path), timeout=timeout)
    except (asyncio.TimeoutError, Exception):
        return None

    track = result.get("track")
    if not track:
        return None

    title = track.get("title", "").strip()
    artist = track.get("subtitle", "").strip()
    if not title:
        return None

    images = track.get("images", {})
    artwork = images.get("coverarthq") or images.get("coverart", "")
    apple_music_url = parse_apple_music_url(track)
    genre = shazam_genre(track)

    return {
        "title": title,
        "artist": artist,
        "artwork_url": artwork,
        "apple_music_url": apple_music_url,
        "genre": genre,
        "tags": clean_music_tags(artist, genre),
    }


async def main() -> None:
    if len(sys.argv) < 2:
        emit({"type": "error", "message": "用法：detect_music.py <media_path>"})
        sys.exit(1)

    media_path = sys.argv[1]
    if not os.path.exists(media_path):
        emit({"type": "error", "message": f"文件不存在：{media_path}"})
        sys.exit(1)

    duration = get_duration(media_path)
    if duration <= 0:
        emit({"type": "error", "message": "无法读取媒体时长：请确认已安装 ffmpeg/ffprobe，且文件可被读取"})
        sys.exit(1)
    if duration <= 3:
        emit({"type": "error", "message": f"音频过短：当前约 {duration:.1f} 秒"})
        sys.exit(1)

    # Build sampling positions
    starts: list[float] = []
    # Start slightly after zero as well as at zero: intros often have dialogue
    # or fade-ins that make the first recognition window unreliable.
    t = 0.0
    while t < duration - 3:
        starts.append(t)
        t += STEP_INTERVAL
    if duration > SEGMENT_DURATION + 8:
        t = min(8.0, max(0.0, duration - SEGMENT_DURATION))
        while t < duration - 3:
            starts.append(t)
            t += STEP_INTERVAL
    starts = sorted(set(round(s, 2) for s in starts))
    if len(starts) > MAX_SEGMENTS:
        if MAX_SEGMENTS == 1:
            starts = [starts[0]]
        else:
            stride = (len(starts) - 1) / (MAX_SEGMENTS - 1)
            starts = [starts[round(i * stride)] for i in range(MAX_SEGMENTS)]
    total = len(starts)

    emit({"type": "progress", "value": 0.0, "message": f"共 {total} 段"})

    shazam = Shazam()
    found: dict[str, dict] = {}   # dedup key → song dict
    started_at = time.monotonic()

    with tempfile.TemporaryDirectory() as tmpdir:
        for idx, start in enumerate(starts):
            elapsed = time.monotonic() - started_at
            if elapsed >= TOTAL_TIMEOUT:
                emit({
                    "type": "progress",
                    "value": idx / max(total, 1),
                    "message": "已达到识别时间上限，返回当前结果",
                })
                break

            seg_path = os.path.join(tmpdir, f"seg_{idx}.wav")
            ok = extract_segment(media_path, start, SEGMENT_DURATION, seg_path)

            if ok:
                remaining = max(1.0, TOTAL_TIMEOUT - (time.monotonic() - started_at))
                song = await recognize(shazam, seg_path, timeout=min(RECOGNIZE_TIMEOUT, remaining))
                if song:
                    key = f"{song['title'].casefold()}|{song['artist'].casefold()}"
                    if key not in found:
                        # Prefer iTunes artwork: it is more consistently decodable
                        # by the macOS UI than some Shazam CDN variants.
                        extra = itunes_enrich(song["title"], song["artist"])
                        if not song.get("artist"):
                            song["artist"] = extra.get("artist", "")
                        if not song["apple_music_url"]:
                            song["apple_music_url"] = extra.get("apple_music_url", "")
                        if extra.get("artwork_url"):
                            song["artwork_url"] = extra.get("artwork_url", "")
                        if not song.get("genre"):
                            song["genre"] = extra.get("genre", "")
                        if not song.get("duration"):
                            song["duration"] = extra.get("duration", 0)

                        song["detected_at"] = start
                        song["tags"] = clean_music_tags(song.get("artist", ""), song.get("genre", ""))
                        found[key] = song
                        emit({"type": "found", "song": song})

                try:
                    os.remove(seg_path)
                except OSError:
                    pass

            emit({
                "type": "progress",
                "value": (idx + 1) / total,
                "message": f"{idx + 1}/{total}",
            })

            # Brief pause to avoid hammering the API
            await asyncio.sleep(0.4)

    emit({"type": "done", "songs": list(found.values())})


if __name__ == "__main__":
    asyncio.run(main())
