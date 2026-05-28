//
//  LapianBaoApp.swift
//  LapianBao
//
//  Created by 郑士泓 on 2026/5/24.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var previewKeyMonitor: Any?
    private var pressedPreviewKeyCodes = Set<UInt16>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        installPreviewKeyboardMonitor()
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

    func application(_ application: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        false
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
            if isPlainShortcut && (event.keyCode == 37 || event.keyCode == 38) {
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
        let isShuttling = pressedPreviewKeyCodes.contains(37) || pressedPreviewKeyCodes.contains(38)
        guard let command = PreviewKeyboardEventRouter.command(for: event.keyCode, isShuttling: isShuttling) else {
            return event
        }

        PreviewKeyboardEventRouter.post(command)
        return nil
    }
}

@main
struct LapianBaoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var libraryStore = LibraryStore()

    var body: some Scene {
        Window("LapianBao", id: "main") {
            ContentView()
                .environmentObject(libraryStore)
                .onAppear {
                    libraryStore.loadLastLibrary()
                }
        }
        .defaultSize(width: 1280, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开文件夹") {
                    libraryStore.chooseFolder()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}
