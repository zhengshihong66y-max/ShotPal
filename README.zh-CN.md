Language: [EN](README.md) | 简中

<a name="feature-previews"></a>
<a name="showcase"></a>

<p align="center">
  <a href="https://shotpal.newtybei.com/#overview-story">
    <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/36785bf1dc5ff11f2d2ebc0453805eb310e102cd/docs/assets/github/shotpal-feature-trio-github.%67if" width="1100" height="606" alt="ShotPal Pro deconstructs a film through download, analysis, and reusable output workflows">
  </a>
</p>

<p align="center">
  <a href="https://shotpal.newtybei.com">
    <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/36785bf1dc5ff11f2d2ebc0453805eb310e102cd/docs/assets/github/release-strip.svg" width="820" height="98" alt="Visit the official ShotPal Pro website — version and platform information">
  </a>
</p>

<p align="center">
  <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/36785bf1dc5ff11f2d2ebc0453805eb310e102cd/docs/assets/github/showcase/posters/download.webp" width="1100" height="825" alt="Download — Paste a public link to import the film and its source details into your library.">
</p>

<p align="center">
  <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/36785bf1dc5ff11f2d2ebc0453805eb310e102cd/docs/assets/github/showcase/posters/scene.webp" width="1100" height="825" alt="Scene Detection — Automatically detect cuts and jump between edits with the up and down arrow keys.">
</p>

<p align="center">
  <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/36785bf1dc5ff11f2d2ebc0453805eb310e102cd/docs/assets/github/showcase/posters/capture.webp" width="1100" height="825" alt="Capture Frame — Save the exact current frame with its source and timecode using E.">
</p>

<p align="center">
  <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/36785bf1dc5ff11f2d2ebc0453805eb310e102cd/docs/assets/github/showcase/posters/audio.webp" width="1100" height="825" alt="Audio Range — Set In and Out with I and O, then export the audio clip with P.">
</p>

<p align="center">
  <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/36785bf1dc5ff11f2d2ebc0453805eb310e102cd/docs/assets/github/showcase/posters/subtitle.webp" width="1100" height="825" alt="Local Subtitles — Transcribe on your Mac and keep every subtitle synchronized with playback.">
</p>

<p align="center">
  <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/f9f00c185df035ac50d0a38c1496756dfee5e56e/docs/assets/github/showcase/posters/storyboard.webp" width="1100" height="825" alt="Storyboard — Export shot numbers, timecodes, frames, and subtitles in one organized table.">
</p>

<p align="center">
  <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/f9f00c185df035ac50d0a38c1496756dfee5e56e/docs/assets/github/showcase/posters/drag.webp" width="1100" height="825" alt="Drag Out — Drag saved frames, audio, and music directly into your editing software.">
</p>

<p align="center">
  <img src="https://github.com/zhengshihong66y-max/ShotPal/raw/36785bf1dc5ff11f2d2ebc0453805eb310e102cd/docs/assets/github/showcase/posters/music.webp" width="1100" height="825" alt="Music Recognition — Identify tracks and locate the matching moments in the film.">
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
