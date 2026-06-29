//
//  LapianBaoApp.swift
//  LapianBao
//
//  Created by 郑士泓 on 2026/5/24.
//

import AppKit
import Darwin
import SwiftUI

nonisolated final class CommandLineSelfCheckExitBox: @unchecked Sendable {
    var code: Int32 = 1
}

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static var retainedDelegate: AppDelegate?

    private let libraryStore = LibraryStore()
    private var didHandleInitialActivation = false
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
        CommandLineImportPanelCheck.runIfRequested()
        CommandLineAnnotationSaveCheck.runIfRequested()
        CommandLineDownloadProgressCheck.runIfRequested()
        CommandLineSceneTimelineCheck.runIfRequested()
        CommandLineDragProviderCheck.runIfRequested()
        CommandLineMusicRuntimeCheck.runIfRequested()
        runCommandLineMusicWaveformCachePrewarmIfRequested()
        runCommandLineSelfCheckIfRequested()
        StartupDiagnostics.mark(.mainEntered)
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }

    nonisolated private static func runCommandLineSelfCheckIfRequested() {
        let arguments = CommandLine.arguments
        let repairMode: LibraryStore.DownloaderSelfCheckRepairMode
        if arguments.contains("--lapianbao-self-repair") {
            repairMode = .always
        } else if arguments.contains("--lapianbao-self-check") {
            repairMode = .afterFailure
        } else {
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        let exitBox = CommandLineSelfCheckExitBox()
        Task.detached(priority: .utility) {
            let report = await LibraryStore.runDownloaderSelfCheck(startedAt: Date(), repairMode: repairMode)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(report) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            exitBox.code = report.status == .succeeded ? 0 : 1
            semaphore.signal()
        }
        semaphore.wait()
        Darwin.exit(exitBox.code)
    }

    nonisolated private static func runCommandLineMusicWaveformCachePrewarmIfRequested() {
        let arguments = CommandLine.arguments
        guard MusicWaveformRenderCachePrewarmer.shouldRun(arguments: arguments) else { return }

        let semaphore = DispatchSemaphore(value: 0)
        let exitBox = CommandLineSelfCheckExitBox()
        Task.detached(priority: .utility) {
            exitBox.code = await MusicWaveformRenderCachePrewarmer.runAndPrintReport(arguments: arguments)
            semaphore.signal()
        }
        semaphore.wait()
        Darwin.exit(exitBox.code)
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
        guard didHandleInitialActivation else {
            didHandleInitialActivation = true
            return
        }
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
        let hasActiveHandler = PreviewKeyboardEventRouter.hasActiveHandler
        let musicPreviewKeyboardTargetJobID = isPlainShortcut && event.keyCode == 49
            ? libraryStore.musicPreviewKeyboardTargetJobID
            : nil
        let isMusicPreviewSpace = musicPreviewKeyboardTargetJobID != nil

        if event.type == .keyUp {
            if isMusicPreviewSpace,
               !PreviewKeyboardEventRouter.isEditableTextResponder(NSApp.keyWindow?.firstResponder) {
                return nil
            }

            let wasTrackingKey = pressedPreviewKeyCodes.contains(event.keyCode)
            pressedPreviewKeyCodes.remove(event.keyCode)

            guard hasActiveHandler || wasTrackingKey else { return event }

            if PreviewKeyboardEventRouter.isShuttleKeyCode(event.keyCode) {
                PreviewKeyboardEventRouter.post(.stopShuttle)
                if isPlainShortcut || wasTrackingKey {
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

        if isMusicPreviewSpace {
            if !event.isARepeat, let id = musicPreviewKeyboardTargetJobID {
                AppEventBus.postMusicPreviewToggleRequest(id: id)
            }
            return nil
        }

        guard hasActiveHandler else { return event }
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
