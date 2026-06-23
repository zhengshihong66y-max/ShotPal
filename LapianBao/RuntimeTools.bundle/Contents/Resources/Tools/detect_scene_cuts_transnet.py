#!/usr/bin/env python3
import argparse
import contextlib
import json
import os
import sys
import time

import numpy as np
import torch
from transnetv2_pytorch import TransNetV2


PROGRESS_PREFIX = "LAPIANBAO_PROGRESS\t"
TIMING_PREFIX = "LAPIANBAO_TIMING\t"
FRAME_WIDTH = 48
FRAME_HEIGHT = 27
FRAME_CHANNELS = 3
FRAME_SIZE = FRAME_WIDTH * FRAME_HEIGHT * FRAME_CHANNELS
DEFAULT_ACCELERATOR_BATCH_SIZE = 1
DEFAULT_SAMPLE_FPS = 0.0
DEFAULT_EAGER_FRAME_LIMIT = 60_000


def emit_progress(progress: float) -> None:
    progress = min(1.0, max(0.0, float(progress)))
    print(f"{PROGRESS_PREFIX}{progress:.6f}", file=sys.stderr, flush=True)


def emit_timing(stage: str, started_at: float, detail: str = "") -> None:
    elapsed = max(0.0, time.perf_counter() - started_at)
    if detail:
        print(f"{TIMING_PREFIX}{stage}\t{elapsed:.3f}\t{detail}", file=sys.stderr, flush=True)
    else:
        print(f"{TIMING_PREFIX}{stage}\t{elapsed:.3f}", file=sys.stderr, flush=True)


def resolve_device(requested_device: str) -> str:
    if requested_device != "auto":
        return requested_device
    if torch.cuda.is_available():
        return "cuda"

    mps_backend = getattr(torch.backends, "mps", None)
    if mps_backend is not None:
        try:
            if mps_backend.is_built() and mps_backend.is_available():
                return "mps"
        except Exception:
            pass

    return "cpu"


def inference_batch_size(device: torch.device | str) -> int:
    raw_value = os.environ.get("LAPIANBAO_SCENE_BATCH_SIZE")
    if raw_value:
        try:
            parsed = int(raw_value)
            if parsed > 0:
                return parsed
        except ValueError:
            pass

    device_type = torch.device(device).type
    if device_type in {"cuda", "mps"}:
        return DEFAULT_ACCELERATOR_BATCH_SIZE
    return 1


def configured_sample_fps(requested_sample_fps: float | None, source_fps: float) -> float:
    raw_value = os.environ.get("LAPIANBAO_SCENE_SAMPLE_FPS") or os.environ.get("LAPIANBAO_SCENE_DETECTION_FPS")
    sample_fps = requested_sample_fps
    if sample_fps is None and raw_value:
        try:
            sample_fps = float(raw_value)
        except ValueError:
            sample_fps = DEFAULT_SAMPLE_FPS
    if sample_fps is None:
        sample_fps = DEFAULT_SAMPLE_FPS

    if sample_fps <= 0 or source_fps <= 0:
        return source_fps
    return min(source_fps, sample_fps)


def output_frame_rate(source_fps: float, sample_fps: float) -> float | None:
    if source_fps <= 0 or sample_fps <= 0:
        return None
    if sample_fps < source_fps - 0.01:
        return sample_fps
    return None


def estimated_sample_frame_count(source_fps: float, source_frames: int, duration: float, sample_fps: float) -> int:
    if sample_fps <= 0:
        return max(0, source_frames)
    if duration > 0:
        return max(0, int(round(duration * sample_fps)))
    if source_fps > 0 and source_frames > 0:
        return max(0, int(round(source_frames * sample_fps / source_fps)))
    return max(0, source_frames)


def ffmpeg_output_kwargs(output_fps: float | None = None) -> dict:
    output_kwargs = {
        "format": "rawvideo",
        "pix_fmt": "rgb24",
        "s": f"{FRAME_WIDTH}x{FRAME_HEIGHT}",
    }
    if output_fps is not None and output_fps > 0:
        output_kwargs["r"] = f"{output_fps:.6f}".rstrip("0").rstrip(".")
    return output_kwargs


def eager_frame_limit() -> int:
    raw_value = os.environ.get("LAPIANBAO_SCENE_EAGER_FRAME_LIMIT")
    if raw_value:
        try:
            parsed = int(raw_value)
            if parsed >= 0:
                return parsed
        except ValueError:
            pass
    return DEFAULT_EAGER_FRAME_LIMIT


def should_load_frames_eager(device: torch.device | str, total_frames: int) -> bool:
    if torch.device(device).type == "cpu":
        return True
    limit = eager_frame_limit()
    return limit > 0 and 0 < total_frames <= limit


def disable_unused_many_hot_head(model: TransNetV2) -> None:
    if hasattr(model, "cls_layer2"):
        model.cls_layer2 = None


def predict_single_frame_batch(model: TransNetV2, batch_input: torch.Tensor) -> torch.Tensor:
    with torch.inference_mode():
        output = model.forward(batch_input)
        single_frame_logits = output[0] if isinstance(output, tuple) else output
        return torch.sigmoid(single_frame_logits)


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


def probe_video(video_path: str) -> tuple[float, int, float]:
    import ffmpeg

    probe = ffmpeg.probe(video_path)
    video_stream = next(
        (stream for stream in probe.get("streams", []) if stream.get("codec_type") == "video"),
        None,
    )
    if video_stream is None:
        return 25.0, 0, 0.0

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

    return fps, max(0, total_frames), max(0.0, duration)


def load_video_frames_with_progress(
    video_path: str,
    total_frames: int,
    sample_fps: float,
    output_fps: float | None
) -> np.ndarray:
    import ffmpeg

    started_at = time.perf_counter()
    process = (
        ffmpeg
        .input(video_path)
        .output("pipe:", **ffmpeg_output_kwargs(output_fps))
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
    frame_array = np.concatenate(frames, axis=0)
    rate_detail = f"sample_fps={sample_fps:.3f}" if output_fps is not None else "sample_fps=full"
    emit_timing("load_frames", started_at, f"frames={len(frame_array)} {rate_detail}")
    return frame_array


def predict_loaded_frames_with_progress(model: TransNetV2, video_np: np.ndarray) -> tuple[torch.Tensor, int]:
    transfer_started_at = time.perf_counter()
    frames = torch.from_numpy(np.ascontiguousarray(video_np)).to(model.device)
    emit_timing("transfer_frames", transfer_started_at, f"frames={len(frames)} device={model.device}")

    assert len(frames.shape) == 4 and frames.shape[1:] == model._input_size, \
        "Input shape must be [frames, height, width, 3]."

    batch_size = inference_batch_size(model.device)

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
            yield batch

    prediction_started_at = time.perf_counter()
    predictions = []
    pending_windows: list[torch.Tensor] = []
    processed_windows = 0

    def flush_windows() -> None:
        nonlocal processed_windows
        if not pending_windows:
            return

        batch_input = torch.stack(pending_windows, 0).contiguous()
        single_frame_pred = predict_single_frame_batch(model, batch_input)
        start_idx = 25
        end_idx = 75
        predictions.append(single_frame_pred[:, start_idx:end_idx, 0].cpu().reshape(-1).clone())
        processed_windows += len(pending_windows)
        pending_windows.clear()

        processed_frames = min(processed_windows * 50, len(frames))
        emit_progress(0.45 + (processed_frames / max(1, len(frames))) * 0.37)

    for window in input_iterator():
        pending_windows.append(window)
        if len(pending_windows) >= batch_size:
            flush_windows()
    flush_windows()

    single_frame_pred = torch.cat(predictions, 0)
    emit_progress(0.82)
    emit_timing("predict_frames", prediction_started_at, f"frames={len(frames)} batch={batch_size}")
    return single_frame_pred[:len(frames)], len(frames)


def predict_frames_with_progress(
    model: TransNetV2,
    video_path: str,
    total_frames: int,
    sample_fps: float,
    output_fps: float | None
) -> tuple[torch.Tensor, int]:
    import ffmpeg

    stream_started_at = time.perf_counter()
    prediction_started_at: float | None = None
    process = (
        ffmpeg
        .input(video_path)
        .output("pipe:", **ffmpeg_output_kwargs(output_fps))
        .global_args("-v", "error")
        .run_async(pipe_stdout=True, pipe_stderr=True)
    )

    frame_buffer: list[np.ndarray] = []
    buffer_start_index = 0
    first_frame: np.ndarray | None = None
    last_frame: np.ndarray | None = None
    predictions: list[torch.Tensor] = []
    pending_windows: list[np.ndarray] = []
    next_window_start = 0
    processed_windows = 0
    buffer = bytearray()
    read_frames = 0
    chunk_size = FRAME_SIZE * 32
    batch_size = inference_batch_size(model.device)

    def frame_at(index: int) -> np.ndarray:
        nonlocal first_frame, last_frame
        if index < 0:
            assert first_frame is not None
            return first_frame
        if index >= read_frames:
            assert last_frame is not None
            return last_frame

        buffer_index = index - buffer_start_index
        if buffer_index < 0 or buffer_index >= len(frame_buffer):
            raise RuntimeError("Frame window buffer was trimmed too early")
        return frame_buffer[buffer_index]

    def trim_frame_buffer() -> None:
        nonlocal buffer_start_index
        min_needed_index = max(0, next_window_start - 25)
        remove_count = min(min_needed_index - buffer_start_index, len(frame_buffer))
        if remove_count > 0:
            del frame_buffer[:remove_count]
            buffer_start_index += remove_count

    def flush_windows(force: bool = False) -> None:
        nonlocal processed_windows, prediction_started_at
        if not pending_windows or (not force and len(pending_windows) < batch_size):
            return

        if prediction_started_at is None:
            prediction_started_at = time.perf_counter()

        batch_input = torch.from_numpy(np.ascontiguousarray(np.stack(pending_windows, axis=0))).to(model.device)
        single_frame_pred = predict_single_frame_batch(model, batch_input)
        start_idx = 25
        end_idx = 75
        predictions.append(single_frame_pred[:, start_idx:end_idx, 0].cpu().reshape(-1).clone())
        processed_windows += len(pending_windows)
        pending_windows.clear()

        frames = range(max(total_frames, read_frames))
        processed_frames = min(processed_windows * 50, len(frames))
        emit_progress(0.45 + (processed_frames / max(1, len(frames))) * 0.37)

    def process_window() -> None:
        nonlocal next_window_start, prediction_started_at
        if prediction_started_at is None:
            prediction_started_at = time.perf_counter()

        window = np.stack(
            [frame_at(index) for index in range(next_window_start - 25, next_window_start + 75)],
            axis=0
        )
        pending_windows.append(window)
        next_window_start += 50
        trim_frame_buffer()
        flush_windows()

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
        for raw_frame in frame_chunk:
            frame = np.array(raw_frame, copy=True)
            if first_frame is None:
                first_frame = frame
            last_frame = frame
            frame_buffer.append(frame)
            read_frames += 1

        if not predictions and total_frames > 0:
            emit_progress(0.05 + min(1.0, read_frames / total_frames) * 0.40)

        while read_frames > next_window_start + 74:
            process_window()

    stderr = process.stderr.read() if process.stderr else b""
    status = process.wait()
    if status != 0:
        message = stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(message or f"ffmpeg exited with status {status}")

    if read_frames <= 0:
        raise RuntimeError("No video frames extracted")

    while next_window_start < read_frames:
        process_window()
    flush_windows(force=True)

    single_frame_pred = torch.cat(predictions, 0)
    emit_progress(0.82)
    rate_detail = f"sample_fps={sample_fps:.3f}" if output_fps is not None else "sample_fps=full"
    emit_timing("stream_frames", stream_started_at, f"frames={read_frames} {rate_detail}")
    if prediction_started_at is not None:
        emit_timing("predict_frames", prediction_started_at, f"frames={read_frames} batch={batch_size}")
    return single_frame_pred[:read_frames], read_frames


def analyze_video_with_progress(
    model: TransNetV2,
    video_path: str,
    threshold: float,
    requested_sample_fps: float | None
) -> dict:
    probe_started_at = time.perf_counter()
    source_fps, source_total_frames, duration = probe_video(video_path)
    sample_fps = configured_sample_fps(requested_sample_fps, source_fps)
    output_fps = output_frame_rate(source_fps, sample_fps)
    total_frames = estimated_sample_frame_count(source_fps, source_total_frames, duration, sample_fps)
    emit_timing(
        "probe_video",
        probe_started_at,
        f"fps={source_fps:.3f} sample_fps={sample_fps:.3f} frames={source_total_frames} sample_frames={total_frames}"
    )
    emit_progress(0.04)

    if should_load_frames_eager(model.device, total_frames):
        video_np = load_video_frames_with_progress(video_path, total_frames, sample_fps, output_fps)
        single_frame_predictions, _decoded_frames = predict_loaded_frames_with_progress(model, video_np)
    else:
        single_frame_predictions, _decoded_frames = predict_frames_with_progress(
            model,
            video_path,
            total_frames,
            sample_fps,
            output_fps
        )

    emit_progress(0.84)
    postprocess_started_at = time.perf_counter()
    single_frame_np = single_frame_predictions.cpu().detach().numpy()
    scenes = model.predictions_to_scenes_with_data(single_frame_np, fps=sample_fps, threshold=threshold)
    emit_timing("postprocess_scenes", postprocess_started_at, f"scenes={len(scenes)}")
    emit_progress(0.86)

    return {
        "fps": sample_fps,
        "source_fps": source_fps,
        "sample_fps": sample_fps,
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


def run_detection(args: argparse.Namespace, device: str) -> dict:
    emit_progress(0.01)
    model_started_at = time.perf_counter()
    with contextlib.redirect_stdout(sys.stderr):
        model = TransNetV2(device=device)
    disable_unused_many_hot_head(model)
    emit_timing("load_model", model_started_at, f"device={device}")
    emit_progress(0.03)
    analysis_started_at = time.perf_counter()
    results = analyze_video_with_progress(model, args.video_path, args.threshold, args.sample_fps)
    emit_timing("analyze_video", analysis_started_at, f"device={device}")

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
        "device": device,
        "fps": fps,
        "source_fps": float(results.get("source_fps", fps)),
        "sample_fps": float(results.get("sample_fps", fps)),
        "scene_count": len(scenes),
        "cut_times": [round(candidate["time"], 3) for candidate in merged_candidates],
        "candidates": merged_candidates,
        "scenes": scenes,
    }
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Detect video scene cuts with TransNetV2.")
    parser.add_argument("video_path")
    parser.add_argument("--threshold", type=float, default=0.35)
    parser.add_argument("--device", choices=["auto", "cpu", "mps", "cuda"], default="auto")
    parser.add_argument("--sample-fps", type=float, default=None)
    args = parser.parse_args()

    requested_device = args.device
    device = resolve_device(requested_device)
    total_started_at = time.perf_counter()

    try:
        payload = run_detection(args, device)
    except Exception:
        if requested_device != "auto" or device == "cpu":
            raise
        emit_timing("device_fallback", total_started_at, f"from={device} to=cpu")
        payload = run_detection(args, "cpu")

    emit_timing("total", total_started_at, f"device={payload.get('device', device)}")
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
