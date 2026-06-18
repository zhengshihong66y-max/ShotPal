#!/usr/bin/env python3
import argparse
import json
import sys

import numpy as np
import torch
from transnetv2_pytorch import TransNetV2


PROGRESS_PREFIX = "LAPIANBAO_PROGRESS\t"
FRAME_WIDTH = 48
FRAME_HEIGHT = 27
FRAME_CHANNELS = 3
FRAME_SIZE = FRAME_WIDTH * FRAME_HEIGHT * FRAME_CHANNELS


def emit_progress(progress: float) -> None:
    progress = min(1.0, max(0.0, float(progress)))
    print(f"{PROGRESS_PREFIX}{progress:.6f}", file=sys.stderr, flush=True)


def parse_frame_rate(raw_value: str | None) -> float:
    if not raw_value:
        return 0.0
    try:
        if "/" in raw_value:
            numerator, denominator = raw_value.split("/", 1)
            denominator_value = float(denominator)
            if denominator_value == 0:
                return 0.0
            return float(numerator) / denominator_value
        return float(raw_value)
    except ValueError:
        return 0.0


def probe_video(video_path: str) -> tuple[float, int]:
    import ffmpeg

    probe = ffmpeg.probe(video_path)
    video_stream = next(
        (stream for stream in probe.get("streams", []) if stream.get("codec_type") == "video"),
        None,
    )
    if video_stream is None:
        return 25.0, 0

    fps = parse_frame_rate(video_stream.get("avg_frame_rate")) or parse_frame_rate(video_stream.get("r_frame_rate")) or 25.0
    duration = 0.0
    for value in [video_stream.get("duration"), probe.get("format", {}).get("duration")]:
        try:
            duration = float(value)
            if duration > 0:
                break
        except (TypeError, ValueError):
            continue

    total_frames = 0
    try:
        total_frames = int(video_stream.get("nb_frames") or 0)
    except (TypeError, ValueError):
        total_frames = 0
    if total_frames <= 0 and fps > 0 and duration > 0:
        total_frames = int(round(fps * duration))

    return fps, max(0, total_frames)


def load_video_frames_with_progress(video_path: str, total_frames: int) -> np.ndarray:
    import ffmpeg

    process = (
        ffmpeg
        .input(video_path)
        .output("pipe:", format="rawvideo", pix_fmt="rgb24", s=f"{FRAME_WIDTH}x{FRAME_HEIGHT}")
        .global_args("-v", "error")
        .run_async(pipe_stdout=True, pipe_stderr=True)
    )

    frames: list[np.ndarray] = []
    buffer = bytearray()
    read_frames = 0
    chunk_size = FRAME_SIZE * 32

    while True:
        chunk = process.stdout.read(chunk_size)
        if not chunk:
            break

        buffer.extend(chunk)
        usable_byte_count = (len(buffer) // FRAME_SIZE) * FRAME_SIZE
        if usable_byte_count <= 0:
            continue

        frame_bytes = bytes(buffer[:usable_byte_count])
        del buffer[:usable_byte_count]

        frame_chunk = np.frombuffer(frame_bytes, np.uint8).reshape([-1, FRAME_HEIGHT, FRAME_WIDTH, FRAME_CHANNELS])
        frames.append(np.array(frame_chunk, copy=True))
        read_frames += frame_chunk.shape[0]

        if total_frames > 0:
            emit_progress(0.05 + min(1.0, read_frames / total_frames) * 0.40)

    stderr = process.stderr.read() if process.stderr else b""
    status = process.wait()
    if status != 0:
        message = stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(message or f"ffmpeg exited with status {status}")

    if not frames:
        raise RuntimeError("No video frames extracted")

    emit_progress(0.45)
    return np.concatenate(frames, axis=0)


def predict_frames_with_progress(model: TransNetV2, frames: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
    assert len(frames.shape) == 4 and frames.shape[1:] == model._input_size, \
        "Input shape must be [frames, height, width, 3]."

    def input_iterator():
        window_size = 100
        step_size = 50
        remainder = len(frames) % step_size
        no_padded_frames_start = 25
        no_padded_frames_end = 25 + step_size - (remainder if remainder != 0 else step_size)

        start_frame = torch.unsqueeze(frames[0], 0)
        end_frame = torch.unsqueeze(frames[-1], 0)
        padded_inputs = torch.cat(
            [start_frame] * no_padded_frames_start + [frames] + [end_frame] * no_padded_frames_end,
            0,
        )

        ptr = 0
        while ptr + window_size <= len(padded_inputs):
            batch = padded_inputs[ptr:ptr + window_size]
            ptr += step_size
            yield batch[np.newaxis]

    predictions = []

    for batch_input in input_iterator():
        with torch.no_grad():
            single_frame_pred, all_frames_pred = model.predict_raw(batch_input)
            start_idx = 25
            end_idx = 75
            predictions.append((
                single_frame_pred[0, start_idx:end_idx, 0].cpu().clone(),
                all_frames_pred[0, start_idx:end_idx, 0].cpu().clone(),
            ))

            processed_frames = min(len(predictions) * 50, len(frames))
            emit_progress(0.45 + (processed_frames / max(1, len(frames))) * 0.37)

    single_frame_pred = torch.cat([single_ for single_, _ in predictions], 0)
    all_frames_pred = torch.cat([all_ for _, all_ in predictions], 0)

    emit_progress(0.82)
    return single_frame_pred[:len(frames)], all_frames_pred[:len(frames)]


def analyze_video_with_progress(model: TransNetV2, video_path: str, threshold: float) -> dict:
    fps, total_frames = probe_video(video_path)
    emit_progress(0.04)

    video_np = load_video_frames_with_progress(video_path, total_frames)
    video_frames = torch.from_numpy(np.ascontiguousarray(video_np)).to(model.device)
    single_frame_predictions, all_frame_predictions = predict_frames_with_progress(model, video_frames)

    emit_progress(0.84)
    single_frame_np = single_frame_predictions.cpu().detach().numpy()
    scenes = model.predictions_to_scenes_with_data(single_frame_np, fps=fps, threshold=threshold)
    emit_progress(0.86)

    return {
        "video_frames": video_frames,
        "single_frame_predictions": single_frame_predictions,
        "all_frame_predictions": all_frame_predictions,
        "fps": fps,
        "scenes": scenes,
        "total_scenes": len(scenes),
    }


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

    emit_progress(0.01)
    model = TransNetV2(device=args.device)
    emit_progress(0.03)
    results = analyze_video_with_progress(model, args.video_path, args.threshold)

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
    merged_candidates = merge_cut_candidates(candidates, fps)
    merged_candidates = filter_short_scenes(merged_candidates, fps)

    payload = {
        "engine": "transnetv2",
        "threshold": args.threshold,
        "fps": fps,
        "scene_count": len(scenes),
        "cut_times": [round(candidate["time"], 3) for candidate in merged_candidates],
        "candidates": merged_candidates,
        "scenes": scenes,
    }
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
