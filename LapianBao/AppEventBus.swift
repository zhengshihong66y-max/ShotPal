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

    private enum UserInfoKey {
        static let path = "path"
        static let time = "time"
        static let id = "id"
        static let source = "source"
        static let type = "type"
    }

    private static let seekRequestName = Notification.Name("lapianBaoSeekRequest")
    private static let pausePreviewRequestName = Notification.Name("lapianBaoPausePreviewRequest")
    private static let musicPreviewStartedName = Notification.Name("lapianBaoMusicPreviewStarted")
    private static let musicPreviewToggleRequestName = Notification.Name("lapianBaoMusicPreviewToggleRequest")

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
}
