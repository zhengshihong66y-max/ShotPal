# LapianBao Runtime Resources

这个目录会随 Xcode 同步到 App 的 `Contents/Resources/RuntimeTools.bundle/Contents/Resources/Tools`。打包前优先检查 `runtime-manifest.json`。

## 已内嵌

- `transcribe_with_whisper.sh`：本地 Whisper 转写脚本。
- `whisper.cpp/build/bin/whisper-cli`：本地 Whisper 命令行工具。
- `whisper.cpp/models/ggml-large-v3-turbo-q5_0.bin`：默认语音转写模型。
- `whisper.cpp/models/for-tests-silero-v6.2.0-ggml.bin`：可选 VAD 模型。
- `bin/ffmpeg`、`bin/ffprobe`：静态 universal 二进制，支持 arm64 和 x86_64。
- `python/cpython-3.11-aarch64-apple-darwin`、`python/cpython-3.11-x86_64-apple-darwin`：内置 standalone Python 3.11。
- `detect_music.py`：音乐识别脚本。
- `detect_scene_cuts_transnet.py`：场景识别脚本。
- `requirements-music.txt`、`requirements-transnet.txt`：首次运行安装 Python 环境时使用。
- `setup_music_env.sh`、`setup_transnet_env.sh`：手动重建 Python 环境的备用脚本。
- `third-party-licenses/whisper.cpp-LICENSE`：第三方许可。
- `third-party-licenses/FFmpeg-static-binaries.md`：FFmpeg 来源、哈希和许可说明。
- `third-party-licenses/python-build-standalone.md`：Python 运行时来源、哈希和许可说明。

## App 管理的运行时

- `music-env` 和 `transnet-env` 是 Python 虚拟环境，本机生成的副本包含解释器绝对路径，不能直接作为可分发资源。
- App 首次使用音乐识别或场景识别时，会根据 requirements 在 `~/Library/Application Support/LapianBao/PythonRuntimes/` 下创建对应环境。
- 自动创建环境优先使用 bundle 内置的 standalone Python，不要求目标 Mac 预装 Python；首次安装依赖仍需要网络连接。
- `yt-dlp` 当前由 App 自检流程下载安装到 Application Support，Homebrew 包装脚本不能作为可分发二进制。

## 打包前处理

1. 保留当前目录中的模型、脚本和许可文件。
2. 不要把本机 `music-env`、`transnet-env`、`tmp`、`output`、`.codex-derived` 放进分发包。
3. 构建后检查 App 内是否存在 `Contents/Resources/RuntimeTools.bundle/Contents/Resources/Tools/runtime-manifest.json`、Whisper 模型和 `bin/ffmpeg`。
4. 正式签名时，确保 `whisper-cli`、`ffmpeg`、`ffprobe` 等嵌套 Mach-O 工具也使用 Developer ID 重新签名。
