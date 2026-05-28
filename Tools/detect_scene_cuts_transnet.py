#!/usr/bin/env python3
import argparse
import json
import sys

import ffmpeg
import numpy as np
from transnetv2_pytorch import TransNetV2


def iter_lowres_frame_chunks(video_path: str, width: int = 48, height: int = 27, chunk_size: int = 512):
    frame_size = width * height * 3
    process = (
        ffmpeg
        .input(video_path)
        .output("pipe:", format="rawvideo", pix_fmt="rgb24", s=f"{width}x{height}", threads=2)
        .global_args("-nostdin", "-loglevel", "error")
        .run_async(pipe_stdout=True, pipe_stderr=True)
    )

    try:
        pending = b""
        read_size = frame_size * max(1, chunk_size)
        while True:
            chunk = process.stdout.read(read_size)
            if not chunk:
                break

            pending += chunk
            frame_count = len(pending) // frame_size
            if frame_count == 0:
                continue

            usable = frame_count * frame_size
            yield np.frombuffer(pending[:usable], np.uint8).reshape((frame_count, height, width, 3))
            pending = pending[usable:]
    finally:
        if process.stdout:
            process.stdout.close()
        stderr = process.stderr.read() if process.stderr else b""
        returncode = process.wait()
        if returncode != 0:
            raise RuntimeError(stderr.decode("utf-8", errors="ignore"))


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


def frame_change_scores(
    luma: np.ndarray,
    histograms: np.ndarray,
    edges: np.ndarray,
    contrast: np.ndarray,
) -> np.ndarray:
    if len(luma) < 2:
        return np.empty(0, dtype=np.float32)

    luma_diff = np.mean(np.abs(luma[1:] - luma[:-1]), axis=(1, 2))
    histogram_diff = np.sum(np.abs(histograms[1:] - histograms[:-1]), axis=1) * 0.5
    edge_diff = np.mean(np.abs(edges[1:] - edges[:-1]), axis=(1, 2))
    contrast_diff = np.abs(contrast[1:] - contrast[:-1])
    return luma_diff * 0.38 + histogram_diff * 0.32 + edge_diff * 0.22 + contrast_diff * 0.08


def rescue_hard_cut_times(video_path: str, fps: float) -> list[dict]:
    if fps <= 0:
        return []

    previous = None
    scores = []
    try:
        for frames in iter_lowres_frame_chunks(video_path):
            luma, histograms, edges, contrast = frame_fingerprints(frames)
            if previous is not None:
                previous_luma, previous_histogram, previous_edges, previous_contrast = previous
                luma = np.concatenate([previous_luma[np.newaxis, ...], luma], axis=0)
                histograms = np.concatenate([previous_histogram[np.newaxis, ...], histograms], axis=0)
                edges = np.concatenate([previous_edges[np.newaxis, ...], edges], axis=0)
                contrast = np.concatenate([np.asarray([previous_contrast], dtype=np.float32), contrast], axis=0)

            scores.extend(frame_change_scores(luma, histograms, edges, contrast).tolist())
            previous = (luma[-1].copy(), histograms[-1].copy(), edges[-1].copy(), float(contrast[-1]))
    except Exception:
        return []

    if len(scores) < 2:
        return []

    scores = np.asarray(scores, dtype=np.float32)

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


def filter_short_scenes(candidates: list[dict], fps: float) -> list[dict]:
    """Remove cuts that create scenes shorter than the minimum duration."""
    if len(candidates) < 2:
        return candidates

    min_duration = max(0.3, 8.0 / max(fps, 1.0))
    filtered = [candidates[0]]
    for candidate in candidates[1:]:
        if candidate["time"] - filtered[-1]["time"] >= min_duration:
            filtered.append(candidate)
        else:
            prev = filtered[-1]
            prev_rank = (2 if prev.get("source") == "transnetv2" else 1, prev.get("score", 0.0))
            curr_rank = (2 if candidate.get("source") == "transnetv2" else 1, candidate.get("score", 0.0))
            if curr_rank > prev_rank:
                filtered[-1] = candidate
    return filtered


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
    rescue_candidates = []
    if len(candidates) < 2:
        rescue_candidates = rescue_hard_cut_times(args.video_path, fps)
    merged_candidates = merge_cut_candidates(candidates + rescue_candidates, fps)
    merged_candidates = filter_short_scenes(merged_candidates, fps)

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
