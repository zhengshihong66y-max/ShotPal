//
//  StartupDiagnostics.swift
//  LapianBao
//
//  Startup-stage markers used to separate pre-main launch problems from
//  AppDelegate, window, and library-restore failures.
//

import Foundation
import OSLog

enum StartupDiagnostics {
    enum Stage: String {
        case mainEntered = "main entered"
        case didFinishLaunching = "applicationDidFinishLaunching"
        case setupScheduled = "startup setup scheduled"
        case setupStarted = "startup setup started"
        case mainMenuInstalled = "main menu installed"
        case mainWindowRequested = "main window requested"
        case mainWindowCreated = "main window created"
        case mainWindowOrderedFront = "main window ordered front"
        case visibilityChecksScheduled = "visibility checks scheduled"
        case keyboardMonitorInstalled = "keyboard monitor installed"
        case appActivated = "app activated"
        case savedCollectionPrewarmScheduled = "saved collection prewarm scheduled"
        case libraryRestoreScheduled = "library restore scheduled"
        case libraryRestoreStarted = "library restore started"
    }

    private static let logger = Logger(
        subsystem: "com.lapianbao.app",
        category: "Startup"
    )

    static func mark(_ stage: Stage) {
        logger.notice("\(stage.rawValue, privacy: .public)")
    }
}

nonisolated enum PerformanceDiagnostics {
    private static let logger = Logger(
        subsystem: "com.lapianbao.app",
        category: "Performance"
    )

    static func mark(_ event: String, path: String? = nil) {
        if let path {
            logger.debug("\(event, privacy: .public) \(path, privacy: .public)")
        } else {
            logger.debug("\(event, privacy: .public)")
        }
    }
}
