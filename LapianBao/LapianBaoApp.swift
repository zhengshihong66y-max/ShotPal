//
//  LapianBaoApp.swift
//  LapianBao
//
//  Created by 郑士泓 on 2026/5/24.
//

import AppKit
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static var retainedDelegate: AppDelegate?

    private let libraryStore = LibraryStore()
    private var mainWindow: NSWindow?
    private var didCompleteLaunchSetup = false
    private var previewKeyMonitor: Any?
    private var pressedPreviewKeyCodes = Set<UInt16>()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.completeLaunchSetupIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let previewKeyMonitor {
            NSEvent.removeMonitor(previewKeyMonitor)
        }
        previewKeyMonitor = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ensureMainWindowVisible()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        ensureMainWindowVisible()
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === mainWindow {
            mainWindow = nil
        }
    }

    func application(_ application: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        false
    }

    @objc private func chooseFolderFromMenu() {
        libraryStore.chooseFolder()
    }

    private func completeLaunchSetupIfNeeded() {
        guard !didCompleteLaunchSetup else { return }
        didCompleteLaunchSetup = true

        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        ensureMainWindowVisible()
        scheduleStartupVisibilityChecks()
        installPreviewKeyboardMonitor()
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            self?.libraryStore.loadLastLibraryForLaunch()
        }
    }

    private func ensureMainWindowVisible() {
        let window = mainWindow ?? createMainWindow()
        restoreWindowToVisibleScreenIfNeeded(window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func scheduleStartupVisibilityChecks() {
        [0.25, 1.0, 2.0].forEach { delay in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !NSApp.isHidden else { return }
                self.ensureMainWindowVisible()
            }
        }
    }

    private func createMainWindow() -> NSWindow {
        let contentView = ContentView()
            .environmentObject(libraryStore)
        let hostingController = NSHostingController(rootView: contentView)
        let window = PreviewKeyboardWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .resizable, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "LapianBao"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.contentMinSize = NSSize(
            width: Design.minimumWindowWidth,
            height: Design.minimumWindowHeight
        )
        window.minSize = window.frameRect(forContentRect: NSRect(
            origin: .zero,
            size: window.contentMinSize
        )).size
        window.center()
        mainWindow = window
        return window
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
        window.setFrame(CGRect(origin: clampedOrigin, size: windowSize), display: true)
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "退出 LapianBao",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(
            withTitle: "打开文件夹",
            action: #selector(chooseFolderFromMenu),
            keyEquivalent: "o"
        )
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(
            withTitle: "撤销",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        editMenu.addItem(
            withTitle: "重做",
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        )
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(
            withTitle: "剪切",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: "拷贝",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: "粘贴",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "全选",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    func application(_ application: NSApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        false
    }

    private func installPreviewKeyboardMonitor() {
        guard previewKeyMonitor == nil else { return }
        previewKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.processPreviewKeyboardEvent(event) ?? event
        }
    }

    private func processPreviewKeyboardEvent(_ event: NSEvent) -> NSEvent? {
        guard !PreviewKeyboardEventRouter.isEditableTextResponder(NSApp.keyWindow?.firstResponder) else {
            return event
        }

        let isPlainShortcut = PreviewKeyboardEventRouter.isPlainShortcutEvent(event)

        if event.type == .keyUp {
            pressedPreviewKeyCodes.remove(event.keyCode)
            if isPlainShortcut && PreviewKeyboardEventRouter.isShuttleKeyCode(event.keyCode) {
                PreviewKeyboardEventRouter.post(.stopShuttle)
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
        let isShuttling = PreviewKeyboardEventRouter.isShuttling(pressedPreviewKeyCodes)
        guard let command = PreviewKeyboardEventRouter.command(for: event.keyCode, isShuttling: isShuttling) else {
            return nil
        }

        PreviewKeyboardEventRouter.post(command)
        return nil
    }
}
