# Project Rules

## 基本规则

- 默认用中文沟通和提交说明，除非用户明确要求英文。
- 本仓库已经进入收尾阶段。默认不新增大型功能、不重做视觉体系、不引入新的平台分支，优先处理稳定性、分发、验收、文档和少量必要修补。
- 原"交付版"从 2026-07 起统一改称 **Pro 版**。历史分支 `交付版1.0`、`交付版1.1` 保持原名，新分支、文档和提交说明使用 `Pro X.Y` 命名（当前工作分支 `Pro1.2`）。
- 例外：项目所有者已批准在 `Pro1.2` 分支进行架构优化，目标是渐进拆分 `LibraryStore` 巨型对象、收敛手工 Task 字典。该工作按领域小步推进，每步必须通过验证命令，不改变用户可见行为。
- 项目级 Markdown 只保留 `AGENTS.md` 和 `README.md`。`AGENTS.md` 给 Codex 和后续开发者读，`README.md` 给用户和项目所有者读。
- `Tools/whisper.cpp` 是第三方 submodule，里面的 README 不属于本项目文档清理范围，除非明确更新 submodule，不要改写其中内容。
- 删除文件前先确认它不是源码、脚本、Xcode 工程配置、submodule 指针或仍被代码引用的测试夹具。
- 不提交 `.DS_Store`、`.codex-derived/`、`__pycache__/`、`*.pyc`、虚拟环境、旧导出测试或一次性计划文件。

## 验证命令

- 普通代码或文档收尾后，至少运行 `python3 Tools/regression_checks.py`。
- 影响 Swift 代码后，运行 `xcodebuild -project LapianBao.xcodeproj -scheme LapianBao -configuration Debug -destination 'platform=macOS' build`。
- 改到 App 启动、窗口、`AppStartup/`、`AppChrome.swift`、`LapianBaoApp.swift`、工程构建设置或启动脚本后，运行 `Tools/check_launch_window.sh`。
- `Tools/regression_checks.py` 是收尾阶段的轻量护栏，不替代真实启动和手动操作验收。

## 架构护栏和收尾边界

- `README.md` 是用户视角的软件说明，不再承载 AI 接手手册、调试历史或长篇内部规则。
- `AGENTS.md` 是内部规则入口。新增 AI/开发护栏先写到这里，再按需同步到 `Tools/regression_checks.py`。
- `LibraryStore.swift` 只能保留状态壳、共享常量、轻量 helper 和门面入口。新增下载、转码、解析、持久化、导入、场景、字幕、音乐逻辑时，优先放到已有 `Stores/LibraryStore+*.swift` 边界里。
- `ContentView.swift` 只能保留主布局壳、全局 overlay、workspace 切换和跨工作区跳转。复杂导入面板、筛选、资产列表、播放行、分析视图继续拆在 `Views/*` 子目录。
- `LapianBaoApp.swift` 只做 AppDelegate/lifecycle 桥接，不接业务逻辑。启动顺序归 `AppStartupCoordinator`，窗口归 `AppWindowManager`，启动可诊断标记归 `StartupDiagnostics`。
- 外部短命令执行当前 owner 是 `ExternalProcessRunner.swift`；项目隐藏 JSON 路径和基础读写当前 owner 是 `ProjectRepository.swift`；`UserDefaults.standard` 当前唯一 owner 是 `AppSettings.swift`；自定义 `lapianBao*` App 事件当前唯一 owner 是 `AppEventBus.swift`。
- 浏览器 cookie 读取(`--cookies-from-browser`)当前唯一 owner 是 `Stores/YouTubeCookieStore.swift`,触发方式仅两种:设置页按钮手动点击;用户已启用 cookie 方案后,下载遇到 YouTube 登录验证失败时按冷却(15 分钟)自动更新一次并重试。不允许恢复自动账号状态识别、登录态轮询或收藏列表读取,回归脚本对此有硬检查。
- per-key 后台任务记账当前唯一 owner 是 `KeyedTaskRunner.swift`。不要再在 store 上新增手工 `[Key: Task<Void, Never>]` 字典；新任务族一律用 `KeyedTaskRunner`（启动去重用 `start`/`startDetached`，先取消再启动用 `replace`，完成令牌用 `finish`）。
- 领域拆分模式（Pro1.2 起）：从 LibraryStore 拆出的领域 store 是独立 `@MainActor ObservableObject`，由 LibraryStore 以 `let` 持有，`AppWindowManager.createMainWindow()` 逐个 `.environmentObject(...)` 注入；视图只观察自己需要的领域 store。首例是 `Stores/DownloaderSelfCheckStore.swift`（自检报告/自检任务/preflight 冷却），无状态工具函数仍留在原 `LibraryStore+*.swift` 静态扩展里。
- `Views/` 不直接启动外部进程，不直接读写项目 JSON，不直接枚举素材库目录。View 可以发起用户意图，执行必须落到 Store 或独立 service。
- 收尾阶段新增抽象必须服务真实复杂度，不能为了“更架构化”继续拆散稳定代码。Pro1.2 分支已批准的架构优化不受此条限制，但仍要求每步行为等价并通过验证命令。

## 启动和窗口

- 不要在 `applicationDidFinishLaunching(_:)` 同步创建主窗口或恢复素材库。该 delegate callback 必须快速返回，并用 `DispatchQueue.main.async` 调度 `completeLaunchSetupIfNeeded()`。
- `completeLaunchSetupIfNeeded()` 的顺序应保持为安装菜单、创建并显示主窗口、安装可见性复查和键盘监听、激活 App、延后恢复素材库。
- 不要恢复 SwiftUI `WindowGroup` 作为主窗口。当前 App 由 AppDelegate 显式持有 `NSWindow`，用于规避 Debug/Xcode/Preview/JIT 路径下的无窗口进程问题。
- 启动恢复素材库时，目录枚举必须在后台完成。主窗口先显示并完成一次绘制，再恢复上次素材库。
- 如果启动后只有进程没有窗口，先判断是否是 pre-main 问题。`sample` 只有 `_dyld_start`、`vmmap -summary` 显示进程尚未开始、物理内存约 `96K`，都说明 App 代码还没运行。此时先查 Xcode 断点、旧 `debugserver`、LaunchServices、签名或隔离属性。
- Xcode 用户断点会让 App 在窗口创建前挂起。`Tools/check_launch_window.sh` 会扫描 `Breakpoints_v2.xcbkptlist`，存在启用断点时应失败。

## 交互命中检查

- 全窗口遮罩背景不能写成 `Button { Color... }` 或 `Button(action: close...) { Color... }`。macOS SwiftUI 会把它变成巨型可访问性/命中测试按钮，吞掉弹窗和主界面的点击。
- Modal 和导入弹窗背景必须使用非控件视图：`Color.black.opacity(...).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { ... }.accessibilityHidden(true)`，真正的面板内容再用 `zIndex` 放在上面。
- `LapianBaoApp.swift` 的 App 级预览键盘监听只能监听 `.keyDown` 和 `.keyUp`。不要添加 `.leftMouseDown`、`.rightMouseDown` 或其它 App 级鼠标监听。
- 不要在 App 级鼠标按下路径里调用 `window.makeFirstResponder(nil)`。鼠标焦点恢复只能留在局部桥接视图，例如 `PreviewKeyboardHandler`。
- 局部预览键盘焦点恢复不能在鼠标命中 `NSControl` 时抢 first responder；批注保存、取消、删除等控件必须先收到自己的 mouseDown/mouseUp。
- 如果整个 App 变得无法点击，先用 `pgrep -fl LapianBao` 确认没有多个实例或旧调试窗口叠在一起，再查 SwiftUI 遮罩层和 AppKit 事件监听。

## 设计和 UI

- 不要把拉片宝改成网页后台、营销页、超大 hero 或装饰性界面。它应保持 macOS 原生工具感：暗色、克制、Finder/Apple Music 式侧边栏、轻量材质和紧凑信息密度。
- 左侧 rail、素材区工具栏、搜索框、窗口按钮和工作区顶部栏已有像素基线。除非用户明确要求重设设计，不要改 `Design` 里的尺寸常量。
- 主页播放器必须继续使用 `AVPlayerLayer` 承载画面，不要改回 SwiftUI 原生 `VideoPlayer`。
- 主页、画面、声音、音乐等媒体工作区顶部工具条应继续使用统一的 `LibraryToolbar` 视觉系统。
- 主页、画面和音乐工作区的顶部搜索框必须由 `LibraryToolbarSearchField` 使用旧版主页基线：`Design.libraryToolbarSearchMinWidth` 为 110，`Design.libraryToolbarSearchWidth` 为 280，并通过 `idealWidth`/`maxWidth` 锁住正常宽度；不要改回 140，也不要按页面、右侧按钮数量或剩余空间扩展到 `.infinity`。
- 画面和音乐工作区的 `LibraryToolbar` 必须接收 `ContentView` 通过 `homeMediaContentWidth(containerWidth:)` 传入的主页素材内容区宽度；不能让全宽工作区或分镜自己的宽面板直接决定顶部搜索框长度。
- 主页、画面和音乐工作区的顶部按钮必须由 `LibraryToolbarActionRow` 统一排列成 3 个固定槽位，槽位使用 `Design.libraryToolbarButtonSlotWidth`/`Design.libraryToolbarButtonSlotHeight`，按钮间距使用 `Design.libraryToolbarButtonGap`；音乐页两个可见按钮直接从第一个槽位开始排列，只有中间缺槽时才用 `LibraryToolbarActionPlaceholder` 占位，不要在单个页面里用额外 `Spacer`、局部 `.frame`、宽滑杆或自定义间距重做工具栏。
- 播放驱动的时间线移动、帧带平移、滚轮平移、缩放和播放头更新是高频路径。不要让它们继承 SwiftUI 隐式动画。
- 主页画面时间线的默认缩放由场景数量决定，换视频后只要用户还没有手动平移或缩放，就要在分镜切点、缓存恢复或视频 duration 后到时自动补套聚焦，不要依赖当前激活的是不是画面 tab；密集分镜素材不能被 0.02 可见跨度或 50x 最大缩放卡住；场景进度条只吃外层平滑播放 clock，不要再套第二层进度插值。
- 画面时间线识别到分镜切点后必须立即使用分段样式；分段显示只能依赖 `sceneCuts`，不能因为 `sceneStripImages` 数量不完整退回普通连续帧带，代表帧缺失时用现有帧带或缩略图兜底。
- 主页画面时间线播放中的横向跟随必须用平滑播放 clock 计算显示用 viewport offset，不能只靠 30fps 发布状态跳动；展开画面时间线后的场景网格不能为了进度显示整网格重绘，只有当前活动卡片的进度层可以用 60fps clock 更新。
- 分镜网格点击场景卡片时不能直接 seek 到剪辑点边界；必须使用 `sceneGridSeekTime(for:)` 跳到剪辑点后一帧安全位置并关闭本次 `snapToFrame`，`activeSceneItemID` 也要保留剪辑点边界容差，避免落到上一个网格。
- 素材库滚动路径不得同步解码图片、读取扩展属性、扫描文件夹、生成波形或无限制生成缩略图。
- 标签筛选区使用紧凑胶囊 chip，标签名可以按中间省略，后缀数字不能省略成 `...`。数字位必须固定宽度、不可压缩，并优先保留完整显示。
- 标签筛选区进入编辑模式时，chip 的宽度、高度、颜色和排列位置不能跳动。不要额外叠加独立叉号；把原数字槽位替换为 `xmark` 删除按钮即可。
- 标签筛选区的编辑按钮放在整组标签 chip 之后，普通状态用铅笔，编辑状态用对勾；编辑状态的文字输入应沿用原 chip 颜色，不要突然变成白底或白色块。
- 标签编辑弹窗的垂直节奏与其它菜单一致：外层横向留白 14，纵向留白 16，输入框与标签区间距 16，标签网格自身不再额外加上下 padding。
- 标签编辑弹窗中通过输入框新建出来的标签，第一次再次点击不能立刻触发删除；需要防止“刚创建就误删”的交互。
- 视频卡片标签小菜单和平台小菜单不能跟随视频网格上下滚动；视频网格和画面页左侧视频列表必须通过 `fadingVerticalScrollIndicators(onScroll:)` 在滚动时关闭已打开的 `LibraryVideoTile` 菜单，且只有 `activeLibraryCardMenuID` 非空时才递增 `libraryCardMenuDismissToken`。
- 内容类标签弹窗不额外显示“内容”“图片标签”等标题；音乐界面不提供自添加标签系统，只显示系统自动识别出的流派标签，历史保存的非流派音乐标签不能进入行内显示或类型筛选。
- 所有音乐必须始终有至少一个流派标签；无法识别出具体流派时使用项目内已有的 `Soundtrack` 兜底，但仍要继续允许后续元数据补全替换为更准确流派。
- 导出面板图片行的标签加号必须跟在最后一个可见标签后面，并和标签保持同一条水平线；宽度不足时在加号前显示溢出 chip，不能把加号单独推到行尾。
- 画面详情浮层不使用省略号菜单；顶部栏左半显示可点击取消的单行标签并在末尾放加号，显示不下时用溢出 chip，右半显示色卡；顶部栏、预览框和底部栏按预览框实际宽度居中对齐，外框宽度跟随预览框宽度加统一 padding，外层上下 padding 与行间距使用同一个较小值；关闭时立即移除遮罩，空白处点击只关闭并消费当前点击，不能穿透到底层图片；底部栏左侧为回到原视频和访达，中间为播放/暂停，右侧为删除，底部按钮不加圆形背景。
- 批注编辑弹层要保留舒适的输入区左右内边距和适中的文字尺寸；回车用于输入换行，不能作为保存批注的默认动作；底部按钮行必须在内容区内等宽铺开，不能用前置 `Spacer()` 把取消/保存整体推到右侧。
- 下载队列活动卡片必须同时保留状态百分比文字和 URL 下方的 4pt 可见细进度条；进度条使用自绘 `RoundedRectangle` 轨道和状态色填充，不要只依赖系统 `ProgressView` 或只显示文字。
- 音乐列表行的标签区如果因为窄列换成多行，整行高度必须随流派标签流自动增高，不能用封面高度或固定行高裁掉后续标签；音乐条目的封面、标题、流派、下载按钮、波形和右侧操作按钮必须使用同一套固定列计算，不能因为某一行缺流派或缺波形而横向错位。
- 主页声音时间线保持播放头居中，但必须支持双指捏合缩放；缩放只改变声音时间线的可见时间跨度，不复用画面时间线的 `timelineZoom/timelineOffset` 状态。

## 媒体标签边界

- App 有四个独立标签域：视频、图片/画面、音效、音乐。
- 视频标签只存在于 `tagsByVideoPath` 和 `.lapianbaotags.json`。
- 图片标签只存在于 `SampledFrame.tags`。
- 音效标签只存在于 `AudioClipItem.tags` 和 `LocalAudioAsset.tags`。
- 音乐标签只存在于 `MusicRecognitionItem.tags` 和 `LocalMusicAsset.tags`。
- 不要把一种媒体类型的标签当作另一种媒体类型的默认值、建议、筛选或可见标签，除非用户明确要求做跨域迁移命令。

## 预览快捷键

- 预览快捷键必须静默。任何已处理的 `keyDown` 和 `keyUp` 都要被消费，不能让 macOS 播放系统 beep。
- 默认语义保持不变：`Space` 播放/暂停，`J` 后退或向后 shuttle，`L` 前进或向前 shuttle，`K` 播放/暂停或提升 shuttle 速度，方向键逐帧或切换场景，`I/O` 设置声音 In/Out，`E` 导出图片，`U` 清除声音选区，`P` 导出声音选区。
- 快捷键命令只能由 App 级 `NSEvent` local monitor 解析并派发到 `PreviewKeyboardCommandDispatcher`。
- `PreviewKeyboardWindow` 和 capture view 可以消费事件防止 beep，但不能独立重复执行命令。

## 分发和提交

- 用户要求本地提交时，只提交 `LapianBao` 项目仓库，不提交外层知识库仓库。
- 默认不推送到 GitHub，除非用户明确要求推送。
- 对外发包前至少验证本地导入、网络导入、播放、截图、声音导出、字幕导出、音乐识别、重启恢复和首次打开流程。
- 分发给单个普通用户时，优先给 `.app` 压缩包；只有需要源码协作时才邀请 GitHub collaborator。
