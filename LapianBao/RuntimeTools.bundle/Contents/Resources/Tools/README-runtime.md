# LapianBao Runtime Resources

这个目录会随 Xcode 同步到 App 的 `Contents/Resources/RuntimeTools.bundle/Contents/Resources/Tools`。打包前优先检查 `runtime-manifest.json`。

## 已内嵌

- `bin/yt-dlp`：固定版本官方 zipimport 发行包（含 EJS），只通过内置 Python 的绝对路径调用。
- `bin/deno`：Apple Silicon JavaScript 运行时；不需要首次启动下载。
- `downloader-manifest.json`：上述下载组件的版本、上游地址和 SHA256；`licenses/` 保存许可证。
- `transcribe_with_whisper.sh`：本地 Whisper 转写脚本。
- `whisper.cpp/build/bin/whisper-cli`：本地 Whisper 命令行工具。
- `whisper.cpp/models/ggml-large-v3-turbo-q5_0.bin`：默认语音转写模型。
- `whisper.cpp/models/for-tests-silero-v6.2.0-ggml.bin`：可选 VAD 模型。
- `bin/ffmpeg`、`bin/ffprobe`：静态 universal 二进制，支持 arm64 和 x86_64。
- `python/cpython-3.11-aarch64-apple-darwin`、`python/cpython-3.11-x86_64-apple-darwin`：内置 standalone Python 3.11。
- `detect_music.py`：音乐识别脚本。
- `detect_scene_cuts_transnet.py`：场景识别脚本。
- `recognition/site-packages`：43 个固定版本 arm64 wheel 的完整依赖闭包，包括 ShazamIO/native core、PyTorch、NumPy 与 TransNetV2 权重。
- `recognition/manifest.json`、`recognition/recognition-wheels.lock.json`：逐文件哈希、wheel 来源和 SHA256；各包的 dist-info 保留第三方许可证。
- `recognition_bootstrap.py`：由内置 Python `-I -B -u` 显式加载上述目录，不使用宿主 site-packages 或 venv。
- `requirements-music.txt`、`requirements-transnet.txt`：构建机器解析锁文件的输入，不在用户机器安装。
- `setup_music_env.sh`、`setup_transnet_env.sh`：手动重建 Python 环境的备用脚本。
- `third-party-licenses/whisper.cpp-LICENSE`：第三方许可。
- `third-party-licenses/FFmpeg-static-binaries.md`：FFmpeg 来源、哈希和许可说明。
- `third-party-licenses/python-build-standalone.md`：Python 运行时来源、哈希和许可说明。

## App 管理的运行时

- `music-env` 和 `transnet-env` 是 Python 虚拟环境，本机生成的副本包含解释器绝对路径，不能直接作为可分发资源。
- App 的音乐识别和场景识别直接使用内嵌识别资源；不会创建 PythonRuntimes、运行 pip、寻找 Homebrew 或使用旧 venv。旧用户环境不删除但不再选用。
- 识别依赖和分镜模型可离线初始化；音乐匹配仍需要在线 Shazam 服务，服务失败会明确报错，不当作无匹配。
- 内置 yt-dlp 是始终保留的基线；仅手动更新时下载到 Application Support，哈希校验、内置解释器启动验证及验证凭据写入成功后才允许选用。旧版无验证凭据的下载器不会被自动选中。

## 打包前处理

1. 保留当前目录中的模型、脚本和许可文件；缺少下载组件时运行 `Tools/prepare_download_runtime.py`（构建机器操作，不是用户首次启动步骤）。
2. 不要把本机 `music-env`、`transnet-env`、`tmp`、`output`、`.codex-derived` 放进分发包。
3. 构建后运行 `Tools/verify_download_runtime.py /absolute/path/to/拉片宝.app`；必须验证成品 app，不以源码目录存在文件替代。
4. 正式签名时，确保 Deno、Python、`whisper-cli`、`ffmpeg`、`ffprobe` 等嵌套 Mach-O 工具也使用 Developer ID 重新签名；Deno 要验证真实 JS 执行而不只是版本号。
5. 缺少识别资源时，在构建机器运行 `Tools/prepare_recognition_runtime.py`，它仅使用仓库内的固定 wheel 锁文件；Xcode 构建前运行 `Tools/check_recognition_bundle_inputs.py` 校验全部文件。不要复制本机虚拟环境。
6. 签名后与最终 DMG 内均运行 `Tools/verify_recognition_runtime.py /absolute/path/to/拉片宝.app`，验证离线模型加载、原生音频指纹、真实分镜推理与网络失败分类。此测试不等价于物理 M4 / macOS14 / 手动 UI / 在线歌曲匹配验收。
