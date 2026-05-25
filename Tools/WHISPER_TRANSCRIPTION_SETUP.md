# 本地语音转文字准备

日期：2026-05-25

本目录已经准备好基于 `whisper.cpp` 的本地语音转文字能力，用于后续“内容”页面生成原脚本、字幕时间轴和 Markdown 导出。

## 已准备内容

- 引擎：`Tools/whisper.cpp`
- 命令行工具：`Tools/whisper.cpp/build/bin/whisper-cli`
- 模型：`Tools/whisper.cpp/models/ggml-large-v3-turbo-q5_0.bin`
- 包装脚本：`Tools/transcribe_with_whisper.sh`

模型说明：

```text
large-v3-turbo-q5_0
多语言
约 547 MiB
适合先做本地内容提取 MVP
```

## 使用方式

```bash
Tools/transcribe_with_whisper.sh <input-video-or-audio> <output-base-path> [language]
```

示例：

```bash
Tools/transcribe_with_whisper.sh movie.mp4 Tools/transcripts/movie zh
```

输出：

```text
Tools/transcripts/movie.txt
Tools/transcripts/movie.srt
Tools/transcripts/movie.json
```

## 当前策略

脚本会先用 `ffmpeg` 把输入视频或音频转成 16kHz 单声道 WAV，再调用 `whisper-cli`。

当前默认使用 `--no-gpu`。原因是首次测试 GPU / Metal 路径时在缓冲区分配阶段出现崩溃；CPU + Accelerate 路径已经验证可用。后续可以单独排查 Metal 后端，或者改用 WhisperKit 做原生 Core ML 集成。

## 验证结果

已用 `Tools/whisper.cpp/samples/jfk.wav` 测试通过，成功输出 `.txt`、`.srt`、`.json`。
