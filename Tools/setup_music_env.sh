#!/bin/bash
# Setup the Python environment for music recognition.
# Run once from the repo root: bash Tools/setup_music_env.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_DIR="$SCRIPT_DIR/music-env"

PYTHON_BIN=""
PIP_BIN=""
for candidate in /opt/miniconda3/bin/python /opt/anaconda3/bin/python python3.13 python3.12 python3.11 python3; do
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
    echo "未找到 Python 3，请先安装 Python 3.11/3.12/3.13。"
    exit 1
fi

for candidate in /opt/miniconda3/bin/pip /opt/anaconda3/bin/pip pip3.13 pip3.12 pip3.11 pip3; do
    if [ -x "$candidate" ]; then
        PIP_BIN="$candidate"
        break
    fi
    if command -v "$candidate" >/dev/null 2>&1; then
        PIP_BIN="$(command -v "$candidate")"
        break
    fi
done

if [ -z "$PIP_BIN" ]; then
    echo "未找到 pip。请先安装 pip，或修复当前 Python 的 ensurepip。"
    exit 1
fi

echo "Creating virtual environment at $ENV_DIR …"
"$PYTHON_BIN" -m venv --clear --without-pip "$ENV_DIR"

echo "Installing dependencies …"
"$PIP_BIN" --python "$ENV_DIR/bin/python3" install --upgrade pip -q
"$ENV_DIR/bin/python3" -m pip install shazamio aiohttp requests audioop-lts -q

echo ""
echo "Done! Interpreter: $ENV_DIR/bin/python3"
echo "Test: $ENV_DIR/bin/python3 $SCRIPT_DIR/detect_music.py <video_file>"
