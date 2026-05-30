# 拉片宝 AI 接手手册

最后更新：2026-05-29

本文是拉片宝项目的唯一权威 Markdown。后续 AI 或开发者接手时，先读本文，再按需读源码。本文同时记录产品结构、工程结构、设计原则、已经定下来的 UI 数值和可恢复的设计基线。

## 1. 项目一句话

拉片宝是一个 macOS 原生 SwiftUI App，用来把视频素材导入本地库，快速看片、识别场景、采样画面、截取声音、转写内容、识别音乐，并把这些拉片结果沉淀为可导出的创作资产。

它不是网页后台，不是通用文件管理器，也不是传统剪辑软件。它的核心价值是：让用户更快完成拉片，并把画面、声音、文本、音乐、批注和场景切点保存下来，后续可以回到原视频时间点，也可以导出到外部整理或剪辑流程。

## 2. 接手前先记住

- 当前项目是 macOS App，入口是 `LapianBaoApp.swift`，主界面是 `ContentView.swift`，数据中心是 `LibraryStore.swift`，播放控制是 `PreviewController.swift`，窗口和键盘桥接是 `AppChrome.swift`。
- 不要把主播放器改回 SwiftUI 原生 `VideoPlayer`。当前用 `AVPlayerLayer` 承载画面，原因是避免系统悬停控制层压暗视频。
- 不要引入网页式后台、营销页、超大 hero、装饰渐变球、表格管理器风格。
- 不要随手重置 `Design` 里的尺寸。本文第 9 节列出的数值是当前设计基线。
- `Tools/whisper.cpp` 是第三方依赖目录，里面的 Markdown 不是项目产品文档，平时不要清理或改写。
- 每次较大代码修改后用 `xcodebuild -project LapianBao.xcodeproj -scheme LapianBao -destination 'platform=macOS' build` 验证。
- 改到 App 启动、窗口、`AppChrome.swift`、`LapianBaoApp.swift`、工程构建设置后，必须再跑 `Tools/check_launch_window.sh`。它会用独立 DerivedData 构建、确认没有 Preview/JIT debug dylib、冷启动 App，并验证系统窗口数至少为 1。
- 启动阶段不能同步做重活：`applicationDidFinishLaunching(_:)` 必须异步调度 `completeLaunchSetupIfNeeded()`；主窗口先显示并完成一次绘制，再用 `DispatchQueue.main.asyncAfter` 延后 `loadLastLibraryForLaunch()`。启动恢复素材库时，目录枚举必须在后台完成。这是防止 Xcode 增量构建后旧调试进程/Dock 显示“应用未响应”的硬规则，`Tools/check_launch_window.sh` 会检查。
- 不要在项目源码里新增 SwiftUI `#Preview`。本项目以真实 App 冷启动检查为准，避免重新引入 Preview macro/plugin server 或 JIT 注入路径。

## 3. 当前产品结构

主窗口是三段结构：

```text
左侧 icon rail + 素材区 | 主工作区
```

普通宽度下，素材区和主工作区左右排列；宽度小于 `900pt` 时，素材区在上、工作区在下。窗口默认尺寸是 `1280 x 800`，最小内容尺寸是 `960 x 720`。

### 3.1 左侧 rail

左侧 rail 是工作区入口，不是标签栏。宽度固定 `56pt`，包含 macOS 原生红黄绿窗口按钮和五个工作区入口：

- `主页`：看片、时间线、场景识别、截图、批注、声音采样、转写摘要、音乐识别。
- `画面`：已收集画面的网格、预览、亮度直方图、色卡、本地视觉模型分析。
- `声音`：已导出的声音片段列表、播放、定位回原视频、音乐识别和下载。
- `内容`：Whisper 字幕、内容节点时间线、本地文本模型整理。
- `设置`：批量识别管理、API 服务配置、本机模型配置。

对应源码是 `AppWorkspace`。

### 3.2 素材区

素材区包含：

- 顶部工具栏：下载视频、标签筛选、排序、三档网格密度。
- 视频网格：每张素材卡可点击自动播放、拖出原视频文件、打开更多菜单。
- 标签菜单：筛选标签、重命名标签、全局删除标签。
- 排序菜单：名称、导入时间、片长、文件大小、分辨率、标签；方向为升序或降序。

素材区默认宽度 `340pt`。非画面工作区宽度限制为 `320pt...660pt`；画面工作区默认宽度是窗口宽度的 `50%`，最大到 `containerWidth - 260pt`。用户拖动分隔线后保存到 `UserDefaults` 的 `mediaPanelWidth` 或 `frameMediaPanelWidth`。

### 3.3 主工作区

主工作区根据 rail 当前选择切换：

- `PreviewPanelView`：主页。
- `FramesWorkspaceView`：画面工作区。
- `AudioWorkspaceView`：声音工作区。
- `ContentWorkspaceView`：内容工作区。
- `SettingsWorkspaceView`：设置工作区。

工作区之间跳转时通过 `jumpToVideo(path:time:)` 选中视频，并发出 `.lapianBaoSeekRequest` 通知，让主页播放器跳到对应时间点。

## 4. 核心文件地图

### `LapianBaoApp.swift`

负责 App 生命周期和全局菜单：

- `AppDelegate`：设置常规 macOS App 激活策略；显式创建和强引用主 `NSWindow`；安装全局预览键盘监听；关闭最后窗口后退出；禁用系统状态保存和恢复。
- 主窗口不走 SwiftUI `WindowGroup`。这是为了避免 Debug 构建或 Xcode Preview/JIT 注入导致“进程存在但没有可见窗口”。
- `applicationDidFinishLaunching(_:)` 只负责异步调度启动设置，不能同步创建 SwiftUI 主界面。主窗口可见并完成一次绘制后，再用 `loadLastLibraryForLaunch()` 恢复上次素材库；启动恢复的目录枚举在后台线程执行，避免启动握手阶段或首帧绘制前被同步目录扫描卡住。
- `ensureMainWindowVisible()` 是启动兜底：启动完成、应用激活、Dock 重新打开、启动后延迟复查都会确保窗口存在、在可见屏幕内，并被拉到前台。
- 窗口标题为 `LapianBao`，默认尺寸 `1280 x 800`，最小内容尺寸来自 `Design.minimumWindowWidth = 960` 和 `Design.minimumWindowHeight = 720`。
- 菜单替换默认新建项，提供 `打开文件夹`，快捷键 `Command + O`。

### `AppChrome.swift`

负责 AppKit 桥接：

- `PreviewKeyboardCommand`：播放器快捷键命令枚举。
- `PreviewKeyboardEventRouter`：把物理按键转换为命令，且在文本输入框中不拦截。
- `WindowConfigurator`：去掉系统标题栏，透明窗口背景，保留可调整大小、关闭、最小化、全屏能力。
- `WindowDragRegion`：自定义窗口拖拽区域。
- `PreviewKeyboardHandler` 和 `KeyboardCaptureNSView`：局部键盘焦点捕获。
- `NativeWindowTrafficLights`：隐藏系统红黄绿按钮，在自定义 rail 的固定坐标绘制同尺寸按钮，并转发关闭、最小化、全屏动作到 `NSWindow`。

红黄绿按钮尺寸 `12pt`，间距 `6pt`。不要把 `window.standardWindowButton(...)` 重新挂到 SwiftUI 容器中；系统标题栏会在启动和激活阶段重排它们，导致位置漂移。

### `LibraryStore.swift`

全局数据和媒体处理中心，标记为 `@MainActor ObservableObject`。

主要模型：

- `VideoItem`：视频 URL、名称、文件夹名、扩展名。
- `VideoMetadata`：时长、帧率、分辨率、文件大小、创建和修改时间。
- `SampledFrame`：截图或场景代表帧，含视频路径、时间、缩略图、备注、标签。
- `AnnotationItem`：某个视频时间点的文字批注。
- `AudioClipItem`：In/Out 声音片段，含导出路径和波形。
- `TranscriptSegment`：Whisper 转写片段。
- `MusicRecognitionItem`：识别到的音乐，含歌名、作者、封面、Apple Music 链接、出现时间。
- `RemoteImportJob`：网络视频下载任务。

主要职责：

- 扫描本地视频库，递归读取 `mp4`、`mov`、`m4v`、`mkv`、`avi`、`webm`。
- 生成缩略图、时长、帧率、分辨率、文件大小。
- 标签保存和筛选。
- 视频排序。
- 远程视频下载和必要转码。
- 生成视频波形、帧带和场景切点。
- 截图、批注、声音片段、字幕、音乐识别结果的项目数据保存。
- 导出图片、声音、字幕和音乐。

### `PreviewController.swift`

播放器状态中心，标记为 `@MainActor ObservableObject`：

- 使用单例 `AVPlayer`。
- 以 `1 / 30s` 周期更新 `elapsed`、`duration`、`progress`、`playbackRate`。
- `loadVideo(_:autoplay:)` 切换视频，加载波形、帧带和缓存场景切点。
- 支持播放、暂停、跳转、逐帧、正向变速、反向播放。
- 反向播放会尝试使用 ffmpeg 生成 intra-only 静音代理视频，缓存到用户缓存目录 `LapianBao/ReversePlaybackProxies`。
- ffmpeg 查找路径是 `/opt/homebrew/bin/ffmpeg`、`/usr/local/bin/ffmpeg`、`/usr/bin/ffmpeg`。

### `ContentView.swift`

绝大部分 UI 目前仍在这个文件中。它包含设计常量、素材区、主页播放器、时间线、导出面板、画面/声音/内容工作区、标签 UI、音乐识别 UI、本地模型分析 UI 等。后续可以拆文件，但拆分时保持行为不变。

## 5. 数据保存与文件约定

用户打开的素材库文件夹是项目数据根目录。当前保存规则：

- 最近素材库路径：`UserDefaults.lastLibraryPath`。
- 素材库安全书签：`UserDefaults.lastLibraryBookmark`。
- 素材网格密度：`UserDefaults.mediaGridSize`，取值 `0...2`。
- 当前工作区：`UserDefaults.appWorkspace`。
- 侧边栏折叠状态：`UserDefaults.isSidebarCollapsed`，当前 UI 里暂未作为主要交互使用。
- 素材区宽度：`UserDefaults.mediaPanelWidth`。
- 画面工作区素材区宽度：`UserDefaults.frameMediaPanelWidth`。
- 排序字段：`UserDefaults.videoSortOption`。
- 排序方向：`UserDefaults.videoSortDirection`。
- 自定义下载 API：`UserDefaults.instagramImportEndpoint`。

素材库内项目文件：

- `.lapianbaotags.json`：视频标签。
- `.lapianbao_project.json`：采样画面、批注、声音片段、字幕、音乐识别结果。
- `.lapianbao_scene_cuts.json`：场景切点缓存，含检测器版本、视频签名、相对路径、文件大小、修改时间、切点和场景 ID。
- `LapianBaoExports/图片`：导出的截图和场景代表帧，生成 `index.md`。
- `LapianBaoExports/音效`：导出的 In/Out 声音片段。
- `LapianBaoExports/音乐`：下载的原曲和伴奏。

## 6. 四条主链路

### 导入

本地导入：

- `File > 打开文件夹` 选择素材库。
- `scanVideos(in:)` 递归扫描视频。
- 自动生成封面、时长、帧率、分辨率、文件大小和播放支持状态。
- 默认素材库路径是 `/Users/zhengshihong/Downloads/通用资源/视觉/视频`，存在时会优先打开。

网络导入：

- 入口是素材区顶部 `plus` 按钮。
- 支持一次输入多个链接。
- 当前平台识别：Instagram、YouTube、小红书、Bilibili、抖音 / TikTok。
- 优先本地 `yt-dlp`，小红书有原生解析回退；也支持用户填写自定义 API。
- 下载后如果编码不适合播放，会转码为 H.264。

### 分析

画面分析：

- 主页时间线显示均匀帧带或场景代表帧带。
- 可以截图当前帧，保存为 `SampledFrame(kind: .screenshot)`。
- 场景识别优先使用 TransNetV2，失败时有本地画面变化检测回退。
- 场景网格可显示切点代表帧，点击回到原视频时间。
- 画面工作区可查看已收集图片、亮度直方图、色卡，并用本机 Ollama 视觉模型分析。

声音分析：

- 视频波形样本数是 `4096`。
- 声音片段波形样本数是 `96`，版本 `AudioClipItem.currentWaveformVersion = 2`。
- 主页时间线支持 In/Out，导出为 `.m4a`。
- 声音片段可以播放、拖出、跳回原视频时间。

文本分析：

- `Tools/transcribe_with_whisper.sh` 调用 `Tools/whisper.cpp/build/bin/whisper-cli`。
- 转写输出保存为 `TranscriptSegment`，可导出 Markdown。
- 内容工作区能把字幕整理为章节/节点时间线。
- 本地文本模型是 Ollama `qwen3:4b-instruct`。

音乐分析：

- `Tools/detect_music.py` 识别视频中的音乐。
- 结果包含歌名、作者、封面、Apple Music 链接和出现时间。
- 可下载原曲或伴奏，下载工具走 YouTube 搜索和 `yt-dlp`。
- 音乐波形样本数是 `180`。

### 沉淀

项目资产包括：

- 视频标签。
- 截图和场景代表帧。
- 批注。
- In/Out 声音片段。
- Whisper 字幕。
- 音乐识别结果。
- 场景切点缓存。

所有资产都应该保留回到原视频时间点的能力。后续新增资产类型时，也要包含 `videoPath`、`videoName`、`time` 或时间区间。

### 导出

当前支持：

- 图片：JPG，写入 `LapianBaoExports/图片`，并维护 `index.md`。
- 声音：In/Out 区间导出 `.m4a` 到 `LapianBaoExports/音效`。
- 文本：Whisper 原脚本导出 Markdown，包含视频标题和时间戳文本行。
- 音乐：下载原曲和伴奏到 `LapianBaoExports/音乐`。

## 7. 播放与快捷键

播放器必须保持自定义控制，不使用系统 `VideoPlayer` 控制层。

键盘命令：

- `Space`：播放/暂停。
- `K`：播放/暂停；如果正在 J/L shuttle，则提升 shuttle 速度。
- `J`：单击后退一帧；按住进入向后 shuttle。
- `L`：单击前进一帧；按住进入向前 shuttle，不能启动普通正向播放或直接调用 `setRate(1)`。
- `Left Arrow`：后退一帧。
- `Right Arrow`：前进一帧。
- `I`：设置声音 In 点。
- `O`：设置声音 Out 点。
- `E`：导出当前帧图片。
- `U`：清除声音选区。
- `P`：导出当前声音选区。

键盘监听规则：

- 不带 `Command`、`Control`、`Option` 才拦截。
- 文本编辑控件获得焦点时不拦截。
- 快捷键命令只能由 app-level `NSEvent` monitor 分发到 `PreviewKeyboardCommandDispatcher`。
- `PreviewKeyboardWindow`、`PreviewKeyboardHandler`、capture view 可以消费事件防止系统 beep，但不能各自重复执行命令。
- 所有已处理的 `keyDown` 和 `keyUp` 都必须被消费；尤其是 `J/L` 松开时只发 `stopShuttle`，不能把事件继续传给系统。
- `J/L` shuttle 通过逐帧 seek，进入 shuttle 后初始每次 `2` 帧，最多加速到 `12` 帧，每 `33_000_000ns` 一次。

## 8. 外部工具和模型

本项目依赖若干本机工具。后续 AI 不要假设这些工具都能联网安装，先检查本地路径。

- `ffmpeg`：用于转码、提取音频、反向播放代理、音乐/音频处理。
- `yt-dlp`：用于网络视频和音乐下载，查找路径包含 `/opt/miniconda3/bin/yt-dlp`、`/opt/anaconda3/bin/yt-dlp`、`/opt/homebrew/bin/yt-dlp`、`/usr/local/bin/yt-dlp`、`/usr/bin/yt-dlp`。
- `TransNetV2`：场景识别，Python 路径 `Tools/transnet-env/bin/python`，脚本 `Tools/detect_scene_cuts_transnet.py`。
- `whisper.cpp`：本地转写，包装脚本 `Tools/transcribe_with_whisper.sh`。
- `Ollama qwen3-vl:8b`：画面分析。
- `Ollama qwen3:4b-instruct`：内容节点整理。

## 9. 设计原则和精确数值

### 9.1 总体风格

拉片宝应保持 macOS 原生工具感：暗色、克制、Finder/Apple Music 式侧边栏、轻量材质、紧凑信息密度。它应该像一个每天反复用的工作台，而不是网页 SaaS、后台系统或宣传页。

设计上要优先保证：

- 视频画面有效面积。
- 时间线可扫读。
- 素材卡可快速浏览。
- 资产能回到原视频时间。
- 控件以图标和 macOS 菜单为主，避免长说明文案。

### 9.2 全局设计常量

当前 `Design` 精确值：

```swift
static let windowInset: CGFloat = 0
static let windowRadius: CGFloat = 10
static let panelSpacing: CGFloat = 0
static let panelRadius: CGFloat = 0
static let innerRadius: CGFloat = 6
static let itemRadius: CGFloat = 6
static let railWidth: CGFloat = 56
static let railIconInset: CGFloat = 8
static let railButtonHeight: CGFloat = 34
static let railIconBoxSize: CGFloat = 24
static let railButtonVisualOffsetX: CGFloat = 3.5
static let railSelectionGuideX: CGFloat = railIconInset + railButtonVisualOffsetX
static let libraryToolbarVisualGap: CGFloat = 14
static let libraryToolbarHeight: CGFloat = 22
static let trafficLightSize: CGFloat = 12
static let trafficLightGap: CGFloat = 6
static let trafficLightClusterWidth: CGFloat = trafficLightSize * 3 + trafficLightGap * 2
static let timelineLaneHeight: CGFloat = 100
static let collapsedTimelineLaneHeight: CGFloat = 40
static let timelineLaneButtonSize: CGFloat = 24
static let timelineLaneIconSize: CGFloat = 22
static let expandedTimelineDetailHeight: CGFloat = 280
static let expandedTimelineStackMaxHeight: CGFloat = 520
static let centeredWaveformViewportSpan: Double = 0.22
```

派生值：

- `libraryToolbarTop = 14`。
- `railTopChromeHeight = 36`，来自 `14 + 22`。
- `trafficLightGuideX = 14`，标准窗口按钮左距，不随 rail 图标光学校正值变化。
- `trafficLightGuideY = 19`，来自 `14 + (22 - 12) / 2`。
- `trafficLightClusterWidth = 48`，来自 `12 * 3 + 6 * 2`。
- `railSelectionGuideX = 11.5`，让导航选中块左缘和红黄绿按钮的可见左缘视觉对齐。
- `timelineLaneVisualGap = 7`，来自 `(100 - 24 * 3) / 4`。
- `timelineLaneContentHeight = 86`，来自 `100 - 7 * 2`。

颜色：

```swift
sidebarBg = Color(red: 0.118, green: 0.118, blue: 0.129)
contentBg = Color(red: 0.149, green: 0.149, blue: 0.165)
currentFrameAccent = Color(red: 1.00, green: 0.22, blue: 0.18)
captureFrameAccent = Color(red: 1.00, green: 0.50, blue: 0.18)
annotationAccent = Color(red: 0.68, green: 0.72, blue: 0.72)
```

### 9.3 布局数值

- 窗口默认：`1280 x 800`。
- 窗口最小内容尺寸：`960 x 720`。
- 紧凑布局阈值：窗口宽度 `< 900pt`。
- 主页预览区右侧导出栏显示阈值：工作区宽度 `>= 720pt`。
- 主页导出栏宽度：`max(240, min(320, width * 0.20))`。
- 主页窄屏导出浮层宽度：`min(available, max(260, width / 3))`。
- 主页播放器最小宽度：`360pt`。
- 主页播放器最小高度：`220pt`。
- 主页 header 高度：`38pt`。
- 主页普通间距：`8pt`。
- 主页播放器和导出栏间距：宽屏 `12pt`，窄屏 `0pt`。
- 时间线折叠总高度：`100 * 3 + 8 * 2 = 316pt`。
- 时间线展开高度：`min(520, max(340, workspaceHeight * 0.42))`。
- 素材区默认宽度：`340pt`。
- 素材区最小宽度：`320pt`。
- 非画面工作区素材区最大宽度：`660pt`。
- 画面工作区素材区默认宽度：窗口宽度 `50%`。
- 画面工作区素材区最大宽度：`containerWidth - 260pt`。
- 分隔线交互热区宽度：`8pt`，视觉线宽 `1pt`。

### 9.4 素材网格和卡片

网格密度：

- `mediaGridSize = 0`：3 列。
- `mediaGridSize = 1`：2 列。
- `mediaGridSize = 2`：1 列。

计算公式是 `3 - mediaGridSize`，最少 `1` 列。列间距 `10pt`，网格行距 `10pt`，网格水平内边距 `14pt`。

素材工具栏：

- 顶部距 rail 对齐：`14pt`。
- 工具栏最小高度：`22pt`。
- 顶部按钮尺寸：`28 x 22pt`。
- 网格密度 Slider 宽度：`56pt`。

素材卡片：

- `LibraryVideoTile.cardAspectRatio = 1.06`。
- 信息栏高度比例 `0.36`。
- 信息栏最小高度 `62pt`，最大高度 `74pt`。
- 卡片圆角 `Design.itemRadius = 6pt`。
- 卡片选中边框：白色 `0.42` 透明度，线宽 `1.5pt`。
- 卡片普通边框：白色 `0.10` 透明度，线宽 `1pt`。
- 卡片阴影：黑色 `0.32`，半径 `6pt`，y `3pt`。
- 标题字体：`.system(size: 13, weight: .semibold)`，单行，中间截断。
- 标题固定高度：`18pt`。
- 信息栏水平 padding `10pt`，顶部 `8pt`，底部 `7pt`。
- 三点按钮视觉图标 `ellipsis`，字体 `12pt semibold`，按钮 padding `6pt`，右上角外边距 `6pt`。
- 时长胶囊 `CardTimeBadge`：宽 `64pt`，高 `18pt`，距右边 `10pt`，距缩略图底部 `5pt`。
- 时长胶囊字体：`.system(size: 12, weight: .bold, design: .rounded).monospacedDigit()`。
- 时长胶囊透明度：有时长白色 `0.92`，无时长占位白色 `0.62`；阴影两层，黑色 `0.72` 半径 `2.4pt` y `1pt`，黑色 `0.38` 半径 `7pt` y `2pt`。

### 9.5 标签和平台标记

标签颜色来自 `VideoTagPalette` 的 8 色哈希，不要随机生成：

```swift
(0.94, 0.34, 0.38)
(0.96, 0.55, 0.22)
(0.72, 0.66, 0.28)
(0.30, 0.70, 0.40)
(0.22, 0.72, 0.68)
(0.32, 0.56, 0.96)
(0.56, 0.43, 0.92)
(0.84, 0.38, 0.78)
```

标签尺寸：

- `mini`：字体 `.caption2.semibold`，水平 padding `4pt`，垂直 `2pt`，最大文字宽度 `58pt`。
- `compact`：字体 `.caption2.semibold`，水平 padding `5pt`，垂直 `3pt`，最大文字宽度 `74pt`。
- `regular`：字体 `.caption.medium`，水平 padding `7pt`，垂直 `4pt`，最大文字宽度 `132pt`。
- 删除按钮图标 `xmark`，字体 `8pt bold`，点击框 `12 x 12pt`。

平台标记：

- 支持平台色：Instagram `(0.93,0.31,0.58)`，YouTube `(0.96,0.18,0.18)`，小红书 `(0.88,0.24,0.30)`，Bilibili `(0.28,0.68,0.95)`，抖音 `(0.34,0.84,0.78)`。
- 未知平台色：`(0.62,0.66,0.72)`。

### 9.6 波形和时间线

主波形 `AudioWaveformView`：

- 固定高度 `64pt`。
- 水平 padding `12pt`，垂直 padding `10pt`。
- 背景 `.thinMaterial`。
- 圆角 `Design.innerRadius = 6pt`。
- 占位样本数 `240`。
- 波形条宽 `max(0.65, min(1.6, step * 0.82))`。
- 波形条高 `sample * height * 0.84`，最小归一值 `0.04`。
- 已播放颜色白色透明度 `0.88`，未播放白色透明度 `0.28`，占位透明度 `0.16`。
- 播放头宽 `2pt`，上下留 `2pt`，白色透明度 `0.95`。
- 场景切点线宽 `1.5pt`，橙色透明度 `0.80`，顶部菱形左右 `3pt`。
- In/Out 标记线宽 `1.5pt`，dash `[3,2]`，顶部圆点半径 `5pt`。

居中波形 `CenteredWaveformTimeline`：

- 占位样本数 `360`。
- 最小 viewport span `0.02`。
- 条宽 `max(0.65, min(1.5, visibleWidth / sampleCount * 0.82))`。
- 条高 `sample * height * 0.78`。
- 中心播放头宽 `2pt`。

时间线缩放：

- `timelineZoom` 最小 `1`，最大 `50`。
- `timelineViewportSpan = 1 / timelineZoom`，范围 `0.02...1`。
- 播放头可视边距：`min(0.08, span * 0.18)`。
- 自动跟随动画：`.easeOut(duration: 0.14)`。

### 9.7 导入弹窗

导入弹窗：

- 面板宽度：`max(560, min(containerWidth - 48, 980))`。
- 面板高度：`max(430, min(containerHeight - 56, 720))`。
- 遮罩：黑色透明度 `0.44`。
- 面板背景：`Design.sidebarBg`。
- 面板圆角 `14pt`。
- 面板边框：白色透明度 `0.14`，线宽 `1pt`。
- 阴影：黑色透明度 `0.38`，半径 `28pt`，y `18pt`。
- 面板外边距：水平 `24pt`，垂直 `24pt`。
- Header 水平 padding `22pt`，垂直 `18pt`。
- 关闭按钮 `28 x 28pt`，圆形。
- 窄布局阈值：弹窗内部宽度 `< 760pt`。
- 双列布局右列宽度：`min(360, width * 0.38)`。
- 内容块圆角多为 `10pt`，任务行圆角多为 `8pt`。
- TextEditor 高度：最小 `138pt`，最大 `190pt`。

### 9.8 字体规则

整体使用系统字体，不引入第三方字体。

- 大面板标题：`.title2.bold()`。
- 主页视频标题：`.system(size: 18, weight: .semibold)`。
- 素材卡标题：`.system(size: 13, weight: .semibold)`。
- 分组/行标题：`.caption.weight(.semibold)`。
- 辅助信息：`.caption2` 或 `.caption`，低透明度。
- 时间码一律使用 `.monospacedDigit()`，避免播放时数字跳动。

不要在工具界面里塞长说明文案。空状态可以短，但主工作区不靠解释文字撑版面。

## 10. 现状和已知限制

当前已完成：

- 本地素材库扫描、缩略图、元数据、标签保存、排序筛选。
- 网络视频导入队列和进度状态。
- 自定义播放器、波形、帧带、场景网格、截图、批注。
- 声音 In/Out 采样和导出。
- Whisper 转写和 Markdown 导出。
- 音乐识别、Apple Music 链接、原曲/伴奏下载。
- 画面、声音、内容三个独立工作区。
- 项目资产保存到素材库目录。

仍需谨慎处理：

- `ContentView.swift` 已经很大，拆分有价值，但不要在功能修改中顺手大拆。
- 网络平台下载能力受 `yt-dlp`、平台风控和网络状态影响。
- 本地模型能力依赖 Ollama 和模型是否已安装。
- 反向播放代理需要 ffmpeg，且生成代理可能耗时。
- 场景识别依赖 TransNetV2 环境，失败时才走本地回退。

## 11. 本阶段反复问题复盘

### 11.1 启动和窗口

这阶段反复出现的问题是：Debug/Xcode 增量构建后 Dock 显示应用未响应、进程存在但没有可见窗口、或者启动阶段被素材库扫描拖住。当前定论：

- 主窗口必须由 `AppDelegate` 显式创建并强引用 `NSWindow`，不要恢复 `WindowGroup` 做主入口。
- `applicationDidFinishLaunching(_:)` 必须尽快返回，只能 `DispatchQueue.main.async` 调度 `completeLaunchSetupIfNeeded()`。
- 启动顺序保持：安装菜单、创建并显示主窗口、安装可见性复查和键盘 monitor、激活 App、延后恢复素材库。
- `loadLastLibraryForLaunch()` 必须把目录枚举放到后台线程，枚举完成后才回主线程更新 `LibraryStore`。
- 不要重新打开 SwiftUI `#Preview`、`ENABLE_PREVIEWS` 或 Debug dylib/JIT 路径。这个项目用真实冷启动检查替代 Preview。
- 改到启动、窗口、工程构建设置、AppKit 桥接后，跑 `Tools/check_launch_window.sh`，失败就先修启动，不要继续叠功能。

### 11.2 设计和布局

这阶段反复出现的问题是：UI 数值被顺手改散、窗口过小导致工作台重叠、rail 和红黄绿按钮对不齐、工具界面变得像网页后台。当前定论：

- `Design` 是可恢复设计基线。改任何尺寸、圆角、间距、颜色，都同步更新本文第 9 节。
- 保持 macOS 原生工具感：暗色、克制、密度合理、图标按钮和菜单优先，不做营销页、超大 hero、装饰渐变或后台表格风。
- 窗口最小内容尺寸现在是 `960 x 720`，通过紧凑布局和导出栏阈值保证播放器、素材区、时间线和导出/识别工作流不互相挤压。
- 左侧 rail 是工作区导航，不是标签筛选；标签筛选留在素材区工具栏。
- 页面区块不要靠长说明文字撑版面。空状态可以短，但主工作区要让资产、播放器、时间线、列表成为第一视觉。
- 设置工作区可以更像偏管理的工具面板，但仍要沿用项目的暗色、轻材质、紧凑行高和原生控件。

### 11.3 快捷键和播放器

这阶段反复出现的问题是：快捷键被多个层级重复处理、已处理按键漏传给系统导致 beep、`J/L` shuttle 和普通播放语义混在一起。当前定论：

- 快捷键解析只认 `PreviewKeyboardEventRouter`；命令分发只走 `PreviewKeyboardCommandDispatcher`。
- app-level `NSEvent` monitor 是唯一执行命令的 owner。窗口和 capture view 只负责兜底消费事件。
- 文本输入时不拦截快捷键；无修饰键的播放器快捷键才拦截。
- `J/L` 单击只跳一帧；按住触发 shuttle，松开停止。`L` 不是普通播放键，不能直接调用 `setRate(1)`。
- `K` 平时是播放/暂停；如果已经在 `J/L` shuttle 中，才作为加速键。
- `Space`、箭头、`I/O/E/U/P` 都要在 keyDown/keyUp 路径里安静消费，避免系统 beep。
- 修改快捷键后，同时更新 `PreviewKeyboardCommand`、`PreviewKeyboardEventRouter`、app-level monitor、本文第 7 节和 `AGENTS.md`。

## 12. 后续开发原则

1. 保留 macOS 原生工具感，优先图标按钮、菜单、分段控件、轻量材质。
2. 每个新增资产都必须能定位回原视频时间点。
3. 媒体处理尽量异步，UI 状态通过 `LibraryStore` 发布。
4. 新持久化数据优先放入素材库目录的 JSON；只有数据复杂后再考虑 SQLite。
5. 修改播放器时先读 `PreviewController.swift`，不要绕过它直接控制 `AVPlayer`。
6. 修改键盘快捷键时同步更新 `PreviewKeyboardCommand`、`PreviewKeyboardEventRouter` 和本文第 7 节。
7. 修改设计数值时同步更新本文第 9 节，确保以后能按文档复原。
8. 清理 Markdown 时只处理项目文档，不碰第三方依赖文档和导出样例。
