# 拉片宝项目说明与当前状态

日期：2026-05-24

这份文档用于交接当前版本。任何 AI 或开发者接手本项目时，应先阅读本文，再阅读 `LapianBao/ContentView.swift`、`LapianBao/LibraryStore.swift`、`LapianBao/LapianBaoApp.swift`。

## 项目目标

拉片宝是一个 macOS 本地视频素材库工具。目标不是做网页，也不是做服务器系统，而是做一个可以直接在 Mac 上使用的原生 App：

- 用户从菜单栏 `File > 打开文件夹` 选择一个视频文件夹。
- App 自动扫描文件夹中的视频，并以素材池网格展示。
- 用户可以给视频添加标签，并通过左侧分类栏筛选。
- 用户点击素材后，右侧预览区自动播放该视频。
- 预览区下方显示该视频的音频波形。
- 整体视觉参考 Apple Music 的 macOS 侧边栏、暗色界面和液态玻璃质感。

当前阶段的关键词：本地素材管理、网格浏览、标签分类、右侧预览、自定义播放器、音频波形、Apple Music 式 macOS 视觉。

## 当前已完成

### 基础应用结构

- 已创建 Xcode macOS App 项目，入口是 `LapianBaoApp.swift`。
- 使用 SwiftUI 构建主界面。
- 使用 AppKit 配置窗口，让窗口标题栏隐藏，并实现更接近 Apple Music 的自定义窗口外观。
- 使用 `LibraryStore` 作为全局状态中心，通过 `@StateObject` 和 `@EnvironmentObject` 注入界面。
- 菜单栏中已加入 `打开文件夹`，快捷键为 `Command + O`。
- App 会通过 `UserDefaults` 记住上一次打开的视频文件夹，下次启动时自动加载。

### 素材库

- 支持扫描这些视频格式：`mp4`、`mov`、`m4v`、`mkv`、`avi`、`webm`。
- 素材库使用网格展示，不再是一列列表。
- 网格大小使用三段式滑条控制，不做无意义的无级变化。
- 每个视频卡片显示封面、视频名、时长和标签。
- 封面使用 `AVAssetImageGenerator` 自动抓取。
- 为避免纯黑封面，当前会尝试多个时间点，并用亮度、方差和可见像素比例给候选帧打分，尽量选有内容的帧。

### 标签与筛选

- 左侧分类栏显示 `全部` 和已有标签。
- 选中标签后，素材库只显示包含该标签的视频。
- 右侧预览区中可以给当前视频添加标签。
- 当前标签数据仍是内存状态，尚未做持久化保存。

### 预览区

- 当前采用左右结构：左侧分类栏，中间素材库，右侧预览区。
- 素材库与预览区在普通宽度下是 5:5 的关系。
- 点击素材库中的视频后，右侧会自动开始播放，不需要二次点击。
- 已放弃 SwiftUI 原生 `VideoPlayer`，因为它在鼠标悬停时会显示系统控制层并压暗画面。
- 当前改用 `AVPlayerLayer` 承载视频画面，再由 SwiftUI 绘制自定义控制条。
- 自定义控制条目前包含播放/暂停、当前时间、进度条、总时长。
- 预览视频下方已经加入音频波形。
- 音频波形使用 `AVAssetReader` 读取音轨，生成压缩后的峰值采样，并缓存到内存中。

## 当前技术结构

### `LapianBaoApp.swift`

负责 App 入口与全局菜单：

- 创建 `LibraryStore`。
- 注入 `ContentView`。
- 启动时调用 `loadLastLibrary()`。
- 替换默认新建菜单，加入 `打开文件夹`。

### `LibraryStore.swift`

负责数据与媒体处理：

- `VideoItem`：单个视频的模型。
- `scanVideos(in:)`：扫描文件夹并生成视频列表。
- `chooseFolder()`：调用 `NSOpenPanel` 选择文件夹。
- `loadThumbnails(for:)`：异步生成封面和时长。
- `makeVideoMetadata(for:)`：生成视频封面和时长。
- `imageContentScore(_:)`：给候选封面打分，尽量避免黑帧。
- `loadWaveform(for:)`：按需生成音频波形。
- `makeWaveformSamples(for:sampleCount:)`：读取音轨并下采样成波形数据。

当前数据状态：

- 视频列表、缩略图、时长、波形都保存在内存中。
- 最近打开的文件夹路径保存在 `UserDefaults`。
- 标签目前只在内存中，还没有保存到磁盘。

### `ContentView.swift`

负责界面、窗口外观和交互：

- `WindowConfigurator`：配置 macOS 窗口外观。
- `WindowControlButton`：自定义红黄绿窗口按钮。
- `AudioWaveformView`：绘制音频波形。
- `PlayerSurfaceNSView` / `PlayerSurfaceView`：用 `AVPlayerLayer` 显示视频，避免系统播放器悬停遮罩。
- `PreviewPlayerView`：自定义播放器外层 UI。
- `PreviewScrubber`：自定义进度条。
- `sidebar`：左侧分类栏。
- `videoGrid`：素材库网格。
- `previewPanel`：右侧预览区。
- `playPreview(_:)`：切换视频并自动播放。

## 视觉与交互标准

后续优化时，应尽量遵守这些标准，不要随手改成另一套风格。

### 总体风格

- 参考 Apple Music for macOS，而不是网页后台、普通表格软件或移动端 App。
- 暗色背景，液态玻璃质感，克制的半透明层级。
- 不做营销页，不做大面积装饰性渐变球，不做花哨插画。
- 界面要像工作工具：密度合理、可扫描、适合反复浏览素材。

### 圆角标准

当前核心常量在 `ContentView.swift` 的 `Design` 中：

```swift
static let windowInset: CGFloat = 8
static let windowRadius: CGFloat = 30
static let panelSpacing: CGFloat = windowInset
static let panelRadius: CGFloat = windowRadius - windowInset
static let innerRadius: CGFloat = 18
static let itemRadius: CGFloat = 12
```

解释：

- 外层窗口圆角是 `30`。
- 内容距离窗口边缘是 `8`。
- 面板圆角是 `30 - 8 = 22`，目的是让窗口外框与内部面板看起来同心、适配，而不是互相打架。
- 面板之间的间距与窗口内边距一致，都是 `8`。
- 视频画面、波形、标签编辑区等内部模块使用 `18`。
- 小型列表项、标签选择项使用 `12`。
- 圆角统一使用 `.continuous`。

后续调整圆角时，不要只凭感觉单独改某一个块。优先维持“窗口圆角、内边距、面板圆角”之间的关系。

### 字体标准

当前使用系统字体，不引入第三方字体：

- 面板标题：`.title2.bold()`，例如“素材库”“预览”。
- 当前视频标题：`.title3.weight(.semibold)`。
- 侧边栏分类标题：`.headline`。
- 视频卡片标题：`.callout.weight(.semibold)`。
- 标签、时长、辅助信息：`.caption` 或 `.caption2`。
- 时间显示使用 `.monospacedDigit()`，避免播放时数字跳动。

原则：

- 不要用超大标题占用工具界面空间。
- 不要在界面中加入说明性长文案。
- 信息层级要靠字号、字重、透明度和位置区分。

### 图标标准

- 统一使用 SF Symbols。
- 工具按钮尽量使用图标，不要用大段文字按钮。
- 图标按钮要有 `.help()` 提示。
- 窗口控制按钮保持接近 macOS 原生红黄绿按钮的尺寸与行为。
- 网格大小控制继续使用网格类 SF Symbols。

### 布局标准

- 普通宽度下：分类栏固定宽度，素材库和预览区 5:5。
- 小窗口下：分类栏仍在左侧，素材库和预览区改为上下布局。
- 素材库和预览区的标题位置要对齐。
- 面板之间的间距要与窗口边缘到面板的距离一致。
- 预览区要优先保证视频画面的有效面积。

### 播放器标准

- 不再使用 SwiftUI 原生 `VideoPlayer` 做主预览，因为它的系统悬停控制层会压暗画面。
- 视频显示层使用 `AVPlayerLayer`。
- 控制条由我们自己画，保持轻、薄、透明，不抢画面。
- 后续如增加音量、倍速、全屏、逐帧、循环播放，也应放在自定义控制系统中。

## 当前已知限制

- 标签尚未持久化，重启后会丢失。
- 缩略图和波形目前只缓存于内存，重新扫描后会重新生成。
- 预览区的播放器控制还很基础，尚未精修 hover、拖动、缓冲、结束回到开头等状态。
- 素材库卡片的信息密度、选中状态、标签显示方式还需要继续优化。
- 小窗口下的比例关系还需要继续观察和修正。
- 还没有完整的自动化测试，目前主要通过 `xcodebuild` 编译验证。

## 下一步工作

接下来优先优化预览板块，其次优化素材库。

### 预览板块优先事项

1. 重新设计视频画面、波形、控制条、标签编辑区之间的比例。
2. 让波形更像剪辑软件中的时间线，而不是孤立装饰。
3. 优化自定义播放器的 hover 状态，避免控制条一直压住画面。
4. 增加更自然的播放结束状态，例如结束后停在最后一帧或回到开头。
5. 研究是否要加入音量、倍速、循环播放、全屏、逐帧前进。
6. 将视频路径等低频信息弱化，不要占用主要预览空间。
7. 为未来的“预览下方功能区”预留结构，而不是每次临时塞控件。

### 素材库优化事项

1. 优化视频卡片尺寸、标题行、标签行和时长标记。
2. 继续避免黑帧封面，必要时加入封面重新生成入口。
3. 优化选中视频的视觉反馈，让它明显但不过分刺眼。
4. 改进三段式网格滑条的视觉，保持简单。
5. 思考标签筛选和标签管理是否需要独立区域。
6. 后续加入标签持久化，优先考虑项目目录下的 JSON 文件；如果数据复杂，再考虑 SQLite。

### 工程优化事项

1. 拆分 `ContentView.swift`，把播放器、素材卡片、侧边栏拆成独立 Swift 文件。
2. 把设计常量集中成更清晰的 Design System。
3. 增加简单的数据持久化层。
4. 为媒体扫描、标签保存、波形生成增加更明确的错误处理。
5. 每次较大 UI 修改后运行：

```bash
xcodebuild -project LapianBao.xcodeproj -scheme LapianBao -destination 'platform=macOS' build
```

## 小米 MiMo 接手说明

接下来可能会让小米 MiMo 模型接手本项目。请把它当作一个擅长推理、代码和 Agent 工作流的模型来使用，但必须给它清晰的边界和验收标准。

### 对 MiMo 的基本判断

截至 2026-05-24，公开资料显示 MiMo 系列的定位偏向推理、代码、长上下文和工具调用。小米 MiMo 官方页面介绍 V2.5 系列时强调 1M 上下文、Agent 场景和对 Claude Code、OpenCode、OpenClaw 等编码工具链的兼容；MiMo-7B 的技术报告也强调数学、编程和通用推理任务上的强化训练。

因此，它适合接手这类任务：

- 阅读项目文档和代码，理解已有约束。
- 在明确任务范围内做 SwiftUI 小步 UI 优化。
- 根据现有设计常量继续收敛界面比例。
- 把复杂工作拆成可验证的小提交。
- 做偏工程化的整理，例如组件拆分、状态整理、数据持久化。

但它不应该被直接要求“凭感觉重做整个界面”。本项目最难的部分不是写出 SwiftUI 控件，而是维持 Apple Music 式 macOS 视觉、圆角关系、窗口比例和素材工具的克制感。

### MiMo 的优势应该这样利用

- 利用它的长上下文能力，让它一次读完本文、`ContentView.swift`、`LibraryStore.swift` 和最近的 Git diff。
- 利用它的代码能力，让它做局部、可编译、可回退的小改动。
- 利用它的中文理解能力，让它把用户的中文审美反馈转成具体 UI 调整。
- 利用它的 Agent 能力，让它形成“读文件、改代码、编译、汇报”的闭环。
- 利用它的效率优势，让它快速做多轮小迭代，而不是一次性大重构。

### 需要防范的风险

- 不要让它为了“看起来完整”新增大量无关功能。
- 不要让它重写架构、换技术栈、引入不必要依赖。
- 不要让它重新使用 SwiftUI 原生 `VideoPlayer` 做主预览播放器。
- 不要让它随意修改 `Design` 中的圆角、间距和比例常量。
- 不要让它把视觉做成网页后台、卡片墙或营销页。
- 不要让它在没有编译验证的情况下声称完成。
- 如果它无法看到运行截图，就必须明确说明“本轮只做代码层验证”，不能假装视觉已经确认。

### 给 MiMo 的接手协议

MiMo 接手时必须按这个顺序工作：

1. 运行 `git status --short`，确认当前工作区状态。
2. 阅读 `README.md`。
3. 阅读 `LapianBao/ContentView.swift`。
4. 阅读 `LapianBao/LibraryStore.swift`。
5. 只处理用户明确提出的任务，不顺手做大范围重构。
6. 修改前说明要改的区域和原因。
7. 修改后运行：

```bash
xcodebuild -project LapianBao.xcodeproj -scheme LapianBao -destination 'platform=macOS' build
```

8. 如果修改 UI，应尽量通过 Xcode 预览、运行 App 或截图验证视觉结果。
9. 只有用户明确要求时才提交 Git。

### 可以直接给 MiMo 的启动提示词

```text
你正在接手一个 macOS SwiftUI 项目：拉片宝。

项目路径是：
/Users/zhengshihong/Downloads/Newtybei知识库/进行项目/拉片宝/LapianBao

请先阅读 README.md，再阅读 LapianBao/ContentView.swift 和 LapianBao/LibraryStore.swift。

这个 App 是一个 Apple Music 风格的本地视频素材库，不是网页后台。当前重点是优化右侧预览区和中间素材库的 UI。请保持现有技术栈：SwiftUI + AppKit + AVFoundation。不要重新引入 SwiftUI 原生 VideoPlayer 作为主预览播放器，因为它会在悬停时压暗画面。不要随意破坏 Design 中的圆角、间距和比例关系。

你的工作方式必须是小步修改、编译验证、清楚汇报。完成后运行：
xcodebuild -project LapianBao.xcodeproj -scheme LapianBao -destination 'platform=macOS' build

如果你无法实际看到运行画面，请明确说明本轮只做了代码编译验证，不能声称视觉已经完全确认。
```

### 最适合 MiMo 继续做的下一批任务

1. 优化预览区比例：视频画面、控制条、波形、标签编辑区之间需要更成熟的层级。
2. 优化自定义播放器：控制条 hover 显示、播放结束状态、拖动进度时的反馈。
3. 优化波形：让它更像剪辑工具中的时间线，并与播放进度产生关系。
4. 优化素材库卡片：标题、时长、标签、选中状态和网格密度。
5. 拆分 `ContentView.swift`：先拆播放器，再拆素材卡片，最后拆侧边栏。
6. 实现标签持久化：优先使用项目本地 JSON 文件，不要一开始就上复杂数据库。

### 暂时不建议 MiMo 先做的事

- 不要先做云同步、账号系统、多设备同步。
- 不要先做数据库重构。
- 不要先做完整全屏播放器。
- 不要先改窗口外框和红黄绿按钮位置，除非用户再次明确要求。
- 不要一次性重做整套视觉语言。

### MiMo 资料依据

- 小米 MiMo 官方页：https://mimo.mi.com/
- MiMo-7B 技术报告：https://arxiv.org/abs/2505.07608

## 给下一位 AI 的工作方式

如果你是接手本项目的 AI，请按这个顺序工作：

1. 先读本文，理解项目不是普通文件管理器，而是一个 Apple Music 风格的本地视频素材库。
2. 再读 `LapianBao/ContentView.swift`，理解当前视觉结构和设计常量。
3. 再读 `LapianBao/LibraryStore.swift`，理解视频扫描、缩略图、时长、波形和标签数据流。
4. 不要轻易改动 `Design` 里的圆角关系，除非你能解释为什么整体关系更好了。
5. 不要重新引入 SwiftUI `VideoPlayer` 作为主预览播放器。
6. 修改 UI 时，要优先保持“分类栏、素材库、预览区”的秩序和比例。
7. 完成后必须用 `xcodebuild` 编译验证。

当前项目最重要的下一步：优化右侧预览区，让视频、波形、自定义播放器和标签编辑区成为一个更成熟、更像剪辑工具的整体。
