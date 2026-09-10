#!/usr/bin/env python3
"""The app invokes this with its own Python -I -B -u, never PYTHONPATH/venv."""
import contextlib
import json
from pathlib import Path
import runpy
import sys

TOOLS = Path(__file__).resolve().parent
VENDOR = TOOLS / "recognition/site-packages"


def main():
    if not VENDOR.is_dir():
        raise RuntimeError("内置识别依赖缺失，请重新安装完整安装包")
    # Explicitly add only our sealed vendor directory. Do not process .pth files
    # or put the current directory/user site on the import path.
    sys.path.insert(0, str(VENDOR))
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "--probe":
        if args[1] == "music":
            import shazamio
            import shazamio_core
            import requests
            import asyncio
            import io
            import math
            import struct
            import wave
            audio = io.BytesIO()
            with wave.open(audio, "wb") as stream:
                stream.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
                stream.writeframes(b"".join(struct.pack("<h", int(12000 * math.sin(i * 2 * math.pi * 440 / 16000)))
                                            for i in range(16000 * 12)))
            async def fingerprint():
                return await shazamio.Shazam().core_recognizer.recognize_bytes(audio.getvalue())
            signature = asyncio.run(fingerprint())
            assert signature.signature.uri.startswith("data:")
            modules = [shazamio, shazamio_core, requests]
        elif args[1] == "scene":
            import numpy
            import torch
            import transnetv2_pytorch
            import ffmpeg
            with contextlib.redirect_stdout(sys.stderr):
                model = transnetv2_pytorch.TransNetV2(device="cpu")
            assert sum(p.numel() for p in model.parameters()) > 1_000_000
            modules = [numpy, torch, transnetv2_pytorch, ffmpeg]
        else:
            raise ValueError("Unknown recognition probe")
        origins = {m.__name__: str(Path(m.__file__).resolve()) for m in modules}
        assert all(Path(p).is_relative_to(VENDOR) for p in origins.values())
        print(json.dumps({"status": "succeeded", "python": sys.version.split()[0], "origins": origins}))
        return
    scripts = {"music": "detect_music.py", "scene": "detect_scene_cuts_transnet.py"}
    if not args or args[0] not in scripts:
        raise ValueError("Expected music/scene and an input media path")
    script = TOOLS / scripts[args[0]]
    sys.argv = [str(script)] + args[1:]
    runpy.run_path(str(script), run_name="__main__")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"type": "error", "message": str(error)}, ensure_ascii=False), flush=True)
        raise SystemExit(1)
