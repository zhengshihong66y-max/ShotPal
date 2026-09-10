//
//  AppTypes.swift
//  LapianBao
//
//  Split from ContentView.swift.
//

import SwiftUI
import AVFoundation
import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum PreviewTab: String, CaseIterable {
    var title: String { L10n.key(rawValue) }
    case frames = "提取画面"
    case audio  = "提取声音"
    case content = "提取内容"
}

enum ExportPanelFilter: String, CaseIterable, Identifiable {
    var title: String { L10n.key(rawValue) }
    case recent = "最近"
    case images = "图片"
    case audio = "声音"
    case music = "音乐"

    var id: String { rawValue }
}

enum ExportPanelItem: Identifiable {
    case frame(SampledFrame)
    case audio(AudioClipItem)
    case transcript(TranscriptExportItem)
    case transcriptProgress(TranscriptExportJob)

    var id: String {
        switch self {
        case .frame(let frame): return "frame-\(frame.id.uuidString)"
        case .audio(let clip): return "audio-\(clip.id.uuidString)"
        case .transcript(let export): return "transcript-\(export.id.uuidString)"
        case .transcriptProgress(let job): return "transcript-progress-\(job.videoPath)"
        }
    }

    var createdAt: Date {
        switch self {
        case .frame(let frame): return frame.createdAt
        case .audio(let clip): return clip.createdAt
        case .transcript(let export): return export.createdAt
        case .transcriptProgress(let job): return job.createdAt
        }
    }
}

struct TimelineAnnotationMarker: Identifiable, Equatable {
    var id: UUID
    var progress: Double
    var text: String
    var kind: AnnotationItem.Kind
}

struct AnnotationEditorAnchor: Equatable {
    var progress: Double
    var kind: AnnotationItem.Kind
    var sourceTab: PreviewTab
}

enum AppWorkspace: String, CaseIterable, Identifiable {
    case home
    case frames
    case music
    case settings

    static var allCases: [AppWorkspace] {
        railCases
    }

    static let railCases: [AppWorkspace] = [.home, .frames, .music, .settings]

    var id: String { rawValue }

    var canRestoreFromUserDefaults: Bool {
        Self.railCases.contains(self)
    }

    var canRestoreDuringLaunch: Bool {
        switch self {
        case .home:
            return true
        case .frames, .music, .settings:
            return false
        }
    }

    var title: String {
        switch self {
        case .home: return L10n.text("主页")
        case .frames: return L10n.text("画面")
        case .music: return L10n.text("AM 库")
        case .settings: return L10n.text("设置")
        }
    }

    var icon: String {
        switch self {
        case .home: return "play.rectangle.fill"
        case .frames: return "photo.on.rectangle.angled"
        case .music: return "music.note.list"
        case .settings: return "gearshape"
        }
    }

    var railIconOffset: CGFloat {
        switch self {
        case .home, .settings:
            return 0
        case .frames:
            return 0.25
        case .music:
            return -0.5
        }
    }

    var railIconSize: CGFloat {
        switch self {
        case .home:
            return 15.5
        case .frames:
            return 16.5
        case .music:
            return 16
        case .settings:
            return 16.5
        }
    }
}

enum FramesBoardMode: String, CaseIterable, Identifiable {
    var title: String { L10n.key(rawValue) }
    case storyboard = "分镜"
    case collection = "收藏"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .storyboard: return "rectangle.stack"
        case .collection: return "photo.on.rectangle"
        }
    }
}

struct VideoDateSection: Identifiable, Equatable {
    var id: String
    var title: String
    var videos: [VideoItem]
}

struct ImportHistoryBatch: Identifiable {
    var id: UUID
    var title: String
    var jobs: [RemoteImportJob]

    var totalCount: Int {
        jobs.compactMap(\.batchTotalCount).max() ?? jobs.count
    }

    var succeededCount: Int {
        jobs.filter {
            if case .succeeded = $0.status { return true }
            return false
        }.count
    }

    var failedCount: Int {
        jobs.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
    }

    var completedCount: Int {
        succeededCount + failedCount
    }
}

enum ImportHistoryItem: Identifiable {
    case single(RemoteImportJob)
    case batch(ImportHistoryBatch)

    var id: String {
        switch self {
        case .single(let job):
            return "job-\(job.id.uuidString)"
        case .batch(let batch):
            return "batch-\(batch.id.uuidString)"
        }
    }
}

struct PendingImportVideo: Identifiable, Equatable {
    var id: String
    var urlString: String
    var platform: String
    var title: String
    var subtitle: String
    var authorName: String? = nil
    var thumbnailData: Data? = nil
    var thumbnailURLString: String? = nil
    var hasSeededMetadata: Bool = false
    var isMetadataLoading: Bool = false
    var isSupported: Bool
}

enum VideoSourcePlatform: String, CaseIterable {
    var title: String { L10n.key(rawValue) }
    case instagram = "Instagram"
    case youtube = "YouTube"
    case xiaohongshu = "小红书"
    case bilibili = "Bilibili"
    case douyin = "抖音"
    case other = "其他"

    var iconName: String {
        switch self {
        case .instagram: return "camera"
        case .youtube: return "play.rectangle.fill"
        case .xiaohongshu: return "book.pages.fill"
        case .bilibili: return "play.rectangle.fill"
        case .douyin: return "music.note"
        case .other: return "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .instagram: return Color(red: 0.93, green: 0.31, blue: 0.58)
        case .youtube: return Color(red: 0.96, green: 0.18, blue: 0.18)
        case .xiaohongshu: return Color(red: 0.88, green: 0.24, blue: 0.30)
        case .bilibili: return Color(red: 0.28, green: 0.68, blue: 0.95)
        case .douyin: return .white
        case .other: return Color(red: 0.62, green: 0.66, blue: 0.72)
        }
    }

    static func displayName(for value: String) -> String {
        matching(value)?.title ?? value
    }

    static func matching(_ value: String) -> VideoSourcePlatform? {
        allCases.first { $0.rawValue.caseInsensitiveCompare(value) == .orderedSame }
    }

    static func iconName(for value: String) -> String {
        matching(value)?.iconName ?? "link"
    }

    static func color(for value: String) -> Color {
        matching(value)?.color ?? Color(red: 0.62, green: 0.66, blue: 0.72)
    }
}

enum VideoTagChipSize {
    case mini
    case compact
    case regular

    var font: Font {
        switch self {
        case .mini: return .caption2.weight(.semibold)
        case .compact: return .caption2.weight(.semibold)
        case .regular: return .caption.weight(.medium)
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .mini: return 4
        case .compact: return 5
        case .regular: return 7
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .mini: return 2
        case .compact: return 3
        case .regular: return 4
        }
    }

    var maxTextWidth: CGFloat {
        switch self {
        case .mini: return 58
        case .compact: return 74
        case .regular: return 132
        }
    }
}
