Language: [EN](README.md) | 简中

<a name="feature-previews"></a>
<a name="showcase"></a>

<p align="center">
  <a href="https://shotpal.newtybei.com/#overview-story">
    <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/749a1f5ab7a7224c331f1fd0bd4ce883ebc69333/docs/assets/github/zh-CN/shotpal-feature-trio-github.%67if" width="1100" height="606" alt="ShotPal Pro：导入影片、分析视听语言，将画面与片段整理为可复用素材">
  </a>
</p>

<p align="center">
  <a href="https://shotpal.newtybei.com">
    <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/749a1f5ab7a7224c331f1fd0bd4ce883ebc69333/docs/assets/github/zh-CN/release-strip.svg" width="820" height="98" alt="访问 ShotPal Pro 官网：版本、系统要求、处理器与下载大小">
  </a>
</p>

<p align="center">
  <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/749a1f5ab7a7224c331f1fd0bd4ce883ebc69333/docs/assets/github/zh-CN/posters/download.png" width="1100" height="825" alt="下载：粘贴公开链接，将影片与来源信息一同导入素材库。">
</p>

<p align="center">
  <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/749a1f5ab7a7224c331f1fd0bd4ce883ebc69333/docs/assets/github/zh-CN/posters/scene.png" width="1100" height="825" alt="分镜识别：自动识别切点，使用上下方向键在镜头之间跳转。">
</p>

<p align="center">
  <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/749a1f5ab7a7224c331f1fd0bd4ce883ebc69333/docs/assets/github/zh-CN/posters/capture.png" width="1100" height="825" alt="保存画面：按 E 保存当前画面，同时保留来源与时间码。">
</p>

<p align="center">
  <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/749a1f5ab7a7224c331f1fd0bd4ce883ebc69333/docs/assets/github/zh-CN/posters/audio.png" width="1100" height="825" alt="声音选区：使用 I / O 设置入点和出点，按 P 导出音频。">
</p>

<p align="center">
  <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/749a1f5ab7a7224c331f1fd0bd4ce883ebc69333/docs/assets/github/zh-CN/posters/subtitle.png" width="1100" height="825" alt="本地字幕：在 Mac 上转写字幕，并与影片播放保持同步。">
</p>

<p align="center">
  <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/749a1f5ab7a7224c331f1fd0bd4ce883ebc69333/docs/assets/github/zh-CN/posters/storyboard.png" width="1100" height="825" alt="分镜表：将镜号、时间码、画面与字幕导出为一份表格。">
</p>

<p align="center">
  <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/749a1f5ab7a7224c331f1fd0bd4ce883ebc69333/docs/assets/github/zh-CN/posters/drag.png" width="1100" height="825" alt="拖出素材：将画面、音频和音乐直接拖入剪辑软件。">
</p>

<p align="center">
  <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/749a1f5ab7a7224c331f1fd0bd4ce883ebc69333/docs/assets/github/zh-CN/posters/music.png" width="1100" height="825" alt="音乐识别：识别曲目，并定位它们在影片中出现的时刻。">
</p>

# ShotPal Pro

在 Mac 上拉片、截取画面、提取音频，建立可重复使用的参考素材库。

**macOS 14+ · Apple 芯片 · 英文 / 简体中文**

[官网与演示](https://shotpal.newtybei.com/#overview-story) · [下载](https://github.com/zhengshihong66y-max/ShotPal/releases) · [隐私政策](https://shotpal.newtybei.com/privacy)

## 安装

从 [Releases](https://github.com/zhengshihong66y-max/ShotPal/releases/tag/v1.2.1-rc.2026090901) 下载 **DMG 安装包**，其中包含应用及所需工具。GitHub 的源码 ZIP 供开发者使用。

**当前版本：1.2.1 候选版。** 已完成 Developer ID 签名，Apple 公证与干净 Mac 验收仍在等待完成。如果 macOS 阻止安装，请等待公证完成后的版本。

公证完成后，打开 DMG，将 ShotPal Pro 拖入**应用程序**，再选择一个文件夹作为素材库。

## 快速上手

1. 打开本地视频，或点击 **+** 导入支持的平台链接。
2. 使用**分镜模式**、字幕或音乐识别分析影片。
3. 保存画面、导出音频，或生成分镜表。
4. 将保存的素材拖入剪辑软件。

**快捷键：** Space — 播放/暂停 · E — 保存画面 · I/O — 设置音频入点/出点 · P — 导出音频。

请将原始视频与素材库文件夹一起保存。分镜识别与字幕转写在本地运行；在线导入与音乐识别需要联网。

## 致谢

基于 [yt-dlp](https://github.com/yt-dlp/yt-dlp)、[FFmpeg](https://ffmpeg.org/)、[Whisper](https://github.com/openai/whisper)、[whisper.cpp](https://github.com/ggml-org/whisper.cpp)、[TransNet V2](https://github.com/soCzech/TransNetV2)（[PyTorch 实现](https://github.com/allenday/transnetv2_pytorch)）与 [ShazamIO](https://github.com/shazamio/ShazamIO) 构建。

同时使用 [Python](https://www.python.org/)、[python-build-standalone](https://github.com/astral-sh/python-build-standalone)、[Deno](https://github.com/denoland/deno)、[PyTorch](https://pytorch.org/) 与 [NumPy](https://numpy.org/)。第三方项目保留各自的许可证与声明。
