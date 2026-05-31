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
    private var previewKeyMonitor: Any?
    private var pressedPreviewKeyCodes = Set<UInt16>()
    private lazy var windowManager = AppWindowManager(
        libraryStore: libraryStore,
        windowDelegate: self
    )
    private lazy var startupCoordinator = AppStartupCoordinator(
        libraryStore: libraryStore,
        windowManager: windowManager,
        menuTarget: self,
        chooseFolderAction: #selector(chooseFolderFromMenu),
        installPreviewKeyboardMonitor: { [weak self] in
            self?.installPreviewKeyboardMonitor()
        }
    )

    static func main() {
        StartupDiagnostics.mark(.mainEntered)
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        StartupDiagnostics.mark(.didFinishLaunching)
        DispatchQueue.main.async { [weak self] in
            StartupDiagnostics.mark(.setupScheduled)
            self?.startupCoordinator.completeLaunchSetupIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        libraryStore.flushCurrentVideoLibrarySnapshot()
        libraryStore.flushProjectDataSave()
        if let previewKeyMonitor {
            NSEvent.removeMonitor(previewKeyMonitor)
        }
        previewKeyMonitor = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowManager.ensureMainWindowVisible()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        windowManager.ensureMainWindowVisible()
        libraryStore.startDailyExternalServiceSelfCheckIfNeeded()
    }

    func applicationDidResignActive(_ notification: Notification) {
        libraryStore.saveCurrentVideoLibrarySnapshot()
        stopPreviewShuttleTracking()
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            windowManager.clearMainWindowIfNeeded(window)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow,
           windowManager.isMainWindow(window) {
            stopPreviewShuttleTracking()
        }
    }

    func application(_ application: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        false
    }

    @objc private func chooseFolderFromMenu() {
        libraryStore.chooseFolder()
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
        let isPlainShortcut = PreviewKeyboardEventRouter.isPlainShortcutEvent(event)

        if event.type == .keyUp {
            pressedPreviewKeyCodes.remove(event.keyCode)
            if PreviewKeyboardEventRouter.isShuttleKeyCode(event.keyCode) {
                PreviewKeyboardEventRouter.post(.stopShuttle)
                if isPlainShortcut {
                    return nil
                }
            }
            guard !PreviewKeyboardEventRouter.isEditableTextResponder(NSApp.keyWindow?.firstResponder) else {
                return event
            }
            return isPlainShortcut && PreviewKeyboardEventRouter.isHandledKeyCode(event.keyCode) ? nil : event
        }

        guard event.type == .keyDown else { return event }
        guard !PreviewKeyboardEventRouter.isEditableTextResponder(NSApp.keyWindow?.firstResponder) else {
            return event
        }
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

    private func stopPreviewShuttleTracking() {
        pressedPreviewKeyCodes.removeAll()
        PreviewKeyboardEventRouter.post(.stopShuttle)
    }
}
