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

if [[ ! -x "$WHISPER_CLI" ]]; then
  echo "Missing whisper-cli at $WHISPER_CLI" >&2
  exit 66
fi

if [[ ! -f "$MODEL_PATH" ]]; then
  echo "Missing model at $MODEL_PATH" >&2
  exit 66
fi

mkdir -p "$(dirname "$OUTPUT_BASE")"

WORK_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

WAV_PATH="$WORK_DIR/audio.wav"

ffmpeg -hide_banner -loglevel error \
  -i "$INPUT_PATH" \
  -vn -ar 16000 -ac 1 -c:a pcm_s16le \
  "$WAV_PATH"

"$WHISPER_CLI" \
  -m "$MODEL_PATH" \
  -f "$WAV_PATH" \
  -l "$LANGUAGE" \
  -ng \
  -oj -ojf -osrt -otxt \
  -of "$OUTPUT_BASE" \
  -pp

echo "Transcript written to:"
echo "  $OUTPUT_BASE.json"
echo "  $OUTPUT_BASE.srt"
echo "  $OUTPUT_BASE.txt"
