# Project Rules

## 基本规则

- 默认用中文沟通，除非用户明确要求英文；提交说明、PR 描述和版本更新说明统一使用英文。
- 本仓库已经进入收尾阶段。默认不新增大型功能、不重做视觉体系、不引入新的平台分支，优先处理稳定性、分发、验收、文档和少量必要修补。
- 原"交付版"从 2026-07 起统一改称 **Pro 版**。历史分支 `交付版1.0`、`交付版1.1` 保持原名，新分支、文档和提交说明使用 `Pro X.Y` 命名（当前工作分支 `Pro1.2`）。
- 例外：项目所有者已批准在 `Pro1.2` 分支进行架构优化，目标是渐进拆分 `LibraryStore` 巨型对象、收敛手工 Task 字典。该工作按领域小步推进，每步必须通过验证命令，不改变用户可见行为。
- 项目维护规则保存在 `AGENTS.md`；允许双语 README、LICENSE 及 `.github/` 下的贡献指南和模板。`README.md` 是项目交付时才写给用户的成品说明，进行中一律不写；需要照着走的流程另开手册。
- `Tools/whisper.cpp` 是第三方 submodule，里面的 README 不属于本项目文档清理范围，除非明确更新 submodule，不要改写其中内容。
- 删除文件前先确认它不是源码、脚本、Xcode 工程配置、submodule 指针或仍被代码引用的测试夹具。
- 不提交 `.DS_Store`、`.codex-derived/`、`__pycache__/`、`*.pyc`、虚拟环境、旧导出测试或一次性计划文件。

## 验证命令

- 普通代码或文档收尾后，至少运行 `python3 Tools/regression_checks.py`。
- 影响 Swift 代码后，运行 `xcodebuild -project LapianBao.xcodeproj -scheme LapianBao -configuration Debug -destination 'platform=macOS' build`。
- 改到 App 启动、窗口、`AppStartup/`、`AppChrome.swift`、`LapianBaoApp.swift`、工程构建设置或启动脚本后，运行 `Tools/check_launch_window.sh`。
- `Tools/regression_checks.py` 是收尾阶段的轻量护栏，不替代真实启动和手动操作验收。

## 架构护栏和收尾边界

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

- 搜索输入框必须由原生可编辑控件接收文本选择拖动（`mouseDownCanMoveWindow = false`），不能转成窗口拖动。导入提交后清空草稿；剪贴板自动填充必须排除已排队/已导入链接。音乐下载队列独立于搜索词和搜索结果，AM 搜索保留服务返回相关性顺序，不继承素材库排序。浏览器 cookie 同步只做本地导出，界面区分文件保留、同步失败、登录有效性未验证；不能把公开下载成功当作 cookie 有效证明。相关改动运行 `--lapianbao-ui-state-check` 与 `python3 Tools/test_cookie_export.py`。

- 全窗口遮罩背景不能写成 `Button { Color... }` 或 `Button(action: close...) { Color... }`。macOS SwiftUI 会把它变成巨型可访问性/命中测试按钮，吞掉弹窗和主界面的点击。
- Modal 和导入弹窗背景必须使用非控件视图：`Color.black.opacity(...).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { ... }.accessibilityHidden(true)`，真正的面板内容再用 `zIndex` 放在上面。
- `LapianBaoApp.swift` 的 App 级预览键盘监听只能监听 `.keyDown` 和 `.keyUp`。不要添加 `.leftMouseDown`、`.rightMouseDown` 或其它 App 级鼠标监听。
- 不要在 App 级鼠标按下路径里调用 `window.makeFirstResponder(nil)`。鼠标焦点恢复只能留在局部桥接视图，例如 `PreviewKeyboardHandler`。
- 局部预览键盘焦点恢复不能在鼠标命中 `NSControl` 时抢 first responder；批注保存、取消、删除等控件必须先收到自己的 mouseDown/mouseUp。
- 点击按钮打开全屏遮罩面板时,打开面板的那次鼠标点击会被 macOS 手势系统对更新后的视图树重新命中、落到遮罩上当场把面板关掉(AXPress 无鼠标事件所以复现不了)。遮罩的"点空白关闭"手势必须忽略面板打开后的短窗口(参照导入面板的 `importPanelPresentedAt` + 0.35 秒守卫)。
- 如果整个 App 变得无法点击，先用 `pgrep -fl LapianBao` 确认没有多个实例或旧调试窗口叠在一起，再查 SwiftUI 遮罩层和 AppKit 事件监听。

## 设计和 UI

- 当前暂缓在线音乐搜索：生产默认只搜索已有音乐库，输入文字不得触发在线目录搜索或弹出 AM 搜索 popover；已有音乐、识别、播放与下载任务保留。在线搜索代码与离线回归夹具保留以供后续恢复，但不能提供用户可误开的入口。搜索模式必须进入投影和缓存签名，本地模式忽略旧在线结果；本地曲名/作者/流派筛选、清空恢复及下载任务保留须有验证。
- 保留的在线音乐搜索模式仅在显式测试/后续恢复时开启：结果/加载/空结果/错误位于搜索框锚定 popover，不提供页内 AM 搜索分区、不改变底层库列表。弹层开关保留原生输入与文本选择，不加全 App 鼠标监听；防抖加载及响应按查询和请求代次校验。
- 音乐下载复用普通音乐条目，不另设下载队列卡片或独立进度条；有真实测量时按钮只显示百分比，不显示阶段/暂停/失败文字；未知进度恢复原曲/伴奏标签，不编造数值，具体状态与失败原因保留在右键菜单、辅助功能及重试操作，不新增悬停提示。搜索清空或换词后下载条目仍可见，同一首歌只出现一次；下载完成入库保持行与任务 ID，真实任务优先于本地文件合成任务。纯进度更新不得重建/重新缓存整张音乐列表，不得重置另一轨道的播放时间。
- 音乐下载点击后按歌曲和原曲/伴奏类型立即读取真实任务，不能等待列表投影刷新；活动任务尚无测量值时在原按钮图标位显示微型活动指示，保留原曲/伴奏标签，不编造 0%。首个反馈、测量有无切换及完成值立即发布，后续高频测量仍合并；旧定时回调不能刷新新一轮待发布数据。
- 音乐封面优先使用同一歌曲的有效元数据与下载快照，入库不能丢失封面；同曲刷新保留已加载封面，换曲及迟到的请求不能串图，暂停加载不能清空有效缓存。封面请求按 URL 合并、失败短暂冷却，解码降采样在后台执行；缺失封面使用稳定占位，不得拿不匹配的搜索结果充当封面。

- 未匹配到歌曲或音乐识别未完成时，不显示红色感叹号/失败徽标；音乐专用提示与菜单使用中性色，并保留重试。服务/依赖/文件错误仍须如实显示为“识别未完成”及具体原因，不得伪装成成功无匹配；部分识别失败时已有歌曲仍可见。其他功能的错误样式不随之改变。相关改动运行 `--lapianbao-ui-state-check` 和 `Tools/test_music_recognition.py`。

- 字幕识别无可用文字或失败时，展开的声音时间线必须保留可播放、可拖动的波形与明确状态/重试入口，不能渲染空白灰面板。空结果是已完成尝试，不得自动循环重试；失败或空结果重试不得清除已有有效字幕；延迟到达的进度不得把结束状态改回运行。转写相关改动运行 `--lapianbao-ui-state-check`（包含空/部分/失败/缓存恢复回归）。
- 主页字幕列表右侧滚动条只在用户实际滚动时显示，停止后自动隐藏；打开、布局更新和播放自动跟随不得唤起滚动条。监听必须绑定字幕自身 NSScrollView 的 live-scroll 通知，兼容无 start/end 通知的鼠标滚轮，不加全 App 事件监听、不改系统滚动条设置；保留字幕点击连续播放和自动跟随。

- 不要把拉片宝改成网页后台、营销页、超大 hero 或装饰性界面。它应保持 macOS 原生工具感：暗色、克制、Finder/Apple Music 式侧边栏、轻量材质和紧凑信息密度。
- 左侧 rail、素材区工具栏、搜索框、窗口按钮和工作区顶部栏已有像素基线。除非用户明确要求重设设计，不要改 `Design` 里的尺寸常量。
- 主页播放器必须继续使用 `AVPlayerLayer` 承载画面，不要改回 SwiftUI 原生 `VideoPlayer`。
- 主页、画面、声音、音乐等媒体工作区顶部工具条应继续使用统一的 `LibraryToolbar` 视觉系统。
- 主页、画面和音乐工作区的顶部搜索框必须由 `LibraryToolbarSearchField` 使用旧版主页基线：`Design.libraryToolbarSearchMinWidth` 为 110，`Design.libraryToolbarSearchWidth` 为 280，并通过 `idealWidth`/`maxWidth` 锁住正常宽度；不要改回 140，也不要按页面、右侧按钮数量或剩余空间扩展到 `.infinity`。
- 画面和音乐工作区的 `LibraryToolbar` 必须接收 `ContentView` 通过 `homeMediaContentWidth(containerWidth:)` 传入的主页素材内容区宽度；不能让全宽工作区或分镜自己的宽面板直接决定顶部搜索框长度。
- 主页、画面和音乐工作区的顶部按钮必须由 `LibraryToolbarActionRow` 统一排列成 3 个固定槽位，槽位使用 `Design.libraryToolbarButtonSlotWidth`/`Design.libraryToolbarButtonSlotHeight`，按钮间距使用 `Design.libraryToolbarButtonGap`；音乐页两个可见按钮直接从第一个槽位开始排列，只有中间缺槽时才用 `LibraryToolbarActionPlaceholder` 占位，不要在单个页面里用额外 `Spacer`、局部 `.frame`、宽滑杆或自定义间距重做工具栏。
- 不要在 `LazyVStack`/`LazyVGrid` 的行内容里用 `Spacer` 撑固定高度(包括塞进 `.frame(height:)` 容器里),懒加载测量会触发 EXC_BAD_ACCESS 崩溃;需要把某行内容钉到容器底边时用 `.overlay(alignment: .bottomLeading)`。下载记录列表曾因此连崩三次。
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
- AM 搜索须保留服务返回的真实流派语义；中文/繁体别名（如“国际流行”“电子音乐”“R&B/灵魂乐”）统一映射到既有规范流派，已知英文流派不能因漏写别名而丢弃。别名表与输入使用同一规范化键；不得为绕过兜底而开放任意字符串为流派。改动测试须从 `primaryGenreName` JSON 解码贯穿歌曲标签、行显示、筛选与下载快照，并升级音乐显示缓存版本以淘汰旧投影。
- AM 搜索 HTTP 拒绝或限流必须作为带状态码的服务错误显示，不能返回空数组伪装成“没有搜索结果”；不要为此切换用户网络设置或绕过服务限制。
- 导出面板图片行的标签加号必须跟在最后一个可见标签后面，并和标签保持同一条水平线；宽度不足时在加号前显示溢出 chip，不能把加号单独推到行尾。
- 画面详情浮层不使用省略号菜单；顶部栏左半显示可点击取消的单行标签并在末尾放加号，显示不下时用溢出 chip，右半显示色卡；顶部栏、预览框和底部栏按预览框实际宽度居中对齐，外框宽度跟随预览框宽度加统一 padding，外层上下 padding 与行间距使用同一个较小值；关闭时立即移除遮罩，空白处点击只关闭并消费当前点击，不能穿透到底层图片；底部栏左侧为回到原视频和访达，中间为播放/暂停，右侧为删除，底部按钮不加圆形背景。
- 批注编辑弹层要保留舒适的输入区左右内边距和适中的文字尺寸；回车用于输入换行，不能作为保存批注的默认动作；底部按钮行必须在内容区内等宽铺开，不能用前置 `Spacer()` 把取消/保存整体推到右侧。
- 下载队列活动卡片必须同时保留状态百分比文字和 URL 下方的细进度条；进度条用原生 `ProgressView(value:)`（系统自带前跳平滑，自绘 RoundedRectangle 在整行高频重建下动画吃不上）。进度真实性纪律：条上显示的每个数字必须来自真实测量（下载=yt-dlp 字节进度、转码=ffmpeg out_time），没有真实测量值时传 nil 显示不确定态动画，禁止编造百分比（状态档位 0.92/0.98、按已下字节的渐近饱和曲线都属编造）；转码是独立阶段，从自己的真实 0% 重新起算并配"正在转码"标签，阶段内单调；finalizing(1) 只允许在转码结束后发。
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

- 点击字幕条目应从该条目的开始时间以正常速度持续播放，不暂停、不在该条目结束时停止；应清除之前的片段播放终点。保留用户随后暂停与再次跳转的控制权。改动运行 `--lapianbao-ui-state-check --subtitle-playback-fixture <至少四秒的本地测试媒体>`。

- 预览快捷键必须静默。任何已处理的 `keyDown` 和 `keyUp` 都要被消费，不能让 macOS 播放系统 beep。
- 默认语义保持不变：`Space` 播放/暂停，`J` 后退或向后 shuttle，`L` 前进或向前 shuttle，`K` 播放/暂停或提升 shuttle 速度，方向键逐帧或切换场景，`I/O` 设置声音 In/Out，`E` 导出图片，`U` 清除声音选区，`P` 导出声音选区。
- 快捷键命令只能由 App 级 `NSEvent` local monitor 解析并派发到 `PreviewKeyboardCommandDispatcher`。
- `PreviewKeyboardWindow` 和 capture view 可以消费事件防止 beep，但不能独立重复执行命令。

## 分发和提交

- 音乐识别与分镜识别是核心功能：必须内嵌 arm64 Python wheel 完整依赖闭包与 TransNet 模型权重，通过 `recognition_bootstrap.py` 隔离加载；禁止首次使用 pip/venv 安装和宿主 Python/项目目录回退。构建前校验锁文件、文件清单和模型，签名后及最终 DMG 内运行 `Tools/verify_recognition_runtime.py`；音乐服务失败不能伪装成无匹配。
- 下载运行时必须内嵌 yt-dlp（含 EJS）、Python、Deno、FFmpeg 和 ffprobe；统一通过 `YTDLPRuntime` 调用。下载/元数据/cookie 路径只能 await `DownloaderReadiness`，不能在 MainActor 同步探测或首次启动联网安装。手动更新必须验 SHA256 并保留内置回退。
- YouTube 带 cookie 的视频首试使用 yt-dlp 默认客户端选择，不强制旧 `tv` 或跳过 HLS/DASH；音频优化路径仍必须有默认客户端回退。单一客户端登录验证失败不能跳过其余带 cookie 的客户端/已配置代理尝试；全部失败后才交给既有冷却式 cookie 更新。错误文案根据该次调用是否实际传入 cookie 区分，不能只凭已配置文件就声称已经发送或承诺还会重试。
- 分发前运行 `Tools/verify_download_runtime.py <成品 app 绝对路径>`；必须对最终 DMG 内 app 再跑一次。`--version`、签名、公证、临时 HOME 均不能替代干净系统和真实目标机下载验收；未测试项必须明确标记。
- 用户要求本地提交时，只提交 `LapianBao` 项目仓库，不提交外层知识库仓库。
- 默认不推送到 GitHub，除非用户明确要求推送。
- `Pro1.2` 是唯一开发主线与 GitHub 默认分支；只向 `origin/Pro1.2` 推送，不重新创建或同步 `main`。公开下载仓库只分发安装包与展示资料，不作为另一条开发主线。
- 对外发包前至少验证本地导入、网络导入、播放、截图、声音导出、字幕导出、音乐识别、重启恢复和首次打开流程。
- 分发给单个普通用户时，优先给 `.app` 压缩包；只有需要源码协作时才邀请 GitHub collaborator。

## 语言

- 界面文案通过 `L10n` 与 `en.lproj` / `zh-Hans.lproj` 跟随 macOS 首选应用语言；不覆盖系统语言设置。英文为不支持语言的回退。
- 只本地化显示文案，枚举 rawValue、平台标识、素材库目录、JSON/数据库键和用户内容保持稳定。旧导出文档仍须可读取。语言改动运行 `python3 Tools/check_localizations.py` 与成品 App 的 `--lapianbao-localization-check`（分别带 `-AppleLanguages '(en)'` / `'(zh-Hans)'`）；并验证两种语言下的 `--lapianbao-ui-state-check`。音乐显示缓存必须包含语言，切换语言后重建。

## 最终架构检查补充

- 项目 JSON 写入必须在 ProjectRepository 的同一写锁内检查取消并原子提交；同步退出/切库 flush 递增保存序号，旧任务不得在新快照之后落盘或清除新任务状态。
- 外部进程管道按字节缓存完整行后再解码 UTF-8，不能逐回调解码并丢弃跨包的中文/emoji。相关修改运行 `python3 Tools/check_architecture_boundaries.py`，该检查仅使用临时夹具。

- 读取素材库时，缺失源视频不等于用户删除：保留截图文件与 frame 记录，以支持离线磁盘或暂时不可用媒体；只有显式 removeVideo 操作清理关联导出。

- 项目数据读取必须区分不存在与读取/解码失败；失败保留原文件、停止自动保存并显示错误。保存失败保留 dirty 与内存数据，退出和切库须等待成功 flush；读取中存在修改也不能静默退出。相关验证在 annotation-save-check 中。

- 视频标签、来源信息、素材标签统一使用 ProjectRepository 的 readMetadata/writeMetadata；失败保留待写快照，重试前校验磁盘内容，读取失败后的恢复保留备份中其他条目。ProjectRepository.retryMetadata 纳入退出/切库 flush。错误通过 AppEventBus 通知主界面，并提供重试。运行 `Tools/check_metadata_persistence.py` 与 annotation-save-check。

## GitHub 首页内容稳定性

- 项目所有者于 2026-09-10 明确授权 ShotPal 仓库公开并接受社区贡献；默认通过 fork 和面向 Pro1.2 的 PR 接收修改。
- README 顶部居中展示语言切换，其后依次为与主图同宽的版本与 DMG 下载信息条、主 GIF、下载、分镜识别、截图、声音选区、本地字幕、分镜表、拖出、音乐识别图片；标题、介绍、导航和其余文字全部放在这些媒体之后。默认展示，禁止折叠。
- 保留现有内容、顺序、宽度、图片替代文字和点击目的地；只改用户明确指定的部分，不因维护删除、重新设计或调整其他内容。
- 首页媒体链接固定到已存在的完整 Git 提交 SHA，不使用临时访问令牌或过期链接。仅在用户要求更换媒体时更新相应引用；提交前检查首段全部 10 个媒体目标及后续新增媒体目标存在、顺序与内容保留，发布后验证登录用户的实际加载。

- 主 GIF 的固定链接使用 URL 等价编码 `.％67if`（实际字符为半角 `%`），用于避免 GitHub 的动画播放器移除尺寸占位；不要无故解码回 `.gif`。仍指向同一 GIF 文件。保留主图宽高比及全部图片尺寸占位，检查加载前后尺寸一致。
