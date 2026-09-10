//
//  ContentView+VideoTiles.swift
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

extension ContentView {
    func videoTile(_ video: VideoItem) -> some View {
        let isSelected = libraryStore.selectedVideo == video

        return LibraryVideoTile(
            video: video,
            displayName: videoDisplayName(for: video),
            thumbnailImage: thumbnailImage(for: video),
            thumbnailRevision: thumbnailRevision(for: video),
            durationText: durationTextIfReady(for: video),
            sourcePlatform: sourcePlatformName(for: video),
            tags: libraryStore.videoTags(for: video),
            suggestedTags: libraryStore.videoTagSuggestions(for: video),
            isSelected: isSelected,
            onSelect: {
                libraryStore.selectVideo(video, autoplay: true)
            },
            onAddTag: { tag in
                libraryStore.addTag(tag, to: video)
            },
            onRemoveTag: { tag in
                libraryStore.removeTag(tag, from: video)
            },
            onSetSourcePlatform: { platform in
                libraryStore.setSourcePlatform(platform, for: video)
            },
            onDelete: {
                libraryStore.removeVideo(video)
            },
            menuIdentity: video.url.path,
            menuDismissToken: libraryCardMenuDismissToken,
            onMenuPresentationChanged: { identity, isPresented in
                handleLibraryCardMenuPresentationChange(identity, isPresented: isPresented)
            },
            dragItemProvider: { videoDragItemProvider(for: video) }
        )
        .equatable()
        .onAppear {
            libraryStore.queueMetadataLoadIfNeeded(for: video, allowThumbnailGeneration: true)
        }
    }

    func handleLibraryCardMenuPresentationChange(_ identity: String, isPresented: Bool) {
        if isPresented {
            activeLibraryCardMenuID = identity
        } else if activeLibraryCardMenuID == identity {
            activeLibraryCardMenuID = nil
        }
    }

    func dismissLibraryCardMenusForScroll() {
        guard activeLibraryCardMenuID != nil else { return }
        activeLibraryCardMenuID = nil
        libraryCardMenuDismissToken += 1
    }

    func thumbnailImage(for video: VideoItem) -> NSImage? {
        libraryStore.thumbnailImageForDisplay(for: video)
    }

    func thumbnailRevision(for video: VideoItem) -> Int {
        libraryStore.thumbnailImageRevision(for: video)
    }

    func durationTextIfReady(for video: VideoItem) -> String? {
        guard let duration = libraryStore.durationByVideoPath[video.url.path] else { return nil }
        return formatDuration(duration)
    }

    func analysisMenuItems(for video: VideoItem) -> [VideoAnalysisMenuItem] {
        let path = video.url.path
        let transcriptSegments = libraryStore.transcriptSegmentsByVideoPath[path, default: []]
        let transcriptStatus = libraryStore.transcriptStatusByVideoPath[path] ?? .idle
        let sceneCutCount = libraryStore.sceneRecognitionCutCount(for: video)
        let hasSceneRecognitionResult = sceneCutCount != nil
        let sceneProgress = libraryStore.sceneDetectionProgress[path]
        let sceneError = libraryStore.sceneDetectionErrorByVideoPath[path]
        let musics = libraryStore.musicsByVideoPath[path, default: []]
        let musicStatus = libraryStore.musicDetectionStatusByVideoPath[path] ?? .idle
        let musicPresentation = MusicRecognitionPresentation(status: musicStatus, songCount: musics.count)

        return [
            VideoAnalysisMenuItem(
                kind: .transcript,
                title: L10n.text("内容"),
                icon: "text.bubble",
                detail: transcriptSegments.isEmpty ? L10n.text("暂无字幕") : L10n.text("\(transcriptSegments.count) 段字幕"),
                status: menuStatusText(transcriptStatus, idleText: L10n.text("空闲")),
                tone: menuTone(transcriptStatus),
                canRun: !isRunning(transcriptStatus),
                canDelete: !transcriptSegments.isEmpty || transcriptStatus != .idle
            ),
            VideoAnalysisMenuItem(
                kind: .scene,
                title: L10n.text("画面"),
                icon: "rectangle.on.rectangle",
                detail: sceneCutCount.map { L10n.text("\($0) 个剪辑点") } ?? L10n.text("暂无场景"),
                status: sceneProgress.map { L10n.text("分析中 \(progressPercentText($0))") } ?? (sceneError == nil ? (hasSceneRecognitionResult ? L10n.text("已完成") : L10n.text("空闲")) : L10n.text("失败")),
                tone: sceneProgress == nil ? (sceneError == nil ? (hasSceneRecognitionResult ? .completed : .idle) : .failed) : .running,
                canRun: sceneProgress == nil,
                canDelete: hasSceneRecognitionResult || sceneProgress != nil || sceneError != nil
            ),
            VideoAnalysisMenuItem(
                kind: .music,
                title: L10n.text("声音"),
                icon: "music.note.list",
                detail: musics.isEmpty ? L10n.text("暂无音乐") : L10n.text("\(musics.count) 首音乐"),
                status: musicPresentation.menuStatus,
                tone: musicPresentation.menuTone,
                canRun: !isRunning(musicStatus),
                canDelete: !musics.isEmpty || musicStatus != .idle
            )
        ]
    }

    func runAnalysis(_ kind: VideoAnalysisKind, for video: VideoItem) {
        switch kind {
        case .transcript:
            libraryStore.transcribe(video: video)
        case .scene:
            libraryStore.detectSceneCuts(for: video, force: true)
        case .music:
            libraryStore.detectMusic(for: video)
        }
    }

    func deleteAnalysis(_ kind: VideoAnalysisKind, for video: VideoItem) {
        switch kind {
        case .transcript:
            libraryStore.deleteTranscript(for: video)
        case .scene:
            libraryStore.deleteSceneRecognition(for: video)
        case .music:
            libraryStore.deleteMusicRecognition(for: video)
        }
    }

    func menuStatusText(_ status: TranscriptJobStatus, idleText: String) -> String {
        switch status {
        case .idle:
            return idleText
        case .running(let message):
            return message
        case .completed:
            return L10n.text("已完成")
        case .failed:
            return L10n.text("失败")
        }
    }

    func menuTone(_ status: TranscriptJobStatus) -> VideoAnalysisTone {
        switch status {
        case .idle:
            return .idle
        case .running:
            return .running
        case .completed:
            return .completed
        case .failed:
            return .failed
        }
    }

    func isRunning(_ status: TranscriptJobStatus) -> Bool {
        if case .running = status {
            return true
        }
        return false
    }

    func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

}
