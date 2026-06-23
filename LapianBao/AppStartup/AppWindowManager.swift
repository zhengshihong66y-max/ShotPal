//
//  AppWindowManager.swift
//  LapianBao
//
//  Owns the retained AppKit main window. Keep window creation here so startup
//  regressions are isolated from app delegate and media-library work.
//

import AppKit
import SwiftUI

final class AppWindowManager {
    private let libraryStore: LibraryStore
    private weak var windowDelegate: NSWindowDelegate?
    private var mainWindow: NSWindow?

    init(libraryStore: LibraryStore, windowDelegate: NSWindowDelegate?) {
        self.libraryStore = libraryStore
        self.windowDelegate = windowDelegate
    }

    func clearMainWindowIfNeeded(_ window: NSWindow) {
        if window === mainWindow {
            mainWindow = nil
        }
    }

    func isMainWindow(_ window: NSWindow) -> Bool {
        window === mainWindow
    }

    func ensureMainWindowVisible() {
        let window = mainWindow ?? createMainWindow()
        restoreWindowToVisibleScreenIfNeeded(window)
        NSApp.unhide(nil)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        StartupDiagnostics.mark(.mainWindowOrderedFront)
        activateApplication()
    }

    func activateApplication() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        StartupDiagnostics.mark(.appActivated)
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
        window.title = "拉片宝"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.collectionBehavior.formUnion([.fullScreenPrimary, .moveToActiveSpace])
        window.delegate = windowDelegate
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
        StartupDiagnostics.mark(.mainWindowCreated)
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
}
