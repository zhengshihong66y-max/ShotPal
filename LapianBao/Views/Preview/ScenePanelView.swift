//
//  ScenePanelView.swift
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

// MARK: - ScenePanelView
struct SceneGridItem: Identifiable {
    let id: String
    let time: Double
    let endTime: Double
    let cut: SceneCut?
    let sample: SampledFrame?
    let thumbnailImage: NSImage?
    let sceneIndex: Int?
}

private struct SceneRecognitionProgressGlyph: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.20), lineWidth: 1.6)
            Circle()
                .trim(from: 0, to: normalizedProgressFraction(progress))
                .stroke(.white.opacity(0.88), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 13, height: 13)
        .accessibilityHidden(true)
    }
}

/// Equatable 视图：只有视频、场景数据或选中状态变化时才重新渲染 body。
/// 播放时钟只驱动时间线小组件；PreviewPanelView 的低频重渲
/// 将相同的播放状态传给本视图，
/// .equatable() 比较相等 → body 完全跳过，场景网格不参与渲染循环。
struct ScenePanelView: View, Equatable {
    let video: VideoItem
    let controller: PreviewController
    let sceneCuts: [SceneCut]
    let hasSceneRecognitionResult: Bool
    let sceneDetectionProgress: Double?
    let sceneDetectionError: String?
    let sceneThumbnailVersion: Int
    let sceneThumbnailsNeedHydration: Bool
    let isHydratingSceneThumbnails: Bool
    let sampledFrames: [SampledFrame]
    var activeItemID: String?
    var activeProgressTick: Double?
    let openStoryboardBoard: () -> Void
    @EnvironmentObject private var libraryStore: LibraryStore
    @AppStorage(AppSettings.Key.sceneGridSize) private var sceneGridSize = 1
    @State private var selectedItemID: String?

    static func == (lhs: ScenePanelView, rhs: ScenePanelView) -> Bool {
        lhs.video == rhs.video
            && lhs.controller === rhs.controller
            && lhs.activeItemID == rhs.activeItemID
            && lhs.hasSceneRecognitionResult == rhs.hasSceneRecognitionResult
            && lhs.sceneDetectionProgress == rhs.sceneDetectionProgress
            && lhs.sceneDetectionError == rhs.sceneDetectionError
            && lhs.sceneThumbnailVersion == rhs.sceneThumbnailVersion
            && lhs.sceneThumbnailsNeedHydration == rhs.sceneThumbnailsNeedHydration
            && lhs.isHydratingSceneThumbnails == rhs.isHydratingSceneThumbnails
            && lhs.sceneCutSignature == rhs.sceneCutSignature
            && lhs.sampledFrameSignature == rhs.sampledFrameSignature
            && lhs.activeProgressTick == rhs.activeProgressTick
    }

    var body: some View {
        let cuts = sceneCuts
        let items = sceneGridItems(cuts: cuts)

        VStack(alignment: .leading, spacing: 8) {
            if shouldShowSceneRecognitionStatus {
                sceneRecognitionStatusBlock(centered: items.isEmpty)
            }

            if !items.isEmpty {
                ScrollViewReader { proxy in
                    let tileWidth = [86.0, 116.0, 150.0][min(max(sceneGridSize, 0), 2)]
                    let columns = [GridItem(.adaptive(minimum: tileWidth), spacing: 8)]

                    ZStack(alignment: .bottomTrailing) {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(items) { item in
                                    SceneCutTile(
                                        thumbnailImage: item.thumbnailImage,
                                        timeLabel: item.sample?.kind == .screenshot ? formatDuration(item.time) : sceneDurationLabel(for: item),
                                        isExported: item.sample?.isExported == true,
                                        isScreenshot: item.sample?.kind == .screenshot,
                                        isSelected: selectedItemID == item.id,
                                        isActive: activeItemID == item.id,
                                        activeProgress: activeProgress(for: item),
                                        onTap: {
                                            selectedItemID = item.id
                                            controller.seekToSeconds(item.time)
                                        },
                                        tags: item.sample?.tags ?? [],
                                        suggestedTags: libraryStore.allFrameTags,
                                        onAddTag: addTagAction(for: item),
                                        onRemoveTag: removeTagAction(for: item),
                                        onShowInFinder: showInFinderAction(for: item),
                                        onDelete: deleteAction(for: item),
                                        showsUnavailableFileActions: item.cut != nil && item.sample == nil,
                                        dragItemProvider: dragProvider(for: item)
                                    )
                                    .id(item.id)
                                }
                            }
                            .padding(.bottom, 48)
                        }
                        .fadingVerticalScrollIndicators()

                        sceneGridOverlayControls
                            .padding(.trailing, 8)
                            .padding(.bottom, 8)
                    }
                    .onChange(of: activeItemID) { _, newID in
                        if let newID, !controller.isPlaying, abs(controller.playbackRate) < 0.001 {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(newID, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            startSceneRecognitionIfNeeded()
        }
        .onChange(of: video.url.path) { _, _ in
            startSceneRecognitionIfNeeded()
        }
    }

    private var sceneGridOverlayControls: some View {
        HStack(spacing: 8) {
            storyboardBoardButton
            sceneGridSizeControl
        }
    }

    private var storyboardBoardButton: some View {
        Button(action: openStoryboardBoard) {
            HStack(spacing: 6) {
                if let progress = sceneDetectionProgress {
                    SceneRecognitionProgressGlyph(progress: progress)
                } else {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 11, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                }

                Text(storyboardButtonTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.black.opacity(0.48))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.white.opacity(0.13), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(sceneDetectionProgress == nil ? "在画面页查看此视频分镜" : "场景识别完成后自动进入分镜")
    }

    private var storyboardButtonTitle: String {
        if let progress = sceneDetectionProgress {
            return "识别中 \(progressPercentText(progress))"
        }
        return hasSceneRecognitionResult ? "分镜模式" : "识别场景"
    }

    private var sceneGridSizeControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.3x3")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { Double(sceneGridSize) },
                    set: { sceneGridSize = Int($0.rounded()) }
                ),
                in: 0...2
            )
            .frame(width: 64)
            .controlSize(.small)
            Image(systemName: "rectangle.grid.1x2")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.black.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 0.7)
        }
        .help("视频时间线场景网格大小")
    }

    private var shouldShowSceneRecognitionStatus: Bool {
        sceneDetectionProgress != nil
            || sceneDetectionError != nil
            || (hasSceneRecognitionResult && sceneCuts.isEmpty)
            || (!hasSceneRecognitionResult && sceneCuts.isEmpty && sampledFrames.isEmpty)
    }

    @ViewBuilder
    private func sceneRecognitionStatusBlock(centered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sceneRecognitionStatusContent(centered: centered)
        }
        .recognitionProgressCard()
    }

    @ViewBuilder
    private func sceneRecognitionStatusContent(centered: Bool) -> some View {
        if let progress = sceneDetectionProgress {
            RecognitionProgressRow(
                message: "正在识别场景",
                progress: progress,
                compact: false
            )
            .padding(10)
        } else if let sceneDetectionError {
            sceneRecognitionFailureContent(sceneDetectionError, centered: centered)
        } else if hasSceneRecognitionResult && sceneCuts.isEmpty {
            AppEmptyState(
                title: centered ? "未识别到场景切点" : "未识别到场景切点，已有截图会继续保留",
                systemImage: centered ? "checkmark.circle" : nil,
                style: centered ? .compact : .inline,
                minHeight: centered ? 92 : nil,
                alignment: centered ? .center : .leading,
                textAlignment: centered ? .center : .leading,
                fillsWidth: true
            )
        } else {
            RecognitionProgressRow(
                message: "正在准备场景识别",
                progress: nil,
                compact: false,
                showPercent: false
            )
            .padding(10)
        }
    }

    private func sceneRecognitionFailureContent(_ message: String, centered: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: centered ? 18 : 13, weight: .semibold))
                .foregroundStyle(.red.opacity(0.92))

            VStack(alignment: .leading, spacing: 3) {
                Text("场景识别失败")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button {
                libraryStore.detectSceneCuts(for: video, force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("重新识别场景")
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: centered ? 92 : nil, alignment: .leading)
    }

    private func startSceneRecognitionIfNeeded() {
        if hasSceneRecognitionResult {
            if !controller.isPlaying {
                libraryStore.hydrateSceneThumbnailsIfNeeded(for: video)
            }
            return
        }
        guard !hasSceneRecognitionResult, sceneDetectionProgress == nil, sceneDetectionError == nil else { return }
        libraryStore.detectSceneCuts(for: video)
    }

    private var sceneCutSignature: Int {
        var hasher = Hasher()
        hasher.combine(sceneCuts.count)
        for cut in sceneCuts {
            hasher.combine(cut.id)
            hasher.combine(Int((cut.time * 1000).rounded()))
            hasher.combine(cut.isPlaceholder)
            hasher.combine(ObjectIdentifier(cut.thumbnailImage))
        }
        return hasher.finalize()
    }

    private var sampledFrameSignature: Int {
        var hasher = Hasher()
        hasher.combine(sampledFrames.count)
        for frame in sampledFrames {
            hasher.combine(frame.id)
            hasher.combine(Int((frame.time * 1000).rounded()))
            hasher.combine(frame.kind.rawValue)
            hasher.combine(frame.isExported)
            hasher.combine(frame.sceneIndex)
            for tag in frame.tags {
                hasher.combine(tag)
            }
        }
        return hasher.finalize()
    }

    private func sceneGridItems(cuts: [SceneCut]) -> [SceneGridItem] {
        struct Raw {
            let id: String
            let time: Double
            let cut: SceneCut?
            let sample: SampledFrame?
            let image: NSImage?
            let sceneIndex: Int?
        }

        let samples = sampledFrames
        let representativeSamples = Dictionary(
            samples
                .filter { $0.kind == .sceneRepresentative }
                .map { (sceneSampleKey(for: $0.time), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let cutRaw = cuts.enumerated().map { index, cut in
            Raw(
                id: "cut-\(cut.id)",
                time: cut.time,
                cut: cut,
                sample: representativeSamples[sceneSampleKey(for: cut.time)],
                image: libraryStore.displaySceneCutImage(for: video, cut: cut),
                sceneIndex: index
            )
        }

        let shotRaw = samples
            .filter { $0.kind == .screenshot }
            .map { sample in
                Raw(
                    id: "sample-\(sample.id)",
                    time: sample.time,
                    cut: nil,
                    sample: sample,
                    image: libraryStore.thumbnailImage(for: sample),
                    sceneIndex: sample.sceneIndex
                )
            }

        let sorted = (cutRaw + shotRaw).sorted { $0.time < $1.time }
        let duration = controller.duration
        return sorted.enumerated().map { index, raw in
            let nextTime = index + 1 < sorted.count ? sorted[index + 1].time : max(raw.time + 1, duration)
            return SceneGridItem(
                id: raw.id,
                time: raw.time,
                endTime: nextTime,
                cut: raw.cut,
                sample: raw.sample,
                thumbnailImage: raw.image,
                sceneIndex: raw.sceneIndex
            )
        }
    }

    private func sceneSampleKey(for time: Double) -> Int {
        Int((time * 50).rounded())
    }

    private func normalizedSceneCutProgresses(for video: VideoItem) -> [Double] {
        let path = video.url.path
        guard let duration = libraryStore.durationByVideoPath[path], duration > 0 else { return [] }
        return libraryStore.sceneCutsByVideoPath[path, default: []]
            .map { min(1, max(0, $0.time / duration)) }
    }

    private func addTagAction(for item: SceneGridItem) -> ((String) -> Void)? {
        if let sample = item.sample {
            return { tag in
                libraryStore.addFrameTag(tag, to: sample)
            }
        }

        guard let cut = item.cut else { return nil }
        return { tag in
            Task {
                if let frame = await libraryStore.ensureSceneFrameExported(
                    video: video,
                    cut: cut,
                    sceneIndex: item.sceneIndex
                ) {
                    libraryStore.addFrameTag(tag, to: frame)
                }
            }
        }
    }

    private func removeTagAction(for item: SceneGridItem) -> ((String) -> Void)? {
        guard let sample = item.sample else { return nil }
        return { tag in
            libraryStore.removeFrameTagOrDeleteIfEmpty(tag, from: sample)
        }
    }

    private func showInFinderAction(for item: SceneGridItem) -> (() -> Void)? {
        guard let sample = item.sample else { return nil }
        return {
            if let imageURL = libraryStore.imageExportURL(for: sample) {
                NSWorkspace.shared.activateFileViewerSelecting([imageURL])
            } else {
                NSWorkspace.shared.open(libraryStore.imageExportDestination(for: video))
            }
        }
    }

    private func deleteAction(for item: SceneGridItem) -> (() -> Void)? {
        guard let sample = item.sample else { return nil }
        return {
            libraryStore.deleteSampledFrame(sample)
            if selectedItemID == item.id {
                selectedItemID = nil
            }
        }
    }

    private func dragProvider(for item: SceneGridItem) -> (() -> NSItemProvider)? {
        guard item.thumbnailImage != nil else { return nil }

        if let sample = item.sample {
            return {
                libraryStore.fullResolutionFrameProvider(for: sample)
            }
        }

        return {
            libraryStore.fullResolutionFrameProvider(
                video: video,
                time: item.time,
                kind: .sceneRepresentative,
                fallbackImage: item.thumbnailImage
            )
        }
    }

    private func sceneDurationLabel(for item: SceneGridItem) -> String {
        formatDuration(max(0, item.endTime - item.time))
    }

    private func activeProgress(for item: SceneGridItem) -> Double? {
        guard activeItemID == item.id else { return nil }
        let start = item.time
        let end = sceneEndTime(for: item)
        guard end > start else { return nil }
        return min(1, max(0, (controller.elapsed - start) / (end - start)))
    }

    private func sceneEndTime(for item: SceneGridItem) -> Double {
        guard let sceneIndex = item.sceneIndex,
              sceneCuts.indices.contains(sceneIndex)
        else {
            return item.endTime
        }

        let nextIndex = sceneIndex + 1
        if sceneCuts.indices.contains(nextIndex) {
            return sceneCuts[nextIndex].time
        }

        return max(item.time + 1, controller.duration)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }
}

func previewPlaybackTimecode(_ seconds: Double) -> String {
    let totalSeconds = max(0, Int(seconds.rounded()))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}
