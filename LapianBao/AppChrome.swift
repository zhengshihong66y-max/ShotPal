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
    case setAudioIn
    case setAudioOut
    case clearAudioSelection
    case exportAudioSelection
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

    @discardableResult
    static func dispatch(_ command: PreviewKeyboardCommand) -> Bool {
        handler?(command) ?? false
    }
}

enum PreviewKeyboardEventRouter {
    private enum KeyCode {
        static let space: UInt16 = 49
        static let i: UInt16 = 34
        static let o: UInt16 = 31
        static let u: UInt16 = 32
        static let p: UInt16 = 35
        static let j: UInt16 = 38
        static let k: UInt16 = 40
        static let l: UInt16 = 37
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124

        static let handled: Set<UInt16> = [
            space, i, o, u, p, j, k, l, leftArrow, rightArrow
        ]
    }

    static func isHandledKeyCode(_ keyCode: UInt16) -> Bool {
        KeyCode.handled.contains(keyCode)
    }

    static func isShuttleKeyCode(_ keyCode: UInt16) -> Bool {
        keyCode == KeyCode.j || keyCode == KeyCode.l
    }

    static func isShuttling(_ pressedKeyCodes: Set<UInt16>) -> Bool {
        pressedKeyCodes.contains(KeyCode.j) || pressedKeyCodes.contains(KeyCode.l)
    }

    static func isPlainShortcutEvent(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .control, .option]).isEmpty
    }

    static func command(for keyCode: UInt16, isShuttling: Bool) -> PreviewKeyboardCommand? {
        switch keyCode {
        case KeyCode.space:
            return .togglePlayback
        case KeyCode.k:
            return isShuttling ? .increaseShuttleSpeed : .togglePlayback
        case KeyCode.i:
            return .setAudioIn
        case KeyCode.o:
            return .setAudioOut
        case KeyCode.u:
            return .clearAudioSelection
        case KeyCode.p:
            return .exportAudioSelection
        case KeyCode.l:
            return .shuttleForward
        case KeyCode.j:
            return .shuttleBackward
        case KeyCode.rightArrow:
            return .stepForward
        case KeyCode.leftArrow:
            return .stepBackward
        default:
            return nil
        }
    }

    static func post(_ command: PreviewKeyboardCommand) {
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
    private var pressedPreviewKeyCodes = Set<UInt16>()

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
            pressedPreviewKeyCodes.remove(event.keyCode)
            if isPlainShortcut && PreviewKeyboardEventRouter.isShuttleKeyCode(event.keyCode) {
                return nil
            }
            return isPlainShortcut && PreviewKeyboardEventRouter.isHandledKeyCode(event.keyCode) ? nil : event
        }

        guard event.type == .keyDown else { return event }
        guard isPlainShortcut, PreviewKeyboardEventRouter.isHandledKeyCode(event.keyCode) else { return event }

        if event.isARepeat {
            return nil
        }

        pressedPreviewKeyCodes.insert(event.keyCode)
        guard let command = PreviewKeyboardEventRouter.command(
            for: event.keyCode,
            isShuttling: PreviewKeyboardEventRouter.isShuttling(pressedPreviewKeyCodes)
        ) else {
            return nil
        }

        _ = command
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
                window.styleMask.remove(.fullSizeContentView)
                window.styleMask.insert([.titled, .resizable, .closable, .miniaturizable])
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
        private var pressedKeyCodes = Set<UInt16>()

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
                pressedKeyCodes.remove(event.keyCode)
                if isPlainShortcut && PreviewKeyboardEventRouter.isShuttleKeyCode(event.keyCode) {
                    return nil
                }
                return isPlainShortcut && isHandledKeyCode(event.keyCode) ? nil : event
            }

            guard event.type == .keyDown else { return event }
            guard isPlainShortcut, isHandledKeyCode(event.keyCode) else { return event }

            if event.isARepeat {
                return nil
            }

            pressedKeyCodes.insert(event.keyCode)
            if let command = command(for: event) {
                _ = command
                return nil
            }
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

        private var isShuttling: Bool {
            PreviewKeyboardEventRouter.isShuttling(pressedKeyCodes)
        }

        static func isEditableTextResponder(_ responder: Any?) -> Bool {
            PreviewKeyboardEventRouter.isEditableTextResponder(responder)
        }

        static func hasEditableTextAncestor(_ view: NSView?) -> Bool {
            PreviewKeyboardEventRouter.hasEditableTextAncestor(view)
        }

        private func command(for event: NSEvent) -> PreviewKeyboardCommand? {
            PreviewKeyboardEventRouter.command(for: event.keyCode, isShuttling: isShuttling)
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
    func makeNSView(context: Context) -> TrafficLightContainerView {
        TrafficLightContainerView()
    }
    func updateNSView(_ nsView: TrafficLightContainerView, context: Context) {}
}

final class TrafficLightContainerView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { needsLayout = true }
    }

    override func layout() {
        super.layout()
        guard let window,
              let close = window.standardWindowButton(.closeButton),
              let mini  = window.standardWindowButton(.miniaturizeButton),
              let zoom  = window.standardWindowButton(.zoomButton) else { return }

        if close.superview !== self {
            [close, mini, zoom].forEach { btn in
                btn.removeFromSuperview()
                addSubview(btn)
            }
        }

        let size: CGFloat = 12
        let gap:  CGFloat = 6
        let midY = (bounds.height - size) / 2
        close.frame = CGRect(x: 0,              y: midY, width: size, height: size)
        mini.frame  = CGRect(x: size + gap,     y: midY, width: size, height: size)
        zoom.frame  = CGRect(x: (size + gap) * 2, y: midY, width: size, height: size)
    }
}
