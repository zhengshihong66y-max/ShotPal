//
//  AppEventBus.swift
//  LapianBao
//
//  Centralizes lightweight app-wide notifications.
//

import Combine
import Foundation

nonisolated enum AppEventBus {
    struct SeekRequest: Equatable {
        let path: String
        let time: Double
    }

    struct MusicPreviewStartedEvent {
        let id: UUID?
        let source: String?
        let type: String?
    }

    struct ExportPanelRequest: Equatable {
        let path: String
        let filter: String
    }

    private enum UserInfoKey {
        static let path = "path"
        static let time = "time"
        static let id = "id"
        static let source = "source"
        static let type = "type"
        static let cacheKey = "cacheKey"
        static let filter = "filter"
    }

    private static let seekRequestName = Notification.Name("lapianBaoSeekRequest")
    private static let pausePreviewRequestName = Notification.Name("lapianBaoPausePreviewRequest")
    private static let musicPreviewStartedName = Notification.Name("lapianBaoMusicPreviewStarted")
    private static let musicPreviewToggleRequestName = Notification.Name("lapianBaoMusicPreviewToggleRequest")
    private static let downloadedMusicWaveformRenderCacheUpdatedName = Notification.Name("lapianBaoDownloadedMusicWaveformRenderCacheUpdated")
    private static let openExportPanelRequestName = Notification.Name("lapianBaoOpenExportPanelRequest")

    static var seekRequestPublisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: seekRequestName)
    }

    static var pausePreviewRequestPublisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: pausePreviewRequestName)
    }

    static var musicPreviewStartedPublisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: musicPreviewStartedName)
    }

    static var musicPreviewToggleRequestPublisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: musicPreviewToggleRequestName)
    }

    static var downloadedMusicWaveformRenderCacheUpdatedPublisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: downloadedMusicWaveformRenderCacheUpdatedName)
    }

    static var openExportPanelRequestPublisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: openExportPanelRequestName)
    }

    static func postSeekRequest(path: String, time: Double) {
        NotificationCenter.default.post(
            name: seekRequestName,
            object: nil,
            userInfo: [
                UserInfoKey.path: path,
                UserInfoKey.time: time
            ]
        )
    }

    static func postPausePreviewRequest() {
        NotificationCenter.default.post(name: pausePreviewRequestName, object: nil)
    }

    static func postMusicPreviewStarted(id: UUID, source: String? = nil, type: String? = nil) {
        var userInfo: [String: Any] = [UserInfoKey.id: id]
        if let source {
            userInfo[UserInfoKey.source] = source
        }
        if let type {
            userInfo[UserInfoKey.type] = type
        }
        NotificationCenter.default.post(
            name: musicPreviewStartedName,
            object: nil,
            userInfo: userInfo
        )
    }

    static func postMusicPreviewToggleRequest(id: UUID) {
        NotificationCenter.default.post(
            name: musicPreviewToggleRequestName,
            object: nil,
            userInfo: [UserInfoKey.id: id]
        )
    }

    static func postDownloadedMusicWaveformRenderCacheUpdated(key: String) {
        Task { @MainActor in
            NotificationCenter.default.post(
                name: downloadedMusicWaveformRenderCacheUpdatedName,
                object: nil,
                userInfo: [UserInfoKey.cacheKey: key]
            )
        }
    }

    static func postOpenExportPanelRequest(path: String, filter: String = "最近") {
        NotificationCenter.default.post(
            name: openExportPanelRequestName,
            object: nil,
            userInfo: [
                UserInfoKey.path: path,
                UserInfoKey.filter: filter
            ]
        )
    }

    static func seekRequest(from notification: Notification) -> SeekRequest? {
        guard
            let path = notification.userInfo?[UserInfoKey.path] as? String,
            let time = notification.userInfo?[UserInfoKey.time] as? Double
        else { return nil }
        return SeekRequest(path: path, time: time)
    }

    static func musicPreviewStartedEvent(from notification: Notification) -> MusicPreviewStartedEvent {
        MusicPreviewStartedEvent(
            id: notification.userInfo?[UserInfoKey.id] as? UUID,
            source: notification.userInfo?[UserInfoKey.source] as? String,
            type: notification.userInfo?[UserInfoKey.type] as? String
        )
    }

    static func musicPreviewToggleRequestID(from notification: Notification) -> UUID? {
        notification.userInfo?[UserInfoKey.id] as? UUID
    }

    static func downloadedMusicWaveformRenderCacheKey(from notification: Notification) -> String? {
        notification.userInfo?[UserInfoKey.cacheKey] as? String
    }

    static func exportPanelRequest(from notification: Notification) -> ExportPanelRequest? {
        guard let path = notification.userInfo?[UserInfoKey.path] as? String else { return nil }
        let filter = notification.userInfo?[UserInfoKey.filter] as? String ?? "最近"
        return ExportPanelRequest(path: path, filter: filter)
    }
}
