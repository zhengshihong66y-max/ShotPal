#!/usr/bin/env python3
import argparse
import json
import sys

import ffmpeg
import numpy as np
from transnetv2_pytorch import TransNetV2


def extract_lowres_frames(video_path: str, width: int = 48, height: int = 27) -> np.ndarray:
    video_stream, _ = ffmpeg.input(video_path).output(
        "pipe:", format="rawvideo", pix_fmt="rgb24", s=f"{width}x{height}"
    ).run(capture_stdout=True, capture_stderr=True, quiet=True)
    return np.frombuffer(video_stream, np.uint8).reshape([-1, height, width, 3])


def frame_fingerprints(frames: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    rgb = frames.astype(np.float32) / 255.0
    luma = rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722

    quantized = np.minimum((rgb * 4).astype(np.int16), 3)
    bins = quantized[..., 0] * 16 + quantized[..., 1] * 4 + quantized[..., 2]
    histograms = np.zeros((frames.shape[0], 64), dtype=np.float32)
    for index, frame_bins in enumerate(bins):
        histograms[index] = np.bincount(frame_bins.reshape(-1), minlength=64)
    histograms /= max(1, frames.shape[1] * frames.shape[2])

    edges = np.zeros_like(luma, dtype=np.float32)
    edges[:, 1:-1, 1:-1] = np.minimum(
        1.0,
        np.abs(luma[:, 1:-1, 2:] - luma[:, 1:-1, :-2])
        + np.abs(luma[:, 2:, 1:-1] - luma[:, :-2, 1:-1]),
    )
    contrast = np.mean(np.abs(luma - np.mean(luma, axis=(1, 2), keepdims=True)), axis=(1, 2))
    return luma, histograms, edges, contrast


def rescue_hard_cut_times(video_path: str, fps: float) -> list[dict]:
    if fps <= 0:
        return []

    try:
        frames = extract_lowres_frames(video_path)
    except Exception:
        return []

    if len(frames) < 3:
        return []

    luma, histograms, edges, contrast = frame_fingerprints(frames)
    luma_diff = np.mean(np.abs(luma[1:] - luma[:-1]), axis=(1, 2))
    histogram_diff = np.sum(np.abs(histograms[1:] - histograms[:-1]), axis=1) * 0.5
    edge_diff = np.mean(np.abs(edges[1:] - edges[:-1]), axis=(1, 2))
    contrast_diff = np.abs(contrast[1:] - contrast[:-1])
    scores = luma_diff * 0.38 + histogram_diff * 0.32 + edge_diff * 0.22 + contrast_diff * 0.08

    median = float(np.median(scores))
    mad = float(np.median(np.abs(scores - median)))
    threshold = max(0.12, median + max(0.02, mad * 5.0))

    peak_window = 2
    candidates = []
    for index, score in enumerate(scores):
        lower = max(0, index - peak_window)
        upper = min(len(scores) - 1, index + peak_window)
        if score < threshold or score < np.max(scores[lower : upper + 1]):
            continue
        frame_number = index + 1
        candidates.append({
            "time": round(frame_number / fps, 3),
            "frame": int(frame_number),
            "score": float(score),
            "source": "hard_cut_rescue",
        })

    return candidates


def merge_cut_candidates(candidates: list[dict], fps: float) -> list[dict]:
    if not candidates:
        return [{"time": 0.0, "source": "start", "score": 1.0}]

    min_gap = max(0.045, 1.5 / max(fps, 1.0))
    sorted_candidates = sorted(candidates, key=lambda item: item["time"])
    merged = []
    for candidate in sorted_candidates:
        if not merged or candidate["time"] - merged[-1]["time"] >= min_gap:
            merged.append(candidate)
            continue

        previous = merged[-1]
        previous_rank = 2 if previous.get("source") == "transnetv2" else 1
        candidate_rank = 2 if candidate.get("source") == "transnetv2" else 1
        if (candidate_rank, candidate.get("score", 0.0)) > (previous_rank, previous.get("score", 0.0)):
            merged[-1] = candidate

    if merged[0]["time"] > 0:
        merged.insert(0, {"time": 0.0, "source": "start", "score": 1.0})
    else:
        merged[0]["time"] = 0.0
    return merged


def main() -> int:
    parser = argparse.ArgumentParser(description="Detect video scene cuts with TransNetV2.")
    parser.add_argument("video_path")
    parser.add_argument("--threshold", type=float, default=0.35)
    parser.add_argument("--device", choices=["auto", "cpu", "mps", "cuda"], default="cpu")
    args = parser.parse_args()

    model = TransNetV2(device=args.device)
    results = model.analyze_video(args.video_path, threshold=args.threshold, quiet=True)

    scenes = results.get("scenes", [])
    candidates = []
    for scene in scenes:
        start_time = scene.get("start_time")
        if start_time is None:
            continue
        candidates.append({
            "time": float(start_time),
            "frame": int(scene.get("start_frame", 0)),
            "score": float(scene.get("probability", 0.0)),
            "source": "transnetv2",
        })

    fps = float(results.get("fps", 0.0))
    rescue_candidates = rescue_hard_cut_times(args.video_path, fps)
    merged_candidates = merge_cut_candidates(candidates + rescue_candidates, fps)

    payload = {
        "engine": "transnetv2+hard_cut_rescue",
        "threshold": args.threshold,
        "fps": fps,
        "scene_count": len(scenes),
        "cut_times": [round(candidate["time"], 3) for candidate in merged_candidates],
        "candidates": merged_candidates,
        "rescue_count": len(rescue_candidates),
        "scenes": scenes,
    }
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
