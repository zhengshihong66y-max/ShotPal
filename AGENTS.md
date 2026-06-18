# Project Rules

## 基本规则

- 默认用中文沟通和提交说明，除非用户明确要求英文。
- 本仓库已经进入收尾阶段。默认不新增大型功能、不重做视觉体系、不引入新的平台分支，优先处理稳定性、分发、验收、文档和少量必要修补。
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
- `Views/` 不直接启动外部进程，不直接读写项目 JSON，不直接枚举素材库目录。View 可以发起用户意图，执行必须落到 Store 或独立 service。
- 收尾阶段新增抽象必须服务真实复杂度，不能为了“更架构化”继续拆散稳定代码。

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
- 如果整个 App 变得无法点击，先用 `pgrep -fl LapianBao` 确认没有多个实例或旧调试窗口叠在一起，再查 SwiftUI 遮罩层和 AppKit 事件监听。

## 设计和 UI

- 不要把拉片宝改成网页后台、营销页、超大 hero 或装饰性界面。它应保持 macOS 原生工具感：暗色、克制、Finder/Apple Music 式侧边栏、轻量材质和紧凑信息密度。
- 左侧 rail、素材区工具栏、搜索框、窗口按钮和工作区顶部栏已有像素基线。除非用户明确要求重设设计，不要改 `Design` 里的尺寸常量。
- 主页播放器必须继续使用 `AVPlayerLayer` 承载画面，不要改回 SwiftUI 原生 `VideoPlayer`。
- 主页、画面、声音、音乐等媒体工作区顶部工具条应继续使用统一的 `LibraryToolbar` 视觉系统。
- 播放驱动的时间线移动、帧带平移、滚轮平移、缩放和播放头更新是高频路径。不要让它们继承 SwiftUI 隐式动画。
- 素材库滚动路径不得同步解码图片、读取扩展属性、扫描文件夹、生成波形或无限制生成缩略图。

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
