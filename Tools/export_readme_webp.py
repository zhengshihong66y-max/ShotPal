#!/usr/bin/env python3
"""Convert README GIFs without resizing/retiming; retain GIF originals.

Requires gif2webp (libwebp) and Pillow. Example:
  python3 Tools/export_readme_webp.py --only capture
  python3 Tools/export_readme_webp.py --check-only
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import subprocess

from PIL import Image, ImageChops, ImageStat


ROOT = Path(__file__).resolve().parents[1]


def timeline(image):
    durations = []
    for index in range(image.n_frames):
        image.seek(index)
        image.load()
        durations.append(image.info.get("duration", 0))
    return durations


def verify(source, output):
    with Image.open(source) as original, Image.open(output) as encoded:
        assert original.size == encoded.size, "Canvas dimensions changed"
        assert original.info.get("loop") == encoded.info.get("loop"), "Loop changed"
        source_durations, output_durations = timeline(original), timeline(encoded)
        assert sum(source_durations) == sum(output_durations), "Duration changed"
        # Every encoded frame boundary must be an original frame boundary.
        boundaries = {0}
        elapsed = 0
        for duration in source_durations:
            elapsed += duration
            boundaries.add(elapsed)
        elapsed = 0
        for duration in output_durations:
            assert duration > 0, "Invalid frame duration"
            elapsed += duration
            assert elapsed in boundaries, "Frame timing changed"
        # Compare every source frame at the corresponding playback timestamp.
        errors = []
        elapsed, out_index, out_end = 0, 0, output_durations[0]
        for index, duration in enumerate(source_durations):
            while elapsed >= out_end and out_index + 1 < encoded.n_frames:
                out_index += 1
                out_end += output_durations[out_index]
            original.seek(index)
            encoded.seek(out_index)
            difference = ImageChops.difference(original.convert("RGB"), encoded.convert("RGB"))
            errors.append(sum(ImageStat.Stat(difference).mean) / 3)
            elapsed += duration
        assert max(errors) < 5, f"Frame difference too high: {max(errors):.2f}/255"
        return {
            "source": str(source.relative_to(ROOT)),
            "output": str(output.relative_to(ROOT)),
            "source_bytes": source.stat().st_size,
            "output_bytes": output.stat().st_size,
            "width": original.width,
            "height": original.height,
            "duration_ms": sum(source_durations),
            "source_frames": original.n_frames,
            "encoded_frames": encoded.n_frames,
            "source_frame_durations_ms": sorted(set(source_durations)),
            "loop": encoded.info.get("loop"),
            "mean_pixel_error_255": round(sum(errors) / len(errors), 3),
            "max_frame_pixel_error_255": round(max(errors), 3),
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", default="", help="Filter source filename")
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--workers", type=int, default=2)
    args = parser.parse_args()
    sources = list(dict.fromkeys(
        (ROOT / name).with_suffix(".gif")
        for name in re.findall(r'src="([^\"]+\.(?:gif|webp))"', (ROOT / "README.md").read_text())
        if args.only in name
    ))
    if not sources:
        parser.error("No matching README animation")

    def convert(source):
        output = source.with_suffix(".webp")
        if not args.check_only and not output.exists():
            subprocess.run([
                "gif2webp", "-lossy", "-q", "90", "-m", "4", "-mt", "-sharp_yuv",
                "-metadata", "none", str(source), "-o", str(output),
            ], check=True)
        result = verify(source, output)
        print(json.dumps(result, ensure_ascii=False), flush=True)
        return result

    with ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        results = list(pool.map(convert, sources))
    print(json.dumps({
        "count": len(results),
        "source_bytes": sum(r["source_bytes"] for r in results),
        "output_bytes": sum(r["output_bytes"] for r in results),
    }), flush=True)


if __name__ == "__main__":
    main()
