//
//  AppStartupCoordinator.swift
//  LapianBao
//
//  Coordinates the launch sequence after AppKit calls applicationDidFinishLaunching.
//  Heavy library restoration stays deferred until the retained window is visible.
//

import AppKit
import Foundation

final class AppStartupCoordinator {
    private let libraryStore: LibraryStore
    private let windowManager: AppWindowManager
    private weak var menuTarget: AnyObject?
    private let chooseFolderAction: Selector
    private let installPreviewKeyboardMonitor: () -> Void
    private var didCompleteLaunchSetup = false
    private let libraryRestoreDelay: TimeInterval = 0.75

    init(
        libraryStore: LibraryStore,
        windowManager: AppWindowManager,
        menuTarget: AnyObject,
        chooseFolderAction: Selector,
        installPreviewKeyboardMonitor: @escaping () -> Void
    ) {
        self.libraryStore = libraryStore
        self.windowManager = windowManager
        self.menuTarget = menuTarget
        self.chooseFolderAction = chooseFolderAction
        self.installPreviewKeyboardMonitor = installPreviewKeyboardMonitor
    }

    func completeLaunchSetupIfNeeded() {
        guard !didCompleteLaunchSetup else { return }
        didCompleteLaunchSetup = true

        StartupDiagnostics.mark(.setupStarted)
        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        StartupDiagnostics.mark(.mainWindowRequested)
        windowManager.ensureMainWindowVisible()
        scheduleStartupVisibilityChecks()
        installPreviewKeyboardMonitor()
        StartupDiagnostics.mark(.keyboardMonitorInstalled)
        windowManager.activateApplication()

        DispatchQueue.main.asyncAfter(deadline: .now() + libraryRestoreDelay) { [weak self] in
            StartupDiagnostics.mark(.libraryRestoreStarted)
            let didStartLibraryRestore = self?.libraryStore.loadLastLibraryForLaunch() ?? false
            if !didStartLibraryRestore {
                self?.libraryStore.promptForInitialLibraryIfNeeded()
            }
        }
        StartupDiagnostics.mark(.libraryRestoreScheduled)
    }

    private func scheduleStartupVisibilityChecks() {
        [0.25, 1.0, 2.0].forEach { delay in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !NSApp.isHidden else { return }
                self.windowManager.ensureMainWindowVisible()
            }
        }
        StartupDiagnostics.mark(.visibilityChecksScheduled)
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
        let openFolderItem = NSMenuItem(
            title: "打开文件夹",
            action: chooseFolderAction,
            keyEquivalent: "o"
        )
        openFolderItem.target = menuTarget
        fileMenu.addItem(openFolderItem)
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
        StartupDiagnostics.mark(.mainMenuInstalled)
    }
}
