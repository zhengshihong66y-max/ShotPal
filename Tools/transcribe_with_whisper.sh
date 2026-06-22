#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <input-video-or-audio> <output-base-path> [language]" >&2
  echo "Example: $0 movie.mp4 ./transcripts/movie zh" >&2
  exit 64
fi

INPUT_PATH="$1"
OUTPUT_BASE="$2"
LANGUAGE="${3:-auto}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISPER_DIR="$SCRIPT_DIR/whisper.cpp"
WHISPER_CLI="$WHISPER_DIR/build/bin/whisper-cli"
MODEL_PATH="$WHISPER_DIR/models/ggml-large-v3-turbo-q5_0.bin"

if [[ -x "$SCRIPT_DIR/bin/ffmpeg" ]]; then
  FFMPEG_BIN="$SCRIPT_DIR/bin/ffmpeg"
elif command -v ffmpeg >/dev/null 2>&1; then
  FFMPEG_BIN="$(command -v ffmpeg)"
elif [[ -x /opt/homebrew/bin/ffmpeg ]]; then
  FFMPEG_BIN="/opt/homebrew/bin/ffmpeg"
elif [[ -x /usr/local/bin/ffmpeg ]]; then
  FFMPEG_BIN="/usr/local/bin/ffmpeg"
else
  echo "Missing ffmpeg. Expected bundled tool at $SCRIPT_DIR/bin/ffmpeg or an installed ffmpeg on PATH." >&2
  exit 66
fi

if [[ ! -x "$WHISPER_CLI" ]]; then
  echo "Missing whisper-cli at $WHISPER_CLI" >&2
  exit 66
fi

if [[ ! -f "$MODEL_PATH" ]]; then
  echo "Missing model at $MODEL_PATH" >&2
  exit 66
fi

MODEL_SIZE="$(wc -c < "$MODEL_PATH" | tr -d '[:space:]')"
if [[ "$MODEL_SIZE" -lt 100000000 ]]; then
  echo "Whisper model looks incomplete at $MODEL_PATH (${MODEL_SIZE} bytes)" >&2
  echo "Expected the large-v3-turbo-q5_0 model to be hundreds of MB." >&2
  exit 66
fi

mkdir -p "$(dirname "$OUTPUT_BASE")"
rm -f "$OUTPUT_BASE.json" "$OUTPUT_BASE.srt" "$OUTPUT_BASE.txt"

WORK_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

WAV_PATH="$WORK_DIR/audio.wav"

echo "LPB_PROGRESS 0.05 提取音频"
"$FFMPEG_BIN" -hide_banner -loglevel error \
  -i "$INPUT_PATH" \
  -vn -ar 16000 -ac 1 \
  -af "highpass=f=80,lowpass=f=7600,loudnorm=I=-18:TP=-1.5:LRA=11" \
  -c:a pcm_s16le \
  "$WAV_PATH"

echo "LPB_PROGRESS 0.18 本地 Whisper 转写"
THREADS="${LPB_WHISPER_THREADS:-}"
if [[ -z "$THREADS" ]]; then
  THREADS="$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || sysctl -n hw.physicalcpu 2>/dev/null || echo 4)"
fi
if ! [[ "$THREADS" =~ ^[0-9]+$ ]] || [[ "$THREADS" -lt 2 ]]; then
  THREADS=4
fi

VAD_ARGS=()
VAD_MODEL_PATH="${LPB_WHISPER_VAD_MODEL:-$WHISPER_DIR/models/for-tests-silero-v6.2.0-ggml.bin}"
if [[ "${LPB_WHISPER_USE_VAD:-1}" == "1" && -f "$VAD_MODEL_PATH" ]]; then
  VAD_ARGS=(--vad --vad-model "$VAD_MODEL_PATH" -vt 0.45 -vspd 180 -vsd 450 -vmsd 28 -vp 120)
fi

COMMON_ARGS=(
  -m "$MODEL_PATH"
  -f "$WAV_PATH"
  -l "$LANGUAGE"
  -t "$THREADS"
  -bo 3
  -bs 3
  -mc 64
  -ml 64
  -sow
  -et 2.20
  -lpt -0.80
  -nth 0.72
  -nf
  -sns
  -oj -ojf -osrt -otxt
  -of "$OUTPUT_BASE"
  -pp
)

run_whisper() {
  local -a cmd=("$WHISPER_CLI" "${COMMON_ARGS[@]}")
  if [[ $# -gt 0 ]]; then
    cmd+=("$@")
  fi
  if [[ "${#VAD_ARGS[@]}" -gt 0 ]]; then
    cmd+=("${VAD_ARGS[@]}")
  fi
  "${cmd[@]}"
}

if [[ "${LPB_WHISPER_CPU_ONLY:-0}" == "1" ]]; then
  run_whisper -ng
else
  set +e
  run_whisper
  WHISPER_STATUS=$?
  set -e
  if [[ "$WHISPER_STATUS" -ne 0 && "${LPB_WHISPER_RETRY_CPU:-1}" == "1" ]]; then
    echo "LPB_PROGRESS 0.20 GPU 不稳定，切换 CPU 重试"
    rm -f "$OUTPUT_BASE.json" "$OUTPUT_BASE.srt" "$OUTPUT_BASE.txt"
    run_whisper -ng
  elif [[ "$WHISPER_STATUS" -ne 0 ]]; then
    exit "$WHISPER_STATUS"
  fi
fi

echo "LPB_PROGRESS 0.96 解析字幕结果"
echo "Transcript written to:"
echo "  $OUTPUT_BASE.json"
echo "  $OUTPUT_BASE.srt"
echo "  $OUTPUT_BASE.txt"
