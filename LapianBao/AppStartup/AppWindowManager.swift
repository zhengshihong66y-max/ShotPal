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
    private var pendingInitialCenterPasses = 0

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
        if pendingInitialCenterPasses > 0 {
            pendingInitialCenterPasses -= 1
            centerWindowOnVisibleScreen(window, display: true)
        } else {
            restoreWindowToVisibleScreenIfNeeded(window)
        }
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
            .environmentObject(libraryStore.downloaderSelfCheck)
            .environmentObject(libraryStore.youtubeCookie)
        let hostingController = NSHostingController(rootView: contentView)
        let window = PreviewKeyboardWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .resizable, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("拉片宝")
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
        centerWindowOnVisibleScreen(window, display: false)
        pendingInitialCenterPasses = 4
        mainWindow = window
        StartupDiagnostics.mark(.mainWindowCreated)
        return window
    }

    private func centerWindowOnVisibleScreen(_ window: NSWindow, display: Bool) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let windowSize = CGSize(
            width: min(window.frame.width, visibleFrame.width),
            height: min(window.frame.height, visibleFrame.height)
        )
        let centeredFrame = CGRect(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2,
            width: windowSize.width,
            height: windowSize.height
        )
        window.setFrame(centeredFrame, display: display)
    }

    private func restoreWindowToVisibleScreenIfNeeded(_ window: NSWindow) {
        let frame = window.frame
        let containingScreen = NSScreen.screens.first { screen in
            screen.visibleFrame.contains(frame)
        }
        guard containingScreen == nil else { return }

        let windowCenter = CGPoint(x: frame.midX, y: frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(windowCenter) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        else { return }

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
