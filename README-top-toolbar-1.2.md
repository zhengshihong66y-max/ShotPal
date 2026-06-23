## 目标

这份说明用于让后续 AI 直接复现 1.2 版本的主页、音乐、画面顶部工具栏布局。核心要求是三个界面的搜索框长度、左起位置、按钮槽位和按钮间距保持一致。

## 固定数值

- `Design.railWidth = 56`：左侧导航 rail 宽度。
- `Design.libraryContentInset = 14`：工具栏左右内边距，也是搜索框与按钮区之间的标准间距。
- `Design.libraryToolbarHeight = 26`：顶部工具栏视觉高度。
- `Design.libraryToolbarSearchHeight = 26`：搜索框高度。
- `Design.libraryToolbarSearchMinWidth = 110`：搜索框被压缩时的最小宽度。
- `Design.libraryToolbarSearchWidth = 280`：搜索框正常理想宽度和最大宽度。
- `Design.libraryToolbarButtonSlotWidth = 18`：每个顶部按钮槽位宽度。
- `Design.libraryToolbarButtonSlotHeight = 22`：每个顶部按钮槽位高度。
- `Design.libraryToolbarButtonGap = Design.libraryContentInset = 14`：按钮槽位之间的横向间距。
- `Design.libraryToolbarActionSlotCount = 3`：顶部按钮区固定为 3 个槽位。
- `Design.libraryToolbarActionRowWidth = 18 * 3 + 14 * 2 = 82`：顶部按钮区固定宽度。

当前窗口下实测的主页素材区总宽约为 `340pt`，去掉 `56pt` rail 后，工具栏约束宽度为 `284pt`。因为工具栏两侧 padding 各 `14pt`，按钮区 `82pt`，搜索框与按钮区间距 `14pt`，所以搜索框实际显示宽度为：

```text
284 - 14 - 14 - 82 - 14 = 160pt
```

1.2 版本重启 Debug app 后的实测值：

| 界面 | 搜索框宽度 | 文本框宽度 | 可见按钮 x 坐标 |
|---|---:|---:|---|
| 主页 | 160 | 124 | 991 / 1023 / 1055 |
| 音乐 | 160 | 124 | 991 / 1023 |
| 画面 | 160 | 124 | 991 / 1023 / 1055 |

音乐页只有两个可见按钮，但必须从第一个槽位开始排列，不能在最左侧加透明占位。

## 布局原因

- 主页工具栏不是全窗口宽度，而是受左侧素材栏宽度限制；在当前基准窗口下，搜索框会从理想的 `280pt` 压缩到 `160pt`。
- 音乐和画面界面本身是全宽 workspace，如果让它们直接决定工具栏宽度，搜索框会保持 `280pt`，看起来就比主页长。
- 画面界面还有自己的宽面板逻辑，不能用它来推导顶部工具栏宽度；否则画面页会重新变成 `280pt`。
- 透明占位只能用于中间缺槽，不能放在音乐页最左侧；左侧透明占位会把第一个可见按钮推到第二槽，造成搜索框和按钮之间视觉断开。
- 顶部按钮必须使用固定槽位，不能让下载按钮、标签按钮、排序按钮、网格按钮、滑杆或局部 `Spacer` 自己撑开布局。

## 实现位置

- `LapianBao/Views/Design/Design.swift`
  - `LibraryToolbarSearchField` 使用 `minWidth: 110`、`idealWidth: 280`、`maxWidth: 280`。
  - `LibraryToolbar` 统一包裹 `LibraryToolbarActionRow`。
  - `LibraryToolbarActionRow` 固定宽度为 `Design.libraryToolbarActionRowWidth`。
  - `LibraryToolbarActionPlaceholder` 只用于必要的内部占位。
- `LapianBao/ContentView.swift`
  - `mainLayout` 计算 `let mediaWorkspaceToolbarWidth = homeMediaContentWidth(containerWidth: containerWidth)`。
  - 画面、音乐、设置等全宽 workspace 调用 `workspaceView(toolbarWidth: mediaWorkspaceToolbarWidth)`。
  - `homeMediaContentWidth(containerWidth:)` 只基于主页素材栏宽度 `mediaPanelWidth` 计算，不使用画面页自己的 `frameMediaPanelWidth`。
- `LapianBao/Views/Music/MusicWorkspaceView.swift`
  - `musicHeader()` 使用 `LibraryToolbar`。
  - 按钮顺序为 `musicTagFilterButton`、`musicSortMenu`。
  - 不要在这两个按钮前放 `LibraryToolbarActionPlaceholder()`。
- `LapianBao/Views/Frames/FramesWorkspaceView.swift`
  - `frameBoardToolbar` 使用 `LibraryToolbar`。
  - 按钮顺序为 `frameModeMenu`、`frameTagFilterButton` 或 `LibraryToolbarActionPlaceholder()`、`frameGridSizeMenu`。
  - 不要使用宽滑杆作为顶栏控件，网格大小放入固定槽位菜单。
- `LapianBao/Views/AppShell/ContentView+LibraryGrid.swift`
  - 主页素材栏继续使用同一套 `LibraryToolbar`。

## 操作步骤

1. 新增或修改顶部工具栏时，优先复用 `LibraryToolbar(placeholder: "", text: $...)`。
2. 不要给单个页面单独写搜索框宽度、按钮间距、局部 `.frame`、局部 `Spacer` 或 `.frame(maxWidth: .infinity)`。
3. 全宽 workspace 的顶部工具栏必须接收 `ContentView` 传入的 `toolbarWidth`。
4. 画面和音乐的顶栏外层必须保留 `.frame(width: toolbarWidth, alignment: .leading)`。
5. 音乐页两个按钮直接从第一个槽位开始；只有缺中间槽时才用 `LibraryToolbarActionPlaceholder()`。
6. 修改后运行：

```sh
python3 Tools/regression_checks.py
git diff --check -- AGENTS.md Tools/regression_checks.py LapianBao/ContentView.swift LapianBao/Views/Design/Design.swift LapianBao/Views/Music/MusicWorkspaceView.swift LapianBao/Views/Frames/FramesWorkspaceView.swift
xcodebuild -project LapianBao.xcodeproj -scheme LapianBao -configuration Debug -destination 'platform=macOS' build
```

7. 构建后重启 Debug app，并用可访问性坐标确认三个界面的搜索框和按钮槽位。

## 可接受的实测结果

在当前基准窗口下，三个界面的搜索框应全部为 `160pt`。按钮槽位应按 `14pt` 间距排布：

- 第 1 槽：`x = 991`
- 第 2 槽：`x = 1023`
- 第 3 槽：`x = 1055`

如果主页搜索框仍是 `160pt`，但音乐或画面是 `280pt`，说明全宽 workspace 又绕过了 `homeMediaContentWidth(containerWidth:)`。如果音乐页第一个可见按钮是 `x = 1023`，说明又在最左侧误加了透明占位。
