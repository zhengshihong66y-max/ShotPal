import AppKit
import SwiftUI

enum PreviewKeyboardCommand {
    case togglePlayback
    case pause
    case shuttleForward
    case shuttleBackward
    case stopShuttle
    case increaseShuttleSpeed
    case stepForward
    case stepBackward
    case previousSceneCut
    case nextSceneCut
    case setAudioIn
    case setAudioOut
    case clearAudioSelection
    case captureCurrentFrame
    case exportAudioSelection
}

enum PreviewShortcutAction: String, Identifiable {
    case togglePlayback
    case shuttleSpeed
    case shuttleBackward
    case shuttleForward
    case stepBackward
    case stepForward
    case previousSceneCut
    case nextSceneCut
    case setAudioIn
    case setAudioOut
    case clearAudioSelection
    case captureCurrentFrame
    case exportAudioSelection

    var id: String { rawValue }

    static let allCases: [PreviewShortcutAction] = [
        .togglePlayback,
        .shuttleSpeed,
        .shuttleBackward,
        .shuttleForward,
        .stepBackward,
        .stepForward,
        .setAudioIn,
        .setAudioOut,
        .clearAudioSelection,
        .captureCurrentFrame,
        .exportAudioSelection
    ]

    var title: String {
        switch self {
        case .togglePlayback: return "播放/暂停"
        case .shuttleSpeed: return "播放/加速"
        case .shuttleBackward: return "倒放穿梭"
        case .shuttleForward: return "正放穿梭"
        case .stepBackward: return "后退一帧"
        case .stepForward: return "前进一帧"
        case .previousSceneCut: return "上一个剪辑点"
        case .nextSceneCut: return "下一个剪辑点"
        case .setAudioIn: return "设置 In 点"
        case .setAudioOut: return "设置 Out 点"
        case .clearAudioSelection: return "清除声音选区"
        case .captureCurrentFrame: return "导出当前画面"
        case .exportAudioSelection: return "导出声音选区"
        }
    }

    var defaultKeyCode: UInt16 {
        switch self {
        case .togglePlayback: return 49
        case .shuttleSpeed: return 40
        case .shuttleBackward: return 38
        case .shuttleForward: return 37
        case .stepBackward: return 123
        case .stepForward: return 124
        case .previousSceneCut: return 126
        case .nextSceneCut: return 125
        case .setAudioIn: return 34
        case .setAudioOut: return 31
        case .clearAudioSelection: return 32
        case .captureCurrentFrame: return 14
        case .exportAudioSelection: return 35
        }
    }

    private var defaultsKey: String {
        "previewShortcut.\(rawValue).keyCode"
    }

    var keyCode: UInt16 {
        defaultKeyCode
    }

    func setKeyCode(_ keyCode: UInt16) {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    func command(isShuttling: Bool) -> PreviewKeyboardCommand {
        switch self {
        case .togglePlayback:
            return .togglePlayback
        case .shuttleSpeed:
            return isShuttling ? .increaseShuttleSpeed : .togglePlayback
        case .shuttleBackward:
            return .shuttleBackward
        case .shuttleForward:
            return .shuttleForward
        case .stepBackward:
            return .stepBackward
        case .stepForward:
            return .stepForward
        case .previousSceneCut:
            return .previousSceneCut
        case .nextSceneCut:
            return .nextSceneCut
        case .setAudioIn:
            return .setAudioIn
        case .setAudioOut:
            return .setAudioOut
        case .clearAudioSelection:
            return .clearAudioSelection
        case .captureCurrentFrame:
            return .captureCurrentFrame
        case .exportAudioSelection:
            return .exportAudioSelection
        }
    }

    static func action(for keyCode: UInt16) -> PreviewShortcutAction? {
        allCases.first { $0.keyCode == keyCode }
    }

    static func actions(for keyCode: UInt16) -> [PreviewShortcutAction] {
        allCases.filter { $0.keyCode == keyCode }
    }

    static func hasConflict(action: PreviewShortcutAction, keyCode: UInt16) -> Bool {
        allCases.contains { $0 != action && $0.keyCode == keyCode }
    }
}

enum PreviewShortcutKeyOption: UInt16, CaseIterable, Identifiable {
    case space = 49
    case a = 0
    case s = 1
    case d = 2
    case f = 3
    case h = 4
    case g = 5
    case z = 6
    case x = 7
    case c = 8
    case v = 9
    case b = 11
    case q = 12
    case w = 13
    case e = 14
    case r = 15
    case y = 16
    case t = 17
    case one = 18
    case two = 19
    case three = 20
    case four = 21
    case six = 22
    case five = 23
    case equal = 24
    case nine = 25
    case seven = 26
    case minus = 27
    case eight = 28
    case zero = 29
    case o = 31
    case u = 32
    case i = 34
    case p = 35
    case l = 37
    case j = 38
    case k = 40
    case n = 45
    case m = 46
    case leftArrow = 123
    case rightArrow = 124
    case downArrow = 125
    case upArrow = 126

    var id: UInt16 { rawValue }

    var title: String {
        switch self {
        case .space: return "Space"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .downArrow: return "↓"
        case .upArrow: return "↑"
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .five: return "5"
        case .six: return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        case .zero: return "0"
        case .minus: return "-"
        case .equal: return "="
        default: return String(describing: self).uppercased()
        }
    }

    static func title(for keyCode: UInt16) -> String {
        Self(rawValue: keyCode)?.title ?? "Key \(keyCode)"
    }
}

@MainActor
enum PreviewKeyboardCommandDispatcher {
    private static var handler: ((PreviewKeyboardCommand) -> Bool)?

    static func setHandler(_ newHandler: @escaping (PreviewKeyboardCommand) -> Bool) {
        handler = newHandler
    }

    static func clearHandler() {
        handler = nil
    }

    static var hasHandler: Bool {
        handler != nil
    }

    @discardableResult
    static func dispatch(_ command: PreviewKeyboardCommand) -> Bool {
        handler?(command) ?? false
    }
}

enum PreviewKeyboardEventRouter {
    static var hasActiveHandler: Bool {
        PreviewKeyboardCommandDispatcher.hasHandler
    }

    static func isHandledKeyCode(_ keyCode: UInt16) -> Bool {
        PreviewShortcutAction.action(for: keyCode) != nil
    }

    static func isShuttleKeyCode(_ keyCode: UInt16) -> Bool {
        keyCode == PreviewShortcutAction.shuttleBackward.keyCode
            || keyCode == PreviewShortcutAction.shuttleForward.keyCode
    }

    static func isShuttling(_ pressedKeyCodes: Set<UInt16>) -> Bool {
        pressedKeyCodes.contains(PreviewShortcutAction.shuttleBackward.keyCode)
            || pressedKeyCodes.contains(PreviewShortcutAction.shuttleForward.keyCode)
    }

    static func isPlainShortcutEvent(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .control, .option]).isEmpty
    }

    static func command(for keyCode: UInt16, isShuttling: Bool) -> PreviewKeyboardCommand? {
        PreviewShortcutAction.action(for: keyCode)?.command(isShuttling: isShuttling)
    }

    @discardableResult
    static func post(_ command: PreviewKeyboardCommand) -> Bool {
        PreviewKeyboardCommandDispatcher.dispatch(command)
    }

    static func isEditableTextResponder(_ responder: Any?) -> Bool {
        if let textView = responder as? NSTextView {
            return textView.isEditable && (textView.isFieldEditor || textView.enclosingScrollView != nil)
        }

        if let textField = responder as? NSTextField {
            return textField.isEditable || textField.currentEditor() != nil
        }

        return false
    }

    static func hasEditableTextAncestor(_ view: NSView?) -> Bool {
        var current = view
        while let view = current {
            if isEditableTextResponder(view) {
                return true
            }
            current = view.superview
        }
        return false
    }
}

final class PreviewKeyboardWindow: NSWindow {
    override func keyDown(with event: NSEvent) {
        guard let forwardedEvent = processPreviewKeyboardEvent(event) else { return }
        super.keyDown(with: forwardedEvent)
    }

    override func keyUp(with event: NSEvent) {
        guard let forwardedEvent = processPreviewKeyboardEvent(event) else { return }
        super.keyUp(with: forwardedEvent)
    }

    private func processPreviewKeyboardEvent(_ event: NSEvent) -> NSEvent? {
        guard !PreviewKeyboardEventRouter.isEditableTextResponder(firstResponder) else {
            return event
        }

        let isPlainShortcut = PreviewKeyboardEventRouter.isPlainShortcutEvent(event)

        if event.type == .keyUp {
            return isPlainShortcut && PreviewKeyboardEventRouter.isHandledKeyCode(event.keyCode) ? nil : event
        }

        guard event.type == .keyDown else { return event }
        guard isPlainShortcut, PreviewKeyboardEventRouter.isHandledKeyCode(event.keyCode) else { return event }
        return nil
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.configureIfNeeded(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.configureIfNeeded(nsView.window)
        }
    }

    final class Coordinator {
        private weak var configuredWindow: NSWindow?

        func configureIfNeeded(_ window: NSWindow?) {
            guard let window else { return }
            if configuredWindow !== window {
                configuredWindow = window
                window.styleMask.insert([.titled, .resizable, .closable, .miniaturizable, .fullSizeContentView])
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.backgroundColor = .clear
                window.isOpaque = false
                window.hasShadow = true
                window.isMovableByWindowBackground = false
                window.collectionBehavior.insert(.fullScreenPrimary)
            }
            DispatchQueue.main.async {
                self.restoreWindowToVisibleScreenIfNeeded(window)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.restoreWindowToVisibleScreenIfNeeded(window)
            }
        }

        private func restoreWindowToVisibleScreenIfNeeded(_ window: NSWindow) {
            let frame = window.frame
            let windowCenter = CGPoint(x: frame.midX, y: frame.midY)
            let isCenteredOnVisibleScreen = NSScreen.screens.contains { screen in
                screen.visibleFrame.contains(windowCenter)
            }
            guard !isCenteredOnVisibleScreen, let screen = NSScreen.main ?? NSScreen.screens.first else { return }

            let visibleFrame = screen.visibleFrame
            let windowSize = CGSize(
                width: min(frame.width, visibleFrame.width),
                height: min(frame.height, visibleFrame.height)
            )
            let clampedOrigin = CGPoint(
                x: min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - windowSize.width),
                y: min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - windowSize.height)
            )
            window.setFrame(
                CGRect(origin: clampedOrigin, size: windowSize),
                display: true
            )
            window.makeKeyAndOrderFront(nil)
        }
    }
}

struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

struct PreviewKeyboardHandler: NSViewRepresentable {
    let handle: (PreviewKeyboardCommand) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(handle: handle)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installMonitor()
        let view = KeyboardCaptureNSView(frame: .zero)
        view.coordinator = context.coordinator
        context.coordinator.captureView = view
        view.requestKeyboardFocus()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handle = handle
        if let view = nsView as? KeyboardCaptureNSView {
            view.coordinator = context.coordinator
            context.coordinator.captureView = view
            view.requestKeyboardFocus()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var handle: (PreviewKeyboardCommand) -> Bool
        fileprivate weak var captureView: KeyboardCaptureNSView?
        private var mouseMonitor: Any?

        init(handle: @escaping (PreviewKeyboardCommand) -> Bool) {
            self.handle = handle
        }

        func installMonitor() {
            if mouseMonitor == nil {
                mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                    self?.restoreKeyboardFocusIfNeeded(for: event)
                    return event
                }
            }
        }

        func removeMonitor() {
            if let mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
            }
            mouseMonitor = nil
        }

        fileprivate func process(_ event: NSEvent) -> NSEvent? {
            if isEditingText {
                return event
            }

            let isPlainShortcut = isPlainShortcutEvent(event)

            if event.type == .keyUp {
                return isPlainShortcut && isHandledKeyCode(event.keyCode) ? nil : event
            }

            guard event.type == .keyDown else { return event }
            guard isPlainShortcut, isHandledKeyCode(event.keyCode) else { return event }
            return nil
        }

        private var isEditingText: Bool {
            Self.isEditableTextResponder(NSApp.keyWindow?.firstResponder)
        }

        private func restoreKeyboardFocusIfNeeded(for event: NSEvent) {
            guard let captureView, let window = captureView.window, event.window === window else { return }
            let location = event.locationInWindow
            guard let hitView = window.contentView?.hitTest(location) else { return }
            guard !Self.hasEditableTextAncestor(hitView) else { return }
            window.makeFirstResponder(captureView)
        }

        private func isPlainShortcutEvent(_ event: NSEvent) -> Bool {
            PreviewKeyboardEventRouter.isPlainShortcutEvent(event)
        }

        private func isHandledKeyCode(_ keyCode: UInt16) -> Bool {
            PreviewKeyboardEventRouter.isHandledKeyCode(keyCode)
        }

        static func isEditableTextResponder(_ responder: Any?) -> Bool {
            PreviewKeyboardEventRouter.isEditableTextResponder(responder)
        }

        static func hasEditableTextAncestor(_ view: NSView?) -> Bool {
            PreviewKeyboardEventRouter.hasEditableTextAncestor(view)
        }

    }
}

private final class KeyboardCaptureNSView: NSView {
    weak var coordinator: PreviewKeyboardHandler.Coordinator?
    private weak var observedWindow: NSWindow?
    private var windowDidBecomeKeyObserver: NSObjectProtocol?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindowObserver()
        requestKeyboardFocus()
    }

    func requestKeyboardFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            guard !PreviewKeyboardHandler.Coordinator.isEditableTextResponder(window.firstResponder) else { return }
            window.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        if let forwardedEvent = coordinator?.process(event) {
            super.keyDown(with: forwardedEvent)
        }
    }

    override func keyUp(with event: NSEvent) {
        if let forwardedEvent = coordinator?.process(event) {
            super.keyUp(with: forwardedEvent)
        }
    }

    deinit {
        removeWindowObserver()
    }

    private func updateWindowObserver() {
        guard observedWindow !== window else { return }
        removeWindowObserver()
        observedWindow = window
        guard let window else { return }
        windowDidBecomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.requestKeyboardFocus()
        }
    }

    private func removeWindowObserver() {
        if let windowDidBecomeKeyObserver {
            NotificationCenter.default.removeObserver(windowDidBecomeKeyObserver)
        }
        windowDidBecomeKeyObserver = nil
        observedWindow = nil
    }

}

struct NativeWindowTrafficLights: NSViewRepresentable {
    let buttonSize: CGFloat
    let buttonGap: CGFloat

    func makeNSView(context: Context) -> TrafficLightContainerView {
        TrafficLightContainerView(buttonSize: buttonSize, buttonGap: buttonGap)
    }

    func updateNSView(_ nsView: TrafficLightContainerView, context: Context) {
        nsView.configure(buttonSize: buttonSize, buttonGap: buttonGap)
    }
}

final class TrafficLightContainerView: NSView {
    private var buttonSize: CGFloat
    private var buttonGap: CGFloat
    private let closeButton = TrafficLightButton(kind: .close)
    private let miniaturizeButton = TrafficLightButton(kind: .miniaturize)
    private let zoomButton = TrafficLightButton(kind: .zoom)
    private var windowObservers: [NSObjectProtocol] = []

    init(buttonSize: CGFloat, buttonGap: CGFloat) {
        self.buttonSize = buttonSize
        self.buttonGap = buttonGap
        super.init(frame: NSRect(x: 0, y: 0, width: buttonSize * 3 + buttonGap * 2, height: buttonSize))
        installButtons()
    }

    required init?(coder: NSCoder) {
        self.buttonSize = 12
        self.buttonGap = 8
        super.init(coder: coder)
        installButtons()
    }

    private func installButtons() {
        [closeButton, miniaturizeButton, zoomButton].forEach { button in
            button.target = self
            button.action = #selector(performWindowButtonAction(_:))
            if button.superview !== self {
                addSubview(button)
            }
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: buttonSize * 3 + buttonGap * 2, height: buttonSize)
    }

    func configure(buttonSize: CGFloat, buttonGap: CGFloat) {
        guard self.buttonSize != buttonSize || self.buttonGap != buttonGap else { return }
        self.buttonSize = buttonSize
        self.buttonGap = buttonGap
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindowObservers()
        applyFixedButtonFrames()
        DispatchQueue.main.async { [weak self] in
            self?.hideSystemWindowButtons()
            self?.applyFixedButtonFrames()
        }
    }

    override func layout() {
        super.layout()
        hideSystemWindowButtons()
        applyFixedButtonFrames()
    }

    deinit {
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func applyFixedButtonFrames() {
        closeButton.frame = CGRect(x: 0, y: 0, width: buttonSize, height: buttonSize)
        miniaturizeButton.frame = CGRect(x: buttonSize + buttonGap, y: 0, width: buttonSize, height: buttonSize)
        zoomButton.frame = CGRect(x: (buttonSize + buttonGap) * 2, y: 0, width: buttonSize, height: buttonSize)
    }

    private func hideSystemWindowButtons() {
        guard let window else { return }
        [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ].forEach { button in
            button?.isHidden = true
        }
    }

    private func updateWindowObservers() {
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers.removeAll()

        guard let window else { return }
        hideSystemWindowButtons()
        updateButtonActivity()

        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification
        ]
        windowObservers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.hideSystemWindowButtons()
                self?.updateButtonActivity()
            }
        }
    }

    private func updateButtonActivity() {
        let isActive = window?.isKeyWindow ?? false
        [closeButton, miniaturizeButton, zoomButton].forEach { $0.isWindowActive = isActive }
    }

    @objc private func performWindowButtonAction(_ sender: TrafficLightButton) {
        guard let window else { return }
        switch sender.kind {
        case .close:
            window.performClose(sender)
        case .miniaturize:
            window.performMiniaturize(sender)
        case .zoom:
            window.toggleFullScreen(sender)
        }
    }
}

private final class TrafficLightButton: NSButton {
    enum Kind {
        case close
        case miniaturize
        case zoom
    }

    let kind: Kind
    var isWindowActive = false { didSet { needsDisplay = true } }

    private var isHovering = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        self.kind = .close
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isBordered = false
        focusRingType = .none
        setButtonType(.momentaryChange)
        imagePosition = .imageOnly
        bezelStyle = .regularSquare
        setAccessibilityLabel(kind.accessibilityLabel)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let circleRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let circlePath = NSBezierPath(ovalIn: circleRect)
        fillColor.setFill()
        circlePath.fill()

        strokeColor.setStroke()
        circlePath.lineWidth = 0.5
        circlePath.stroke()

        guard isHovering, isWindowActive else { return }
        symbolColor.setStroke()
        let symbol = symbolPath(in: bounds.insetBy(dx: 3.25, dy: 3.25))
        symbol.lineWidth = 1.1
        symbol.lineCapStyle = .round
        symbol.lineJoinStyle = .round
        symbol.stroke()
    }

    private var fillColor: NSColor {
        guard isWindowActive else { return NSColor(calibratedWhite: 0.42, alpha: 1) }
        switch kind {
        case .close:
            return NSColor(calibratedRed: 1.00, green: 0.37, blue: 0.33, alpha: 1)
        case .miniaturize:
            return NSColor(calibratedRed: 1.00, green: 0.73, blue: 0.24, alpha: 1)
        case .zoom:
            return NSColor(calibratedRed: 0.24, green: 0.80, blue: 0.33, alpha: 1)
        }
    }

    private var strokeColor: NSColor {
        guard isWindowActive else { return NSColor(calibratedWhite: 0.36, alpha: 1) }
        switch kind {
        case .close:
            return NSColor(calibratedRed: 0.82, green: 0.22, blue: 0.20, alpha: 1)
        case .miniaturize:
            return NSColor(calibratedRed: 0.54, green: 0.44, blue: 0.08, alpha: 1)
        case .zoom:
            return NSColor(calibratedRed: 0.16, green: 0.60, blue: 0.22, alpha: 1)
        }
    }

    private var symbolColor: NSColor {
        guard isWindowActive else { return NSColor(calibratedWhite: 0.20, alpha: 0.70) }
        switch kind {
        case .close:
            return NSColor(calibratedRed: 0.46, green: 0.06, blue: 0.05, alpha: 0.70)
        case .miniaturize:
            return NSColor(calibratedRed: 0.48, green: 0.29, blue: 0.02, alpha: 0.70)
        case .zoom:
            return NSColor(calibratedRed: 0.04, green: 0.34, blue: 0.09, alpha: 0.70)
        }
    }

    private func symbolPath(in rect: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        switch kind {
        case .close:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.line(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .miniaturize:
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.line(to: CGPoint(x: rect.maxX, y: rect.midY))
        case .zoom:
            path.move(to: CGPoint(x: rect.minX + 0.4, y: rect.midY))
            path.line(to: CGPoint(x: rect.midX, y: rect.midY))
            path.line(to: CGPoint(x: rect.midX, y: rect.maxY - 0.4))
            path.move(to: CGPoint(x: rect.maxX - 0.4, y: rect.midY))
            path.line(to: CGPoint(x: rect.midX, y: rect.midY))
            path.line(to: CGPoint(x: rect.midX, y: rect.minY + 0.4))
        }
        return path
    }
}

private extension TrafficLightButton.Kind {
    var accessibilityLabel: String {
        switch self {
        case .close:
            return "关闭"
        case .miniaturize:
            return "最小化"
        case .zoom:
            return "全屏"
        }
    }
}
