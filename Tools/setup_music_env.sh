#!/usr/bin/env bash
# Setup the Python environment for music recognition.
# Run once from the repo root: bash Tools/setup_music_env.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_DIR="$SCRIPT_DIR/music-env"
REQUIREMENTS_FILE="$SCRIPT_DIR/requirements-music.txt"

PYTHON_BIN=""
ARCH="$(uname -m)"
PYTHON_CANDIDATES=()
case "$ARCH" in
    arm64)
        PYTHON_CANDIDATES+=(
            "$SCRIPT_DIR/python/cpython-3.11-aarch64-apple-darwin/bin/python3.11"
            "$SCRIPT_DIR/../LapianBao/RuntimeTools.bundle/Contents/Resources/Tools/python/cpython-3.11-aarch64-apple-darwin/bin/python3.11"
        )
        ;;
    x86_64)
        PYTHON_CANDIDATES+=(
            "$SCRIPT_DIR/python/cpython-3.11-x86_64-apple-darwin/bin/python3.11"
            "$SCRIPT_DIR/../LapianBao/RuntimeTools.bundle/Contents/Resources/Tools/python/cpython-3.11-x86_64-apple-darwin/bin/python3.11"
        )
        ;;
esac
PYTHON_CANDIDATES+=(python3.12 python3.11 python3.13 python3)

for candidate in "${PYTHON_CANDIDATES[@]}"; do
    if [ -x "$candidate" ]; then
        PYTHON_BIN="$candidate"
        break
    fi
    if command -v "$candidate" >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v "$candidate")"
        break
    fi
done

if [ -z "$PYTHON_BIN" ]; then
    echo "未找到 Python 3.11 以上版本。"
    exit 1
fi

if [ ! -f "$REQUIREMENTS_FILE" ]; then
    echo "缺少依赖清单：$REQUIREMENTS_FILE"
    exit 1
fi

export PYTHONDONTWRITEBYTECODE=1
echo "Creating virtual environment at $ENV_DIR"
"$PYTHON_BIN" -m venv --clear "$ENV_DIR"

echo "Installing dependencies"
"$ENV_DIR/bin/python3" -m pip install --upgrade pip setuptools wheel
"$ENV_DIR/bin/python3" -m pip install -r "$REQUIREMENTS_FILE"

echo ""
echo "Done! Interpreter: $ENV_DIR/bin/python3"
echo "Test: $ENV_DIR/bin/python3 $SCRIPT_DIR/detect_music.py <video_file>"
