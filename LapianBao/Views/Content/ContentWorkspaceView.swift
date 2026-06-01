//
//  ContentWorkspaceView.swift
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

struct ContentWorkspaceView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let goHome: (String, Double) -> Void
    @State private var selectedSegmentID: UUID?
    @State private var timelineStatus: TranscriptTimelineStatus = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("内容")
                    .font(.title2.bold())
                Spacer()
                if let video = libraryStore.selectedVideo {
                    let segments = libraryStore.transcriptSegmentsByVideoPath[video.url.path, default: []]
                    if !segments.isEmpty {
                        Button {
                            libraryStore.exportTranscriptMarkdown(video: video)
                        } label: {
                            floatingExportButtonIcon(size: 26, iconSize: 12)
                        }
                        .buttonStyle(.plain)
                        .help("导出字幕")
                    }
                }
            }

            if let video = libraryStore.selectedVideo {
                let segments = libraryStore.transcriptSegmentsByVideoPath[video.url.path, default: []]
                contentWorkspaceColumns(for: video, segments: segments)
            } else {
                AppEmptyState(
                    title: "选择一个视频",
                    systemImage: "play.rectangle",
                    style: .large
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .contentPanel()
    }

    private func contentWorkspaceColumns(for video: VideoItem, segments: [TranscriptSegment]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            workspaceSubtitleBlock(for: video, segments: segments)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            workspaceNodeBlock(for: video, segments: segments)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func workspaceSubtitleBlock(for video: VideoItem, segments: [TranscriptSegment]) -> some View {
        let status = libraryStore.transcriptStatusByVideoPath[video.url.path]

        VStack(alignment: .leading, spacing: 10) {
            if case let .running(message) = status {
                workspaceProgressRow(message)

                if !segments.isEmpty {
                    workspaceSubtitleList(segments)
                }
            } else if segments.isEmpty {
                VStack(spacing: 12) {
                    if case let .failed(message) = status {
                        ContentUnavailableView("转写失败", systemImage: "exclamationmark.triangle", description: Text(message))
                    } else {
                        AppEmptyState(
                            title: "暂无字幕",
                            systemImage: "text.quote",
                            description: "使用本地 Whisper 生成逐句时间戳。",
                            style: .large
                        )
                    }

                    Button {
                        libraryStore.transcribe(video: video)
                    } label: {
                        Label(transcriptStatusFailed(status) ? "重试" : "生成字幕", systemImage: "text.badge.plus")
                    }
                    .buttonStyle(.borderless)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                workspaceSubtitleList(segments)
            }
        }
        .padding(12)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func workspaceNodeBlock(for video: VideoItem, segments: [TranscriptSegment]) -> some View {
        let chapters = loadedTimelineChapters(for: video)

        VStack(alignment: .leading, spacing: 10) {
            switch timelineStatus {
            case let .running(videoPath) where videoPath == video.url.path:
                workspaceProgressRow("正在用本机文本模型生成内容时间线…")
            case let .failed(videoPath, message) where videoPath == video.url.path:
                VStack(spacing: 12) {
                    ContentUnavailableView("生成失败", systemImage: "exclamationmark.triangle", description: Text(message))

                    Button {
                        generateTranscriptTimeline(video: video, segments: segments)
                    } label: {
                        Label("重试", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderless)
                    .disabled(segments.isEmpty)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            default:
                if chapters.isEmpty {
                    VStack(spacing: 12) {
                        AppEmptyState(
                            title: segments.isEmpty ? "暂无字幕" : "暂无视频节点",
                            systemImage: "point.3.connected.trianglepath.dotted",
                            description: segments.isEmpty ? "生成字幕后再整理视频节点。" : "把字幕整理成更适合拉片的视频节点。",
                            style: .large
                        )

                        Button {
                            generateTranscriptTimeline(video: video, segments: segments)
                        } label: {
                            Label("生成视频节点", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderless)
                        .disabled(segments.isEmpty)
                        .help(segments.isEmpty ? "先生成字幕，再整理视频节点" : "使用本机 Ollama 文本模型把口播稿整理成内容时间线")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    workspaceNodeList(chapters, video: video)
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func workspaceProgressRow(_ message: String) -> some View {
        RecognitionProgressRow(
            message: message,
            progress: activityProgressValue(from: message)
        )
        .recognitionProgressCard()
    }

    private func workspaceSubtitleList(_ segments: [TranscriptSegment]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(segments) { segment in
                    let isSelected = selectedSegmentID == segment.id
                    Button {
                        selectedSegmentID = segment.id
                        goHome(segment.videoPath, segment.start)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text(clockText(segment.start))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(isSelected ? .white : .secondary)
                                .frame(width: 58, alignment: .leading)
                            Text(segment.text)
                                .font(.body)
                                .foregroundStyle(isSelected ? .white : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(isSelected ? Color.white.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func workspaceNodeList(_ chapters: [TranscriptTimelineChapter], video: VideoItem) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(chapters) { chapter in
                    Button {
                        selectedSegmentID = chapter.segmentID
                        goHome(video.url.path, chapter.start)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 7) {
                                Text(clockText(chapter.start))
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.secondary)
                                if let end = chapter.end {
                                    Text("- \(clockText(end))")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Text(chapter.type)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Text(chapter.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(chapter.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.white.opacity(selectedSegmentID == chapter.segmentID ? 0.12 : 0.055))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loadedTimelineChapters(for video: VideoItem) -> [TranscriptTimelineChapter] {
        if case let .loaded(videoPath, chapters) = timelineStatus,
           videoPath == video.url.path {
            return chapters
        }
        return []
    }

    private func transcriptStatusFailed(_ status: TranscriptJobStatus?) -> Bool {
        if case .failed = status { return true }
        return false
    }

    @ViewBuilder
    private func timelineStatusBanner(for video: VideoItem) -> some View {
        switch timelineStatus {
        case let .running(videoPath) where videoPath == video.url.path:
            RecognitionProgressRow(
                message: "正在用本机文本模型生成内容时间线…",
                progress: nil,
                showPercent: false
            )
            .recognitionProgressCard()
        case let .failed(videoPath, message) where videoPath == video.url.path:
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(Color.red.opacity(0.86))
        case let .loaded(videoPath, chapters) where videoPath == video.url.path && !chapters.isEmpty:
            Label("已生成 \(chapters.count) 个内容时间点", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private func chapterTimeline(for video: VideoItem, segments: [TranscriptSegment]) -> some View {
        let chapters = timelineChapters(for: video, segments: segments)
        let cardWidth: CGFloat = 184
        let cardHeight: CGFloat = 68

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chapters) { chapter in
                    Button {
                        selectedSegmentID = chapter.segmentID
                        goHome(video.url.path, chapter.start)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Text(clockText(chapter.start))
                                    .font(.caption2.monospacedDigit().weight(.bold))
                                    .foregroundStyle(.secondary)
                                if chapter.isModelGenerated {
                                    Text(chapter.type)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Text(chapter.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(chapter.isModelGenerated ? chapter.summary : "按时间粗略分段")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
                        .background(.white.opacity(selectedSegmentID == chapter.segmentID ? 0.13 : 0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(.white.opacity(selectedSegmentID == chapter.segmentID ? 0.26 : 0.10), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(chapter.isModelGenerated ? chapter.summary : "跳到 \(clockText(chapter.start))")
                }
            }
            .padding(.bottom, 2)
        }
        .frame(height: 86)
    }

    private func timelineChapters(for video: VideoItem, segments: [TranscriptSegment]) -> [TranscriptTimelineChapter] {
        if case let .loaded(videoPath, chapters) = timelineStatus,
           videoPath == video.url.path,
           !chapters.isEmpty {
            return chapters
        }
        return generatedChapters(from: segments)
    }

    private func generatedChapters(from segments: [TranscriptSegment]) -> [TranscriptTimelineChapter] {
        guard let first = segments.first else { return [] }

        var chapters: [TranscriptTimelineChapter] = [
            TranscriptTimelineChapter(
                title: "开场",
                start: first.start,
                end: first.end,
                segmentID: first.id,
                type: "粗分",
                summary: "按时间粗略分段",
                isModelGenerated: false
            )
        ]
        var nextBoundary = max(90.0, first.start + 90.0)

        for segment in segments.dropFirst() where segment.start >= nextBoundary {
            chapters.append(TranscriptTimelineChapter(
                title: "段落 \(chapters.count + 1)",
                start: segment.start,
                end: segment.end,
                segmentID: segment.id,
                type: "粗分",
                summary: "按时间粗略分段",
                isModelGenerated: false
            ))
            nextBoundary = segment.start + 90.0
        }

        return Array(chapters.prefix(12))
    }

    private func isTimelineRunning(for video: VideoItem) -> Bool {
        if case let .running(videoPath) = timelineStatus {
            return videoPath == video.url.path
        }
        return false
    }

    private func generateTranscriptTimeline(video: VideoItem, segments: [TranscriptSegment]) {
        guard !segments.isEmpty else { return }
        let authorName = libraryStore.videoAuthorName(for: video)
        timelineStatus = .running(videoPath: video.url.path)
        libraryStore.prepareExternalServiceWork()

        Task {
            do {
                let chapters = try await LocalTranscriptTimelineAnalyzer.analyze(
                    videoName: video.name,
                    videoAuthor: authorName,
                    segments: segments
                )
                await MainActor.run {
                    timelineStatus = .loaded(videoPath: video.url.path, chapters: chapters)
                }
            } catch {
                await MainActor.run {
                    timelineStatus = .failed(videoPath: video.url.path, message: LocalTranscriptTimelineAnalyzer.userFacingMessage(for: error))
                }
            }
        }
    }
}
