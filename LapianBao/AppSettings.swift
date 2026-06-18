//
//  AppSettings.swift
//  LapianBao
//
//  Centralizes UserDefaults keys and lightweight preference access.
//

import Foundation

nonisolated enum AppSettings {
    enum Key {
        static let appWorkspace = "appWorkspace"
        static let isSidebarCollapsed = "isSidebarCollapsed"
        static let mediaPanelWidth = "mediaPanelWidth"
        static let frameMediaPanelWidth = "frameMediaPanelWidth"
        static let sceneGridSize = "sceneGridSize"
        static let frameBoardGridSize = "frameBoardGridSize"
        static let storyboardVideoPickerGridSize = "storyboardVideoPickerGridSize"

        static let lastLibraryPath = "lastLibraryPath"
        static let lastLibraryBookmark = "lastLibraryBookmark"
        static let videoSortOption = "videoSortOption"
        static let videoSortDirection = "videoSortDirection"
        static let musicSortOption = "musicSortOption"
        static let musicSortDirection = "musicSortDirection"
        static let instagramImportEndpoint = "instagramImportEndpoint"
        static let downloaderSelfCheckReport = "downloaderSelfCheckReport"

        static let autoSceneBatch = "autoStartSceneBatch"
        static let autoTranscriptBatch = "autoStartTranscriptBatch"
        static let autoMusicDownloadBatch = "autoStartMusicDownloadBatch"

        static func previewShortcutKeyCode(_ actionRawValue: String) -> String {
            "previewShortcut.\(actionRawValue).keyCode"
        }
    }

    static let defaultLibraryPath = "/Users/zhengshihong/Downloads/通用资源/素材库"
    static let defaultMediaPanelWidth = 340.0

    private static let defaults = UserDefaults.standard

    static var mediaPanelWidth: Double {
        get { defaults.object(forKey: Key.mediaPanelWidth) as? Double ?? defaultMediaPanelWidth }
        set { defaults.set(newValue, forKey: Key.mediaPanelWidth) }
    }

    static var frameMediaPanelWidth: Double? {
        get { defaults.object(forKey: Key.frameMediaPanelWidth) as? Double }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.frameMediaPanelWidth)
            } else {
                defaults.removeObject(forKey: Key.frameMediaPanelWidth)
            }
        }
    }

    static var appWorkspaceRawValue: String? {
        defaults.string(forKey: Key.appWorkspace)
    }

    static var lastLibraryPath: String? {
        get { defaults.string(forKey: Key.lastLibraryPath) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.lastLibraryPath)
            } else {
                defaults.removeObject(forKey: Key.lastLibraryPath)
            }
        }
    }

    static var lastLibraryBookmark: Data? {
        get { defaults.data(forKey: Key.lastLibraryBookmark) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.lastLibraryBookmark)
            } else {
                defaults.removeObject(forKey: Key.lastLibraryBookmark)
            }
        }
    }

    static var videoSortOptionRawValue: String? {
        get { defaults.string(forKey: Key.videoSortOption) }
        set { setOptionalString(newValue, forKey: Key.videoSortOption) }
    }

    static var videoSortDirectionRawValue: String? {
        get { defaults.string(forKey: Key.videoSortDirection) }
        set { setOptionalString(newValue, forKey: Key.videoSortDirection) }
    }

    static var instagramImportEndpoint: String {
        get { defaults.string(forKey: Key.instagramImportEndpoint) ?? "" }
        set { defaults.set(newValue, forKey: Key.instagramImportEndpoint) }
    }

    static var downloaderSelfCheckReportData: Data? {
        get { defaults.data(forKey: Key.downloaderSelfCheckReport) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.downloaderSelfCheckReport)
            } else {
                defaults.removeObject(forKey: Key.downloaderSelfCheckReport)
            }
        }
    }

    static var autoSceneBatchEnabled: Bool {
        removeDeprecatedBatchAutomationSettings()
        return false
    }

    static var autoTranscriptBatchEnabled: Bool {
        removeDeprecatedBatchAutomationSettings()
        return false
    }

    static var autoMusicDownloadBatchEnabled: Bool {
        removeDeprecatedBatchAutomationSettings()
        return false
    }

    static func previewShortcutKeyCode(actionRawValue: String) -> UInt16? {
        let key = Key.previewShortcutKeyCode(actionRawValue)
        guard defaults.object(forKey: key) != nil else { return nil }
        let value = defaults.integer(forKey: key)
        guard value >= 0, value <= Int(UInt16.max) else { return nil }
        return UInt16(value)
    }

    static func setPreviewShortcutKeyCode(_ keyCode: UInt16, actionRawValue: String) {
        defaults.set(Int(keyCode), forKey: Key.previewShortcutKeyCode(actionRawValue))
    }

    static func resetPreviewShortcutKeyCode(actionRawValue: String) {
        defaults.removeObject(forKey: Key.previewShortcutKeyCode(actionRawValue))
    }

    static func removeDeprecatedBatchAutomationSettings() {
        [
            Key.autoSceneBatch,
            Key.autoTranscriptBatch,
            Key.autoMusicDownloadBatch
        ].forEach { defaults.removeObject(forKey: $0) }
    }

    static func removeExternalAPISettings() {
        [
            "contentAnalysisProvider",
            "openAIAPIKey",
            "openAIBaseURL",
            "openAIModel",
            "anthropicAPIKey",
            "anthropicBaseURL",
            "anthropicModel",
            "geminiAPIKey",
            "geminiModel",
            "deepSeekAPIKey",
            "deepSeekBaseURL",
            "deepSeekModel",
            "customAPIProviderName",
            "customAPIKey",
            "customAPIBaseURL",
            "customAPIModel"
        ].forEach { defaults.removeObject(forKey: $0) }
    }

    private static func setOptionalString(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
