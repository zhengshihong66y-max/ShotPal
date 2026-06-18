# 拉片宝 AI 接手手册

最后更新：2026-06-10

本文是拉片宝项目的唯一权威 Markdown。后续 AI 或开发者接手时，先读本文，再按需读源码。本文同时记录产品结构、工程结构、设计原则、已经定下来的 UI 数值和可恢复的设计基线。

## 1. 项目一句话

拉片宝是一个 macOS 原生 SwiftUI App，用来把视频素材导入本地库，快速看片、识别场景、采样画面、截取声音、转写内容、识别音乐，并把这些拉片结果沉淀为可导出的创作资产。

它不是网页后台，不是通用文件管理器，也不是传统剪辑软件。它的核心价值是：让用户更快完成拉片，并把画面、声音、文本、音乐、批注和场景切点保存下来，后续可以回到原视频时间点，也可以导出到外部整理或剪辑流程。

## 2. 接手前先记住

- 当前项目是 macOS App，入口是 `LapianBaoApp.swift`，启动协调在 `AppStartup/`，主界面壳是 `ContentView.swift`，UI 细分在 `Views/`，数据中心壳是 `LibraryStore.swift`，媒体和导入逻辑细分在 `Stores/`，共享模型在 `Models/LibraryModels.swift`，播放控制是 `PreviewController.swift`，窗口和键盘桥接是 `AppChrome.swift`。
- 当前 App bundle 版本仍由 `LapianBao.xcodeproj` 的 `MARKETING_VERSION = 1.0` 和 `CURRENT_PROJECT_VERSION = 1` 控制；Git 提交数只作为内部迭代口径，用 `git rev-list --count HEAD` 实时查询，不手写成固定产品版本。
- 不要把主播放器改回 SwiftUI 原生 `VideoPlayer`。当前用 `AVPlayerLayer` 承载画面，原因是避免系统悬停控制层压暗视频。
- 不要引入网页式后台、营销页、超大 hero、装饰渐变球、表格管理器风格。
- 不要随手重置 `Design` 里的尺寸。本文第 9 节列出的数值是当前设计基线。
- `Tools/whisper.cpp` 是第三方依赖目录，里面的 Markdown 不是项目产品文档，平时不要清理或改写。
- 每次较大代码修改后用 `xcodebuild -project LapianBao.xcodeproj -scheme LapianBao -destination 'platform=macOS' build` 验证。
- 改到 App 启动、窗口、`AppStartup/`、`AppChrome.swift`、`LapianBaoApp.swift`、工程构建设置后，必须再跑 `Tools/check_launch_window.sh`。它会用独立 DerivedData 构建、确认没有 Preview/JIT debug dylib、冷启动 App，并验证系统窗口数至少为 1。
- 启动阶段不能同步做重活：`applicationDidFinishLaunching(_:)` 必须异步调度 `completeLaunchSetupIfNeeded()`；主窗口先显示并完成一次绘制，再用 `DispatchQueue.main.asyncAfter` 延后 `loadLastLibraryForLaunch()`。启动恢复素材库时，目录枚举必须在后台完成。这是防止 Xcode 增量构建后旧调试进程/Dock 显示“应用未响应”的硬规则，`Tools/check_launch_window.sh` 会检查。
- 如果启动后只有进程没有窗口，先判断是不是 pre-main 问题：`sample` 只有 `_dyld_start`、`vmmap -summary` 显示 `Process exists but has not started -- it is launched-suspended`、物理内存约 `96K`，都说明 App 代码尚未运行。此时优先检查 Xcode 用户断点、旧 `debugserver` / `lldb`、LaunchServices / Xcode 启动状态或签名/隔离属性，不要先改 SwiftUI 或素材库扫描逻辑。
- Xcode 用户断点会让 App 在窗口创建前被挂起。`Tools/check_launch_window.sh` 会扫描 `Breakpoints_v2.xcbkptlist`，只要存在 `shouldBeEnabled = "Yes"` 就失败；启动验收前必须禁用这些断点。
- 不要在项目源码里新增 SwiftUI `#Preview`。本项目以真实 App 冷启动检查为准，避免重新引入 Preview macro/plugin server 或 JIT 注入路径。
- 不要把全窗口遮罩背景写成 `Button { Color... }` 或 `Button(action: close...) { Color... }`。macOS SwiftUI 会把它变成巨型可访问性/命中测试按钮，吞掉弹窗和主界面的点击。遮罩背景必须用非控件视图：`Color.black.opacity(...).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { ... }.accessibilityHidden(true)`，真正的面板内容再用 `zIndex` 放在上面。
- `LapianBaoApp.swift` 的 App 级预览键盘监听只能监听 `.keyDown` 和 `.keyUp`。不要在这里加 `.leftMouseDown`、`.rightMouseDown` 或其它全局鼠标监听，也不要在 App 级鼠标按下路径里调用 `window.makeFirstResponder(nil)`；鼠标焦点恢复只能留在局部桥接视图如 `PreviewKeyboardHandler` 中。
- 如果出现“整个 App 无法点击”，先用 `pgrep -fl LapianBao` 确认没有多个 `LapianBao` 实例或旧调试窗口叠在一起，再查 SwiftUI 遮罩层和 AppKit 事件监听。
- 每轮较大改动前先确认 `python3 Tools/regression_checks.py` 和 `xcodebuild -project LapianBao.xcodeproj -scheme LapianBao -destination 'platform=macOS' build` 的当前基线；如果工作区已有大量未提交改动，先做可恢复 checkpoint，再继续拆分。

## 3. 当前产品结构

主窗口是三段结构：

```text
左侧 icon rail + 素材区 | 主工作区
```

普通宽度下，素材区和主工作区左右排列；宽度小于 `900pt` 时，素材区在上、工作区在下。窗口默认尺寸是 `1280 x 800`，最小内容尺寸是 `960 x 720`。

### 3.1 左侧 rail

左侧 rail 是工作区入口，不是标签栏。宽度固定 `56pt`，包含 macOS 原生红黄绿窗口按钮和五个可见工作区入口：

- `主页`：看片、时间线、场景识别、截图、批注、声音采样、转写摘要、音乐识别。
- `画面`：已收集画面的网格、预览、亮度直方图、色卡、本地视觉模型分析。
- `声音`：已导出的声音片段列表、播放、定位回原视频、音乐识别和下载。
- `音乐`：音乐识别结果、音乐下载、音乐素材列表和回溯定位。
- `设置`：画面切分、字幕识别、音乐下载的批量操作、停止、清空和自动执行开关。

对应源码是 `AppWorkspace.allCases`。`content` 工作区的实现仍在代码里，当前不作为 rail 入口展示。

Rail 选中态不再使用外部包围高亮；图标本身变为白色，未选中图标保持低透明度。图标先使用全局 `railIconAlignmentOffsetX` 对齐红黄绿窗口按钮左缘，再以各自的 `railIconOffset` 和 `railIconSize` 做光学修正；不要通过移动窗口按钮或素材区 inset 来补 rail 图标对齐。

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
- `SettingsWorkspaceView`：设置工作区。

`ContentWorkspaceView` 仍保留在代码中，用于内容节点时间线和本地文本模型整理，当前不是 rail 可见入口。

工作区之间跳转时通过 `jumpToVideo(path:time:)` 选中视频，并经由 `AppEventBus` 发出 seek 请求，让主页播放器跳到对应时间点。

## 4. 核心文件地图

### `LapianBaoApp.swift`

负责 App 生命周期桥接：

- `AppDelegate`：设置常规 macOS App 激活策略；保留 `LibraryStore`、`AppWindowManager`、`AppStartupCoordinator`；安装全局预览键盘监听；关闭最后窗口后退出；禁用系统状态保存和恢复。
- `applicationDidFinishLaunching(_:)` 只做诊断标记，并用 `DispatchQueue.main.async` 调度 `AppStartupCoordinator.completeLaunchSetupIfNeeded()`。不要把窗口创建、菜单安装、素材库恢复或任何重活塞回这个 delegate callback。
- `applicationDidBecomeActive(_:)` 和 Dock reopen 只转发到 `AppWindowManager.ensureMainWindowVisible()`。

### `AppStartup/`

负责启动阶段的可检修边界：

- `AppStartupCoordinator.swift`：启动顺序唯一所有者。顺序必须是安装菜单、创建并显示主窗口、安装可见性复查和键盘监听、激活 App、预热保存集合 cookie、启动外部服务日自检，最后用 `DispatchQueue.main.asyncAfter` 延后 `loadLastLibraryForLaunch()`。
- `AppWindowManager.swift`：主 `NSWindow` 唯一所有者。它显式创建并强引用 `PreviewKeyboardWindow`，负责恢复窗口到可见屏幕、`makeKeyAndOrderFront`、`orderFrontRegardless` 和应用激活。
- `StartupDiagnostics.swift`：启动阶段日志标记。用来区分是否进入了 `main`、是否到了 `applicationDidFinishLaunching`、是否创建和展示了窗口、是否开始素材库恢复。
- 主窗口不走 SwiftUI `WindowGroup`。这是为了避免 Debug 构建或 Xcode Preview/JIT 注入导致“进程存在但没有可见窗口”。
- `ensureMainWindowVisible()` 是启动兜底：启动完成、应用激活、Dock 重新打开、启动后延迟复查都会确保窗口存在、在可见屏幕内，并被拉到前台。
- 窗口标题为 `LapianBao`，默认尺寸 `1280 x 800`，最小内容尺寸来自 `Design.minimumWindowWidth = 960` 和 `Design.minimumWindowHeight = 720`。
- 菜单替换默认新建项，提供 `打开文件夹`，快捷键 `Command + O`。

### `AppChrome.swift`

负责 AppKit 桥接：

- `PreviewKeyboardCommand`：播放器快捷键命令枚举。
- `PreviewShortcutAction` 和 `PreviewShortcutKeyOption`：播放器快捷键默认值、用户改绑数据结构和冲突检测。
- `PreviewKeyboardEventRouter`：按当前快捷键配置把物理按键转换为命令，且在文本输入框中不拦截。
- `WindowConfigurator`：使用全尺寸内容视图和透明标题栏，保留可调整大小、关闭、最小化、全屏能力。
- `WindowDragRegion`：自定义窗口拖拽区域。
- `PreviewKeyboardHandler` 和 `KeyboardCaptureNSView`：局部键盘焦点捕获。
- `NativeWindowTrafficLights`：隐藏系统红黄绿按钮，在自定义 rail 的固定坐标绘制同尺寸按钮，并转发关闭、最小化、全屏动作到 `NSWindow`。

红黄绿按钮尺寸 `14pt`，间距 `7pt`。不要把 `window.standardWindowButton(...)` 重新挂到 SwiftUI 容器中；系统标题栏会在启动和激活阶段重排它们，导致位置漂移。

### `LibraryStore.swift`、`Models/` 和 `Stores/`

`LibraryStore.swift` 保留全局数据中心的状态壳，标记为 `@MainActor ObservableObject`。共享模型移到 `Models/LibraryModels.swift`，具体能力按职责拆到 `Stores/LibraryStore+*.swift` extension 中。

主要模型：

- `VideoItem`：视频 URL、名称、文件夹名、扩展名。
- `VideoMetadata`：时长、帧率、分辨率、文件大小、创建和修改时间。
- `SampledFrame`：截图或场景代表帧，含视频路径、时间、缩略图、备注、标签。
- `AnnotationItem`：某个视频时间点的文字批注。
- `AudioClipItem`：In/Out 声音片段，含导出路径和波形。
- `TranscriptSegment`：Whisper 转写片段。
- `MusicRecognitionItem`：识别到的音乐，含歌名、作者、封面、Apple Music 链接、出现时间和独立音乐标签。
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

当前拆分边界：

- `LibraryStore+IndexesAndBasics.swift`：索引缓存、筛选排序、基础选择和自检入口。
- `LibraryStore+LaunchAndRemoteImports.swift`：启动恢复、素材库授权、远程导入队列。
- `LibraryStore+VideoLibraryAndTags.swift`：本地视频扫描、视频删除、标签操作。
- `LibraryStore+PersistenceAndSources.swift`：JSON 持久化、项目数据迁移、来源推断。
- `LibraryStore+TimelineMedia.swift`：波形、帧带、场景识别状态、批注和资产标签。
- `LibraryStore+CaptureTranscriptMusic.swift`：截图、声音导出、字幕、音乐识别和下载命令入口。
- `LibraryStore+MusicDetection.swift`：音乐识别和音乐下载辅助逻辑。
- `LibraryStore+TranscriptExportAndSceneCache.swift`：字幕 Markdown 导出和场景缓存。
- `LibraryStore+SceneDetection.swift`：TransNetV2 和本地场景变化检测。
- `LibraryStore+RemoteDownloadTypes.swift` 和 `LibraryStore+RemoteDownload.swift`：远程下载共用类型和统一下载入口。
- `LibraryStore+RemoteTranscoding.swift`：VP9/AV1/VP8 转 H.264 的兼容处理。
- `LibraryStore+XiaohongshuDownload.swift`：小红书原生解析和下载。
- `LibraryStore+DownloaderSelfCheck.swift`：yt-dlp 最新版检查、应用托管下载器安全替换和自动修复。
- `LibraryStore+YTDLPDownload.swift`：yt-dlp 下载、探测、进度解析和缩略图抓取。
- `LibraryStore+CobaltDownload.swift`：cobalt.tools 备用下载和导入文件名清洗。
- `LibraryStore+MetadataAndExportHelpers.swift`：元数据、缩略图、图片/音频导出辅助。

### `PreviewController.swift`

播放器状态中心，标记为 `@MainActor ObservableObject`：

- 使用单例 `AVPlayer`。
- 以 `1 / 12s` 周期同步 `elapsed`、`duration`、`progress`、`playbackRate` 等控制状态；视频帧刷新交给 `AVPlayerLayer`，避免用显示器刷新率驱动整块 SwiftUI 预览面板重算。
- `loadVideo(_:autoplay:)` 切换视频，加载波形、帧带和缓存场景切点。
- 支持播放、暂停、跳转、逐帧、正向变速、反向播放。
- 反向播放会尝试使用 ffmpeg 生成 intra-only 静音代理视频，缓存到用户缓存目录 `LapianBao/ReversePlaybackProxies`。
- ffmpeg 查找路径是 `/opt/homebrew/bin/ffmpeg`、`/usr/local/bin/ffmpeg`、`/usr/bin/ffmpeg`。

### `ContentView.swift` 和 `Views/`

`ContentView.swift` 只保留 App 主布局壳：rail、素材区、工作区切换、导入和设置 overlay、全局跳转。设计常量、素材卡、播放器、时间线、各工作区和共享组件已经拆入 `Views/`，拆分时保持行为和页面不变。

当前 UI 拆分边界：

- `Views/AppShell/`：工作区、标签页、导出筛选等 App 壳层类型。
- `Views/Design/`：`Design` 尺寸、颜色和视觉基线。
- `Views/Library/`：素材视频卡和分析菜单。
- `Views/Preview/`：主页播放器、场景面板、时间线控件。
- `Views/Frames/`：画面工作区、本地画面分析、直方图和色卡。
- `Views/Audio/`：声音工作区。
- `Views/Music/`：音乐工作区、音乐识别行、封面、下载状态和波形。
- `Views/Content/`：内容工作区和本地文本时间线分析。
- `Views/Settings/`：设置工作区。
- `Views/Components/`：标签、空状态、场景 tile、进度和卡片辅助组件。
- `Views/Shared/`：拖拽、面板背景、分隔线光标等跨页面 helper。

## 4.5 架构护栏和拆分路线

当前架构优化的目标不是一次性大重写，而是把容易复发的问题变成可检查边界。后续 AI 或开发者改动时，优先保持现有行为和数据格式，再逐步移动职责。

### 4.5.1 当前硬边界

- `README.md` 是唯一权威 Markdown。不要另建平行架构说明；新增规则先写回本文，再按需让 `Tools/regression_checks.py` 检查。
- `LibraryStore.swift` 只能保留状态壳、共享常量、轻量 helper 和门面入口。新增下载、转码、解析、持久化、导入、场景、字幕、音乐逻辑时，优先放到已有 `Stores/LibraryStore+*.swift` 边界里。
- `ContentView.swift` 只能保留主布局壳、全局 overlay、workspace 切换和跨工作区跳转。复杂导入面板、筛选、资产列表、播放行、分析视图都应该继续拆在 `Views/*` 子目录。
- `LapianBaoApp.swift` 只做 AppDelegate/lifecycle 桥接，不接业务逻辑。启动顺序归 `AppStartupCoordinator`，窗口归 `AppWindowManager`，启动可诊断标记归 `StartupDiagnostics`。
- 点击命中边界是硬规则：全屏遮罩背景不能是 `Button`，App 级事件监听不能接管鼠标按下事件；新增 overlay 或 AppKit 桥接时必须确认不会生成覆盖全窗的 `AXButton` 或提前改写 first responder。
- `Views/` 不直接启动外部进程，不直接读写项目 JSON，不直接枚举素材库目录。View 可以发起用户意图，但执行必须落到 Store 或后续独立 service。
- 外部副作用要收敛：`Process()`、`UserDefaults.standard`、`NotificationCenter.default`、项目隐藏 JSON 读写都必须有明确 owner。短命令执行当前 owner 是 `ExternalProcessRunner.swift`；项目隐藏 JSON 路径和基础读写当前 owner 是 `ProjectRepository.swift`；`UserDefaults.standard` 当前唯一 owner 是 `AppSettings.swift`；SwiftUI `@AppStorage` 的 key 也必须来自 `AppSettings.Key`；自定义 `lapianBao*` App 事件当前唯一 owner 是 `AppEventBus.swift`。新增使用点前先看 `Tools/regression_checks.py` 是否允许。

### 4.5.2 自动检查边界

`Tools/regression_checks.py` 是轻量架构护栏，不替代真实测试。它当前检查：

- 启动、窗口、快捷键、场景识别、音乐识别、字幕导出和外部服务自检等已踩坑规则。
- 核心文件体量上限，防止 `LibraryStore.swift`、`ContentView.swift`、`LapianBaoApp.swift`、`PreviewController.swift` 和大 View/Store 文件继续无声膨胀。
- 短命令 `Process()` 必须走 `ExternalProcessRunner`；少量直接 `Process()` 只允许暂留在需要流式进度、可取消下载或代理进程的已知边界。
- `UserDefaults.standard` 只能出现在 `AppSettings.swift`；`@AppStorage` 必须使用 `AppSettings.Key.*`，不要重新散落裸字符串 key。
- 自定义 `lapianBao*` 通知只能出现在 `AppEventBus.swift`；其他 `NotificationCenter.default` 使用点只能保留在 AppKit 窗口观察或局部 `AVPlayerItemDidPlayToEndTime` 观察边界。
- `.lapianbao*.json` 和 `.lapianbaotags.json` 这类项目隐藏 JSON 文件名只能出现在 `ProjectRepository.swift`，其他模块通过 repository 取 URL 或调用读写 helper。
- 交互命中检查会拦截 App 级鼠标事件监听、AppDelegate 中的 `makeFirstResponder(nil)` 鼠标焦点重置，以及导入遮罩退回全窗口 `Button` 的写法。

每次架构拆分后，同步更新本文和 `Tools/regression_checks.py`。如果脚本误拦，需要先确认是不是职责边界真的变了，再调整白名单。

### 4.5.3 推荐拆分顺序

第一阶段只抽副作用，不改 UI 和数据结构：

1. `AppSettings`：集中 `UserDefaults` key、默认值、读写和迁移。当前已完成第一轮收拢，后续新增偏好项继续先加到 `AppSettings.Key`。
2. `AppEventBus`：集中 `.lapianBaoSeekRequest`、`.lapianBaoPausePreviewRequest`、`.lapianBaoMusicPreviewStarted` 等通知。当前已完成第一轮收拢，后续新增 App 级事件继续先加到 `AppEventBus`。
3. `ExternalProcessRunner`：集中短命令 `Process` 启动、输出读取、取消、超时和错误描述。当前已完成第一轮收拢；下载/转码进度流和反向播放代理仍保留在原边界，后续按行为测试逐个迁移。
4. `ProjectRepository`：集中 `.lapianbao_project.json`、`.lapianbaotags.json`、`.lapianbao_sources.json`、`.lapianbao_scene_cuts.json`、waveform/video/resource cache 和 IG/XHS 导入基线等项目隐藏 JSON 路径与基础读写。当前已完成第一轮收拢，网络 API 响应解析仍留在对应 feature。
5. `ToolLocator`：集中 ffmpeg、yt-dlp、Python、whisper、TransNet、音乐识别脚本路径查找。

第二阶段再把 `LibraryStore` 退成门面：

- `VideoLibraryFeature`：素材扫描、标签、排序、视频删除、素材库授权。
- `RemoteImportFeature`：远程导入队列、平台识别、下载、任务状态。
- `TimelineMediaFeature`：波形、帧带、批注、截图、声音片段。
- `SceneDetectionFeature`：TransNetV2、场景缓存。
- `TranscriptFeature`：Whisper 转写、字幕导出、内容节点时间线。
- `MusicFeature`：音乐识别、音乐下载、本地音乐/音频资产、波形。
- `AssetExportFeature`：图片、音频、字幕、音乐导出目录和索引。

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
- 自定义播放器快捷键：`UserDefaults.previewShortcut.<action>.keyCode`。

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
- 下载任务状态包含导入、转码、收尾、暂停、成功和失败；导入队列支持暂停、继续、删除和跳转到导入结果。
- 导入成功后尽量保存来源标题和作者标签；`yt-dlp` 会优先请求 H.264 / m4a / MP4 组合，降低后续播放兼容问题。
- 下载后如果编码不适合播放，会转码为 H.264。

### 分析

画面分析：

- 主页时间线显示均匀帧带或场景代表帧带。
- 可以截图当前帧，保存为 `SampledFrame(kind: .screenshot)`。
- 场景识别使用 TransNetV2。
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
- 结果包含歌名、作者、封面、Apple Music 链接、出现时间和独立音乐标签；脚本优先使用 Shazam 流派，并用 iTunes Search API 补充 `primaryGenreName`。
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
- 文本：Whisper 字幕导出 Markdown，包含 AI 友好的分镜字幕索引、每个分镜的时间区间和对应字幕，并保留完整原脚本；导出任务会在主页导出栏显示进度条，完成后进入导出记录。
- 音乐：下载原曲和伴奏到 `LapianBaoExports/音乐`。

## 7. 播放与快捷键

播放器必须保持自定义控制，不使用系统 `VideoPlayer` 控制层。

默认键盘命令如下：

- `Space`：播放/暂停。
- `K`：播放/暂停；如果正在默认 J/L shuttle，则提升 shuttle 速度。
- `J`：单击后退一帧；按住进入向后 shuttle。
- `L`：单击前进一帧；按住进入向前 shuttle，不能启动普通正向播放或直接调用 `setRate(1)`。
- `Left Arrow`：后退一帧。
- `Right Arrow`：前进一帧。
- `Up Arrow`：上一个场景切点。
- `Down Arrow`：下一个场景切点。
- `I`：设置声音 In 点。
- `O`：设置声音 Out 点。
- `E`：导出当前帧图片。
- `U`：清除声音选区。
- `P`：导出当前声音选区。

键盘监听规则：

- 不带 `Command`、`Control`、`Option` 才拦截。
- 文本编辑控件获得焦点时不拦截。
- 快捷键默认值和改绑数据都由 `PreviewShortcutAction` 管，允许的按键来自 `PreviewShortcutKeyOption`。
- 自定义快捷键保存到 `UserDefaults.previewShortcut.<action>.keyCode`；冲突键需要提示并阻止覆盖。
- 快捷键命令只能由 app-level `NSEvent` monitor 分发到 `PreviewKeyboardCommandDispatcher`。
- `PreviewKeyboardWindow`、`PreviewKeyboardHandler`、capture view 可以消费事件防止系统 beep，但不能各自重复执行命令。
- 所有已处理的 `keyDown` 和 `keyUp` 都必须被消费；尤其是当前 shuttle 键松开时只发 `stopShuttle`，不能把事件继续传给系统。
- 默认 `J/L` shuttle 通过逐帧 seek，进入 shuttle 后初始每次 `2` 帧，最多加速到 `12` 帧，每 `33_000_000ns` 一次；如果用户改绑，以 `PreviewShortcutAction.shuttleBackward` 和 `.shuttleForward` 的当前 keyCode 为准。

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
static let railIconAlignmentOffsetX: CGFloat = -2.5
static let railButtonVisualOffsetX: CGFloat = 3.5
static let railSelectionGuideX: CGFloat = railIconInset + railButtonVisualOffsetX
static let railIconVisualGuideX: CGFloat = (railWidth - railIconBoxSize) / 2
static let libraryContentInset: CGFloat = 14
static let libraryToolbarElementGap: CGFloat = 8
static let libraryToolbarVisualGap: CGFloat = 14
static let libraryToolbarHeight: CGFloat = 26
static let libraryToolbarButtonSlotWidth: CGFloat = 18
static let libraryToolbarButtonSlotHeight: CGFloat = 22
static let libraryToolbarButtonGap: CGFloat = libraryToolbarElementGap
static let libraryToolbarSearchMinWidth: CGFloat = 80
static let libraryToolbarSearchWidth: CGFloat = 131
static let libraryToolbarSearchHeight: CGFloat = 26
static let libraryDateDividerTopInset: CGFloat = 10
static let libraryDateDividerBottomInset: CGFloat = 10
static let libraryHeaderDateDividerTopInset: CGFloat = 3
static let libraryHeaderDateDividerBottomInset: CGFloat = 17
static let previewHeaderTagRowHeight: CGFloat = 12
static let previewHeaderTopInset: CGFloat = libraryToolbarVisualGap
static let previewHeaderTitleTagGap: CGFloat = 8
static let previewHeaderBottomInset: CGFloat = 0
static let previewHeaderTitleLineHeight: CGFloat = 22
static let previewHeaderHeight: CGFloat = previewHeaderTopInset + previewHeaderTitleLineHeight + previewHeaderTitleTagGap + previewHeaderTagRowHeight + previewHeaderBottomInset
static let trafficLightSize: CGFloat = 12
static let trafficLightGap: CGFloat = 5
static let trafficLightClusterWidth: CGFloat = trafficLightSize * 3 + trafficLightGap * 2
static let libraryToolbarTop: CGFloat = libraryToolbarVisualGap
static let railTopChromeHeight: CGFloat = libraryToolbarTop + libraryToolbarHeight
static let trafficLightGuideX: CGFloat = railIconVisualGuideX
static let trafficLightGuideY: CGFloat = libraryToolbarTop + (libraryToolbarHeight - trafficLightSize) / 2
static let libraryToolbarLeadingInset: CGFloat = libraryContentInset
static let libraryToolbarTrailingInset: CGFloat = libraryContentInset
static let settingsRailWidth: CGFloat = max(railWidth, trafficLightGuideX + trafficLightClusterWidth)
static let timelineLaneHeight: CGFloat = 100
static let collapsedTimelineLaneHeight: CGFloat = 40
static let timelineLaneButtonSize: CGFloat = 24
static let timelineLaneIconSize: CGFloat = 22
static let timelineLaneVisualGap: CGFloat = (timelineLaneHeight - timelineLaneButtonSize * 3) / 4
static let timelineLaneContentHeight: CGFloat = timelineLaneHeight - timelineLaneVisualGap * 2
static let expandedTimelineDetailHeight: CGFloat = 280
static let sceneTimelineAutoVisibleSceneLimit = 36
static let sceneTimelineAutoMaxZoom: Double = 6
static let centeredWaveformViewportSpan: Double = 0.22
static let previewExportOverlayWidthRatio: CGFloat = 1.0 / 3.0
static let previewExportOverlayMinWidth: CGFloat = 260
static let previewExportOverlayButtonSize: CGFloat = 28
static let previewExportOverlayButtonIconSize: CGFloat = 13
static let previewExportOverlayButtonInset: CGFloat = 10
static let previewExportPanelPadding: CGFloat = 10
```

派生值：

- `libraryToolbarTop = 14`。
- `railTopChromeHeight = 40`，来自 `14 + 26`。
- `libraryContentInset = 14`，素材网格左右内边距和素材工具栏左右内边距共用同一基线；不要为了窗口按钮位置改动它。
- `libraryToolbarElementGap = 8`，顶部工具条中搜索框和图标按钮之间共用的视觉间距。
- 主页、画面、声音、音乐等媒体工作区的左上角工具条统一使用 `libraryToolbarLeadingInset = libraryContentInset = 14` 和 `libraryToolbarTrailingInset = 14`；搜索框左缘、下方内容卡片/条目左边线共线，最右侧工具按钮槽位右缘和下方内容卡片/条目右边线共线。
- 日期分割器默认使用 `libraryDateDividerTopInset = 10` 和 `libraryDateDividerBottomInset = 10`，让分组之间的线条上下留白对称；列表最上方那条日期分割器单独使用 `libraryHeaderDateDividerTopInset = 3` 和 `libraryHeaderDateDividerBottomInset = 17`，保留头部基准线位置。
- `trafficLightGuideX = 16`，来自 `railIconVisualGuideX = (56 - 24) / 2`，让红黄绿按钮左缘和侧边栏图标盒子的左缘共线；搜索框仍跟随素材区 `14pt` inset，避免素材区被窗口按钮带偏。
- `trafficLightGuideY = 21`，来自 `14 + (26 - 12) / 2`，让窗口按钮与顶部工具条垂直居中。
- `trafficLightClusterWidth = 46`，来自 `12 * 3 + 5 * 2`；窗口按钮组右缘 `16 + 46 = 62`，到搜索框左缘 `56 + 14 = 70` 正好为 `8pt`。
- `railIconAlignmentOffsetX = -2.5`，只移动侧边栏图标的绘制位置，不改变 rail 宽度、按钮点击区和窗口按钮位置；用于让侧边栏图标视觉左缘贴近红黄绿按钮左缘。
- `railSelectionGuideX = 11.5`，保留为 rail 的基础光学校正基线；当前红黄绿按钮改用 `railIconVisualGuideX` 对齐侧栏图标实际左缘。
- `settingsRailWidth = 62`，来自 `max(56, 16 + 46)`。
- `previewHeaderHeight = 56`，来自 `14 + 22 + 8 + 12 + 0`。
- `timelineLaneVisualGap = 7`，来自 `(100 - 24 * 3) / 4`。
- `timelineLaneContentHeight = 86`，来自 `100 - 7 * 2`。
- `sceneTimelineAutoMaxZoom = 6`，场景很多时自动聚焦到局部时间线，但不把主页初始视图推得太窄。

颜色：

```swift
sidebarBg = Color(red: 0.118, green: 0.118, blue: 0.129)
contentBg = Color(red: 0.149, green: 0.149, blue: 0.165)
neutralAccent = Color.white.opacity(0.72)
neutralStrongAccent = Color.white.opacity(0.88)
neutralBadgeFill = Color.white.opacity(0.18)
timelineIOAccent = Color(red: 1.00, green: 0.50, blue: 0.18)
timelinePlayheadAccent = Color.white.opacity(0.92)
screenshotFrameAccent = Color(red: 1.00, green: 0.50, blue: 0.18)
currentFrameAccent = Color(red: 1.00, green: 0.22, blue: 0.18)
captureFrameAccent = neutralAccent
annotationAccent = Color(red: 0.68, green: 0.72, blue: 0.72)
libraryToolbarIconTint = Color.white.opacity(0.72)
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
- 主页 header 高度：`56pt`。
- 主页 header 标题行高：`22pt`。
- 主页 header 标签行高：`12pt`。
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
- 工具栏图标槽位：`22 x 22pt`。
- 工具栏按钮间距：`13pt`。
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
- 网络视频导入队列、进度状态、暂停继续、删除和结果跳转。
- 自定义播放器、波形、帧带、场景网格、截图、批注。
- 播放器默认快捷键、改绑数据结构和冲突检测。
- 声音 In/Out 采样和导出。
- Whisper 转写和 Markdown 导出，导出记录可进入主页导出栏。
- 音乐识别、Apple Music 链接、原曲/伴奏下载。
- 主页、画面、声音、设置四个可见工作区；内容工作区代码保留。
- 项目资产保存到素材库目录。

仍需谨慎处理：

- UI 和 Store 已按职责拆分；后续功能修改应优先放到现有边界内，不要重新堆回 `ContentView.swift` 或 `LibraryStore.swift`。
- 网络平台下载能力受 `yt-dlp`、平台风控和网络状态影响。
- 本地模型能力依赖 Ollama 和模型是否已安装。
- 反向播放代理需要 ffmpeg，且生成代理可能耗时。
- 场景识别依赖 TransNetV2 环境。

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
- 设置工作区是偏管理的工具面板，只保留画面切分、字幕识别、音乐下载的总体操作，不放外接付费 AI API 配置。

### 11.3 快捷键和播放器

这阶段反复出现的问题是：快捷键被多个层级重复处理、已处理按键漏传给系统导致 beep、shuttle 和普通播放语义混在一起。当前定论：

- 快捷键默认值、用户改绑和冲突检测以 `PreviewShortcutAction` 为准；物理键转换只认 `PreviewKeyboardEventRouter`；命令分发只走 `PreviewKeyboardCommandDispatcher`。
- app-level `NSEvent` monitor 是唯一执行命令的 owner。窗口和 capture view 只负责兜底消费事件。
- 文本输入时不拦截快捷键；无修饰键的播放器快捷键才拦截。
- 默认 `J/L` 单击只跳一帧；按住触发 shuttle，松开停止。shuttle forward 不是普通播放键，不能直接调用 `setRate(1)`。
- 默认 `K` 平时是播放/暂停；如果已经在 shuttle 中，才作为加速键。
- `Space`、箭头、`I/O/E/U/P` 都要在 keyDown/keyUp 路径里安静消费，避免系统 beep。
- 修改快捷键动作或默认键位后，同时更新 `PreviewKeyboardCommand`、`PreviewShortcutAction`、`PreviewKeyboardEventRouter`、本文第 7 节和 `AGENTS.md`。

## 12. 后续开发原则

1. 保留 macOS 原生工具感，优先图标按钮、菜单、分段控件、轻量材质。
2. 每个新增资产都必须能定位回原视频时间点。
3. 媒体处理尽量异步，UI 状态通过 `LibraryStore` 发布。
4. 新持久化数据优先放入素材库目录的 JSON；只有数据复杂后再考虑 SQLite。
5. 修改播放器时先读 `PreviewController.swift`，不要绕过它直接控制 `AVPlayer`。
6. 修改键盘快捷键时同步更新 `PreviewKeyboardCommand`、`PreviewShortcutAction`、`PreviewKeyboardEventRouter` 和本文第 7 节。
7. 修改设计数值时同步更新本文第 9 节，确保以后能按文档复原。
8. 清理 Markdown 时只处理项目文档，不碰第三方依赖文档和导出样例。
