   //
//  ContentView.swift
//  LapianBao
//
//  Created by 郑士泓 on 2026/5/24.
//

import SwiftUI
import AVFoundation
import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

private extension View {
    @ViewBuilder
    func itemProviderDrag(_ itemProvider: (() -> NSItemProvider)?) -> some View {
        if let itemProvider {
            self.onDrag {
                itemProvider()
            }
        } else {
            self
        }
    }

    func fullResolutionImageDrag(_ itemProvider: (() -> NSItemProvider)?) -> some View {
        itemProviderDrag(itemProvider)
    }

    func recognitionProgressCard() -> some View {
        self
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.078))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 0.8)
            }
    }
}

private func videoDragItemProvider(for video: VideoItem) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.suggestedName = video.url.lastPathComponent

    let typeIdentifier = UTType(filenameExtension: video.url.pathExtension)?.identifier ?? UTType.movie.identifier
    provider.registerFileRepresentation(
        forTypeIdentifier: typeIdentifier,
        fileOptions: .openInPlace,
        visibility: .all
    ) { completion in
        let progress = Progress(totalUnitCount: 1)
        guard FileManager.default.fileExists(atPath: video.url.path) else {
            completion(nil, true, NSError(
                domain: "LapianBao.VideoDragExport",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "视频文件不存在"]
            ))
            return progress
        }

        progress.completedUnitCount = 1
        completion(video.url, true, nil)
        return progress
    }

    provider.registerObject(video.url as NSURL, visibility: .all)
    return provider
}

enum Design {
    static let minimumWindowWidth: CGFloat = 960
    static let minimumWindowHeight: CGFloat = 720
    static let windowInset: CGFloat = 0
    // macOS 标准窗口圆角约 10pt（Big Sur+），这里用 10 与系统保持一致
    static let windowRadius: CGFloat = 10
    static let panelSpacing: CGFloat = 0
    static let panelRadius: CGFloat = 0
    static let innerRadius: CGFloat = 6
    static let itemRadius: CGFloat = 6
    static let railWidth: CGFloat = 56
    static let railIconInset: CGFloat = 8
    static let railButtonHeight: CGFloat = 34
    static let railIconBoxSize: CGFloat = 24
    static let railButtonVisualOffsetX: CGFloat = 3.5
    static let railSelectionGuideX: CGFloat = railIconInset + railButtonVisualOffsetX
    static let libraryToolbarVisualGap: CGFloat = 14
    static let libraryToolbarHeight: CGFloat = 22
    static let libraryToolbarButtonSlotWidth: CGFloat = 22
    static let libraryToolbarButtonSlotHeight: CGFloat = 22
    static let libraryToolbarButtonGap: CGFloat = 13
    static let previewHeaderTagRowHeight: CGFloat = 12
    static let previewHeaderTopInset: CGFloat = libraryToolbarVisualGap
    static let previewHeaderTitleTagGap: CGFloat = 4
    static let previewHeaderTitleLineHeight: CGFloat = 22
    static let previewHeaderHeight: CGFloat = previewHeaderTopInset + previewHeaderTitleLineHeight + previewHeaderTitleTagGap + previewHeaderTagRowHeight + previewHeaderTitleTagGap
    static let trafficLightSize: CGFloat = 12
    static let trafficLightGap: CGFloat = 6
    static let trafficLightClusterWidth: CGFloat = trafficLightSize * 3 + trafficLightGap * 2
    static let libraryToolbarTop: CGFloat = libraryToolbarVisualGap
    static let railTopChromeHeight: CGFloat = libraryToolbarTop + libraryToolbarHeight
    static let trafficLightGuideX: CGFloat = 14
    static let trafficLightGuideY: CGFloat = 19
    static let settingsRailWidth: CGFloat = max(railWidth, trafficLightGuideX + trafficLightClusterWidth)
    static let timelineLaneHeight: CGFloat = 100
    static let collapsedTimelineLaneHeight: CGFloat = 40
    static let timelineLaneButtonSize: CGFloat = 24
    static let timelineLaneIconSize: CGFloat = 22
    static let timelineLaneVisualGap: CGFloat = (timelineLaneHeight - timelineLaneButtonSize * 3) / 4
    static let timelineLaneContentHeight: CGFloat = timelineLaneHeight - timelineLaneVisualGap * 2
    static let expandedTimelineDetailHeight: CGFloat = 280
    static let expandedTimelineStackMaxHeight: CGFloat = 520
    static let sceneTimelineAutoVisibleSceneLimit = 36
    static let sceneTimelineAutoMaxZoom: Double = 6
    static let centeredWaveformViewportSpan: Double = 0.22
    static let previewExportOverlayWidthRatio: CGFloat = 1.0 / 3.0
    static let previewExportOverlayMinWidth: CGFloat = 260
    static let previewExportOverlayButtonSize: CGFloat = 28
    static let previewExportOverlayButtonIconSize: CGFloat = 13
    static let previewExportOverlayButtonInset: CGFloat = 10
    static let previewExportPanelPadding: CGFloat = 10
    static let libraryToolbarIconTint = Color.white.opacity(0.72)

    // 侧边栏（icon rail + 内容区）统一同色，主内容略亮，形成嵌套层次感
    static let sidebarBg = Color(red: 0.118, green: 0.118, blue: 0.129)
    static let contentBg = Color(red: 0.149, green: 0.149, blue: 0.165)

    static let currentFrameAccent = Color(red: 1.00, green: 0.22, blue: 0.18)
    static let captureFrameAccent = Color(red: 1.00, green: 0.50, blue: 0.18)
    static let annotationAccent = Color(red: 0.68, green: 0.72, blue: 0.72)
}

private func floatingExportButtonIcon(
    systemImage: String = "square.and.arrow.up",
    size: CGFloat = 24,
    iconSize: CGFloat? = nil
) -> some View {
    Image(systemName: systemImage)
        .font(.system(size: iconSize ?? min(13, size * 0.48), weight: .semibold))
        .foregroundStyle(Design.captureFrameAccent)
        .frame(width: size, height: size)
        .background(.white.opacity(0.18))
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.28), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        .contentShape(Circle())
}

private func cardOverlayExportButtonIcon(
    systemImage: String = "square.and.arrow.up"
) -> some View {
    let shape = RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous)

    return Image(systemName: systemImage)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.88))
        .frame(width: 24, height: 24)
        .background(.black.opacity(0.48))
        .clipShape(shape)
        .overlay {
            shape
                .stroke(.white.opacity(0.12), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 1)
        .contentShape(shape)
}

private enum PreviewTab: String, CaseIterable {
    case frames = "提取画面"
    case audio  = "提取声音"
    case content = "提取内容"
}

private enum ExportPanelFilter: String, CaseIterable, Identifiable {
    case recent = "最近"
    case images = "图片"
    case audio = "声音"
    case music = "音乐"

    var id: String { rawValue }
}

private enum ExportPanelItem: Identifiable {
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

private struct TimelineAnnotationMarker: Identifiable, Equatable {
    var id: UUID
    var progress: Double
    var text: String
    var kind: AnnotationItem.Kind
}

private struct AnnotationEditorAnchor: Equatable {
    var progress: Double
    var kind: AnnotationItem.Kind
    var sourceTab: PreviewTab
}

private enum AppWorkspace: String, CaseIterable, Identifiable {
    case home
    case frames
    case audio
    case music
    case content
    case settings

    static var allCases: [AppWorkspace] {
        railCases
    }

    static let railCases: [AppWorkspace] = [.home, .frames, .audio, .music, .settings]

    var id: String { rawValue }

    var canRestoreFromUserDefaults: Bool {
        Self.railCases.contains(self)
    }

    var canRestoreDuringLaunch: Bool {
        switch self {
        case .home:
            return true
        case .frames, .audio, .music, .content, .settings:
            return false
        }
    }

    var title: String {
        switch self {
        case .home: return "主页"
        case .frames: return "画面"
        case .audio: return "音效"
        case .music: return "AM 库"
        case .content: return "内容"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .home: return "play.rectangle.fill"
        case .frames: return "photo.on.rectangle.angled"
        case .audio: return "waveform"
        case .music: return "music.note.list"
        case .content: return "text.quote"
        case .settings: return "gearshape"
        }
    }

    var railIconOffset: CGFloat {
        switch self {
        case .home, .audio, .music, .content, .settings:
            return 0
        case .frames:
            return 0.5
        }
    }
}

private enum FramesBoardMode: String, CaseIterable, Identifiable {
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

private struct VideoDateSection: Identifiable {
    var id: String
    var title: String
    var videos: [VideoItem]
}

private enum VideoSourcePlatform: String, CaseIterable {
    case instagram = "Instagram"
    case youtube = "YouTube"
    case xiaohongshu = "小红书"
    case bilibili = "Bilibili"
    case douyin = "抖音"

    var iconName: String {
        switch self {
        case .instagram: return "camera"
        case .youtube: return "play.rectangle.fill"
        case .xiaohongshu: return "book.pages.fill"
        case .bilibili: return "play.rectangle.fill"
        case .douyin: return "music.note.tv.fill"
        }
    }

    var color: Color {
        switch self {
        case .instagram: return Color(red: 0.93, green: 0.31, blue: 0.58)
        case .youtube: return Color(red: 0.96, green: 0.18, blue: 0.18)
        case .xiaohongshu: return Color(red: 0.88, green: 0.24, blue: 0.30)
        case .bilibili: return Color(red: 0.28, green: 0.68, blue: 0.95)
        case .douyin: return Color(red: 0.34, green: 0.84, blue: 0.78)
        }
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

private enum VideoTagPalette {
    private static let colors: [Color] = [
        Color(red: 0.94, green: 0.34, blue: 0.38),
        Color(red: 0.96, green: 0.55, blue: 0.22),
        Color(red: 0.72, green: 0.66, blue: 0.28),
        Color(red: 0.30, green: 0.70, blue: 0.40),
        Color(red: 0.22, green: 0.72, blue: 0.68),
        Color(red: 0.32, green: 0.56, blue: 0.96),
        Color(red: 0.56, green: 0.43, blue: 0.92),
        Color(red: 0.84, green: 0.38, blue: 0.78)
    ]

    static func color(for tag: String) -> Color {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return colors.first ?? Color(red: 0.62, green: 0.66, blue: 0.72)
        }

        var hash: UInt64 = 14_695_981_039_346_656_037
        for scalar in trimmed.lowercased().unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash &*= 1_099_511_628_211
        }
        return colors[Int(hash % UInt64(colors.count))]
    }
}

private enum VideoTagChipSize {
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

private struct VideoTagChip: View {
    let tag: String
    var size: VideoTagChipSize = .regular
    var onRemove: (() -> Void)? = nil

    var body: some View {
        let tint = VideoTagPalette.color(for: tag)

        HStack(spacing: 3) {
            Text(tag)
                .font(size.font)
                .lineLimit(1)
                .truncationMode(.tail)
                .allowsTightening(true)
                .frame(maxWidth: size.maxTextWidth, alignment: .leading)
                .layoutPriority(1)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("移除标签")
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(tint.opacity(0.18))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.34), lineWidth: 0.8)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct VideoTagOverflowChip: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.caption2.weight(.bold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(.white.opacity(0.84))
            .background(.white.opacity(0.13))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.18), lineWidth: 0.8)
            }
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct TagSuggestionGrid: View {
    let currentTags: [String]
    let suggestedTags: [String]
    var limit = 12
    let onAdd: (String) -> Void

    private var candidates: [String] {
        suggestedTags.filter { !currentTags.contains($0) }
    }

    var body: some View {
        if !candidates.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(candidates.prefix(limit), id: \.self) { tag in
                    Button {
                        onAdd(tag)
                    } label: {
                        HStack(spacing: 4) {
                            VideoTagColorDot(tag: tag)
                            Text(tag)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct InlineTagEditorButton: View {
    let title: String
    let tags: [String]
    let suggestedTags: [String]
    var buttonSize: CGFloat = 26
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    @State private var isPresented = false
    @State private var draftTag = ""

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: tags.isEmpty ? "tag" : "tag.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tags.isEmpty ? .secondary : Design.captureFrameAccent)
                .frame(width: buttonSize, height: buttonSize)
                .overlay(alignment: .topTrailing) {
                    if !tags.isEmpty {
                        Text("\(tags.count)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(title)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            tagEditorPopover
        }
    }

    private var tagEditorPopover: some View {
        return VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if tags.isEmpty {
                AppEmptyState(title: "暂无标签", style: .inline, alignment: .leading, fillsWidth: false)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            VideoTagChip(tag: tag, size: .compact) {
                                onRemove(tag)
                            }
                        }
                    }
                }
            }

            TagSuggestionGrid(currentTags: tags, suggestedTags: suggestedTags, onAdd: onAdd)

            HStack(spacing: 6) {
                TextField("添加标签", text: $draftTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addDraftTag)

                Button(action: addDraftTag) {
                    Image(systemName: "plus")
                }
                .disabled(draftTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 260)
        .onChange(of: isPresented) { _, presented in
            if !presented { draftTag = "" }
        }
    }

    private func addDraftTag() {
        let tag = draftTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        onAdd(tag)
        draftTag = ""
    }
}

private struct PreviewTitleTagChip: View {
    let tag: String

    var body: some View {
        let tint = VideoTagPalette.color(for: tag)

        Text(tag)
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .allowsTightening(true)
            .frame(maxWidth: 64, minHeight: Design.previewHeaderTagRowHeight, maxHeight: Design.previewHeaderTagRowHeight, alignment: .center)
            .padding(.horizontal, 5)
            .foregroundStyle(.primary.opacity(0.88))
            .background(tint.opacity(0.16))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.28), lineWidth: 0.7)
            }
    }
}

private struct VideoTagColorDot: View {
    let tag: String

    var body: some View {
        Circle()
            .fill(VideoTagPalette.color(for: tag))
            .frame(width: 7, height: 7)
    }
}

private struct SourcePlatformBadge: View {
    let platform: String
    var compact = false

    var body: some View {
        let tint = VideoSourcePlatform.color(for: platform)

        HStack(spacing: compact ? 3 : 5) {
            Image(systemName: VideoSourcePlatform.iconName(for: platform))
                .font(.system(size: compact ? 8 : 10, weight: .semibold))
                .frame(width: compact ? 10 : 12)

            Text(platform)
                .font(compact ? .caption2.weight(.bold) : .caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
        }
        .foregroundStyle(.white.opacity(0.90))
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(tint.opacity(0.24))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.42), lineWidth: 0.8)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SourcePlatformIconBadge: View {
    static let size: CGFloat = 18

    let platform: String

    var body: some View {
        let tint = VideoSourcePlatform.color(for: platform)

        Image(systemName: VideoSourcePlatform.iconName(for: platform))
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: Self.size, height: Self.size)
            .shadow(color: .black.opacity(0.72), radius: 1.4, x: 0, y: 0.7)
            .shadow(color: .black.opacity(0.32), radius: 4, x: 0, y: 1.5)
    }
}


private struct AudioWaveformView: View {
    let samples: [Double]?
    let progress: Double
    let seek: (Double) -> Void
    var sceneCuts: [Double] = []
    var inPoint: Double? = nil
    var outPoint: Double? = nil
    var viewportStart: Double = 0
    var viewportSpan: Double = 1
    var duration: Double = 0
    var panViewport: ((Double) -> Void)? = nil
    var zoomViewport: ((Double, Double) -> Void)? = nil

    @State private var isDragging = false
    @State private var draftProgress: Double?
    @State private var lastMagnification: CGFloat = 1

    private let placeholderSamples: [Double] = (0..<240).map { index in
        0.14 + 0.10 * abs(sin(Double(index) * 0.46))
    }

    var body: some View {
        let activeProgress = min(1, max(0, draftProgress ?? progress))
        let displayedProgress = localProgress(activeProgress)

        GeometryReader { proxy in
            ZStack {
                Canvas { context, size in
                    let values = samples ?? placeholderSamples

                    guard !values.isEmpty else {
                        let rect = CGRect(x: 0, y: size.height / 2, width: size.width, height: 1)
                        context.fill(Path(rect), with: .color(.white.opacity(0.18)))
                        return
                    }

                    // In/Out 区间高亮
                    if let inP = inPoint, let outP = outPoint, size.width > 0 {
                        let lo = CGFloat(localProgress(min(inP, outP)))
                        let hi = CGFloat(localProgress(max(inP, outP)))
                        var regionPath = Path()
                        regionPath.addRect(CGRect(x: size.width * lo, y: 0, width: size.width * (hi - lo), height: size.height))
                        context.fill(regionPath, with: .color(.white.opacity(0.18)))
                    }

                    let sampleCount = values.count
                    let span = max(0.0001, min(1, viewportSpan))
                    let visibleStart = min(1, max(0, viewportStart))
                    let visibleEnd = min(1, max(visibleStart, visibleStart + span))
                    let contentWidth = size.width / CGFloat(span)
                    let contentOffset = -CGFloat(visibleStart / span) * size.width
                    let step = contentWidth / CGFloat(sampleCount)
                    let barWidth = max(0.65, min(1.6, step * 0.82))
                    let firstIndex = max(0, Int(floor(visibleStart * Double(sampleCount))) - 1)
                    let lastIndex = min(sampleCount - 1, Int(ceil(visibleEnd * Double(sampleCount))) + 1)

                    if firstIndex <= lastIndex {
                        for index in firstIndex...lastIndex {
                            let value = values[index]
                            let normalized = max(0.04, min(1, value))
                            let barHeight = CGFloat(normalized) * size.height * 0.84
                            let x = CGFloat(index) * step + contentOffset + (step - barWidth) / 2
                            guard x <= size.width, x + barWidth >= 0 else { continue }
                            let y = (size.height - barHeight) / 2
                            let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)

                            let barProgress = (Double(index) + 0.5) / Double(sampleCount)
                            let color: Color = samples == nil
                                ? .white.opacity(0.16)
                                : (barProgress <= activeProgress
                                    ? .white.opacity(0.88)
                                    : .white.opacity(0.28))

                            var path = Path()
                            path.addRoundedRect(
                                in: rect,
                                cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
                            )
                            context.fill(path, with: .color(color))
                        }
                    }

                    // In/Out 竖线标记
                    for (pt, isIn) in [(inPoint, true), (outPoint, false)].compactMap({ p, flag -> (Double, Bool)? in
                        guard let p else { return nil }; return (p, flag)
                    }) where size.width > 0 && isVisible(pt) {
                        let x = size.width * CGFloat(localProgress(pt))
                        var line = Path()
                        line.move(to: CGPoint(x: x, y: 0))
                        line.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(line, with: .color(Color.orange.opacity(0.85)),
                                       style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        // 顶部小标签圆
                        let labelR: CGFloat = 5
                        var dot = Path()
                        dot.addEllipse(in: CGRect(x: x - labelR, y: 1, width: labelR * 2, height: labelR * 2))
                        context.fill(dot, with: .color(Color.orange.opacity(isIn ? 0.92 : 0.70)))
                    }

                    if samples != nil, size.width > 0 {
                        let headX = min(max(1, size.width * CGFloat(displayedProgress)), max(1, size.width - 1))
                        var headPath = Path()
                        headPath.addRoundedRect(
                            in: CGRect(x: headX - 1, y: 2, width: 2, height: size.height - 4),
                            cornerSize: CGSize(width: 1, height: 1)
                        )
                        context.fill(headPath, with: .color(.white.opacity(0.95)))
                    }

                    var drawnCutColumns = Set<Int>()
                    for cut in sceneCuts where size.width > 0 && isVisible(cut) {
                        let x = size.width * CGFloat(localProgress(cut))
                        let column = Int(x.rounded())
                        guard drawnCutColumns.insert(column).inserted else { continue }
                        var cutPath = Path()
                        cutPath.move(to: CGPoint(x: x, y: 5))
                        cutPath.addLine(to: CGPoint(x: x, y: size.height - 5))
                        context.stroke(
                            cutPath,
                            with: .color(Color.orange.opacity(0.80)),
                            style: StrokeStyle(lineWidth: 1.5)
                        )
                        var diamondPath = Path()
                        diamondPath.move(to: CGPoint(x: x, y: 2))
                        diamondPath.addLine(to: CGPoint(x: x + 3, y: 5))
                        diamondPath.addLine(to: CGPoint(x: x, y: 8))
                        diamondPath.addLine(to: CGPoint(x: x - 3, y: 5))
                        diamondPath.closeSubpath()
                        context.fill(diamondPath, with: .color(Color.orange.opacity(0.90)))
                    }
                }

                if panViewport != nil {
                    ScrollPanLayer(panViewport: panViewport, viewportSpan: viewportSpan)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        draftProgress = globalProgress(from: value.location, width: proxy.size.width)
                    }
                    .onEnded { value in
                        let final = globalProgress(from: value.location, width: proxy.size.width)
                        draftProgress = nil
                        isDragging = false
                        seek(final)
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        let factor = value / max(lastMagnification, 0.001)
                        lastMagnification = value
                        zoomViewport?(Double(factor), 0.5)
                    }
                    .onEnded { _ in lastMagnification = 1 }
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: 64)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous))
        .accessibilityLabel("音频波形进度条")
    }

    private func globalProgress(from location: CGPoint, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        let local = min(1, max(0, Double(location.x / width)))
        return min(1, max(0, viewportStart + local * viewportSpan))
    }

    private func localProgress(_ global: Double) -> Double {
        guard viewportSpan > 0 else { return global }
        return min(1, max(0, (global - viewportStart) / viewportSpan))
    }

    private func isVisible(_ global: Double) -> Bool {
        global >= viewportStart && global <= viewportStart + viewportSpan
    }

}

private struct CenteredWaveformTimeline: View {
    let samples: [Double]?
    let progress: Double
    let seek: (Double) -> Void
    var sceneCuts: [Double] = []
    var inPoint: Double? = nil
    var outPoint: Double? = nil
    var annotationItems: [TimelineAnnotationMarker] = []
    var onAnnotationSelect: ((UUID) -> Void)? = nil
    var onClearSelection: (() -> Void)? = nil
    var viewportSpan: Double = 1
    var playheadTint: Color = .white.opacity(0.96)
    var panViewport: ((Double) -> Void)? = nil
    var zoomViewport: ((Double, Double) -> Void)? = nil

    @State private var dragStartProgress: Double?
    @State private var draftProgress: Double?
    @State private var isHoveringSelection = false
    @State private var lastMagnification: CGFloat = 1

    private let placeholderSamples: [Double] = (0..<360).map { index in
        0.12 + 0.18 * abs(sin(Double(index) * 0.34))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Canvas { context, size in
                    let values = samples ?? placeholderSamples
                    guard !values.isEmpty, size.width > 0, size.height > 0 else { return }

                    let span = max(0.02, min(1, viewportSpan))
                    let focus = min(1, max(0, draftProgress ?? progress))
                    let centerX = size.width / 2

                    if let inPoint, let outPoint {
                        let x1 = xPosition(for: min(inPoint, outPoint), focus: focus, span: span, width: size.width)
                        let x2 = xPosition(for: max(inPoint, outPoint), focus: focus, span: span, width: size.width)
                        let rect = CGRect(
                            x: max(0, min(x1, x2)),
                            y: 0,
                            width: min(size.width, max(x1, x2)) - max(0, min(x1, x2)),
                            height: size.height
                        )
                        if rect.width > 0 {
                            context.fill(Path(rect), with: .color(Color.orange.opacity(0.14)))
                        }
                    }

                    let sampleStep = 1 / Double(values.count)
                    let visibleWidth = size.width / CGFloat(span)
                    let barWidth = max(0.65, min(1.5, visibleWidth / CGFloat(values.count) * 0.82))
                    let visibleStart = max(0, focus - span / 2)
                    let visibleEnd = min(1, focus + span / 2)
                    let firstIndex = max(0, Int(floor(visibleStart / sampleStep)) - 1)
                    let lastIndex = min(values.count - 1, Int(ceil(visibleEnd / sampleStep)) + 1)

                    if firstIndex <= lastIndex {
                        for index in firstIndex...lastIndex {
                            let value = values[index]
                            let sampleProgress = (Double(index) + 0.5) * sampleStep
                            let x = xPosition(for: sampleProgress, focus: focus, span: span, width: size.width)
                            guard x > -barWidth, x < size.width + barWidth else { continue }

                            let normalized = max(0.04, min(1, value))
                            let barHeight = CGFloat(normalized) * size.height * 0.78
                            let rect = CGRect(x: x - barWidth / 2, y: (size.height - barHeight) / 2, width: barWidth, height: barHeight)
                            var path = Path()
                            path.addRoundedRect(in: rect, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
                            let color: Color = samples == nil
                                ? .white.opacity(0.18)
                                : (sampleProgress <= focus ? .white.opacity(0.72) : .white.opacity(0.30))
                            context.fill(path, with: .color(color))
                        }
                    }

                    for cut in sceneCuts {
                        let x = xPosition(for: cut, focus: focus, span: span, width: size.width)
                        guard x >= 0, x <= size.width else { continue }
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 5))
                        path.addLine(to: CGPoint(x: x, y: size.height - 5))
                        context.stroke(path, with: .color(Color.orange.opacity(0.64)), style: StrokeStyle(lineWidth: 1.2))
                    }

                    var centerLine = Path()
                    centerLine.addRoundedRect(
                        in: CGRect(x: centerX - 1, y: 1, width: 2, height: size.height - 2),
                        cornerSize: CGSize(width: 1, height: 1)
                    )
                    context.fill(centerLine, with: .color(playheadTint))
                }

                ForEach(annotationItems) { item in
                    Button {
                        onAnnotationSelect?(item.id)
                    } label: {
                        Circle()
                            .fill(Color.orange.opacity(0.92))
                            .frame(width: 8, height: 8)
                            .overlay {
                                Circle().stroke(.black.opacity(0.36), lineWidth: 0.6)
                            }
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .offset(
                        x: xPosition(
                            for: item.progress,
                            focus: min(1, max(0, draftProgress ?? progress)),
                            span: max(0.02, min(1, viewportSpan)),
                            width: proxy.size.width
                        ) - 9,
                        y: 4
                    )
                    .opacity(isMarkerVisible(item.progress, focus: min(1, max(0, draftProgress ?? progress)), span: max(0.02, min(1, viewportSpan))) ? 1 : 0)
                    .zIndex(5)
                }

                if isHoveringSelection,
                   let onClearSelection,
                   let frame = selectionFrame(
                       focus: min(1, max(0, draftProgress ?? progress)),
                       span: max(0.02, min(1, viewportSpan)),
                       width: proxy.size.width,
                       height: proxy.size.height
                   ) {
                    Button(action: onClearSelection) {
                        Image(systemName: "trash")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 22, height: 22)
                            .background(Color.orange.opacity(0.82))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .position(x: frame.midX, y: frame.midY)
                    .help("清除声音选区")
                    .zIndex(3)
                }

                if panViewport != nil {
                    ScrollPanLayer(panViewport: panViewport, viewportSpan: viewportSpan)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    isHoveringSelection = selectionFrame(
                        focus: min(1, max(0, draftProgress ?? progress)),
                        span: max(0.02, min(1, viewportSpan)),
                        width: proxy.size.width,
                        height: proxy.size.height
                    )?.contains(location) == true
                case .ended:
                    isHoveringSelection = false
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let next = scrubProgress(for: value, width: proxy.size.width)
                        draftProgress = next
                        seek(next)
                    }
                    .onEnded { value in
                        let final = scrubProgress(for: value, width: proxy.size.width)
                        draftProgress = nil
                        dragStartProgress = nil
                        seek(final)
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        let factor = value / max(lastMagnification, 0.001)
                        lastMagnification = value
                        zoomViewport?(Double(factor), 0.5)
                    }
                    .onEnded { _ in lastMagnification = 1 }
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.7)
        }
        .accessibilityLabel("居中播放头音频波形")
    }

    private func xPosition(for sampleProgress: Double, focus: Double, span: Double, width: CGFloat) -> CGFloat {
        width / 2 + CGFloat((sampleProgress - focus) / span) * width
    }

    private func isMarkerVisible(_ sampleProgress: Double, focus: Double, span: Double) -> Bool {
        abs(sampleProgress - focus) <= span / 2
    }

    private func selectionFrame(focus: Double, span: Double, width: CGFloat, height: CGFloat) -> CGRect? {
        guard let inPoint, let outPoint, width > 0, height > 0 else { return nil }
        let x1 = xPosition(for: min(inPoint, outPoint), focus: focus, span: span, width: width)
        let x2 = xPosition(for: max(inPoint, outPoint), focus: focus, span: span, width: width)
        let minX = max(0, min(x1, x2))
        let maxX = min(width, max(x1, x2))
        guard maxX - minX >= 10 else { return nil }
        return CGRect(x: minX, y: 0, width: maxX - minX, height: height)
    }

    private func scrubProgress(for value: DragGesture.Value, width: CGFloat) -> Double {
        if dragStartProgress == nil {
            dragStartProgress = progress
        }

        let base = dragStartProgress ?? progress
        let span = max(0.02, min(1, viewportSpan))
        let next = base - Double(value.translation.width / max(width, 1)) * span
        return min(1, max(0, next))
    }
}

private final class PlayerSurfaceNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.backgroundColor = NSColor.black.cgColor
        layer = rootLayer

        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        rootLayer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

private struct PlayerSurfaceView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerSurfaceNSView {
        let view = PlayerSurfaceNSView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerSurfaceNSView, context: Context) {
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
    }

    static func dismantleNSView(_ nsView: PlayerSurfaceNSView, coordinator: ()) {
        nsView.playerLayer.player = nil
    }
}

private struct PreviewPlayerView: View {
    let player: AVPlayer
    let statusMessage: String?
    var dragItemProvider: (() -> NSItemProvider)? = nil
    var onSurfaceHold: (() -> Void)? = nil
    var onSurfaceTap: (() -> Void)? = nil

    @State private var isHoldingSurface = false

    var body: some View {
        ZStack {
            PlayerSurfaceView(player: player)
                .background(.black)

            Color.clear
                .contentShape(Rectangle())

            if let statusMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24, weight: .semibold))
                    Text(statusMessage)
                        .font(.callout.weight(.medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .foregroundStyle(.white.opacity(0.82))
                .padding(18)
                .frame(maxWidth: 360)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isHoldingSurface else { return }
                    isHoldingSurface = true
                    onSurfaceHold?()
                }
                .onEnded { value in
                    let isTap = abs(value.translation.width) < 4 && abs(value.translation.height) < 4
                    if isTap {
                        onSurfaceTap?()
                    }
                    isHoldingSurface = false
                }
        )
        .fullResolutionImageDrag(dragItemProvider)
        .help(dragItemProvider == nil ? "点击播放/暂停" : "点击播放/暂停，按住拖出当前帧")
    }
}

private struct WaveformControlBar: View {
    let samples: [Double]?
    let progress: Double
    let timecodeText: String
    let isPlaying: Bool
    let togglePlayback: () -> Void
    let seek: (Double) -> Void
    var sceneCuts: [Double] = []
    var inPoint: Double? = nil
    var outPoint: Double? = nil
    var prevScene: (() -> Void)? = nil
    var nextScene: (() -> Void)? = nil
    var stepBack: (() -> Void)? = nil
    var stepForward: (() -> Void)? = nil
    var onScreenshot: (() -> Void)? = nil
    var onAnnotate: (() -> Void)? = nil
    var viewportStart: Double = 0
    var viewportSpan: Double = 1
    var duration: Double = 0
    var zoomLevel: Double = 1
    var panViewport: ((Double) -> Void)? = nil
    var zoomViewport: ((Double, Double) -> Void)? = nil
    var resetViewport: (() -> Void)? = nil

    var body: some View {
        AudioWaveformView(
            samples: samples,
            progress: progress,
            seek: seek,
            sceneCuts: sceneCuts,
            inPoint: inPoint,
            outPoint: outPoint,
            viewportStart: viewportStart,
            viewportSpan: viewportSpan,
            duration: duration,
            panViewport: panViewport,
            zoomViewport: zoomViewport
        )
        .frame(maxWidth: .infinity)
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            navButton(icon: "backward.end.fill", help: "上一个场景", action: prevScene)
            navButton(icon: "gobackward.1", help: "后退一帧", action: stepBack)

            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "暂停" : "播放")

            navButton(icon: "goforward.1", help: "前进一帧", action: stepForward)
            navButton(icon: "forward.end.fill", help: "下一个场景", action: nextScene)

            Text(timecodeText)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.74))
                .frame(minWidth: 72, alignment: .center)

            Spacer()

            if let fn = onScreenshot {
                Button(action: fn) { Label("截图", systemImage: "camera.fill") }
                    .help("截取当前帧")
            }
            if let fn = onAnnotate {
                Button(action: fn) { Label("批注", systemImage: "text.bubble.fill") }
                    .help("添加批注")
            }
        }
        .buttonStyle(.borderless)
        .font(.caption.weight(.semibold))
    }


    @ViewBuilder
    private func navButton(icon: String, help: String, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(action == nil ? .quaternary : .secondary)
        .disabled(action == nil)
        .help(help)
    }

    private func globalProgress(from location: CGPoint, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        let local = min(1, max(0, Double(location.x / width)))
        return min(1, max(0, viewportStart + local * viewportSpan))
    }

    private func localProgress(_ global: Double) -> Double {
        guard viewportSpan > 0 else { return global }
        return min(1, max(0, (global - viewportStart) / viewportSpan))
    }

    private func localizedMarkers(_ markers: [Double]) -> [Double] {
        markers.filter(isVisible).map(localProgress)
    }

    private func isVisible(_ global: Double) -> Bool {
        global >= viewportStart && global <= viewportStart + viewportSpan
    }

    private func shouldPan(translation: CGFloat) -> Bool {
        panViewport != nil && viewportSpan < 0.999 && abs(translation) > 6
    }
}

private struct SceneCutMarkersCanvas: View {
    let sceneCuts: [Double]

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0, !sceneCuts.isEmpty else { return }

            var drawnColumns = Set<Int>()
            for cut in sceneCuts {
                let clamped = min(1, max(0, cut))
                let x = size.width * CGFloat(clamped)
                let column = Int(x.rounded())
                guard drawnColumns.insert(column).inserted else { continue }

                var line = Path()
                line.addRect(CGRect(x: x - 0.5, y: 0, width: 1, height: size.height))
                context.fill(line, with: .color(.white.opacity(0.52)))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct TimelineCaptureMarker: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "camera.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Design.captureFrameAccent)
                .frame(width: 14, height: 11)
                .background(
                    Capsule()
                        .fill(.black.opacity(0.62))
                )
                .overlay {
                    Capsule()
                        .stroke(Design.captureFrameAccent.opacity(0.72), lineWidth: 0.8)
                }

            Rectangle()
                .fill(Design.captureFrameAccent.opacity(0.92))
                .frame(width: 1.5, height: 6)
        }
        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
        .allowsHitTesting(false)
    }
}

private struct TimelineTicksCanvas: View {
    let duration: Double
    let viewportStart: Double
    let viewportSpan: Double

    var body: some View {
        Canvas { context, size in
            guard duration > 0, size.width > 0, viewportSpan > 0 else { return }

            let start = viewportStart * duration
            let visibleDuration = max(0.01, viewportSpan * duration)
            let end = min(duration, start + visibleDuration)
            let interval = tickInterval(for: visibleDuration, width: size.width)
            var tick = ceil(start / interval) * interval

            while tick <= end + 0.001 {
                let x = CGFloat((tick - start) / visibleDuration) * size.width
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: 6))
                context.stroke(line, with: .color(.white.opacity(0.42)), lineWidth: 1)

                let label = Text(clockText(tick))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.56))
                context.draw(label, at: CGPoint(x: min(max(x + 18, 18), size.width - 18), y: 13))
                tick += interval
            }
        }
        .allowsHitTesting(false)
    }

    private func tickInterval(for visibleDuration: Double, width: CGFloat) -> Double {
        let targetCount = max(2, Double(width / 92))
        let raw = visibleDuration / targetCount
        let options: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800]
        return options.first(where: { $0 >= raw }) ?? 3600
    }
}

/// 将双指水平滑动转换为时间线左右平移，同时穿透鼠标拖拽和捏合手势。
private struct ScrollPanLayer: NSViewRepresentable {
    var panViewport:  ((Double) -> Void)?
    var viewportSpan: Double

    func makeNSView(context: Context) -> PanCapture {
        let view = PanCapture()
        view.installMonitor()
        return view
    }

    func updateNSView(_ v: PanCapture, context: Context) {
        v.panViewport  = panViewport
        v.viewportSpan = viewportSpan
    }

    static func dismantleNSView(_ nsView: PanCapture, coordinator: ()) {
        nsView.removeMonitor()
    }

    final class PanCapture: NSView {
        var panViewport:  ((Double) -> Void)?
        var viewportSpan: Double = 1.0
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.processScrollWheel(event) ?? event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit {
            removeMonitor()
        }

        private func processScrollWheel(_ event: NSEvent) -> NSEvent? {
            guard event.window === window else { return event }
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else { return event }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            guard panViewport != nil, abs(dx) > abs(dy) * 0.5, abs(dx) > 0.5 else { return event }

            let fraction = -Double(dx) / Double(max(bounds.width, 1)) * viewportSpan
            panViewport?(fraction)
            return nil
        }
    }
}

private struct ViewSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}

private struct CardInlineTagChip: View {
    let tag: String

    var body: some View {
        let tint = VideoTagPalette.color(for: tag)

        Text(tag)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: VideoTagChipSize.mini.maxTextWidth, minHeight: 18, maxHeight: 18, alignment: .center)
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .background(tint.opacity(0.18))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.34), lineWidth: 0.8)
            }
    }
}

private struct ScaledCardTagCloud: View {
    let tags: [String]

    private var visibleTags: [String] {
        Array(tags.prefix(2))
    }

    private var overflowCount: Int {
        max(0, tags.count - visibleTags.count)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visibleTags, id: \.self) { tag in
                CardInlineTagChip(tag: tag)
            }

            if overflowCount > 0 {
                VideoTagOverflowChip(count: overflowCount)
                    .frame(height: 18, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

private struct HiddenScrollIndicators: NSViewRepresentable {
    final class Coordinator {
        weak var configuredScrollView: NSScrollView?
        var isLookupScheduled = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Self.configureSoon(from: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Self.configureSoon(from: nsView, coordinator: context.coordinator)
    }

    private static func configureSoon(from view: NSView, coordinator: Coordinator) {
        if configureIfAvailable(from: view, coordinator: coordinator) {
            return
        }

        guard !coordinator.isLookupScheduled else { return }
        coordinator.isLookupScheduled = true
        DispatchQueue.main.async { [weak view, weak coordinator] in
            guard let view, let coordinator else { return }
            coordinator.isLookupScheduled = false
            _ = configureIfAvailable(from: view, coordinator: coordinator)
        }
    }

    private static func configureIfAvailable(from view: NSView, coordinator: Coordinator) -> Bool {
        if let scrollView = coordinator.configuredScrollView {
            configure(scrollView)
            return true
        }

        guard let scrollView = nearestScrollView(from: view) else {
            return false
        }
        coordinator.configuredScrollView = scrollView
        configure(scrollView)
        return true
    }

    private static func nearestScrollView(from view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView {
                return scrollView
            }
            current = candidate.superview
        }
        return nil
    }

    private static func configure(_ scrollView: NSScrollView) {
        if scrollView.hasVerticalScroller {
            scrollView.hasVerticalScroller = false
        }
        if scrollView.hasHorizontalScroller {
            scrollView.hasHorizontalScroller = false
        }
        if !scrollView.autohidesScrollers {
            scrollView.autohidesScrollers = true
        }
        if scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
        }
        if scrollView.drawsBackground {
            scrollView.drawsBackground = false
        }
        if scrollView.verticalScroller?.isHidden == false {
            scrollView.verticalScroller?.isHidden = true
        }
        if scrollView.horizontalScroller?.isHidden == false {
            scrollView.horizontalScroller?.isHidden = true
        }
    }
}

private struct SceneStoryboardStrip: View {
    let images: [NSImage]
    let sceneCuts: [Double]
    let viewportStart: Double
    let viewportSpan: Double
    let activeProgress: Double
    let previewProgress: Double?

    private let segmentGap: CGFloat = 7
    private let segmentRadius: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let visibleRange = visibleSceneRange()

            ZStack(alignment: .leading) {
                if images.count == sceneCuts.count + 1,
                   viewportSpan > 0,
                   let visibleRange {
                    ForEach(Array(visibleRange), id: \.self) { index in
                        if let frame = visibleFrame(for: index, width: width) {
                            Image(nsImage: images[index])
                                .resizable()
                                .scaledToFill()
                                .frame(width: frame.width, height: height)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: segmentRadius, style: .continuous))
                                .overlay(alignment: .leading) {
                                    Rectangle()
                                        .fill(.white.opacity(0.16))
                                        .frame(width: playbackWidth(for: index, visibleFrameWidth: frame.width))
                                        .clipShape(RoundedRectangle(cornerRadius: segmentRadius, style: .continuous))
                                }
                                .overlay {
                                    if isActive(index) {
                                        CurrentFrameFocusOverlay(cornerRadius: segmentRadius)
                                    }
                                }
                                .offset(x: frame.x)
                        }
                    }
                }
            }
            .frame(width: width, height: height, alignment: .leading)
            .clipped()
        }
        .allowsHitTesting(false)
    }

    private func visibleSceneRange() -> ClosedRange<Int>? {
        let sceneCount = sceneCuts.count + 1
        guard images.count == sceneCount, sceneCount > 0, viewportSpan > 0 else { return nil }

        let start = min(1, max(0, viewportStart))
        let end = min(1, max(start, viewportStart + viewportSpan))
        guard end > start else { return nil }

        let first = min(sceneCount - 1, firstSceneIndexEnding(after: start))
        let last = min(sceneCount - 1, lastSceneIndexStarting(before: end))
        guard first <= last else { return nil }
        return first...last
    }

    private func firstSceneIndexEnding(after progress: Double) -> Int {
        var lower = 0
        var upper = sceneCuts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if cutProgress(at: middle) <= progress {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func lastSceneIndexStarting(before progress: Double) -> Int {
        var lower = 0
        var upper = sceneCuts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if cutProgress(at: middle) < progress {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func visibleFrame(for index: Int, width: CGFloat) -> (x: CGFloat, width: CGFloat)? {
        guard viewportSpan > 0, index >= 0, index < images.count else { return nil }

        let viewportStart = min(1, max(0, self.viewportStart))
        let viewportEnd = min(1, max(viewportStart, self.viewportStart + viewportSpan))
        let start = sceneStart(for: index)
        let end = sceneEnd(for: index)
        let visibleStart = max(start, viewportStart)
        let visibleEnd = min(end, viewportEnd)
        guard visibleEnd > visibleStart else { return nil }

        var x0 = CGFloat((visibleStart - viewportStart) / viewportSpan) * width
        var x1 = CGFloat((visibleEnd - viewportStart) / viewportSpan) * width
        let rawWidth = max(0, x1 - x0)

        var leadingInset: CGFloat = index > 0 && start >= viewportStart ? segmentGap / 2 : 0
        var trailingInset: CGFloat = index < images.count - 1 && end <= viewportEnd ? segmentGap / 2 : 0
        let totalInset = leadingInset + trailingInset
        if totalInset > 0 {
            let scale = min(1, max(0, (rawWidth - 2) / totalInset))
            leadingInset *= scale
            trailingInset *= scale
        }

        x0 += leadingInset
        x1 -= trailingInset
        guard x1 > x0 else { return nil }
        return (x: x0, width: x1 - x0)
    }

    private func isActive(_ index: Int) -> Bool {
        guard index >= 0, index < images.count else { return false }
        let progress = min(1, max(0, activeProgress))
        if index == images.count - 1 {
            return progress >= sceneStart(for: index) && progress <= sceneEnd(for: index)
        }
        return progress >= sceneStart(for: index) && progress < sceneEnd(for: index)
    }

    private func playbackWidth(for index: Int, visibleFrameWidth: CGFloat) -> CGFloat {
        guard index >= 0, index < images.count else { return 0 }
        let start = sceneStart(for: index)
        let end = sceneEnd(for: index)
        let isActive = index == images.count - 1
            ? activeProgress >= start && activeProgress <= end
            : activeProgress >= start && activeProgress < end
        guard isActive else { return 0 }

        let viewportStart = min(1, max(0, self.viewportStart))
        let viewportEnd = min(1, max(viewportStart, self.viewportStart + viewportSpan))
        let visibleStart = max(start, viewportStart)
        let visibleEnd = min(end, viewportEnd)
        guard visibleEnd > visibleStart, activeProgress > visibleStart else { return 0 }
        let played = min(visibleEnd, activeProgress)
        return visibleFrameWidth * CGFloat((played - visibleStart) / (visibleEnd - visibleStart))
    }

    private func sceneStart(for index: Int) -> Double {
        index <= 0 ? 0 : cutProgress(at: index - 1)
    }

    private func sceneEnd(for index: Int) -> Double {
        index < sceneCuts.count ? cutProgress(at: index) : 1
    }

    private func cutProgress(at index: Int) -> Double {
        guard sceneCuts.indices.contains(index) else { return index < 0 ? 0 : 1 }
        return min(1, max(0, sceneCuts[index]))
    }
}

private struct FrameScrubberView: View {
    let frames: [NSImage]?
    let progress: Double
    let timecodeText: String
    let sceneCuts: [Double]
    let isPlaying: Bool
    let togglePlayback: () -> Void
    let seek: (Double) -> Void
    var screenshotMarkers: [Double] = []
    var annotationItems: [TimelineAnnotationMarker] = []
    var prevScene: (() -> Void)? = nil
    var nextScene: (() -> Void)? = nil
    var stepBack: (() -> Void)? = nil
    var stepForward: (() -> Void)? = nil
    var onScreenshot: (() -> Void)? = nil
    var onAnnotate: (() -> Void)? = nil
    var onAnnotationSelect: ((UUID) -> Void)? = nil
    var viewportStart: Double = 0
    var viewportSpan: Double = 1
    var duration: Double = 0
    var zoomLevel: Double = 1
    var playheadTint: Color = .white.opacity(0.92)
    var showsPlayhead: Bool = false
    var panViewport: ((Double) -> Void)? = nil
    var zoomViewport: ((Double, Double) -> Void)? = nil
    var resetViewport: (() -> Void)? = nil
    var timelineHeight: CGFloat = 48
    /// 场景识别完成后传入：每个场景一张缩略图（index 0 = 片头帧，1…N = 各切点首帧）
    var sceneImages: [NSImage]? = nil

    @State private var draftProgress: Double?
    @State private var tappedAnnotationText: String? = nil
    @State private var showAnnotationDetail = false
    @State private var hoverProgress: Double?
    @State private var lastMagnification: CGFloat = 1

    var body: some View {
        let dp = localProgress(draftProgress ?? progress)

        VStack(spacing: 4) {
            // 行一：帧缩略图时间线
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height

                ZStack(alignment: .leading) {
                    // 优先使用场景识别缩略图（每场景宽度 ∝ 时长）
                    if let sceneImages, !sceneImages.isEmpty,
                       sceneCuts.count == sceneImages.count - 1 {
                        SceneStoryboardStrip(
                            images: sceneImages,
                            sceneCuts: sceneCuts,
                            viewportStart: viewportStart,
                            viewportSpan: viewportSpan,
                            activeProgress: draftProgress ?? progress,
                            previewProgress: hoverProgress
                        )
                    } else if let frames, !frames.isEmpty {
                        // 暂无场景识别结果时：均匀采样帧带，随 viewport 缩放/平移
                        let count   = frames.count
                        let frameW  = width / (CGFloat(viewportSpan) * CGFloat(count))
                        let originX = -CGFloat(viewportStart / viewportSpan) * width
                        let first   = max(0, Int(viewportStart * Double(count)))
                        let last    = min(count - 1, Int((viewportStart + viewportSpan) * Double(count)) + 1)
                        if first <= last {
                            ZStack(alignment: .leading) {
                                ForEach(first...last, id: \.self) { i in
                                    Image(nsImage: frames[i])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: max(1, frameW), height: height)
                                        .clipped()
                                        .offset(x: CGFloat(i) * frameW + originX)
                                }

                                Rectangle()
                                    .fill(.white.opacity(0.16))
                                    .frame(width: width * CGFloat(dp))
                            }
                            .frame(width: width, height: height, alignment: .leading)
                            .clipped()
                        }
                    } else {
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.06), location: 0),
                                .init(color: .white.opacity(0.10), location: 0.5),
                                .init(color: .white.opacity(0.06), location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }

                    if let hoverProgress, isVisible(hoverProgress) {
                        Rectangle()
                            .fill(.white.opacity(0.92))
                            .frame(width: 1, height: height)
                            .shadow(color: .black.opacity(0.35), radius: 1)
                            .offset(x: width * CGFloat(localProgress(hoverProgress)) - 0.5)
                            .allowsHitTesting(false)
                    }

                    // 批注点：可点击，显示批注文本
                    ForEach(Array(annotationItems.enumerated()), id: \.offset) { _, item in
                        Button {
                            if let onAnnotationSelect {
                                onAnnotationSelect(item.id)
                            } else {
                                tappedAnnotationText = item.text
                                showAnnotationDetail = true
                            }
                        } label: {
                            Circle()
                                .fill(annotationTint(for: item.kind).opacity(0.92))
                                .frame(width: 7, height: 7)
                                .overlay {
                                    Circle()
                                        .stroke(.black.opacity(0.35), lineWidth: 0.6)
                                }
                                .frame(width: 18, height: 18)
                        }
                    .buttonStyle(.plain)
                    .opacity(isVisible(item.progress) ? 1 : 0)
                    .offset(x: width * CGFloat(localProgress(item.progress)) - 9, y: 3)
                    .zIndex(5)
                }

                if showsPlayhead, isVisible(draftProgress ?? progress) {
                    Rectangle()
                        .fill(playheadTint)
                            .frame(width: 2, height: height)
                        .shadow(color: .black.opacity(0.35), radius: 1)
                        .offset(x: width * CGFloat(localProgress(draftProgress ?? progress)) - 1)
                        .allowsHitTesting(false)
                        .zIndex(3)
                }

                    // 双指水平滑动平移时间线（透明覆盖层，仅拦截 scroll 事件）
                    if panViewport != nil {
                        ScrollPanLayer(panViewport: panViewport, viewportSpan: viewportSpan)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous))
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(location):
                        hoverProgress = globalProgress(from: location, width: width)
                    case .ended:
                        hoverProgress = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            draftProgress = globalProgress(from: value.location, width: width)
                        }
                        .onEnded { value in
                            let final = globalProgress(from: value.location, width: width)
                            draftProgress = nil
                            seek(final)
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let factor = value / max(lastMagnification, 0.001)
                            lastMagnification = value
                            zoomViewport?(Double(factor), 0.5)
                        }
                        .onEnded { _ in lastMagnification = 1 }
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: timelineHeight)
        }
        .popover(isPresented: $showAnnotationDetail, arrowEdge: .top) {
            if let text = tappedAnnotationText {
                VStack(alignment: .leading, spacing: 6) {
                    Label("批注", systemImage: "text.bubble.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Design.annotationAccent)
                    Text(text)
                        .font(.callout)
                        .frame(maxWidth: 220)
                }
                .padding(12)
            }
        }
    }

    // 播放键居中，快退/快进紧贴两侧，工具区图标靠右，去掉缩放按钮
    private var controlRow: some View {
        ZStack {
            // 播放控制组：ZStack 默认居中 → 播放键始终在正中心
            HStack(spacing: 4) {
                navButton(icon: "backward.end.fill", help: "上一个场景", action: prevScene)
                navButton(icon: "gobackward.1",      help: "后退一帧",   action: stepBack)

                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.14))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(isPlaying ? "暂停" : "播放")

                navButton(icon: "goforward.1",      help: "前进一帧",   action: stepForward)
                navButton(icon: "forward.end.fill", help: "下一个场景", action: nextScene)
            }

            // 右侧辅助区：timecode + 图标按钮（无文字标签）
            HStack(spacing: 4) {
                Spacer()

                Text(timecodeText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.74))
                    .frame(minWidth: 60, alignment: .center)

                if let fn = onScreenshot {
                    Button(action: fn) {
                        Image(systemName: "camera.fill")
                            .frame(width: 22, height: 22)
                    }
                    .help("截取当前帧")
                }
                if let fn = onAnnotate {
                    Button(action: fn) {
                        Image(systemName: "text.bubble.fill")
                            .frame(width: 22, height: 22)
                    }
                    .help("添加批注")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .font(.caption.weight(.semibold))
    }

    @ViewBuilder
    private func navButton(icon: String, help: String, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(action == nil ? .quaternary : .secondary)
        .disabled(action == nil)
        .help(help)
    }

    private func globalProgress(from location: CGPoint, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        let local = min(1, max(0, Double(location.x / width)))
        return min(1, max(0, viewportStart + local * viewportSpan))
    }

    private func localProgress(_ global: Double) -> Double {
        guard viewportSpan > 0 else { return global }
        return min(1, max(0, (global - viewportStart) / viewportSpan))
    }

    private func localizedMarkers(_ markers: [Double]) -> [Double] {
        markers.filter(isVisible).map(localProgress)
    }

    private func isVisible(_ global: Double) -> Bool {
        global >= viewportStart && global <= viewportStart + viewportSpan
    }

    private func annotationTint(for kind: AnnotationItem.Kind) -> Color {
        switch kind {
        case .frame: return Design.captureFrameAccent
        case .audio: return .orange
        case .content: return Design.annotationAccent
        }
    }

}

private struct SimpleProgressBar: View {
    let progress: Double
    let timecodeText: String
    let isPlaying: Bool
    let togglePlayback: () -> Void
    let seek: (Double) -> Void
    var chapters: [TranscriptTimelineChapter] = []
    var duration: Double = 0
    var annotationItems: [TimelineAnnotationMarker] = []
    var onAnnotationSelect: ((UUID) -> Void)? = nil
    var playheadTint: Color = .white.opacity(0.92)
    var stepBack: (() -> Void)? = nil
    var stepForward: (() -> Void)? = nil
    var onScreenshot: (() -> Void)? = nil
    var onAnnotate: (() -> Void)? = nil

    @State private var draftProgress: Double?

    var body: some View {
        let dp = draftProgress ?? progress

        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let cornerRadius = min(Design.innerRadius, height / 2)
            let chapterSegments = normalizedChapterSegments(duration: duration)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.thinMaterial)

                if chapterSegments.isEmpty {
                    Rectangle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: max(0, width * CGFloat(dp)))
                } else {
                    let segmentGap: CGFloat = 4

                    ForEach(Array(chapterSegments.enumerated()), id: \.element.id) { index, segment in
                        let isFirst = index == chapterSegments.startIndex
                        let isLast = index == chapterSegments.index(before: chapterSegments.endIndex)
                        let leadingInset: CGFloat = isFirst ? 0 : segmentGap / 2
                        let trailingInset: CGFloat = isLast ? 0 : segmentGap / 2
                        let x = width * CGFloat(segment.start) + leadingInset
                        let segmentWidth = max(0, width * CGFloat(segment.end - segment.start) - leadingInset - trailingInset)

                        RoundedRectangle(cornerRadius: min(Design.innerRadius, height / 2), style: .continuous)
                            .fill(chapterFill(for: segment, progress: dp))
                            .overlay(alignment: .leading) {
                                if segmentWidth > 42 {
                                    Text(segment.title)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white.opacity(segmentTextOpacity(for: segment, progress: dp)))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.72)
                                        .padding(.horizontal, 7)
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: min(Design.innerRadius, height / 2), style: .continuous)
                                    .stroke(.white.opacity(segmentStrokeOpacity(for: segment, progress: dp)), lineWidth: 0.7)
                            }
                            .frame(width: segmentWidth, height: height)
                            .offset(x: x)
                    }
                }

                Rectangle()
                    .fill(playheadTint)
                    .frame(width: 2, height: height)
                    .shadow(color: .black.opacity(0.28), radius: 1)
                    .offset(x: min(max(0, width * CGFloat(dp) - 1), max(0, width - 2)))
                    .allowsHitTesting(false)
                    .zIndex(3)

                ForEach(annotationItems) { item in
                    Button {
                        onAnnotationSelect?(item.id)
                    } label: {
                        Circle()
                            .fill(annotationTint(for: item.kind).opacity(0.92))
                            .frame(width: 7, height: 7)
                            .overlay {
                                Circle().stroke(.black.opacity(0.58), lineWidth: 0.8)
                            }
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .zIndex(5)
                    .offset(
                        x: min(max(0, width * CGFloat(item.progress) - 9), max(0, width - 18)),
                        y: annotationYOffset(for: item.kind, height: height)
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 0.7)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        draftProgress = min(1, max(0, Double(value.location.x / width)))
                    }
                    .onEnded { value in
                        let final = min(1, max(0, Double(value.location.x / width)))
                        draftProgress = nil
                        seek(final)
                    }
            )
        }
        .frame(maxWidth: .infinity)
    }

    private struct ChapterSegment: Identifiable {
        let id: UUID
        let title: String
        let start: Double
        let end: Double
    }

    private func normalizedChapterSegments(duration: Double) -> [ChapterSegment] {
        let sorted = chapters.sorted { $0.start < $1.start }
        let fallbackDuration = max(duration, sorted.last?.end ?? sorted.last?.start ?? 0)
        guard fallbackDuration > 0 else { return [] }

        return sorted.enumerated().compactMap { index, chapter in
            let startTime = index == sorted.startIndex ? 0 : chapter.start
            let rawStart = min(max(0, startTime / fallbackDuration), 1)
            let nextStart = sorted.indices.contains(index + 1) ? sorted[index + 1].start : fallbackDuration
            let rawEndTime = nextStart
            let rawEnd = min(max(rawStart, rawEndTime / fallbackDuration), 1)
            guard rawEnd > rawStart else { return nil }

            return ChapterSegment(
                id: chapter.id,
                title: chapter.title,
                start: rawStart,
                end: rawEnd
            )
        }
    }

    private func chapterFill(for segment: ChapterSegment, progress: Double) -> Color {
        if progress >= segment.start, progress <= segment.end {
            return Design.annotationAccent.opacity(0.32)
        }
        return progress > segment.end ? .white.opacity(0.20) : .white.opacity(0.10)
    }

    private func segmentTextOpacity(for segment: ChapterSegment, progress: Double) -> Double {
        if progress >= segment.start, progress <= segment.end { return 0.92 }
        return progress > segment.end ? 0.72 : 0.54
    }

    private func segmentStrokeOpacity(for segment: ChapterSegment, progress: Double) -> Double {
        if progress >= segment.start, progress <= segment.end { return 0.24 }
        return 0.08
    }

    private func annotationYOffset(for kind: AnnotationItem.Kind, height: CGFloat) -> CGFloat {
        let margin: CGFloat = min(max(12, height * 0.16), max(12, height / 2))
        let topCenter = margin
        let middleCenter = height / 2
        let bottomCenter = max(margin, height - margin)
        let targetCenter: CGFloat
        switch kind {
        case .frame:
            targetCenter = topCenter
        case .audio:
            targetCenter = middleCenter
        case .content:
            targetCenter = bottomCenter
        }
        return targetCenter - height / 2
    }

    private func annotationTint(for kind: AnnotationItem.Kind) -> Color {
        .white
    }
}

private struct AppEmptyState: View {
    enum Style: Equatable {
        case large
        case compact
        case inline
    }

    let title: String
    var systemImage: String? = nil
    var description: String? = nil
    var style: Style = .compact
    var minHeight: CGFloat? = nil
    var alignment: Alignment = .center
    var textAlignment: TextAlignment = .center
    var showsBackground = false
    var fillsWidth = true

    var body: some View {
        Group {
            if style == .inline {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(2)
                    .frame(
                        maxWidth: fillsWidth ? .infinity : nil,
                        minHeight: minHeight,
                        alignment: alignment
                    )
            } else {
                VStack(spacing: spacing) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: iconSize, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }

                    Text(title)
                        .font(titleFont)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(textAlignment)

                    if let description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(textAlignment)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: minHeight ?? defaultMinHeight)
                .padding(padding)
                .background {
                    if showsBackground {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.white.opacity(backgroundOpacity))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
    }

    private var spacing: CGFloat {
        style == .large ? 10 : 7
    }

    private var iconSize: CGFloat {
        style == .large ? 34 : 18
    }

    private var titleFont: Font {
        style == .large ? .callout.weight(.medium) : .caption
    }

    private var defaultMinHeight: CGFloat {
        style == .large ? 136 : 82
    }

    private var padding: CGFloat {
        style == .large ? 12 : 7
    }

    private var cornerRadius: CGFloat {
        style == .large ? 8 : 7
    }

    private var backgroundOpacity: Double {
        style == .large ? 0.04 : 0.055
    }
}

private struct GenerationProgressRow: View {
    let message: String
    var progress: Double?
    var tint: Color = .orange
    var progressTint: Color? = nil
    var systemImage: String? = nil
    var compact = false
    var showPercent = true
    var showStepCount = true

    private var normalizedProgress: Double? {
        progress.map(normalizedProgressFraction)
    }

    private var displayMessage: String {
        guard !showStepCount else { return message }
        return message.replacingOccurrences(
            of: #"\s*[·•]\s*\d+\s*/\s*\d+\s*$"#,
            with: "",
            options: .regularExpression
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            HStack(spacing: compact ? 6 : 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                        .foregroundStyle(tint)
                }

                Text(displayMessage)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer(minLength: 6)

                if showPercent, let normalizedProgress {
                    Text(progressPercentText(normalizedProgress))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            if let normalizedProgress {
                ProgressView(value: normalizedProgress)
                    .progressViewStyle(.linear)
                    .controlSize(compact ? .mini : .small)
                    .tint(progressTint ?? tint)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(compact ? .mini : .small)
                    .tint(progressTint ?? tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecognitionProgressRow: View {
    let message: String
    var progress: Double?
    var compact = true
    var showPercent = true
    var showStepCount = true

    var body: some View {
        GenerationProgressRow(
            message: message,
            progress: progress,
            tint: .white.opacity(0.90),
            progressTint: .white.opacity(0.90),
            compact: compact,
            showPercent: showPercent,
            showStepCount: showStepCount
        )
    }
}

private func normalizedProgressFraction(_ progress: Double) -> Double {
    guard progress.isFinite else { return 0 }
    return min(1, max(0, progress))
}

private func progressPercentText(_ progress: Double) -> String {
    "\(Int((normalizedProgressFraction(progress) * 100).rounded()))%"
}

private func activityProgressValue(from message: String) -> Double? {
    let normalized = message.replacingOccurrences(of: "％", with: "%")

    if let percentRange = normalized.range(of: "%", options: .backwards) {
        let prefix = normalized[..<percentRange.lowerBound]
        let chars = Array(prefix)
        var start = chars.count

        while start > 0 {
            let char = chars[start - 1]
            if char.isNumber || char == "." {
                start -= 1
            } else {
                break
            }
        }

        if start < chars.count,
           let value = Double(String(chars[start...])) {
            return normalizedProgressFraction(value / 100)
        }
    }

    if let fractionRange = normalized.range(
        of: #"(?<!\d)(\d+)\s*/\s*(\d+)(?!\d)"#,
        options: .regularExpression
    ) {
        let fractionText = normalized[fractionRange]
        let parts = fractionText
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count == 2,
           let current = Double(parts[0]),
           let total = Double(parts[1]),
           total > 0 {
            return normalizedProgressFraction(current / total)
        }
    }

    return nil
}

private struct SceneCutTile: View {
    let thumbnailImage: NSImage?
    let timeLabel: String
    var isExported = false
    var isScreenshot = false
    var isSelected = false
    var isActive = false
    let onTap: () -> Void
    var onCollect: (() -> Void)?
    var onDelete: (() -> Void)?
    var dragItemProvider: (() -> NSItemProvider)?

    @State private var isHovered = false
    @State private var isMorePresented = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                ZStack(alignment: .bottomTrailing) {
                    if let thumbnailImage {
                        Image(nsImage: thumbnailImage)
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFill()
                    } else {
                        Color.white.opacity(0.08)
                    }

                    CardTimeBadge(text: timeLabel, placeholder: timeLabel)
                        .padding(.trailing, CardTimeBadge.edgeInset)
                        .padding(.bottom, CardTimeBadge.verticalInset)

                    if isScreenshot {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Design.captureFrameAccent)
                            .padding(6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .aspectRatio(thumbnailAspectRatio, contentMode: .fit)
                .clipShape(tileShape)
                .overlay {
                    tileShape
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                }
            }
            .buttonStyle(.plain)

            if let onCollect, !isScreenshot, !isExported {
                collectButton(onCollect: onCollect)
                    .opacity(isHovered ? 1 : 0)
                    .allowsHitTesting(isHovered)
                    .animation(.easeInOut(duration: 0.12), value: isHovered)
                    .padding(6)
            }

            if isScreenshot, let onDelete {
                moreButton(onDelete: onDelete)
                    .opacity(isHovered || isMorePresented ? 1 : 0)
                    .allowsHitTesting(isHovered || isMorePresented)
                    .animation(.easeInOut(duration: 0.12), value: isHovered)
                    .padding(6)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fullResolutionImageDrag(dragItemProvider)
    }

    private var thumbnailAspectRatio: CGFloat {
        guard let size = thumbnailImage?.size,
              size.width > 0,
              size.height > 0
        else { return 16 / 9 }
        return size.width / size.height
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    private var overlayControlShape: some Shape {
        RoundedRectangle(cornerRadius: Design.innerRadius, style: .continuous)
    }

    private func collectButton(onCollect: @escaping () -> Void) -> some View {
        Button(action: onCollect) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 24, height: 24)
                .background(.black.opacity(0.48))
                .clipShape(overlayControlShape)
                .overlay {
                    overlayControlShape
                        .stroke(.white.opacity(0.12), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .help("加入画面收藏")
    }

    private func moreButton(onDelete: @escaping () -> Void) -> some View {
        Button {
            isMorePresented.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.black.opacity(0.48))
                .clipShape(overlayControlShape)
                .overlay {
                    overlayControlShape
                        .stroke(.white.opacity(0.12), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("更多")
        .popover(isPresented: $isMorePresented, arrowEdge: .trailing) {
            Button(role: .destructive) {
                onDelete()
                isMorePresented = false
            } label: {
                Label("删除截图", systemImage: "trash")
                    .frame(minWidth: 96, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
    }

    private var borderColor: Color {
        if isActive { return Design.currentFrameAccent.opacity(0.98) }
        if isSelected { return .white.opacity(0.46) }
        if isExported || isScreenshot { return Design.captureFrameAccent.opacity(0.92) }
        return .white.opacity(0.10)
    }

    private var borderWidth: CGFloat {
        if isActive { return 2 }
        if isSelected { return 1.2 }
        return isExported ? 1.7 : 1
    }
}

private struct CaptureFrameBadge: View {
    var body: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Design.captureFrameAccent)
            .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
    }
}

private struct CurrentFrameFocusOverlay: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .inset(by: 0.75)
            .strokeBorder(Design.currentFrameAccent.opacity(0.98), lineWidth: 2)
        .allowsHitTesting(false)
    }
}

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @AppStorage("mediaGridSize") private var mediaGridSize = 1
    @AppStorage("appWorkspace") private var appWorkspaceRawValue = AppWorkspace.home.rawValue
    @AppStorage("isSidebarCollapsed") private var isSidebarCollapsed = false
    @State private var mediaPanelWidth = UserDefaults.standard.object(forKey: "mediaPanelWidth") as? Double ?? 340.0
    @State private var frameMediaPanelWidth = UserDefaults.standard.object(forKey: "frameMediaPanelWidth") as? Double
    @State private var renamingTag: String? = nil
    @State private var renameInput = ""
    @State private var isImportSheetPresented = false
    @State private var isSettingsSheetPresented = false
    @State private var importURLText = ""
    @State private var importEndpointText = ""
    @State private var isInstagramSavedSyncing = false
    @State private var instagramSavedSyncMessage: String?
    @State private var instagramSavedSyncIsError = false
    @State private var isXiaohongshuSavedSyncing = false
    @State private var xiaohongshuSavedSyncMessage: String?
    @State private var xiaohongshuSavedSyncIsError = false
    @State private var observedPasteboardChangeCount = NSPasteboard.general.changeCount
    @State private var isImportDropTargeted = false
    @State private var isTagFilterMenuPresented = false
    @State private var frameFilterVideoPath: String?
    @State private var frameSelectedFrameID: UUID?
    @State private var mediaPanelDragStartWidth: Double?
    @State private var mediaPanelDragStartX: CGFloat?
    @State private var isDividerHovered = false
    @State private var canRestorePersistedWorkspace = false

    private var appWorkspace: AppWorkspace {
        get {
            let stored = AppWorkspace(rawValue: appWorkspaceRawValue) ?? .home
            return stored.canRestoreFromUserDefaults ? stored : .home
        }
        nonmutating set {
            canRestorePersistedWorkspace = true
            appWorkspaceRawValue = newValue.rawValue
        }
    }

    private var presentedAppWorkspace: AppWorkspace {
        canRestorePersistedWorkspace ? appWorkspace : .home
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 900

            ZStack {
                backgroundGradient

                mainLayout(isCompact: isCompact, containerWidth: proxy.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(Design.windowInset)

                if isImportSheetPresented {
                    importOverlay(containerSize: proxy.size)
                }

                if isSettingsSheetPresented {
                    settingsOverlay(containerSize: proxy.size)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(WindowConfigurator())
        .frame(minWidth: Design.minimumWindowWidth, minHeight: Design.minimumWindowHeight)
        .onDrop(
            of: Self.importDropTypeIdentifiers,
            isTargeted: $isImportDropTargeted,
            perform: handleImportDrop
        )
        .onReceive(Self.clipboardProbeTimer) { _ in
            handleClipboardChangeIfNeeded()
        }
        .alert("重命名标签", isPresented: Binding(
            get: { renamingTag != nil },
            set: { if !$0 { renamingTag = nil } }
        )) {
            TextField("新标签名", text: $renameInput)
            Button("确认") {
                if let old = renamingTag {
                    libraryStore.renameGlobalTag(old, to: renameInput)
                }
                renamingTag = nil
            }
            Button("取消", role: .cancel) { renamingTag = nil }
        } message: {
            Text("重命名后，所有含此标签的视频都会同步更新")
        }
        .onAppear(perform: restorePersistedWorkspaceAfterFirstFrame)
    }

    private static let clipboardProbeTimer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()
    private static let importDropTypeIdentifiers = [
        UTType.url.identifier,
        UTType.plainText.identifier,
        UTType.text.identifier,
        UTType.utf8PlainText.identifier,
        UTType.html.identifier
    ]

    private var backgroundGradient: some View {
        Design.contentBg.ignoresSafeArea()
    }

    private func restorePersistedWorkspaceAfterFirstFrame() {
        guard !canRestorePersistedWorkspace else { return }
        let storedRawValue = UserDefaults.standard.string(forKey: "appWorkspace") ?? AppWorkspace.home.rawValue
        let stored = AppWorkspace(rawValue: storedRawValue) ?? .home
        guard stored.canRestoreDuringLaunch else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            canRestorePersistedWorkspace = true
        }
    }

    @ViewBuilder
    private func mainLayout(isCompact: Bool, containerWidth: CGFloat) -> some View {
        let activeMediaPanelWidth = resolvedMediaPanelWidth(containerWidth: containerWidth)

        HStack(spacing: Design.panelSpacing) {
            if presentedAppWorkspace == .audio || presentedAppWorkspace == .frames || presentedAppWorkspace == .music {
                navigationRail
                    .frame(width: Design.railWidth, alignment: .leading)
                    .background(Design.sidebarBg)
                    .zIndex(1)

                workspaceView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Design.sidebarBg)
            } else if isCompact {
                VStack(spacing: Design.panelSpacing) {
                    libraryColumn(isCompact: true)
                        .frame(maxWidth: .infinity, maxHeight: 280)

                    workspaceView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        libraryColumn(isCompact: false)
                            .frame(width: activeMediaPanelWidth)

                        workspaceView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Design.contentBg)
                    }

                    mediaPanelDivider(containerWidth: containerWidth)
                        .frame(maxHeight: .infinity)
                        .offset(x: activeMediaPanelWidth - 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func resolvedMediaPanelWidth(containerWidth: CGFloat) -> CGFloat {
        if presentedAppWorkspace == .frames {
            let defaultWidth = containerWidth * 0.5
            return clampedMediaPanelWidth(frameMediaPanelWidth ?? defaultWidth, containerWidth: containerWidth)
        }
        return clampedMediaPanelWidth(mediaPanelWidth, containerWidth: containerWidth)
    }

    private func clampedMediaPanelWidth(_ width: Double, containerWidth: CGFloat) -> CGFloat {
        clampedMediaPanelWidth(CGFloat(width), containerWidth: containerWidth)
    }

    private func clampedMediaPanelWidth(_ width: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let minimumSidebarWidth: CGFloat = 320
        let maximumSidebarWidth: CGFloat = presentedAppWorkspace == .frames
            ? max(minimumSidebarWidth, containerWidth - 260)
            : 660
        return min(maximumSidebarWidth, max(minimumSidebarWidth, width))
    }

    private func libraryColumn(isCompact: Bool) -> some View {
        HStack(spacing: 0) {
            navigationRail
                .frame(width: Design.railWidth, alignment: .leading)
                .zIndex(1)

            if presentedAppWorkspace == .frames {
                frameVideoFilterColumn(isCompact: isCompact)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                videoGrid(isCompact: isCompact, framed: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Design.sidebarBg)
    }

    private var navigationRail: some View {
        VStack(spacing: 0) {
            // 顶部窗口按键与素材库工具栏共用同一条视觉中心线。
            ZStack(alignment: .topLeading) {
                Design.sidebarBg
                    .frame(
                        width: Design.trafficLightGuideX + Design.trafficLightClusterWidth,
                        height: Design.railTopChromeHeight
                    )

                WindowDragRegion()
                    .frame(
                        width: Design.trafficLightGuideX + Design.trafficLightClusterWidth,
                        height: Design.railTopChromeHeight
                    )

                windowControls
                    .position(
                        x: Design.trafficLightGuideX + Design.trafficLightClusterWidth / 2,
                        y: Design.trafficLightGuideY + Design.trafficLightSize / 2
                    )
            }
            .frame(width: Design.railWidth, height: Design.railTopChromeHeight)

            VStack(spacing: 8) {
                ForEach(AppWorkspace.allCases) { workspace in
                    navigationRailButton(workspace)
                }
            }
            .padding(.top, 14)

            Spacer()
        }
        .padding(.bottom, 12)
    }

    private func navigationRailButton(_ workspace: AppWorkspace) -> some View {
        let isSelected = workspace == .settings ? isSettingsSheetPresented : presentedAppWorkspace == workspace
        let selectionWidth = Design.railWidth - Design.railIconInset * 2

        return Button {
            if workspace == .settings {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                    isSettingsSheetPresented = true
                }
            } else {
                appWorkspace = workspace
            }
        } label: {
            ZStack(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(0.10))
                        .frame(width: selectionWidth, height: Design.railButtonHeight)
                        .offset(x: Design.railSelectionGuideX)
                }

                Image(systemName: workspace.icon)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.88) : Color.white.opacity(0.40))
                    .frame(width: Design.railIconBoxSize, height: Design.railIconBoxSize)
                    .offset(x: workspace.railIconOffset)
                    .frame(width: Design.railWidth, height: Design.railButtonHeight)
                    .offset(x: Design.railButtonVisualOffsetX)
            }
            .frame(width: Design.railWidth, height: Design.railButtonHeight, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help(workspace.title)
    }

    private func mediaPanelDivider(containerWidth: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(isDividerHovered ? 0.18 : 0))
                .frame(width: 1)
                .animation(.easeInOut(duration: 0.12), value: isDividerHovered)

            ResizeLeftRightCursorView()
        }
        .frame(width: 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isDividerHovered = hovering
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if mediaPanelDragStartWidth == nil {
                        mediaPanelDragStartWidth = resolvedMediaPanelWidth(containerWidth: containerWidth)
                        mediaPanelDragStartX = value.startLocation.x
                    }
                    let delta = value.location.x - (mediaPanelDragStartX ?? value.startLocation.x)
                    let nextWidth = clampedMediaPanelWidth(
                        (mediaPanelDragStartWidth ?? resolvedMediaPanelWidth(containerWidth: containerWidth)) + delta,
                        containerWidth: containerWidth
                    )
                    if presentedAppWorkspace == .frames {
                        frameMediaPanelWidth = nextWidth
                    } else {
                        mediaPanelWidth = nextWidth
                    }
                }
                .onEnded { _ in
                    if presentedAppWorkspace == .frames {
                        UserDefaults.standard.set(frameMediaPanelWidth, forKey: "frameMediaPanelWidth")
                    } else {
                        UserDefaults.standard.set(mediaPanelWidth, forKey: "mediaPanelWidth")
                    }
                    mediaPanelDragStartWidth = nil
                    mediaPanelDragStartX = nil
                }
        )
        .help("拖动调整素材库和预览区比例")
    }

    @ViewBuilder
    private var workspaceView: some View {
        switch presentedAppWorkspace {
        case .home:
            PreviewPanelView(openWorkspace: { appWorkspace = $0 })
        case .frames:
            FramesWorkspaceView(
                selectedVideoPath: $frameFilterVideoPath,
                selectedFrameID: $frameSelectedFrameID,
                goHome: jumpToVideo
            )
        case .audio:
            AudioWorkspaceView(goHome: jumpToVideo)
        case .music:
            MusicWorkspaceView(goHome: jumpToVideo)
        case .content:
            ContentWorkspaceView(goHome: jumpToVideo)
        case .settings:
            SettingsWorkspaceView()
        }
    }

    private func jumpToVideo(path: String, time: Double) {
        libraryStore.selectVideo(path: path)
        appWorkspace = .home
        NotificationCenter.default.post(
            name: .lapianBaoSeekRequest,
            object: nil,
            userInfo: ["path": path, "time": time]
        )
    }

    private var windowControls: some View {
        NativeWindowTrafficLights(buttonSize: Design.trafficLightSize, buttonGap: Design.trafficLightGap)
            .frame(width: Design.trafficLightClusterWidth, height: Design.trafficLightSize)
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            WindowDragRegion()
                .frame(height: isSidebarCollapsed ? 44 : 56)
                .padding(.leading, isSidebarCollapsed ? 48 : 88)
                .padding(.trailing, 12)

            windowControls
                .padding(.leading, isSidebarCollapsed ? 7 : 9)
                .padding(.top, isSidebarCollapsed ? 14 : 7)

            sidebarContent
                .padding(.top, isSidebarCollapsed ? 56 : 88)
                .padding(.bottom, 18)
        }
        .frame(maxHeight: .infinity)
        .glassPanel()
    }

    private var sidebarContent: some View {
        VStack(alignment: isSidebarCollapsed ? .center : .leading, spacing: isSidebarCollapsed ? 4 : 0) {
            if isSidebarCollapsed {
                sidebarCollapseButton
                    .padding(.bottom, 12)
            } else {
                HStack {
                    Text("拉片宝")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    sidebarCollapseButton
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            if !isSidebarCollapsed {
                sidebarSectionLabel("工作区")
            }

            ForEach(AppWorkspace.allCases) { workspace in
                sidebarItem(
                    icon: workspace.icon,
                    label: workspace.title,
                    isSelected: presentedAppWorkspace == workspace
                ) {
                    appWorkspace = workspace
                }
            }

            Spacer()

            if !isSidebarCollapsed {
                Text("\(libraryStore.videos.count) 个视频")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }
        }
    }

    private var sidebarCollapseButton: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                isSidebarCollapsed.toggle()
            }
        } label: {
            Image(systemName: isSidebarCollapsed ? "sidebar.left" : "sidebar.leading")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(isSidebarCollapsed ? .white.opacity(0.06) : .clear)
                }
        }
        .buttonStyle(.plain)
        .help(isSidebarCollapsed ? "展开侧边栏" : "收起侧边栏")
    }

    @ViewBuilder
    private func sidebarSectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 4)
    }

    private func sidebarItem(
        icon: String,
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isSidebarCollapsed {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .frame(width: 36, height: 32)
                } else {
                    HStack(spacing: 9) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    Text(label)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
            }
            .frame(maxWidth: isSidebarCollapsed ? 40 : .infinity, alignment: isSidebarCollapsed ? .center : .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous)
                        .fill(.white.opacity(isSidebarCollapsed ? 0.12 : 0.10))
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, isSidebarCollapsed ? 8 : 4)
        .padding(.vertical, isSidebarCollapsed ? 1 : 0)
    }

    private var videosWithCollectedFrames: [VideoItem] {
        libraryStore.videos.filter { !libraryStore.sampledFrames(for: $0).isEmpty }
    }

    @ViewBuilder
    private func frameVideoFilterColumn(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Spacer(minLength: 4)

                HStack(spacing: 8) {
                    frameAllButton
                }
            }
            .frame(minHeight: 22)
            .padding(.horizontal, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(videosWithCollectedFrames) { video in
                        frameFilterVideoRow(video)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 14)
            }
            .scrollIndicators(.hidden)
            .background(HiddenScrollIndicators())
            .overlay {
                if videosWithCollectedFrames.isEmpty {
                    AppEmptyState(
                        title: "暂无已收集画面",
                        systemImage: "photo.on.rectangle",
                        description: "在主页截图后，这里会出现对应视频。",
                        style: .compact,
                        minHeight: 116
                    )
                    .padding(14)
                }
            }
        }
        .padding(.top, Design.libraryToolbarTop)
        .padding(.bottom, 14)
    }

    private var frameAllButton: some View {
        Button {
            frameFilterVideoPath = nil
            frameSelectedFrameID = libraryStore.collectedFrames.first?.id
        } label: {
            Image(systemName: frameFilterVideoPath == nil ? "photo.on.rectangle.angled.fill" : "photo.on.rectangle.angled")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 22)
                .overlay(alignment: .topTrailing) {
                    if !libraryStore.collectedFrames.isEmpty {
                        Text("\(libraryStore.collectedFrames.count)")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .clipShape(Capsule())
                            .offset(x: 5, y: -4)
                    }
                }
        }
        .buttonStyle(.borderless)
        .help("全部画面")
    }

    private func frameFilterVideoRow(_ video: VideoItem) -> some View {
        let frames = libraryStore.sampledFrames(for: video)

        return HStack(alignment: .top, spacing: 8) {
            LibraryVideoTile(
                video: video,
                displayName: videoDisplayName(for: video),
                thumbnailImage: thumbnailImage(for: video),
                durationText: durationTextIfReady(for: video),
                sourcePlatform: sourcePlatformName(for: video),
                tags: libraryStore.tagsByVideoPath[video.url.path, default: []],
                suggestedTags: libraryStore.allTags,
                analysisItems: analysisMenuItems(for: video),
                isSelected: frameFilterVideoPath == video.url.path,
                onSelect: {
                    frameFilterVideoPath = video.url.path
                    frameSelectedFrameID = frames.first?.id
                },
                onAddTag: { tag in
                    libraryStore.addTag(tag, to: video)
                },
                onRemoveTag: { tag in
                    libraryStore.removeTag(tag, from: video)
                },
                onRunAnalysis: { kind in
                    runAnalysis(kind, for: video)
                },
                onDeleteAnalysis: { kind in
                    deleteAnalysis(kind, for: video)
                },
                onDelete: {
                    libraryStore.removeVideo(video)
                },
                dragItemProvider: { videoDragItemProvider(for: video) }
            )
            .equatable()
            .frame(width: 122)
            .help("筛选这个视频的画面")

            framePreviewColumn(frames)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(7)
        .background(frameFilterVideoPath == video.url.path ? .white.opacity(0.055) : .white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(frameFilterVideoPath == video.url.path ? 0.12 : 0.05), lineWidth: 0.7)
        }
    }

    private func framePreviewColumn(_ frames: [SampledFrame]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 5)], spacing: 5) {
            ForEach(frames.prefix(12)) { frame in
                Button {
                    frameFilterVideoPath = frame.videoPath
                    frameSelectedFrameID = frame.id
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        if let image = libraryStore.thumbnailImage(for: frame) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.black.opacity(0.26)
                        }

                        if frame.kind == .screenshot {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundStyle(Design.captureFrameAccent)
                                .shadow(color: .black.opacity(0.55), radius: 1)
                                .padding(3)
                        }
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(
                                frameSelectedFrameID == frame.id
                                    ? .white.opacity(0.42)
                                    : .white.opacity(0.08),
                                lineWidth: frameSelectedFrameID == frame.id ? 1.1 : 0.7
                            )
                    }
                }
                .buttonStyle(.plain)
                .fullResolutionImageDrag {
                    libraryStore.fullResolutionFrameProvider(for: frame)
                }
                .help("\(frame.videoName) · \(clockText(frame.time))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func videoGrid(isCompact: Bool, framed: Bool = true) -> some View {
        let columns = libraryGridColumns

        let content = VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Spacer(minLength: 4)

                HStack(spacing: Design.libraryToolbarButtonGap) {
                    importButton
                    tagFilterMenu
                    sortMenu
                }
                .frame(height: Design.libraryToolbarButtonSlotHeight)

                gridSizeControl
            }
            .frame(minHeight: 22)
            .padding(.horizontal, 14)

            ScrollView {
                Group {
                    if libraryStore.sortOption == .importDate {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(importDateVideoSections) { section in
                                VStack(alignment: .leading, spacing: 0) {
                                    dateDivider(section.title)

                                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                                        ForEach(section.videos) { video in
                                            videoTile(video)
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                            ForEach(libraryStore.filteredVideos) { video in
                                videoTile(video)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                .padding(.horizontal, 14)
            }
            .scrollIndicators(.hidden)
            .background(HiddenScrollIndicators())
        }
        .padding(.top, Design.libraryToolbarTop)
        .padding(.bottom, 14)

        if framed {
            content.contentPanel()
        } else {
            content
        }
    }

    private var libraryGridColumns: [GridItem] {
        let count = max(1, 3 - min(max(mediaGridSize, 0), 2))
        return Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10),
            count: count
        )
    }

    private var importDateVideoSections: [VideoDateSection] {
        var sections: [VideoDateSection] = []
        for video in libraryStore.filteredVideos {
            let section = importDateSection(for: video)
            if sections.last?.id == section.id {
                sections[sections.count - 1].videos.append(video)
            } else {
                sections.append(VideoDateSection(id: section.id, title: section.title, videos: [video]))
            }
        }
        return sections
    }

    private func importDateSection(for video: VideoItem) -> (id: String, title: String) {
        guard let date = libraryStore.metadataByVideoPath[video.url.path]?.createdAt else {
            return ("unknown", "日期未知")
        }
        let startOfDay = Calendar.current.startOfDay(for: date)
        let id = String(Int(startOfDay.timeIntervalSince1970))
        let title = DateFormatter.localizedString(from: startOfDay, dateStyle: .medium, timeStyle: .none)
        return (id, title)
    }

    private func dateDivider(_ title: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 10)
    }

    private var importButton: some View {
        Button {
            importEndpointText = libraryStore.instagramImportEndpoint
            autoFillClipboardURL()
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                isImportSheetPresented = true
            }
        } label: {
            libraryToolbarIcon(systemName: "arrow.down.circle", size: 13)
        }
        .buttonStyle(.plain)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
        .contentShape(Rectangle())
        .help("下载视频")
    }

    private var tagFilterMenu: some View {
        Button {
            isTagFilterMenuPresented.toggle()
        } label: {
            libraryToolbarIcon(systemName: libraryStore.selectedTags.isEmpty ? "tag" : "tag.fill", size: 12)
                .overlay(alignment: .topTrailing) {
                    if !libraryStore.selectedTags.isEmpty {
                        Text("\(libraryStore.selectedTags.count)")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -3)
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
        .contentShape(Rectangle())
        .help("标签筛选")
        .popover(isPresented: $isTagFilterMenuPresented, arrowEdge: .bottom) {
            tagFilterPopover
        }
    }

    private var tagFilterPopover: some View {
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("标签筛选")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("全部") {
                    libraryStore.selectedTags.removeAll()
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .disabled(libraryStore.selectedTags.isEmpty)
            }

            if libraryStore.allTags.isEmpty {
                AppEmptyState(title: "暂无标签", style: .inline, alignment: .leading)
                    .frame(minHeight: 36)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(libraryStore.allTags, id: \.self) { tag in
                            HStack(spacing: 7) {
                                Button {
                                    libraryStore.toggleTagSelection(tag)
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: libraryStore.selectedTags.contains(tag) ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(libraryStore.selectedTags.contains(tag) ? Color.orange : .secondary)
                                            .frame(width: 15)
                                        VideoTagColorDot(tag: tag)
                                        Text(tag)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    renamingTag = tag
                                    renameInput = tag
                                } label: {
                                    Image(systemName: "pencil")
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)
                                .help("重命名标签")

                                Button(role: .destructive) {
                                    libraryStore.removeGlobalTag(tag)
                                } label: {
                                    Image(systemName: "trash")
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)
                                .help("从所有视频中删除")
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(libraryStore.selectedTags.contains(tag) ? Color.white.opacity(0.08) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 260)
                .scrollIndicators(.hidden)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private var sortMenu: some View {
        Menu {
            Section("排序方式") {
                ForEach(VideoSortOption.allCases) { option in
                    Button {
                        libraryStore.setSort(option: option)
                    } label: {
                        Label(option.title, systemImage: libraryStore.sortOption == option ? "checkmark" : "")
                    }
                }
            }

            Section("方向") {
                ForEach(VideoSortDirection.allCases) { direction in
                    Button {
                        libraryStore.setSort(direction: direction)
                    } label: {
                        Label(direction.title, systemImage: libraryStore.sortDirection == direction ? "checkmark" : direction.systemImage)
                    }
                }
            }
        } label: {
            libraryToolbarIcon(systemName: "arrow.up.arrow.down", size: 12, opticalOffsetX: 3.5)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
        .help("排序")
    }

    private func libraryToolbarIcon(systemName: String, size: CGFloat, opticalOffsetX: CGFloat = 0) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Design.libraryToolbarIconTint)
            .frame(
                width: Design.libraryToolbarButtonSlotWidth,
                height: Design.libraryToolbarButtonSlotHeight,
                alignment: .center
            )
            .offset(x: opticalOffsetX)
    }

    private var importTile: some View {
        Button {
            importEndpointText = libraryStore.instagramImportEndpoint
            autoFillClipboardURL()
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                isImportSheetPresented = true
            }
        } label: {
            ZStack {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(.white.opacity(0.03))
            .contentShape(RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous)
                    .stroke(.white.opacity(0.09), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .buttonStyle(.plain)
    }

    private func autoFillClipboardURL() {
        guard
            let clip = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !clip.isEmpty
        else { return }
        pasteImportURLs(Self.supportedImportURLs(from: clip))
    }

    private func handleClipboardChangeIfNeeded() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != observedPasteboardChangeCount else { return }
        observedPasteboardChangeCount = changeCount

        guard
            let clip = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !clip.isEmpty
        else { return }

        let urls = Self.supportedImportURLs(from: clip)
        guard !urls.isEmpty else { return }

        openImportPanel(with: urls)
    }

    private func handleImportDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        Task {
            let urls = await Self.supportedImportURLs(from: providers)
            guard !urls.isEmpty else { return }
            await MainActor.run {
                openImportPanel(with: urls)
            }
        }
        return true
    }

    private func openImportPanel(with urls: [String]) {
        guard !urls.isEmpty else { return }

        pasteImportURLs(urls)
        importEndpointText = libraryStore.instagramImportEndpoint
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            isImportSheetPresented = true
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func pasteImportURLs(_ urls: [String]) {
        guard !urls.isEmpty else { return }

        var merged = importURLTokens
        for url in urls where !merged.contains(url) {
            merged.append(url)
        }
        importURLText = merged.joined(separator: "\n")
    }

    private static func supportedImportURLs(from text: String) -> [String] {
        var seen = Set<String>()
        var urls: [String] = []

        func appendIfSupported(_ rawValue: String) {
            let trimmed = sanitizedURLString(rawValue)
            guard
                !trimmed.isEmpty,
                let url = URL(string: trimmed),
                LibraryStore.platformName(for: url) != nil,
                seen.insert(trimmed).inserted
            else { return }
            urls.append(trimmed)
        }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            detector.enumerateMatches(in: text, options: [], range: nsRange) { match, _, _ in
                if let url = match?.url?.absoluteString {
                    appendIfSupported(url)
                }
            }
        }

        let pattern = #"https?://[^\s<>"'，。、“”‘’（）()【】\[\]{}]+"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: nsRange) {
                guard let range = Range(match.range, in: text) else { continue }
                appendIfSupported(String(text[range]))
            }
        }

        return urls
    }

    private static func supportedImportURLs(from providers: [NSItemProvider]) async -> [String] {
        var seen = Set<String>()
        var urls: [String] = []

        func append(_ candidates: [String]) {
            for candidate in candidates where seen.insert(candidate).inserted {
                urls.append(candidate)
            }
        }

        for provider in providers {
            if let text = await itemProviderString(provider, for: UTType.url.identifier) {
                append(supportedImportURLs(from: text))
            }
            if let text = await itemProviderString(provider, for: UTType.plainText.identifier) {
                append(supportedImportURLs(from: text))
            }
            if let text = await itemProviderString(provider, for: UTType.text.identifier) {
                append(supportedImportURLs(from: text))
            }
            if let text = await itemProviderString(provider, for: UTType.utf8PlainText.identifier) {
                append(supportedImportURLs(from: text))
            }
            if let text = await itemProviderString(provider, for: UTType.html.identifier) {
                append(supportedImportURLs(from: text))
            }
        }

        return urls
    }

    private static func itemProviderString(_ provider: NSItemProvider, for typeIdentifier: String) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else { return nil }

        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let string = item as? String {
                    continuation.resume(returning: string)
                } else if let url = item as? URL {
                    continuation.resume(returning: url.absoluteString)
                } else if let url = item as? NSURL {
                    continuation.resume(returning: url.absoluteString)
                } else if let data = item as? Data {
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func sanitizedURLString(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?，。；：！？、)]}）】》>\"'“”‘’"))
    }

    private func importOverlay(containerSize: CGSize) -> some View {
        let panelWidth = max(560, min(containerSize.width - 48, 980))
        let panelHeight = max(430, min(containerSize.height - 56, 720))

        return ZStack {
            Color.black.opacity(0.44)
                .ignoresSafeArea()
                .onTapGesture {
                    closeImportPanel()
                }

            importSheet
                .frame(width: panelWidth, height: panelHeight)
                .background(Design.sidebarBg)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.38), radius: 28, y: 18)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
        }
        .zIndex(20)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }

    private func settingsOverlay(containerSize: CGSize) -> some View {
        let panelWidth = max(560, min(containerSize.width - 48, 980))
        let panelHeight = max(430, min(containerSize.height - 56, 720))

        return ZStack {
            Color.black.opacity(0.44)
                .ignoresSafeArea()
                .onTapGesture {
                    closeSettingsPanel()
                }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Label("设置", systemImage: "gearshape")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Button {
                        closeSettingsPanel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    .help("关闭")
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)

                SettingsWorkspaceView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: panelWidth, height: panelHeight)
            .background(Design.sidebarBg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.38), radius: 28, y: 18)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .zIndex(21)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }

    private func closeSettingsPanel() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            isSettingsSheetPresented = false
        }
    }

    private var importSheet: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let isNarrow = proxy.size.width < 760

                if isNarrow {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            importInputSection
                            activeDownloadsSection
                            importHistorySection
                        }
                        .padding(18)
                    }
                    .scrollIndicators(.hidden)
                    .background(HiddenScrollIndicators())
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 14) {
                            importInputSection
                            activeDownloadsSection
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                        VStack(alignment: .leading, spacing: 14) {
                            importHistorySection
                        }
                        .frame(width: min(360, proxy.size.width * 0.38), alignment: .top)
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .padding(18)
                }
            }
        }
    }

    private var importInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("链接输入", systemImage: "link")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !importURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("清空") {
                        importURLText = ""
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $importURLText)
                    .font(.body)
                    .frame(minHeight: 138, maxHeight: 190)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    }

                if importURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("每行一个链接，支持 Instagram、YouTube、小红书、Bilibili、抖音…")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(14)
                        .allowsHitTesting(false)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Button {
                        syncLatestInstagramSaved()
                    } label: {
                        Label(
                            isInstagramSavedSyncing ? "同步中" : "同步 IG 收藏前 10 条",
                            systemImage: "bookmark.fill"
                        )
                        .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isInstagramSavedSyncing || libraryStore.libraryURL == nil)
                    .help("从已登录的 Google Chrome 读取 Instagram 收藏页链接")

                    Button {
                        syncLatestXiaohongshuSavedVideos()
                    } label: {
                        Label(
                            isXiaohongshuSavedSyncing ? "同步中" : "同步小红书视频前 10 条",
                            systemImage: "play.rectangle.fill"
                        )
                        .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isXiaohongshuSavedSyncing || libraryStore.libraryURL == nil)
                    .help("从已登录的 Google Chrome 读取小红书收藏页里的视频笔记链接")

                    Spacer(minLength: 0)
                }

                if let instagramSavedSyncMessage {
                    Text(instagramSavedSyncMessage)
                        .font(.caption)
                        .foregroundStyle(instagramSavedSyncIsError ? Color.red.opacity(0.86) : .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let xiaohongshuSavedSyncMessage {
                    Text(xiaohongshuSavedSyncMessage)
                        .font(.caption)
                        .foregroundStyle(xiaohongshuSavedSyncIsError ? Color.red.opacity(0.86) : .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                if !importURLTokens.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: platformIconName)
                            .font(.caption)
                            .foregroundStyle(VideoSourcePlatform.color(for: detectedImportPlatform))
                        Text(detectedImportPlatformSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .allowsTightening(true)
                    }
                    .layoutPriority(1)
                }

                Spacer(minLength: 10)

                Button {
                    startRemoteImport()
                } label: {
                    Label(isImporting ? "继续添加" : "加入队列", systemImage: "arrow.down.circle.fill")
                        .fontWeight(.semibold)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(importURLTokens.isEmpty)

                Button {
                    closeImportPanel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("关闭")
            }
        }
        .padding(16)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var activeDownloadsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("下载进度", systemImage: "arrow.down.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(importProgressSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if activeImportJobs.isEmpty {
                AppEmptyState(
                    title: "暂无进行中的下载",
                    systemImage: "checkmark.circle",
                    style: .compact
                )
                    .frame(maxWidth: .infinity, minHeight: 132)
            } else {
                if let progress = activeImportOverallProgress {
                    importLinearProgress(progress, tint: Color(red: 0.36, green: 0.70, blue: 1.00))
                } else {
                    importIndeterminateProgress(tint: Color(red: 0.36, green: 0.70, blue: 1.00))
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(activeImportJobs) { job in
                            importJobStatus(job)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .background(HiddenScrollIndicators())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var importHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("下载记录", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if importHistoryJobs.isEmpty {
                AppEmptyState(
                    title: "暂无记录",
                    systemImage: "tray",
                    style: .compact
                )
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(importHistoryJobs) { job in
                            importJobStatus(job)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .background(HiddenScrollIndicators())

                Button {
                    libraryStore.clearFinishedRemoteImports()
                } label: {
                    Label("一键清空下载记录", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private func closeImportPanel() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            isImportSheetPresented = false
        }
    }

    private func startRemoteImport() {
        let text = importURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !importURLTokens.isEmpty else { return }
        libraryStore.saveInstagramImportEndpoint(importEndpointText)
        libraryStore.importRemoteVideos(from: text)
        importURLText = ""
    }

    private func syncLatestInstagramSaved() {
        guard !isInstagramSavedSyncing else { return }

        isInstagramSavedSyncing = true
        instagramSavedSyncIsError = false
        instagramSavedSyncMessage = "正在读取 Chrome 收藏页..."

        Task { @MainActor in
            defer { isInstagramSavedSyncing = false }

            do {
                let result = try await libraryStore.importLatestInstagramSavedFromChrome(limit: 10)
                instagramSavedSyncIsError = false
                instagramSavedSyncMessage = instagramSavedSyncStatusText(result)
            } catch {
                instagramSavedSyncIsError = true
                instagramSavedSyncMessage = error.localizedDescription
            }
        }
    }

    private func syncLatestXiaohongshuSavedVideos() {
        guard !isXiaohongshuSavedSyncing else { return }

        isXiaohongshuSavedSyncing = true
        xiaohongshuSavedSyncIsError = false
        xiaohongshuSavedSyncMessage = "正在读取 Chrome 小红书收藏页..."

        Task { @MainActor in
            defer { isXiaohongshuSavedSyncing = false }

            do {
                let result = try await libraryStore.importLatestXiaohongshuSavedVideosFromChrome(limit: 10)
                xiaohongshuSavedSyncIsError = false
                xiaohongshuSavedSyncMessage = xiaohongshuSavedSyncStatusText(result)
            } catch {
                xiaohongshuSavedSyncIsError = true
                xiaohongshuSavedSyncMessage = error.localizedDescription
            }
        }
    }

    private func instagramSavedSyncStatusText(_ result: InstagramSavedImportResult) -> String {
        if result.queuedCount > 0 {
            return "发现 \(result.foundCount) 条，新加入 \(result.queuedCount) 条"
        }
        if result.skippedCount > 0 {
            return "发现 \(result.foundCount) 条，均已在库中"
        }
        return "没有新的收藏链接"
    }

    private func xiaohongshuSavedSyncStatusText(_ result: InstagramSavedImportResult) -> String {
        if result.queuedCount > 0 {
            return "发现 \(result.foundCount) 条视频，新加入 \(result.queuedCount) 条"
        }
        if result.skippedCount > 0 {
            return "发现 \(result.foundCount) 条视频，均已在库中"
        }
        return "没有新的视频收藏链接"
    }

    private var detectedImportPlatform: String {
        guard
            let firstLink = importURLTokens.first,
            let url = URL(string: firstLink),
            let platform = LibraryStore.platformName(for: url)
        else { return "等待识别平台" }
        return platform
    }

    private var platformIconName: String {
        VideoSourcePlatform.iconName(for: detectedImportPlatform)
    }

    private var detectedImportPlatformSummary: String {
        let platforms = importURLTokens
            .compactMap { URL(string: $0) }
            .compactMap { LibraryStore.platformName(for: $0) }
        let unique = Array(Set(platforms)).sorted()
        guard !unique.isEmpty else { return "等待识别平台" }
        if unique.count == 1 { return "\(unique[0]) · \(platforms.count) 个链接" }
        return "\(unique.joined(separator: " / ")) · \(platforms.count) 个链接"
    }

    private var importURLTokens: [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",，"))
        return importURLText
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
    }

    private func sourcePlatformName(for video: VideoItem) -> String? {
        guard let platform = libraryStore.videoSourcePlatform(for: video) else { return nil }
        return VideoSourcePlatform.matching(platform)?.rawValue ?? platform
    }

    private func videoDisplayName(for video: VideoItem) -> String {
        libraryStore.videoSourceTitle(for: video) ?? video.name
    }

    private var isImporting: Bool {
        !activeImportJobs.isEmpty
    }

    private var activeImportJobs: [RemoteImportJob] {
        libraryStore.remoteImportJobs.filter(isActiveImportJob)
    }

    private var importHistoryJobs: [RemoteImportJob] {
        Array(libraryStore.remoteImportJobs.filter(isImportHistoryJob).reversed())
    }

    private var finishedImportCount: Int {
        libraryStore.remoteImportJobs.filter { job in
            if case .succeeded = job.status { return true }
            return false
        }.count
    }

    private var failedImportCount: Int {
        libraryStore.remoteImportJobs.filter { job in
            if case .failed = job.status { return true }
            return false
        }.count
    }

    private var importProgressSummary: String {
        guard !activeImportJobs.isEmpty else {
            return libraryStore.remoteImportJobs.isEmpty ? "等待添加下载链接" : "下载任务已完成"
        }

        let progress = activeImportOverallProgress
        guard let progress else { return "\(activeImportJobs.count) 个任务进行中 · 等待准确进度" }
        return "\(activeImportJobs.count) 个任务进行中 · 可追踪 \(progressPercentText(progress))"
    }

    private var activeImportOverallProgress: Double? {
        guard !activeImportJobs.isEmpty else { return nil }
        let progressValues = activeImportJobs.compactMap { job in
            job.downloadProgress.map(normalizedProgressFraction)
        }
        guard progressValues.count == activeImportJobs.count else { return nil }
        return progressValues.reduce(0, +) / Double(progressValues.count)
    }

    private func isActiveImportJob(_ job: RemoteImportJob) -> Bool {
        switch job.status {
        case .importing, .transcoding, .finalizing, .paused:
            return true
        default:
            return false
        }
    }

    private func isImportHistoryJob(_ job: RemoteImportJob) -> Bool {
        switch job.status {
        case .succeeded, .failed:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private func importJobStatus(_ job: RemoteImportJob) -> some View {
        if isImportHistoryJob(job) {
            importHistoryJobStatus(job)
        } else {
            importActiveJobStatus(job)
        }
    }

    private func importActiveJobStatus(_ job: RemoteImportJob) -> some View {
        HStack(alignment: .top, spacing: 12) {
            importJobCover(for: job, width: 100, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(importActiveStatusText(for: job))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 18)

                Text(job.sourceURL.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(height: 16)

                importStatusDetail(for: job)
                    .frame(height: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)

            importJobActions(for: job)
                .frame(height: 56, alignment: .top)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 10)
        .frame(minHeight: 76)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private func importActiveStatusText(for job: RemoteImportJob) -> String {
        switch job.status {
        case .idle:
            return "等待下载"
        case .importing:
            guard let progressText = importStatusProgressText(for: job) else {
                return "正在处理下载任务 · 等待准确进度"
            }
            return "正在下载 \(job.platform) · \(progressText)"
        case .transcoding:
            guard let progressText = importStatusProgressText(for: job) else {
                return "正在转码 · 等待 ffmpeg 返回进度"
            }
            return "正在转码 · \(progressText)"
        case .finalizing:
            guard let progressText = importStatusProgressText(for: job) else {
                return "正在整理导入结果"
            }
            return "正在整理导入结果 · \(progressText)"
        case .paused:
            if let progressText = importStatusProgressText(for: job) {
                return "\(job.platform) 已暂停 · \(progressText)"
            }
            return "\(job.platform) 已暂停"
        case let .succeeded(filename):
            return filename
        case .failed:
            return "\(job.platform) 下载失败"
        }
    }

    private func importHistoryJobStatus(_ job: RemoteImportJob) -> some View {
        HStack(alignment: .top, spacing: 12) {
            importJobCover(for: job, width: 100, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(importStatusTitle(for: job))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(job.sourceURL.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                if case let .failed(message) = job.status {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.96, green: 0.58, blue: 0.24))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)

            if let video = importedVideo(for: job) {
                InlineTagEditorButton(
                    title: "视频标签",
                    tags: libraryStore.tagsByVideoPath[video.url.path, default: []],
                    suggestedTags: libraryStore.allTags,
                    onAdd: { libraryStore.addTag($0, to: video) },
                    onRemove: { libraryStore.removeTag($0, from: video) }
                )
                .frame(height: 56, alignment: .top)
            }

            importJobActions(for: job)
                .frame(height: 56, alignment: .top)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 10)
        .frame(minHeight: 76)
        .background(.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 0.8)
        }
    }

    private func importJobCover(for job: RemoteImportJob, width: CGFloat = 76, height: CGFloat = 52) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.06))

            if let image = importJobThumbnail(for: job) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: importStatusIconName(for: job))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(importStatusTint(for: job))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func importJobThumbnail(for job: RemoteImportJob) -> NSImage? {
        if let outputPath = job.outputPath,
           let image = libraryStore.thumbnailImageByVideoPath[outputPath] {
            return image
        }
        if let data = job.thumbnailData {
            return NSImage(data: data)
        }
        return nil
    }

    private func importedVideo(for job: RemoteImportJob) -> VideoItem? {
        guard let outputPath = job.outputPath else { return nil }
        return libraryStore.selectedVideo(for: outputPath)
    }

    @ViewBuilder
    private func importJobActions(for job: RemoteImportJob) -> some View {
        VStack(spacing: 4) {
            if case .paused = job.status {
                importJobActionButton(icon: "play.fill", help: "继续下载") {
                    libraryStore.resumeRemoteImportJob(id: job.id)
                }
            } else if isActiveImportJob(job) {
                importJobActionButton(icon: "pause.fill", help: "暂停下载") {
                    libraryStore.pauseRemoteImportJob(id: job.id)
                }
            } else if job.outputPath != nil {
                importJobActionButton(icon: "arrow.turn.up.right", help: "跳转到视频") {
                    libraryStore.jumpToRemoteImportJob(id: job.id)
                    closeImportPanel()
                }
            }

            importJobActionButton(icon: "trash", help: "删除条目") {
                libraryStore.deleteRemoteImportJob(id: job.id)
            }
        }
        .frame(width: 30)
    }

    private func importJobActionButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func importStatusTitle(for job: RemoteImportJob) -> String {
        switch job.status {
        case .idle:
            return "等待下载"
        case .importing:
            return "正在下载 \(job.platform)"
        case .transcoding:
            return "正在转码为 H.264"
        case .finalizing:
            return "正在整理导入结果"
        case .paused:
            return "\(job.platform) 已暂停"
        case let .succeeded(filename):
            return filename
        case .failed:
            return "\(job.platform) 下载失败"
        }
    }

    private func importStatusIconName(for job: RemoteImportJob) -> String {
        switch job.status {
        case .idle:
            return "clock"
        case .importing:
            return "arrow.down.circle.fill"
        case .transcoding:
            return "film.circle.fill"
        case .finalizing:
            return "checkmark.seal.fill"
        case .paused:
            return "pause.circle.fill"
        case .succeeded:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private func importStatusTint(for job: RemoteImportJob) -> Color {
        switch job.status {
        case .idle:
            return .secondary
        case .importing:
            return Color(red: 0.36, green: 0.70, blue: 1.00)
        case .transcoding:
            return Design.captureFrameAccent
        case .finalizing:
            return Color(red: 0.42, green: 0.78, blue: 0.48)
        case .paused:
            return .secondary
        case .succeeded:
            return Color(red: 0.42, green: 0.78, blue: 0.48)
        case .failed:
            return Color(red: 0.96, green: 0.58, blue: 0.24)
        }
    }

    private func importStatusProgressText(for job: RemoteImportJob) -> String? {
        switch job.status {
        case .importing, .paused, .succeeded:
            guard let progress = job.downloadProgress else { return nil }
            if case .importing = job.status,
               let speed = job.downloadSpeed,
               !speed.isEmpty {
                return "\(progressPercentText(progress)) · \(speed)"
            }
            return progressPercentText(progress)
        case .transcoding, .finalizing:
            guard let progress = job.downloadProgress else { return nil }
            return progressPercentText(progress)
        default:
            return nil
        }
    }

    @ViewBuilder
    private func importStatusDetail(for job: RemoteImportJob) -> some View {
        switch job.status {
        case .idle:
            EmptyView()
        case .paused:
            if let progress = job.downloadProgress {
                importLinearProgress(progress, tint: .secondary)
            } else {
                EmptyView()
            }
        case .importing:
            if let progress = job.downloadProgress {
                importLinearProgress(progress, tint: Color(red: 0.36, green: 0.70, blue: 1.00))
            } else {
                importIndeterminateProgress(tint: Color(red: 0.36, green: 0.70, blue: 1.00))
            }
        case .transcoding:
            if let progress = job.downloadProgress {
                importLinearProgress(progress, tint: Design.captureFrameAccent)
            } else {
                importIndeterminateProgress(tint: Design.captureFrameAccent)
            }
        case .finalizing:
            if let progress = job.downloadProgress {
                importLinearProgress(progress, tint: Color(red: 0.42, green: 0.78, blue: 0.48))
            } else {
                importIndeterminateProgress(tint: Color(red: 0.42, green: 0.78, blue: 0.48))
            }
        case .succeeded:
            EmptyView()
        case let .failed(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(Color(red: 0.96, green: 0.58, blue: 0.24))
                .lineLimit(4)
                .textSelection(.enabled)
        }
    }

    private func importLinearProgress(_ progress: Double, tint: Color) -> some View {
        ProgressView(value: normalizedProgressFraction(progress))
            .progressViewStyle(.linear)
            .controlSize(.small)
            .tint(tint)
            .transaction { transaction in
                transaction.animation = nil
            }
    }

    private func importIndeterminateProgress(tint: Color) -> some View {
        ProgressView()
            .progressViewStyle(.linear)
            .controlSize(.small)
            .tint(tint)
    }

    private var gridSizeControl: some View {
        HStack(spacing: 5) {
            Image(systemName: "square.grid.3x3")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { Double(mediaGridSize) },
                    set: {
                        let nextSize = Int($0.rounded())
                        if mediaGridSize != nextSize {
                            mediaGridSize = nextSize
                        }
                    }
                ),
                in: 0...2
            )
            .frame(width: 56)
            .controlSize(.small)
            .help("素材视图密度")

            Image(systemName: "rectangle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func videoTile(_ video: VideoItem) -> some View {
        let path = video.url.path
        let isSelected = libraryStore.selectedVideo == video

        return LibraryVideoTile(
            video: video,
            displayName: videoDisplayName(for: video),
            thumbnailImage: thumbnailImage(for: video),
            durationText: durationTextIfReady(for: video),
            sourcePlatform: sourcePlatformName(for: video),
            tags: libraryStore.tagsByVideoPath[path, default: []],
            suggestedTags: libraryStore.allTags,
            analysisItems: analysisMenuItems(for: video),
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
            onRunAnalysis: { kind in
                runAnalysis(kind, for: video)
            },
            onDeleteAnalysis: { kind in
                deleteAnalysis(kind, for: video)
            },
            onDelete: {
                libraryStore.removeVideo(video)
            },
            dragItemProvider: { videoDragItemProvider(for: video) }
        )
        .equatable()
        .onAppear {
            libraryStore.loadMetadataIfNeeded(for: video)
        }
    }

    private func thumbnailImage(for video: VideoItem) -> NSImage? {
        libraryStore.thumbnailImageByVideoPath[video.url.path]
    }

    private func durationTextIfReady(for video: VideoItem) -> String? {
        guard let duration = libraryStore.durationByVideoPath[video.url.path] else { return nil }
        return formatDuration(duration)
    }

    private func analysisMenuItems(for video: VideoItem) -> [VideoAnalysisMenuItem] {
        let path = video.url.path
        let transcriptSegments = libraryStore.transcriptSegmentsByVideoPath[path, default: []]
        let transcriptStatus = libraryStore.transcriptStatusByVideoPath[path] ?? .idle
        let sceneCuts = libraryStore.sceneCutsByVideoPath[path]
        let sceneProgress = libraryStore.sceneDetectionProgress[path]
        let musics = libraryStore.musicsByVideoPath[path, default: []]
        let musicStatus = libraryStore.musicDetectionStatusByVideoPath[path] ?? .idle

        return [
            VideoAnalysisMenuItem(
                kind: .transcript,
                title: "内容",
                icon: "text.bubble",
                detail: transcriptSegments.isEmpty ? "暂无字幕" : "\(transcriptSegments.count) 段字幕",
                status: menuStatusText(transcriptStatus, idleText: "空闲"),
                tone: menuTone(transcriptStatus),
                canRun: !isRunning(transcriptStatus),
                canDelete: !transcriptSegments.isEmpty || transcriptStatus != .idle
            ),
            VideoAnalysisMenuItem(
                kind: .scene,
                title: "画面",
                icon: "rectangle.on.rectangle",
                detail: sceneCuts.map { "\($0.count) 个剪辑点" } ?? "暂无场景",
                status: sceneProgress.map { "分析中 \(progressPercentText($0))" } ?? (sceneCuts == nil ? "空闲" : "已完成"),
                tone: sceneProgress == nil ? (sceneCuts == nil ? .idle : .completed) : .running,
                canRun: sceneProgress == nil,
                canDelete: sceneCuts != nil || sceneProgress != nil
            ),
            VideoAnalysisMenuItem(
                kind: .music,
                title: "声音",
                icon: "music.note.list",
                detail: musics.isEmpty ? "暂无音乐" : "\(musics.count) 首音乐",
                status: menuStatusText(musicStatus, idleText: "空闲"),
                tone: menuTone(musicStatus),
                canRun: !isRunning(musicStatus),
                canDelete: !musics.isEmpty || musicStatus != .idle
            )
        ]
    }

    private func runAnalysis(_ kind: VideoAnalysisKind, for video: VideoItem) {
        switch kind {
        case .transcript:
            libraryStore.transcribe(video: video)
        case .scene:
            libraryStore.detectSceneCuts(for: video)
        case .music:
            libraryStore.detectMusic(for: video)
        }
    }

    private func deleteAnalysis(_ kind: VideoAnalysisKind, for video: VideoItem) {
        switch kind {
        case .transcript:
            libraryStore.deleteTranscript(for: video)
        case .scene:
            libraryStore.deleteSceneRecognition(for: video)
        case .music:
            libraryStore.deleteMusicRecognition(for: video)
        }
    }

    private func menuStatusText(_ status: TranscriptJobStatus, idleText: String) -> String {
        switch status {
        case .idle:
            return idleText
        case .running(let message):
            return message
        case .completed:
            return "已完成"
        case .failed(let message):
            return message.isEmpty ? "失败" : message
        }
    }

    private func menuTone(_ status: TranscriptJobStatus) -> VideoAnalysisTone {
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

    private func isRunning(_ status: TranscriptJobStatus) -> Bool {
        if case .running = status {
            return true
        }
        return false
    }

    private func formatDuration(_ seconds: Double) -> String {
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

private enum VideoAnalysisKind: String, CaseIterable, Equatable {
    case transcript
    case scene
    case music
}

private enum VideoAnalysisTone: Equatable {
    case idle
    case running
    case completed
    case failed

    var color: Color {
        switch self {
        case .idle:
            return .secondary
        case .running:
            return Color(red: 0.36, green: 0.70, blue: 1.00)
        case .completed:
            return Color(red: 0.42, green: 0.78, blue: 0.48)
        case .failed:
            return Color(red: 0.96, green: 0.58, blue: 0.24)
        }
    }
}

private struct VideoAnalysisMenuItem: Identifiable, Equatable {
    var kind: VideoAnalysisKind
    var title: String
    var icon: String
    var detail: String
    var status: String
    var tone: VideoAnalysisTone
    var canRun: Bool
    var canDelete: Bool

    var id: VideoAnalysisKind { kind }
}

private struct LibraryVideoTile: View, Equatable {
    let video: VideoItem
    let displayName: String
    let thumbnailImage: NSImage?
    let durationText: String?
    let sourcePlatform: String?
    let tags: [String]
    let suggestedTags: [String]
    let analysisItems: [VideoAnalysisMenuItem]
    let isSelected: Bool
    let onSelect: () -> Void
    let onAddTag: (String) -> Void
    let onRemoveTag: (String) -> Void
    let onRunAnalysis: (VideoAnalysisKind) -> Void
    let onDeleteAnalysis: (VideoAnalysisKind) -> Void
    let onDelete: () -> Void
    let dragItemProvider: (() -> NSItemProvider)?

    @State private var isHovered = false
    @State private var isMorePresented = false
    @State private var draftTag = ""

    private let cardAspectRatio: CGFloat = 1.06
    private let infoBarMinHeight: CGFloat = 48
    private let infoBarMaxHeight: CGFloat = 64

    static func == (lhs: LibraryVideoTile, rhs: LibraryVideoTile) -> Bool {
        lhs.video == rhs.video
            && lhs.displayName == rhs.displayName
            && lhs.durationText == rhs.durationText
            && lhs.sourcePlatform == rhs.sourcePlatform
            && lhs.tags == rhs.tags
            && lhs.suggestedTags == rhs.suggestedTags
            && lhs.analysisItems == rhs.analysisItems
            && lhs.isSelected == rhs.isSelected
            && sameImage(lhs.thumbnailImage, rhs.thumbnailImage)
            // Action closures are intentionally not compared.
    }

    var body: some View {
        Button(action: onSelect) {
            tileSurface
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            moreButton
                .opacity(isHovered || isMorePresented ? 1 : 0)
                .allowsHitTesting(isHovered || isMorePresented)
                .animation(.easeInOut(duration: 0.12), value: isHovered)
                .padding(6)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .onChange(of: isMorePresented) { _, presented in
            if !presented {
                draftTag = ""
            }
        }
        .itemProviderDrag(dragItemProvider)
    }

    private var tileSurface: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let height = max(1, proxy.size.height)
            let metrics = tileMetrics(width: width, height: height)
            let infoHeight = metrics.infoHeight
            let thumbnailHeight = max(1, height - infoHeight)

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    thumbnailPanel
                        .frame(width: width, height: thumbnailHeight)
                        .clipped()
                    infoBar(metrics: metrics)
                        .frame(width: width, height: infoHeight, alignment: .topLeading)
                        .background(Color.white.opacity(isSelected ? 0.090 : 0.052))
                }

                CardTimeBadge(text: durationText, placeholder: "--:--")
                    .offset(
                        x: width - CardTimeBadge.width - CardTimeBadge.edgeInset,
                        y: max(
                            CardTimeBadge.edgeInset,
                            thumbnailHeight - CardTimeBadge.height - CardTimeBadge.verticalInset
                        )
                    )

                if let sourcePlatform {
                    sourcePlatformIconBadge(sourcePlatform)
                        .offset(
                            x: CardTimeBadge.edgeInset,
                            y: max(
                                CardTimeBadge.edgeInset,
                                thumbnailHeight - SourcePlatformIconBadge.size - CardTimeBadge.verticalInset
                            )
                        )
                }
            }
        }
        .aspectRatio(cardAspectRatio, contentMode: .fit)
        .background(Color.white.opacity(isSelected ? 0.085 : 0.045))
        .contentShape(RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous)
                .stroke(isSelected ? .white.opacity(0.42) : .white.opacity(0.10), lineWidth: isSelected ? 1.5 : 1)
        }
        .shadow(color: .black.opacity(0.32), radius: 6, y: 3)
    }

    private struct TileMetrics {
        let infoHeight: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let titleFontSize: CGFloat
        let titleLineHeight: CGFloat
    }

    private func tileMetrics(width: CGFloat, height: CGFloat) -> TileMetrics {
        let compactness = min(1, max(0, (width - 118) / 140))
        let infoRatio = 0.31 - compactness * 0.03
        let infoHeight = min(infoBarMaxHeight, max(infoBarMinHeight, height * infoRatio))
        let titleLineHeight = min(17, max(15, infoHeight * 0.27))
        let titleBlockHeight = titleLineHeight * 2
        let verticalPadding = max(6, (infoHeight - titleBlockHeight) / 2)

        return TileMetrics(
            infoHeight: infoHeight,
            horizontalPadding: min(10, max(7, width * 0.07)),
            verticalPadding: verticalPadding,
            titleFontSize: min(13, max(11, width * 0.095)),
            titleLineHeight: titleLineHeight
        )
    }

    private var thumbnailPanel: some View {
        ZStack {
            if let thumbnailImage {
                Image(nsImage: thumbnailImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black.opacity(0.32)
                Image(systemName: "play.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func infoBar(metrics: TileMetrics) -> some View {
        Text(displayName)
            .font(.system(size: metrics.titleFontSize, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .truncationMode(.tail)
            .lineSpacing(1)
            .frame(
                maxWidth: .infinity,
                minHeight: metrics.titleLineHeight * 2,
                maxHeight: metrics.titleLineHeight * 2,
                alignment: .leading
            )
            .clipped()
            .layoutPriority(1)
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func sourcePlatformIconBadge(_ platform: String) -> some View {
        SourcePlatformIconBadge(platform: platform)
            .help(platform)
    }

    private var moreButton: some View {
        Button {
            isMorePresented.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isMorePresented, arrowEdge: .trailing) {
            morePopover
                .transaction { $0.animation = nil }
        }
    }

    private var morePopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标签区
            VStack(alignment: .leading, spacing: 8) {
                tagChips

                TagSuggestionGrid(currentTags: tags, suggestedTags: suggestedTags, onAdd: onAddTag)

                HStack(spacing: 6) {
                    TextField("添加标签", text: $draftTag)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addDraftTag)

                    Button(action: addDraftTag) {
                        Image(systemName: "plus")
                    }
                    .disabled(draftTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(14)

            Divider()

            analysisManagementSection

            Divider()

            // 操作区
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    isMorePresented = false
                    NSWorkspace.shared.activateFileViewerSelecting([video.url])
                } label: {
                    Label("在 Finder 中显示", systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    isMorePresented = false
                    onDelete()
                } label: {
                    Label("从素材库删除", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
            .padding(.vertical, 6)
        }
        .frame(minWidth: 220)
    }

    private var analysisManagementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("分析管理")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(analysisItems) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(item.tone.color)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(item.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text(item.status)
                            .font(.caption2)
                            .foregroundStyle(item.tone.color)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        onRunAnalysis(item.kind)
                    } label: {
                        Image(systemName: item.tone == .idle ? "play.fill" : "arrow.clockwise")
                            .font(.system(size: 10.5, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!item.canRun)
                    .help(item.tone == .idle ? "开始识别" : "重新识别")

                    Button(role: .destructive) {
                        onDeleteAnalysis(item.kind)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10.5, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!item.canDelete)
                    .help("删除识别记录")
                }
                .padding(.vertical, 3)
            }
        }
        .padding(14)
    }

    private var tagChips: some View {
        Group {
            if tags.isEmpty {
                AppEmptyState(
                    title: "暂无标签",
                    style: .inline,
                    alignment: .leading
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            VideoTagChip(tag: tag, size: .regular) {
                                onRemoveTag(tag)
                            }
                        }
                    }
                }
            }
        }
        .frame(minHeight: tags.isEmpty ? 18 : nil)
    }

    private func addDraftTag() {
        let tag = draftTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        onAddTag(tag)
        draftTag = ""
    }

    private static func sameImage(_ lhs: NSImage?, _ rhs: NSImage?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (left?, right?):
            return left === right
        default:
            return false
        }
    }
}

private struct CardTimeBadge: View {
    static let edgeInset: CGFloat = 10
    static let verticalInset: CGFloat = 5
    static let width: CGFloat = 64
    static let height: CGFloat = 18

    let text: String?
    var placeholder = "--:--"

    var body: some View {
        Text(text ?? placeholder)
            .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(text == nil ? 0.62 : 0.92))
            .shadow(color: .black.opacity(0.72), radius: 2.4, x: 0, y: 1)
            .shadow(color: .black.opacity(0.38), radius: 7, x: 0, y: 2)
            .lineLimit(1)
            .minimumScaleFactor(0.84)
            .allowsTightening(true)
            .frame(width: Self.width, height: Self.height, alignment: .trailing)
    }
}


// MARK: - ScenePanelView
private struct SceneGridItem: Identifiable {
    let id: String
    let time: Double
    let endTime: Double
    let cut: SceneCut?
    let sample: SampledFrame?
    let thumbnailImage: NSImage?
    let sceneIndex: Int?
}

/// Equatable 视图：只有视频、场景数据或选中状态变化时才重新渲染 body。
/// 播放时钟只驱动时间线小组件；PreviewPanelView 的低频重渲
/// 将相同的播放状态传给本视图，
/// .equatable() 比较相等 → body 完全跳过，场景网格不参与渲染循环。
private struct ScenePanelView: View, Equatable {
    let video: VideoItem
    let controller: PreviewController
    let sceneCuts: [SceneCut]
    let hasSceneRecognitionResult: Bool
    let sceneDetectionProgress: Double?
    let sceneThumbnailVersion: Int
    let sceneThumbnailsNeedHydration: Bool
    let isHydratingSceneThumbnails: Bool
    let sampledFrames: [SampledFrame]
    var activeItemID: String?
    @EnvironmentObject private var libraryStore: LibraryStore
    @AppStorage("sceneGridSize") private var sceneGridSize = 1
    @State private var selectedItemID: String?

    static func == (lhs: ScenePanelView, rhs: ScenePanelView) -> Bool {
        lhs.video == rhs.video
            && lhs.controller === rhs.controller
            && lhs.activeItemID == rhs.activeItemID
            && lhs.hasSceneRecognitionResult == rhs.hasSceneRecognitionResult
            && lhs.sceneDetectionProgress == rhs.sceneDetectionProgress
            && lhs.sceneThumbnailVersion == rhs.sceneThumbnailVersion
            && lhs.sceneThumbnailsNeedHydration == rhs.sceneThumbnailsNeedHydration
            && lhs.isHydratingSceneThumbnails == rhs.isHydratingSceneThumbnails
            && lhs.sceneCutSignature == rhs.sceneCutSignature
            && lhs.sampledFrameSignature == rhs.sampledFrameSignature
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
                                        onTap: {
                                            selectedItemID = item.id
                                            controller.seekToSeconds(item.time)
                                        },
                                        onCollect: collectAction(for: item),
                                        onDelete: deleteAction(for: item),
                                        dragItemProvider: dragProvider(for: item)
                                    )
                                    .id(item.id)
                                }
                            }
                            .padding(.bottom, 48)
                        }
                        .scrollIndicators(.hidden)
                        .background(HiddenScrollIndicators())

                        sceneGridSizeControl
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
            || isHydratingSceneThumbnails
            || (!hasSceneRecognitionResult && !sceneThumbnailsNeedHydration)
            || (hasSceneRecognitionResult && sceneCuts.isEmpty)
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
                message: "正在识别场景...",
                progress: progress
            )
        } else if isHydratingSceneThumbnails {
            RecognitionProgressRow(
                message: "正在补齐场景缩略图...",
                progress: nil,
                showPercent: false
            )
        } else if !hasSceneRecognitionResult {
            RecognitionProgressRow(
                message: "准备识别场景...",
                progress: nil,
                showPercent: false
            )
        } else if sceneCuts.isEmpty {
            AppEmptyState(
                title: centered ? "未识别到场景切点" : "未识别到场景切点，已有截图会继续保留",
                systemImage: centered ? "checkmark.circle" : nil,
                style: centered ? .compact : .inline,
                minHeight: centered ? 92 : nil,
                alignment: centered ? .center : .leading,
                textAlignment: centered ? .center : .leading,
                fillsWidth: true
            )
        }
    }

    private func startSceneRecognitionIfNeeded() {
        if hasSceneRecognitionResult {
            if !controller.isPlaying {
                libraryStore.hydrateSceneThumbnailsIfNeeded(for: video)
            }
            return
        }
        guard !hasSceneRecognitionResult, sceneDetectionProgress == nil else { return }
        libraryStore.detectSceneCuts(for: video)
    }

    private var sceneCutSignature: [String] {
        sceneCuts.map { "\($0.id):\($0.time):\($0.isPlaceholder):\(ObjectIdentifier($0.thumbnailImage).hashValue)" }
    }

    private var sampledFrameSignature: [String] {
        sampledFrames
            .map { "\($0.id):\($0.time):\($0.kind.rawValue):\($0.isExported)" }
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

    private func collectAction(for item: SceneGridItem) -> (() -> Void)? {
        guard let cut = item.cut, item.sample?.isExported != true else { return nil }
        return {
            libraryStore.markSceneFrameExported(video: video, cut: cut, sceneIndex: item.sceneIndex)
        }
    }

    private func deleteAction(for item: SceneGridItem) -> (() -> Void)? {
        guard let sample = item.sample, sample.kind == .screenshot else { return nil }
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

    private func formatDuration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }
}

private struct PlaybackClockSnapshot {
    let elapsed: Double
    let progress: Double

    var timecodeText: String {
        previewPlaybackTimecode(elapsed)
    }
}

private struct PlaybackClockDrivenView<Content: View>: View {
    @ObservedObject var clock: PlaybackClock
    private let content: (PlaybackClockSnapshot) -> Content

    init(clock: PlaybackClock, @ViewBuilder content: @escaping (PlaybackClockSnapshot) -> Content) {
        self.clock = clock
        self.content = content
    }

    var body: some View {
        let value = clock.value
        content(PlaybackClockSnapshot(
            elapsed: value.elapsed,
            progress: value.progress
        ))
    }
}

private func previewPlaybackTimecode(_ seconds: Double) -> String {
    let totalSeconds = max(0, Int(seconds.rounded()))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}

// MARK: - PreviewPanelView
/// 预览面板：使用 @StateObject controller 驱动播放，
/// 场景网格由 ScenePanelView（Equatable）单独渲染，与 Timer 完全解耦。
private struct PreviewPanelView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var controller = PreviewController()
    let openWorkspace: (AppWorkspace) -> Void
    @Namespace private var tabNamespace
    private static let contentTimelineDetailBlockGap: CGFloat = 8
    private static let contentTimelineDetailBlockPadding: CGFloat = 8
    private static let annotationEditorWidth: CGFloat = 288
    private static let annotationEditorHeight: CGFloat = 184
    private static let exportActionButtonSize: CGFloat = 22
    private static let exportRowContentHeight: CGFloat = 78
    private static let exportRowVerticalPadding: CGFloat = 10
    private static let exportRowHeight: CGFloat = exportRowContentHeight + exportRowVerticalPadding * 2
    private static let exportFramePreviewWidth: CGFloat = 100
    private static let exportFramePreviewMinWidth: CGFloat = 48
    private static let exportFramePreviewMaxWidth: CGFloat = 142
    private static let exportTranscriptIconWidth: CGFloat = 34
    @State private var activePreviewTab: PreviewTab = .frames
    @State private var annotationText = ""
    @State private var pendingAnnotationKind: AnnotationItem.Kind = .frame
    @State private var editingAnnotationID: UUID?
    @State private var isAnnotationPopoverPresented = false
    @State private var annotationEditorAnchor = AnnotationEditorAnchor(progress: 0, kind: .frame, sourceTab: .frames)
    @State private var audioInPoint: Double?
    @State private var audioOutPoint: Double?
    @State private var activeTranscriptSegmentID: UUID? = nil
    @State private var contentNodeTimelineStatus: TranscriptTimelineStatus = .idle
    @State private var expandedPreviewTab: PreviewTab?
    @State private var visibleTimelineDetailTab: PreviewTab?
    @State private var timelineZoom: Double = 1
    @State private var timelineOffset: Double = 0
    @State private var sceneTimelineAutoFocusedKey: String?
    @State private var isVideoTagPopoverPresented = false
    @State private var isVideoTagAddHovered = false
    @State private var draftVideoTag = ""
    @State private var isExportPanelPresented = false
    @State private var exportPanelFilter: ExportPanelFilter = .recent
    @State private var exportPanelKnownItemIDs: Set<String> = []
    @State private var exportPanelHighlightedItemID: String?
    @State private var exportPanelHighlightIntensity: Double = 0
    @State private var exportPanelHighlightTask: Task<Void, Never>?
    @State private var exportAudioPlayer: AVPlayer?
    @State private var activeExportAudioClipID: UUID?
    @State private var activeExportAudioProgress: Double = 0
    @State private var exportAudioTimeObserver: Any?
    @State private var exportAudioPlaybackEndObserver: NSObjectProtocol?
    @State private var keyboardShuttleTask: Task<Void, Never>?
    @State private var keyboardShuttleDirection = 0
    @State private var keyboardShuttleFrameStep = 2
    @State private var keyboardShuttleLastCommandAt = Date.distantPast
    @State private var lastTimelineAutoScrollAt = Date.distantPast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selectedVideo = libraryStore.selectedVideo {
                previewWorkspace(for: selectedVideo)
            } else {
                AppEmptyState(
                    title: "选择一个视频",
                    systemImage: "play.rectangle",
                    description: "点击左侧视频后，会在这里直接播放。",
                    style: .large
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .contentPanel()
        .onAppear {
            controller.libraryStore = libraryStore
            controller.loadVideo(libraryStore.selectedVideo, autoplay: false)
            focusSceneTimelineOnOpeningIfNeeded()
            hydrateSceneThumbnailsForFrameTimelineIfIdle()
            PreviewKeyboardCommandDispatcher.setHandler { command in
                handlePreviewKeyboardCommand(command)
            }
        }
        .onDisappear {
            PreviewKeyboardCommandDispatcher.clearHandler()
            stopKeyboardShuttle()
            stopExportAudioClipPlayback()
            exportPanelHighlightTask?.cancel()
            exportPanelHighlightTask = nil
            libraryStore.cancelAllSceneThumbnailHydration()
            controller.stopPlayback()
        }
        .onChange(of: isVideoTagPopoverPresented) { _, isPresented in
            if !isPresented {
                draftVideoTag = ""
            }
        }
        .onChange(of: libraryStore.selectedVideoSelectionID) { _, _ in
            libraryStore.cancelAllSceneThumbnailHydration()
            controller.libraryStore = libraryStore
            controller.loadVideo(
                libraryStore.selectedVideo,
                autoplay: libraryStore.shouldAutoplaySelectedVideo
            )
            audioInPoint = nil
            audioOutPoint = nil
            activeTranscriptSegmentID = nil
            editingAnnotationID = nil
            isAnnotationPopoverPresented = false
            expandedPreviewTab = nil
            visibleTimelineDetailTab = nil
            resetTimelineViewport()
            stopKeyboardShuttle()
            stopExportAudioClipPlayback()
            focusSceneTimelineOnOpeningIfNeeded()
            hydrateSceneThumbnailsForFrameTimelineIfIdle()
            startMusicDetectionIfNeeded(for: libraryStore.selectedVideo, filter: exportPanelFilter)
        }
        .onChange(of: libraryStore.playbackSupportByVideoPath) { _, _ in
            controller.applyPlaybackSupportIfNeeded()
        }
        .onChange(of: controller.isPlaying) { _, isPlaying in
            guard let video = libraryStore.selectedVideo else { return }
            if isPlaying {
                libraryStore.cancelSceneThumbnailHydration(for: video)
            } else if activePreviewTab == .frames || visibleTimelineDetailTab == .frames {
                hydrateSceneThumbnailsForFrameTimelineIfIdle()
            }
        }
        .onReceive(controller.clock.$value) { value in
            handlePlaybackClockTick(value.elapsed)
        }
        .onChange(of: visibleTimelineDetailTab) { _, _ in
            startRecognitionForVisibleTimelineIfNeeded()
        }
        .onChange(of: activePreviewTab) { _, _ in
            focusSceneTimelineOnOpeningIfNeeded()
            hydrateSceneThumbnailsForFrameTimelineIfIdle()
        }
        .onChange(of: libraryStore.sceneCutProgressesByVideoPath) { _, _ in
            focusSceneTimelineOnOpeningIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lapianBaoSeekRequest)) { notification in
            guard
                let path = notification.userInfo?["path"] as? String,
                let time = notification.userInfo?["time"] as? Double,
                path == libraryStore.selectedVideo?.url.path
            else { return }
            controller.pause()
            controller.seekToSeconds(time)
        }
        .onReceive(NotificationCenter.default.publisher(for: .lapianBaoPausePreviewRequest)) { _ in
            controller.pause()
            stopExportAudioClipPlayback()
        }
    }

    private var collapsedPreviewTimelineStackHeight: CGFloat {
        Design.timelineLaneHeight * 3 + timelineLaneGap * 2
    }

    private func expandedPreviewTimelineStackHeight(in workspaceHeight: CGFloat) -> CGFloat {
        min(Design.expandedTimelineStackMaxHeight, max(340, workspaceHeight * 0.42))
    }

    private func previewWorkspace(for video: VideoItem) -> some View {
        GeometryReader { proxy in
            let showsSidebar = proxy.size.width >= 720
            let sidebarWidth = max(240, min(320, proxy.size.width * 0.20))
            let stageGap: CGFloat = showsSidebar ? 12 : 0
            let playerWidth = showsSidebar ? max(360, proxy.size.width - sidebarWidth - stageGap) : proxy.size.width
            let workspaceGap: CGFloat = 8
            let headerHeight = Design.previewHeaderHeight
            let topChromeHeight = headerHeight + workspaceGap
            let timelineHeight = collapsedPreviewTimelineStackHeight
            let expandedTimelineHeight = expandedPreviewTimelineStackHeight(in: proxy.size.height)
            let currentTimelineHeight = expandedPreviewTab == nil ? timelineHeight : expandedTimelineHeight
            let verticalBudget = max(0, proxy.size.height - topChromeHeight - workspaceGap * 2)
            let stageHeight = max(220, verticalBudget - currentTimelineHeight)
            let overlayInset = Design.previewExportOverlayButtonInset
            let overlayAvailableWidth = max(1, proxy.size.width - overlayInset * 2)
            let overlayPreferredWidth = max(
                Design.previewExportOverlayMinWidth,
                proxy.size.width * Design.previewExportOverlayWidthRatio
            )
            let overlayPanelWidth = min(overlayAvailableWidth, overlayPreferredWidth)
            let overlayPanelHeight = max(1, stageHeight - overlayInset * 2)

            if showsSidebar {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: stageGap) {
                        VStack(alignment: .leading, spacing: workspaceGap) {
                            previewHeader(for: video)
                                .frame(width: playerWidth, alignment: .leading)

                            PreviewPlayerView(
                                player: controller.player,
                                statusMessage: controller.playbackMessage,
                                onSurfaceTap: togglePreviewPlayback
                            )
                            .frame(width: playerWidth, height: stageHeight, alignment: .topLeading)
                            .transaction { $0.animation = nil }
                        }
                        .frame(width: playerWidth, alignment: .topLeading)

                        exportPanel(for: video, isOverlay: false)
                            .frame(
                                width: sidebarWidth,
                                height: stageHeight + topChromeHeight - Design.previewHeaderTopInset,
                                alignment: .top
                            )
                            .padding(.top, Design.previewHeaderTopInset)
                            .frame(width: sidebarWidth, height: stageHeight + topChromeHeight, alignment: .top)
                            .transaction { $0.animation = nil }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    timelineStackContainer(
                        for: video,
                        collapsedHeight: timelineHeight,
                        expandedHeight: expandedTimelineHeight
                    )
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                }
                .padding(.bottom, workspaceGap)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: workspaceGap) {
                    previewHeader(for: video)

                    ZStack(alignment: .topTrailing) {
                        PreviewPlayerView(
                            player: controller.player,
                            statusMessage: controller.playbackMessage,
                            onSurfaceTap: togglePreviewPlayback
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: stageHeight)
                        .transaction { $0.animation = nil }

                        if isExportPanelPresented {
                            exportPanel(for: video, isOverlay: true)
                                .frame(width: overlayPanelWidth, height: overlayPanelHeight, alignment: .topTrailing)
                                .padding(overlayInset)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        } else {
                            previewExportOverlayButton(
                                systemImage: "square.and.arrow.up",
                                help: "打开导出区"
                            ) {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    isExportPanelPresented = true
                                }
                            }
                            .padding(Design.previewExportOverlayButtonInset + Design.previewExportPanelPadding)
                        }
                    }
                    .frame(height: stageHeight, alignment: .topLeading)
                    .clipped()

                    timelineStackContainer(
                        for: video,
                        collapsedHeight: timelineHeight,
                        expandedHeight: expandedTimelineHeight
                    )
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                }
                .padding(.bottom, workspaceGap)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func videoDisplayName(for video: VideoItem) -> String {
        libraryStore.videoSourceTitle(for: video) ?? video.name
    }

    private func previewHeader(for video: VideoItem) -> some View {
        VStack(alignment: .leading, spacing: Design.previewHeaderTitleTagGap) {
            Text(videoDisplayName(for: video))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, minHeight: Design.previewHeaderTitleLineHeight, maxHeight: Design.previewHeaderTitleLineHeight, alignment: .leading)
                .layoutPriority(1)

            videoTagStrip(for: video)
        }
        .padding(.top, Design.previewHeaderTopInset)
        .padding(.bottom, Design.previewHeaderTitleTagGap)
        .frame(maxWidth: .infinity, minHeight: Design.previewHeaderHeight, maxHeight: Design.previewHeaderHeight, alignment: .topLeading)
        .clipped()
    }

    private func previewFrameDragProvider(for video: VideoItem) -> NSItemProvider {
        controller.pause()
        return libraryStore.fullResolutionFrameProvider(
            video: video,
            time: controller.elapsed,
            kind: .screenshot
        )
    }

    private func exportPanel(for video: VideoItem, isOverlay: Bool) -> some View {
        let frames = libraryStore.sampledFrames(for: video)
        let clips = libraryStore.audioClips(for: video)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                exportFilterPicker
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isOverlay {
                    previewExportOverlayButton(
                        systemImage: "xmark",
                        help: "关闭导出区"
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isExportPanelPresented = false
                        }
                    }
                }
            }

            exportPanelContent(video: video, frames: frames, clips: clips, isOverlay: isOverlay)
        }
        .padding(Design.previewExportPanelPadding)
        .background(isOverlay ? Color.black.opacity(0.72) : Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.white.opacity(isOverlay ? 0.18 : 0.09), lineWidth: 0.8)
        }
        .shadow(color: isOverlay ? .black.opacity(0.32) : .clear, radius: 18, y: 10)
    }

    private func previewExportOverlayButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if systemImage.hasPrefix("square.and.arrow") {
                floatingExportButtonIcon(
                    systemImage: "square.and.arrow.up",
                    size: Design.previewExportOverlayButtonSize,
                    iconSize: Design.previewExportOverlayButtonIconSize
                )
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: Design.previewExportOverlayButtonIconSize, weight: .semibold))
                    .frame(
                        width: Design.previewExportOverlayButtonSize,
                        height: Design.previewExportOverlayButtonSize
                    )
                    .background(.black.opacity(0.44))
                    .clipShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.88))
        .help(help)
    }

    private var exportFilterPicker: some View {
        HStack(spacing: 3) {
            ForEach(ExportPanelFilter.allCases) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        exportPanelFilter = filter
                    }
                    startMusicDetectionIfNeeded(for: libraryStore.selectedVideo, filter: filter)
                } label: {
                    Text(filter.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(exportPanelFilter == filter ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(exportPanelFilter == filter ? Color.white.opacity(0.14) : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.white.opacity(0.055))
        .clipShape(Capsule())
    }

    private func startMusicDetectionIfNeeded(for video: VideoItem?, filter: ExportPanelFilter) {
        guard filter == .music, let video else { return }
        let path = video.url.path
        guard libraryStore.musicsByVideoPath[path, default: []].isEmpty else { return }

        switch libraryStore.musicDetectionStatusByVideoPath[path] {
        case nil, .idle:
            libraryStore.detectMusic(for: video)
        case .running, .completed, .failed:
            return
        }
    }

    private func exportPanelContent(video: VideoItem, frames: [SampledFrame], clips: [AudioClipItem], isOverlay: Bool) -> some View {
        let sortedFrames = frames.sorted { $0.createdAt < $1.createdAt }
        let sortedAudioClips = clips.sorted { $0.createdAt < $1.createdAt }
        let recentItems = exportPanelFilter == .recent ? recentExportPanelItems() : []
        let recentAudioClipIndexByID = recentExportAudioClipIndexByID(from: recentItems)
        let visibleItemIDs: [String] = {
            switch exportPanelFilter {
            case .recent:
                return recentItems.map(\.id)
            case .images:
                return sortedFrames.map { ExportPanelItem.frame($0).id }
            case .audio:
                return sortedAudioClips.map { ExportPanelItem.audio($0).id }
            case .music:
                return []
            }
        }()

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    switch exportPanelFilter {
                    case .recent:
                        if recentItems.isEmpty {
                            AppEmptyState(title: "暂无素材", style: .inline, minHeight: 80)
                        } else {
                            ForEach(recentItems) { item in
                                switch item {
                                case .frame(let frame):
                                    exportFrameRow(frame, showsSource: true, showsMetadata: !isOverlay, highlightIntensity: exportPanelHighlightedItemID == item.id ? exportPanelHighlightIntensity : 0)
                                        .id(item.id)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                case .audio(let clip):
                                    exportAudioClipRow(clip, index: recentAudioClipIndexByID[clip.id], showsSource: true, highlightIntensity: exportPanelHighlightedItemID == item.id ? exportPanelHighlightIntensity : 0)
                                        .id(item.id)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                case .transcript(let export):
                                    exportTranscriptRow(export, highlightIntensity: exportPanelHighlightedItemID == item.id ? exportPanelHighlightIntensity : 0)
                                        .id(item.id)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                case .transcriptProgress(let job):
                                    exportTranscriptProgressRow(job, highlightIntensity: exportPanelHighlightedItemID == item.id ? exportPanelHighlightIntensity : 0)
                                        .id(item.id)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                        }
                    case .images:
                        if frames.isEmpty {
                            AppEmptyState(title: "暂无图片", style: .inline, minHeight: 80)
                        } else {
                            ForEach(sortedFrames) { frame in
                                let itemID = ExportPanelItem.frame(frame).id
                                exportFrameRow(frame, showsMetadata: !isOverlay, highlightIntensity: exportPanelHighlightedItemID == itemID ? exportPanelHighlightIntensity : 0)
                                    .id(itemID)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    case .audio:
                        if clips.isEmpty {
                            AppEmptyState(title: "暂无声音", style: .inline, minHeight: 80)
                        } else {
                            ForEach(Array(sortedAudioClips.enumerated()), id: \.element.id) { index, clip in
                                let itemID = ExportPanelItem.audio(clip).id
                                exportAudioClipRow(clip, index: index + 1, highlightIntensity: exportPanelHighlightedItemID == itemID ? exportPanelHighlightIntensity : 0)
                                    .id(itemID)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    case .music:
                        exportMusicRecognitionPanel(for: video)
                    }
                }
                .padding(.trailing, 2)
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: visibleItemIDs)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                syncExportPanelTracking(ids: visibleItemIDs, proxy: proxy, shouldTrackNewItems: false)
            }
            .onChange(of: visibleItemIDs) { _, ids in
                syncExportPanelTracking(ids: ids, proxy: proxy, shouldTrackNewItems: true)
            }
            .onChange(of: exportPanelFilter) { _, _ in
                syncExportPanelTracking(ids: visibleItemIDs, proxy: proxy, shouldTrackNewItems: false)
            }
        }
    }

    private func exportPanelItems(
        frames: [SampledFrame],
        clips: [AudioClipItem],
        transcripts: [TranscriptExportItem] = [],
        transcriptJobs: [TranscriptExportJob] = []
    ) -> [ExportPanelItem] {
        let frameItems = frames.map(ExportPanelItem.frame)
        let clipItems = clips.map(ExportPanelItem.audio)
        let transcriptItems = transcripts.map(ExportPanelItem.transcript)
        let transcriptProgressItems = transcriptJobs.map(ExportPanelItem.transcriptProgress)
        return (frameItems + clipItems + transcriptItems + transcriptProgressItems).sorted { $0.createdAt < $1.createdAt }
    }

    private func recentExportPanelItems() -> [ExportPanelItem] {
        let visibleVideoPaths = Set(libraryStore.videos.map { $0.url.path })
        return exportPanelItems(
            frames: libraryStore.sampledFrames.filter { visibleVideoPaths.contains($0.videoPath) },
            clips: libraryStore.audioClips.filter { visibleVideoPaths.contains($0.videoPath) },
            transcripts: libraryStore.transcriptExports.filter { visibleVideoPaths.contains($0.videoPath) },
            transcriptJobs: libraryStore.transcriptExportJobs.values.filter { visibleVideoPaths.contains($0.videoPath) }
        )
    }

    private func recentExportAudioClipIndexByID(from items: [ExportPanelItem]) -> [UUID: Int] {
        let sortedClips = items.compactMap { item -> AudioClipItem? in
            if case let .audio(clip) = item { return clip }
            return nil
        }
        return Dictionary(
            uniqueKeysWithValues: sortedClips.enumerated().map { ($0.element.id, $0.offset + 1) }
        )
    }

    private func syncExportPanelTracking(ids: [String], proxy: ScrollViewProxy, shouldTrackNewItems: Bool) {
        let currentIDs = Set(ids)
        defer { exportPanelKnownItemIDs = currentIDs }

        guard shouldTrackNewItems, let newestID = ids.last(where: { !exportPanelKnownItemIDs.contains($0) }) else {
            return
        }

        exportPanelHighlightTask?.cancel()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            exportPanelHighlightedItemID = newestID
            exportPanelHighlightIntensity = 1
            proxy.scrollTo(newestID, anchor: .bottom)
        }

        exportPanelHighlightTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 1.05)) {
                exportPanelHighlightIntensity = 0
            }
            try? await Task.sleep(nanoseconds: 1_080_000_000)
            guard !Task.isCancelled else { return }
            if exportPanelHighlightIntensity <= 0.001 {
                exportPanelHighlightedItemID = nil
            }
        }
    }

    private func exportSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }

    private func exportFrameRow(_ frame: SampledFrame, showsSource: Bool = false, showsMetadata: Bool = true, highlightIntensity: Double = 0) -> some View {
        let kindText = exportFrameTitle(for: frame)
        let highlight = min(1, max(0, highlightIntensity))

        return HStack(spacing: 9) {
            Button {
                jumpToExportLocation(path: frame.videoPath, time: frame.time)
            } label: {
                HStack(spacing: 9) {
                    exportFramePreview(
                        image: libraryStore.thumbnailImage(for: frame),
                        showsMetadata: showsMetadata
                    )

                    if showsMetadata {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kindText)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(showsSource ? "\(frame.videoName) · \(formatDuration(frame.time))" : formatDuration(frame.time))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(height: Self.exportRowContentHeight, alignment: .center)
                    }
                }
                .frame(height: Self.exportRowContentHeight, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("跳到这张画面")

            exportItemActionColumn(
                jumpHelp: "跳到这张画面",
                deleteHelp: "删除这张画面",
                onJump: {
                    jumpToExportLocation(path: frame.videoPath, time: frame.time)
                },
                onDelete: {
                    libraryStore.deleteSampledFrame(frame)
                }
            ) {
                InlineTagEditorButton(
                    title: "图片标签",
                    tags: frame.tags,
                    suggestedTags: libraryStore.allFrameTags,
                    buttonSize: 22,
                    onAdd: { libraryStore.addFrameTag($0, to: frame) },
                    onRemove: { libraryStore.removeFrameTag($0, from: frame) }
                )
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, Self.exportRowVerticalPadding)
        .frame(height: Self.exportRowHeight)
        .background(exportRowBackground(isActive: false, progress: 0, highlightIntensity: highlight))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(exportRowStrokeColor(highlightIntensity: highlight, fallback: .white.opacity(0.07)), lineWidth: 0.8 + 0.4 * highlight)
        }
        .fullResolutionImageDrag {
            libraryStore.fullResolutionFrameProvider(for: frame)
        }
    }

    private func exportFramePreview(image: NSImage?, showsMetadata: Bool) -> some View {
        let previewWidth = exportFramePreviewWidth(for: image, showsMetadata: showsMetadata)
        let previewShape = RoundedRectangle(cornerRadius: 6, style: .continuous)

        return ZStack {
            previewShape
                .fill(.black.opacity(0.28))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
            } else {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: previewWidth, height: Self.exportRowContentHeight)
        .clipShape(previewShape)
        .overlay {
            previewShape
                .stroke(.white.opacity(0.06), lineWidth: 0.7)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func exportFramePreviewWidth(for image: NSImage?, showsMetadata: Bool) -> CGFloat {
        guard !showsMetadata else { return Self.exportFramePreviewWidth }
        let aspectRatio = exportFramePreviewAspectRatio(for: image)
        return min(
            Self.exportFramePreviewMaxWidth,
            max(Self.exportFramePreviewMinWidth, Self.exportRowContentHeight * aspectRatio)
        )
    }

    private func exportFramePreviewAspectRatio(for image: NSImage?) -> CGFloat {
        guard
            let size = image?.size,
            size.width > 0,
            size.height > 0
        else { return 16 / 9 }
        return size.width / size.height
    }

    private func exportFrameTitle(for frame: SampledFrame) -> String {
        let frames = libraryStore.sampledFrames(for: VideoItem(url: URL(fileURLWithPath: frame.videoPath)))
            .filter { $0.kind == frame.kind }
            .sorted {
                if abs($0.time - $1.time) > 0.001 { return $0.time < $1.time }
                return $0.createdAt < $1.createdAt
            }
        let index = (frames.firstIndex { $0.id == frame.id } ?? 0) + 1
        let prefix = frame.kind == .screenshot ? "截图画面" : "场景画面"
        return "\(prefix) \(String(format: "%02d", index))"
    }

    private func exportAudioClipRow(_ clip: AudioClipItem, index: Int?, showsSource: Bool = false, highlightIntensity: Double = 0) -> some View {
        let isPlaying = activeExportAudioClipID == clip.id
        let highlight = min(1, max(0, highlightIntensity))
        let progress = isPlaying ? activeExportAudioProgress : 0
        let duration = max(0, clip.outTime - clip.inTime)
        let title = showsSource ? clip.videoName : audioClipTitle(index: index)
        let subtitle = "\(audioClipTitle(index: index)) · \(formatDuration(clip.inTime)) - \(formatDuration(clip.outTime))"
        let waveformHeight: CGFloat = showsSource ? 44 : 58

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: showsSource ? 3 : 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text(audioClipTimecode(duration: duration, progress: progress, isPlaying: isPlaying))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white.opacity(isPlaying ? 0.78 : 0.48))
                }
                .frame(height: 16, alignment: .center)

                if showsSource {
                    Text(subtitle)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                        .frame(height: 12, alignment: .leading)
                }

                AudioClipWaveformStrip(
                    samples: clip.waveformSamples,
                    isActive: isPlaying,
                    progress: progress
                )
                .frame(height: waveformHeight)
            }
            .frame(height: Self.exportRowContentHeight, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleExportAudioClipPlayback(clip)
            }
            .help(isPlaying ? "暂停声音片段" : "播放导出的声音片段")
            .itemProviderDrag(audioClipDragProvider(for: clip))

            exportItemActionColumn(
                jumpHelp: "回到原视频位置",
                deleteHelp: "删除声音片段",
                onJump: {
                    jumpToExportLocation(path: clip.videoPath, time: clip.inTime)
                },
                onDelete: {
                    deleteExportAudioClip(clip)
                }
            ) {
                InlineTagEditorButton(
                    title: "声音标签",
                    tags: clip.tags,
                    suggestedTags: libraryStore.allAudioTags,
                    buttonSize: 22,
                    onAdd: { libraryStore.addAudioTag($0, to: clip) },
                    onRemove: { libraryStore.removeAudioTag($0, from: clip) }
                )
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, Self.exportRowVerticalPadding)
        .frame(height: Self.exportRowHeight)
        .background(exportRowBackground(isActive: isPlaying, progress: 0, highlightIntensity: highlight))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(exportRowStrokeColor(highlightIntensity: highlight, fallback: isPlaying ? Color.orange.opacity(0.24) : .white.opacity(0.07)), lineWidth: 0.8 + 0.4 * highlight)
        }
        .onAppear {
            libraryStore.loadAudioClipWaveformIfNeeded(clip)
        }
        .itemProviderDrag(audioClipDragProvider(for: clip))
    }

    private func exportTranscriptProgressRow(_ job: TranscriptExportJob, highlightIntensity: Double = 0) -> some View {
        let highlight = min(1, max(0, highlightIntensity))
        let progress = normalizedProgressFraction(job.progress)
        let isFailed = job.isFailed
        let tint = isFailed ? Design.currentFrameAccent : Design.annotationAccent

        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: isFailed ? "exclamationmark.triangle.fill" : "doc.text")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: Self.exportTranscriptIconWidth, height: Self.exportRowContentHeight)
                .background(.white.opacity(0.075))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(job.videoName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)

                    Text(isFailed ? "失败" : progressPercentText(progress))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(isFailed ? tint.opacity(0.86) : .white.opacity(0.58))
                }

                Text(job.errorMessage ?? "正在生成分镜字幕索引")
                    .font(.caption2)
                    .foregroundStyle(isFailed ? tint.opacity(0.78) : .white.opacity(0.48))
                    .lineLimit(1)

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .frame(height: 4)
            }
            .frame(height: Self.exportRowContentHeight, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, Self.exportRowVerticalPadding)
        .frame(height: Self.exportRowHeight)
        .background(exportRowBackground(isActive: true, progress: progress, highlightIntensity: highlight))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(exportRowStrokeColor(highlightIntensity: highlight, fallback: tint.opacity(0.22)), lineWidth: 0.8 + 0.4 * highlight)
        }
        .help(isFailed ? "字幕导出失败" : "字幕导出中")
    }

    private func exportTranscriptRow(_ export: TranscriptExportItem, highlightIntensity: Double = 0) -> some View {
        let highlight = min(1, max(0, highlightIntensity))
        let rangeText = "\(formatDuration(export.startTime)) - \(formatDuration(export.endTime))"
        let actionSpacing = max(0, Self.exportRowContentHeight - Self.exportActionButtonSize * 2)

        return HStack(alignment: .center, spacing: 10) {
            Button {
                jumpToExportLocation(path: export.videoPath, time: export.startTime)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Design.annotationAccent)
                        .frame(width: Self.exportTranscriptIconWidth, height: Self.exportRowContentHeight)
                        .background(.white.opacity(0.075))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(export.videoName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("字幕 · \(export.segmentCount) 段 · \(rangeText)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(1)
                    }
                    .frame(height: Self.exportRowContentHeight, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: Self.exportRowContentHeight, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("跳到字幕起点")

            VStack(spacing: actionSpacing) {
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: export.filePath))
                } label: {
                    exportItemActionIcon("doc.text", tint: .white.opacity(0.70), size: Self.exportActionButtonSize)
                }
                .buttonStyle(.plain)
                .disabled(!FileManager.default.fileExists(atPath: export.filePath))
                .help("打开字幕文件")

                Button {
                    jumpToExportLocation(path: export.videoPath, time: export.startTime)
                } label: {
                    exportItemActionIcon("arrowshape.turn.up.left", tint: .white.opacity(0.70), size: Self.exportActionButtonSize)
                }
                .buttonStyle(.plain)
                .help("跳到字幕起点")
            }
            .frame(width: Self.exportActionButtonSize, height: Self.exportRowContentHeight)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, Self.exportRowVerticalPadding)
        .frame(height: Self.exportRowHeight)
        .background(exportRowBackground(isActive: false, progress: 0, highlightIntensity: highlight))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(exportRowStrokeColor(highlightIntensity: highlight, fallback: .white.opacity(0.07)), lineWidth: 0.8 + 0.4 * highlight)
        }
    }

    private func exportAudioPlayButton(clip: AudioClipItem, isPlaying: Bool, progress: Double) -> some View {
        Button {
            toggleExportAudioClipPlayback(clip)
        } label: {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.white.opacity(isPlaying ? 0.13 : 0.08))
                    if progress > 0 {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.white.opacity(0.22))
                            .frame(width: proxy.size.width * CGFloat(min(1, max(0, progress))))
                    }
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(.white.opacity(isPlaying ? 0.20 : 0.10), lineWidth: 0.8)
                }
            }
            .frame(width: 58, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!FileManager.default.fileExists(atPath: clip.videoPath))
        .help(isPlaying ? "暂停声音片段" : "播放导出的声音片段")
    }

    private func jumpToExportLocation(path: String, time: Double) {
        stopExportAudioClipPlayback()
        controller.pause()

        if path == libraryStore.selectedVideo?.url.path {
            controller.seekToSeconds(time)
            return
        }

        guard libraryStore.selectedVideo(for: path) != nil else { return }
        libraryStore.selectVideo(path: path)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .lapianBaoSeekRequest,
                object: nil,
                userInfo: ["path": path, "time": time]
            )
        }
    }

    private func exportItemActionColumn<Accessory: View>(
        jumpHelp: String,
        deleteHelp: String,
        onJump: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        let buttonSize = Self.exportActionButtonSize
        let spacing = max(0, (Self.exportRowContentHeight - buttonSize * 3) / 2)

        return VStack(spacing: spacing) {
            accessory()
                .frame(width: buttonSize, height: buttonSize)

            Button(action: onJump) {
                exportItemActionIcon("arrowshape.turn.up.left", tint: .white.opacity(0.70), size: buttonSize)
            }
            .buttonStyle(.plain)
            .help(jumpHelp)

            Button(role: .destructive, action: onDelete) {
                exportItemActionIcon("trash", tint: .white.opacity(0.70), size: buttonSize)
            }
            .buttonStyle(.plain)
            .help(deleteHelp)
        }
        .frame(width: buttonSize)
        .frame(height: Self.exportRowContentHeight, alignment: .center)
    }

    private func exportItemActionIcon(_ systemImage: String, tint: Color, size: CGFloat = 26) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: min(13, size - 9), weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
    }

    private func audioClipTimecode(duration: Double, progress: Double, isPlaying: Bool) -> String {
        guard isPlaying else { return formatDuration(duration) }
        return formatDuration(duration * min(1, max(0, progress)))
    }

    private func exportRowBackground(isActive: Bool, progress: Double, highlightIntensity: Double = 0) -> some View {
        let highlight = min(1, max(0, highlightIntensity))
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(isActive ? 0.075 : 0.055))
                if highlight > 0 {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Design.captureFrameAccent.opacity(0.18 * highlight))
                }
                if progress > 0 {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white.opacity(0.13))
                        .frame(width: proxy.size.width * CGFloat(min(1, max(0, progress))))
                }
            }
        }
    }

    private func exportRowStrokeColor(highlightIntensity: Double, fallback: Color) -> Color {
        let highlight = min(1, max(0, highlightIntensity))
        guard highlight > 0 else { return fallback }
        return Design.captureFrameAccent.opacity(0.52 * highlight)
    }

    private func toggleExportAudioClipPlayback(_ clip: AudioClipItem) {
        guard FileManager.default.fileExists(atPath: clip.videoPath) else { return }

        if activeExportAudioClipID == clip.id {
            stopExportAudioClipPlayback()
            return
        }

        stopExportAudioClipPlayback()
        controller.pause()

        let item = AVPlayerItem(url: URL(fileURLWithPath: clip.videoPath))
        let player = AVPlayer(playerItem: item)
        let start = CMTime(seconds: max(0, clip.inTime), preferredTimescale: 600)
        let end = max(clip.inTime, clip.outTime)
        exportAudioPlayer = player
        activeExportAudioClipID = clip.id
        activeExportAudioProgress = 0

        exportAudioTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            let duration = max(0.001, end - clip.inTime)
            activeExportAudioProgress = min(1, max(0, (seconds - clip.inTime) / duration))
            if seconds >= end {
                stopExportAudioClipPlayback()
            }
        }

        exportAudioPlaybackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            stopExportAudioClipPlayback()
        }

        player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            player.play()
        }
    }

    private func stopExportAudioClipPlayback() {
        if let exportAudioTimeObserver, let exportAudioPlayer {
            exportAudioPlayer.removeTimeObserver(exportAudioTimeObserver)
            self.exportAudioTimeObserver = nil
        }

        exportAudioPlayer?.pause()
        exportAudioPlayer = nil
        activeExportAudioClipID = nil
        activeExportAudioProgress = 0

        if let exportAudioPlaybackEndObserver {
            NotificationCenter.default.removeObserver(exportAudioPlaybackEndObserver)
            self.exportAudioPlaybackEndObserver = nil
        }
    }

    private func deleteExportAudioClip(_ clip: AudioClipItem) {
        if activeExportAudioClipID == clip.id {
            stopExportAudioClipPlayback()
        }
        libraryStore.deleteAudioClip(clip)
    }

    @ViewBuilder
    private func exportMusicRecognitionPanel(for video: VideoItem) -> some View {
        let path = video.url.path
        let status = libraryStore.musicDetectionStatusByVideoPath[path]
        let songs = libraryStore.musicsByVideoPath[path, default: []]

        if case let .running(message) = status {
            HStack(spacing: 8) {
                RecognitionProgressRow(
                    message: message,
                    progress: activityProgressValue(from: message),
                    showPercent: false,
                    showStepCount: false
                )
                Spacer(minLength: 0)

                Button {
                    libraryStore.cancelMusicDetection(for: video)
                } label: {
                    Image(systemName: "stop.circle")
                        .accessibilityLabel("停止")
                }
                .buttonStyle(.borderless)
                .help("停止音乐识别")
            }
            .recognitionProgressCard()

            ForEach(songs) { song in
                ExportMusicRecognitionRow(song: song, videoPath: path) {
                    controller.pause()
                    controller.seekToSeconds(song.detectedAt)
                }
            }
        } else if case .failed = status {
            AppEmptyState(
                title: "暂无音乐识别结果",
                systemImage: "music.note",
                style: .compact,
                minHeight: 82,
                showsBackground: true
            )
        } else if status == .completed, songs.isEmpty {
            AppEmptyState(
                title: "暂无音乐识别结果",
                systemImage: "music.note",
                style: .compact,
                minHeight: 82,
                showsBackground: true
            )
        } else if songs.isEmpty {
            AppEmptyState(
                title: "暂无音乐识别记录",
                systemImage: "music.note",
                description: "选择音乐后会自动开始识别。",
                style: .compact,
                minHeight: 82
            )
        } else {
            ForEach(songs) { song in
                ExportMusicRecognitionRow(song: song, videoPath: path) {
                    controller.pause()
                    controller.seekToSeconds(song.detectedAt)
                }
            }
        }
    }

    private var previewTransportControls: some View {
        ZStack {
            HStack(spacing: 10) {
                Button {
                    controller.stepFrame(by: -1)
                } label: {
                    Image(systemName: "gobackward.1")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 28)
                }
                .help("后退一帧")

                Button {
                    controller.togglePlayback()
                } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.14))
                        .clipShape(Circle())
                }
                .help(controller.isPlaying ? "暂停" : "播放")

                Button {
                    controller.stepFrame(by: 1)
                } label: {
                    Image(systemName: "goforward.1")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 28)
                }
                .help("前进一帧")
            }

            HStack {
                Spacer()
                Button {
                    annotationText = ""
                    isAnnotationPopoverPresented = true
                } label: {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 28)
                }
                .help("添加批注")
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white.opacity(0.76))
        .frame(maxWidth: .infinity)
        .frame(height: 38)
    }

    private func videoTagStrip(for video: VideoItem) -> some View {
        let tags = libraryStore.tagsByVideoPath[video.url.path, default: []]

        return ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    PreviewTitleTagChip(tag: tag)
                }

                videoTagAddButton(for: video)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Design.previewHeaderTagRowHeight, maxHeight: Design.previewHeaderTagRowHeight, alignment: .leading)
        .scrollIndicators(.hidden)
    }

    private func videoTagAddButton(for video: VideoItem) -> some View {
        Button {
            isVideoTagPopoverPresented = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 9, height: Design.previewHeaderTagRowHeight)

                if isVideoTagAddHovered {
                    Text("添加标签")
                        .font(.system(size: 9, weight: .semibold))
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, isVideoTagAddHovered ? 5 : 2)
            .frame(width: isVideoTagAddHovered ? 58 : 14, height: Design.previewHeaderTagRowHeight)
            .background(.white.opacity(isVideoTagAddHovered ? 0.11 : 0.07))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.16)) {
                isVideoTagAddHovered = hovering
            }
        }
        .help("添加标签")
        .popover(isPresented: $isVideoTagPopoverPresented, arrowEdge: .bottom) {
            videoTagPopover(for: video)
        }
    }

    private func videoTagPopover(for video: VideoItem) -> some View {
        let tags = libraryStore.tagsByVideoPath[video.url.path, default: []]

        return VStack(alignment: .leading, spacing: 10) {
            TagSuggestionGrid(currentTags: tags, suggestedTags: libraryStore.allTags) { tag in
                libraryStore.addTag(tag, to: video)
            }

            HStack(spacing: 8) {
                TextField("添加标签", text: $draftVideoTag)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit {
                        addDraftVideoTag(to: video)
                    }

                Button {
                    addDraftVideoTag(to: video)
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(draftVideoTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    private func addDraftVideoTag(to video: VideoItem) {
        let tag = draftVideoTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        libraryStore.addTag(tag, to: video)
        draftVideoTag = ""
        isVideoTagPopoverPresented = false
    }

    private func timelineStackContainer(
        for video: VideoItem,
        collapsedHeight: CGFloat,
        expandedHeight: CGFloat
    ) -> some View {
        let isExpanded = expandedPreviewTab != nil
        let height = isExpanded ? expandedHeight : collapsedHeight

        return PlaybackClockDrivenView(clock: controller.clock) { clock in
            compositeTimelineStack(for: video, expandedHeight: height, clock: clock)
        }
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            .clipped()
            .overlay(alignment: .topLeading) {
                GeometryReader { overlayProxy in
                    annotationEditorOverlay(for: video, in: overlayProxy.size)
                }
                .allowsHitTesting(isAnnotationPopoverPresented)
            }
            .shadow(color: .black.opacity(isExpanded ? 0.18 : 0), radius: isExpanded ? 18 : 0, y: -4)
            .animation(timelineFadeAnimation, value: expandedPreviewTab)
    }

    @ViewBuilder
    private func compositeTimelineStack(
        for video: VideoItem,
        expandedHeight: CGFloat? = nil,
        clock: PlaybackClockSnapshot
    ) -> some View {
        let detailHeight = expandedHeight.map { height in
            expandedTimelineDetailHeight(for: height)
        } ?? Design.expandedTimelineDetailHeight

        VStack(spacing: timelineLaneGap) {
            ForEach(timelineLaneOrder, id: \.self) { tab in
                timelineLaneSlot(tab, for: video, detailHeight: detailHeight, clock: clock)
            }
        }
    }

    private var timelineLaneGap: CGFloat { 8 }

    private var timelineLaneOrder: [PreviewTab] {
        guard let expandedPreviewTab else { return PreviewTab.allCases }
        return [expandedPreviewTab]
    }

    private func expandedTimelineDetailHeight(for stackHeight: CGFloat) -> CGFloat {
        max(120, stackHeight - Design.timelineLaneHeight - 16)
    }

    @ViewBuilder
    private func annotationEditorOverlay(for video: VideoItem, in size: CGSize) -> some View {
        if isAnnotationPopoverPresented {
            let anchor = annotationEditorPoint(in: size)
            annotationEditorView(for: video)
                .frame(width: Self.annotationEditorWidth)
                .background(.black.opacity(0.78))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
                .position(anchor)
                .zIndex(50)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private func annotationEditorPoint(in size: CGSize) -> CGPoint {
        let marker = annotationMarkerPoint(in: size)
        let halfWidth = Self.annotationEditorWidth / 2
        let halfHeight = Self.annotationEditorHeight / 2
        let x = min(max(marker.x, halfWidth + 6), max(halfWidth + 6, size.width - halfWidth - 6))
        let aboveY = marker.y - halfHeight - 14
        let belowY = marker.y + halfHeight + 14
        let rawY = aboveY >= halfHeight + 4 ? aboveY : belowY
        let y = min(max(rawY, halfHeight + 4), max(halfHeight + 4, size.height - halfHeight - 4))
        return CGPoint(x: x, y: y)
    }

    private func annotationMarkerPoint(in size: CGSize) -> CGPoint {
        let tab = visibleAnnotationSourceTab()
        let laneHeight = Design.timelineLaneHeight
        let laneOrigin = expandedPreviewTab == nil
            ? CGFloat(timelineIndex(for: tab)) * (laneHeight + timelineLaneGap)
            : 0
        let contentFrame = timelineContentFrame(in: size, laneOrigin: laneOrigin, laneHeight: laneHeight)
        let progress = min(1, max(0, annotationEditorAnchor.progress))
        let x: CGFloat

        switch tab {
        case .frames:
            let local = (progress - timelineOffset) / max(timelineViewportSpan, 0.0001)
            x = contentFrame.minX + contentFrame.width * CGFloat(local)
        case .audio:
            let span = max(0.02, min(1, Design.centeredWaveformViewportSpan))
            let focus = min(1, max(0, controller.progress))
            x = contentFrame.midX + contentFrame.width * CGFloat((progress - focus) / span)
        case .content:
            x = contentFrame.minX + contentFrame.width * CGFloat(progress)
        }

        return CGPoint(
            x: min(max(x, contentFrame.minX + 9), contentFrame.maxX - 9),
            y: annotationMarkerY(for: annotationEditorAnchor.kind, tab: tab, in: contentFrame)
        )
    }

    private func visibleAnnotationSourceTab() -> PreviewTab {
        if let expandedPreviewTab, expandedPreviewTab != annotationEditorAnchor.sourceTab {
            return expandedPreviewTab
        }
        return annotationEditorAnchor.sourceTab
    }

    private func timelineContentFrame(in size: CGSize, laneOrigin: CGFloat, laneHeight: CGFloat) -> CGRect {
        let horizontalPadding: CGFloat = 8
        let headerSpacing: CGFloat = 8
        let minX = horizontalPadding + Design.timelineLaneButtonSize + headerSpacing
        let maxX = max(minX + 1, size.width - horizontalPadding)
        let sideButtonCount: CGFloat = 3
        let sideButtonsHeight = Design.timelineLaneButtonSize * sideButtonCount
        let visualGap = max(Design.timelineLaneVisualGap, (laneHeight - sideButtonsHeight) / (sideButtonCount + 1))
        let contentHeight = max(Design.timelineLaneContentHeight, laneHeight - visualGap * 2)
        let minY = laneOrigin + max(0, (laneHeight - contentHeight) / 2)

        return CGRect(x: minX, y: minY, width: maxX - minX, height: contentHeight)
    }

    private func annotationMarkerY(for kind: AnnotationItem.Kind, tab: PreviewTab, in frame: CGRect) -> CGFloat {
        switch tab {
        case .frames:
            return frame.midY + 3
        case .audio:
            return frame.midY + 4
        case .content:
            return frame.minY + annotationLaneCenter(for: kind, height: frame.height)
        }
    }

    private func annotationLaneCenter(for kind: AnnotationItem.Kind, height: CGFloat) -> CGFloat {
        let margin: CGFloat = min(max(12, height * 0.16), max(12, height / 2))
        switch kind {
        case .frame:
            return margin
        case .audio:
            return height / 2
        case .content:
            return max(margin, height - margin)
        }
    }

    private func timelineIndex(for tab: PreviewTab) -> Int {
        switch tab {
        case .frames: return 0
        case .audio: return 1
        case .content: return 2
        }
    }

    @ViewBuilder
    private func timelineLaneSlot(
        _ tab: PreviewTab,
        for video: VideoItem,
        detailHeight: CGFloat,
        clock: PlaybackClockSnapshot
    ) -> some View {
        timelineLaneForTab(tab, for: video, detailHeight: detailHeight, clock: clock)
            .frame(height: timelineSlotHeight(for: tab, detailHeight: detailHeight), alignment: .top)
            .clipped()
            .transition(.identity)
    }

    private func timelineSlotHeight(for tab: PreviewTab, detailHeight: CGFloat) -> CGFloat {
        if expandedPreviewTab == tab {
            return Design.timelineLaneHeight + detailHeight + 16
        }

        if expandedPreviewTab != nil {
            return Design.collapsedTimelineLaneHeight
        }

        return Design.timelineLaneHeight
    }

    private var timelineFadeAnimation: Animation {
        .easeInOut(duration: 0.18)
    }

    @ViewBuilder
    private func timelineLaneForTab(
        _ tab: PreviewTab,
        for video: VideoItem,
        detailHeight: CGFloat = Design.expandedTimelineDetailHeight,
        regularLaneHeight: CGFloat? = nil,
        clock: PlaybackClockSnapshot
    ) -> some View {
        switch tab {
        case .frames:
            timelineLane(
                tab: .frames,
                icon: previewTabIcon(.frames),
                accent: previewTabAccent(.frames),
                detailHeight: detailHeight,
                regularLaneHeight: regularLaneHeight,
                actions: {
                    trackHeaderButton(icon: "camera.fill", help: "截取当前帧") {
                        libraryStore.captureCurrentFrame(video: video, time: controller.elapsed)
                    }

                    Spacer(minLength: 0)

                    trackHeaderButton(icon: "text.bubble.fill", help: "添加批注") {
                        beginAnnotation(.frame, sourceTab: .frames)
                    }
                },
                content: {
                    frameTimeline(for: video, clock: clock)
                },
                detail: {
                    timelineDetailContent(.frames, for: video)
                }
            )
        case .audio:
            timelineLane(
                tab: .audio,
                icon: previewTabIcon(.audio),
                accent: previewTabAccent(.audio),
                detailHeight: detailHeight,
                regularLaneHeight: regularLaneHeight,
                actions: {
                    audioSelectionActionButton(for: video)

                    Spacer(minLength: 0)

                    trackHeaderButton(icon: "text.bubble.fill", help: "添加声音批注") {
                        beginAnnotation(.audio, sourceTab: .audio)
                    }
                },
                content: {
                    audioTimeline(for: video, clock: clock)
                },
                detail: {
                    audioTimelineDetailContent(for: video)
                }
            )
        case .content:
            timelineLane(
                tab: .content,
                icon: previewTabIcon(.content),
                accent: previewTabAccent(.content),
                detailHeight: detailHeight,
                regularLaneHeight: regularLaneHeight,
                actions: {
                    trackHeaderButton(icon: "square.and.arrow.up", help: "导出字幕") {
                        exportCurrentTranscript(for: video)
                    }
                    .disabled(libraryStore.transcriptSegmentsByVideoPath[video.url.path, default: []].isEmpty)

                    Spacer(minLength: 0)

                    trackHeaderButton(icon: "text.bubble.fill", help: "添加内容批注") {
                        beginAnnotation(.content, sourceTab: .content)
                    }
                },
                content: {
                    contentTimeline(for: video, clock: clock)
                },
                detail: {
                    timelineDetailContent(.content, for: video)
                }
            )
        }
    }

    private func previewTabIcon(_ tab: PreviewTab) -> String {
        switch tab {
        case .frames: return "photo.on.rectangle"
        case .audio: return "waveform"
        case .content: return "text.quote"
        }
    }

    private func previewTabAccent(_ tab: PreviewTab) -> Color {
        switch tab {
        case .frames: return Design.captureFrameAccent
        case .audio: return .orange
        case .content: return Design.annotationAccent
        }
    }


    private func timelineLane<Content: View, Actions: View, Detail: View>(
        tab: PreviewTab,
        icon: String,
        accent: Color,
        detailHeight: CGFloat = Design.expandedTimelineDetailHeight,
        regularLaneHeight: CGFloat? = nil,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) -> some View {
        let isExpanded = expandedPreviewTab == tab
        let isCollapsed = expandedPreviewTab != nil && !isExpanded
        let laneHeight = isCollapsed ? Design.collapsedTimelineLaneHeight : (regularLaneHeight ?? Design.timelineLaneHeight)

        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                trackHeader(tab: tab, icon: icon, accent: accent, isExpanded: isExpanded, isCollapsed: isCollapsed, actions: actions)

                if !isCollapsed {
                    let sideButtonCount: CGFloat = 3
                    let sideButtonsHeight = Design.timelineLaneButtonSize * sideButtonCount
                    let visualGap = max(Design.timelineLaneVisualGap, (laneHeight - sideButtonsHeight) / (sideButtonCount + 1))
                    let contentHeight = max(Design.timelineLaneContentHeight, laneHeight - visualGap * 2)

                    content()
                        .frame(maxWidth: .infinity)
                        .frame(height: contentHeight)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(height: laneHeight)
            .padding(.horizontal, 8)

            if isExpanded {
                ZStack {
                    if visibleTimelineDetailTab == tab {
                        detail()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: detailHeight)
                .padding(.horizontal, 8)
                .padding(.top, 0)
                .padding(.bottom, 8)
                .clipped()
                .allowsHitTesting(visibleTimelineDetailTab == tab)
            }
        }
        .background(.white.opacity(isExpanded ? 0.055 : 0.035))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.white.opacity(isExpanded ? 0.11 : 0.07), lineWidth: 0.7)
        }
    }

    private func trackHeader<Actions: View>(
        tab: PreviewTab,
        icon: String,
        accent: Color,
        isExpanded: Bool,
        isCollapsed: Bool,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Button {
                toggleExpanded(tab)
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: Design.timelineLaneButtonSize, height: Design.timelineLaneButtonSize)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "收起\(tab.rawValue)" : "展开\(tab.rawValue)")

            if !isCollapsed {
                Spacer(minLength: 0)

                actions()
            }

            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.82))
        .frame(width: Design.timelineLaneButtonSize)
        .frame(maxHeight: .infinity)
    }

    private var audioSelectionButtonTitle: String {
        if audioInPoint == nil || audioOutPoint != nil { return "I" }
        return "O"
    }

    private var audioSelectionButtonHelp: String {
        if audioInPoint == nil || audioOutPoint != nil { return "设置声音 In 点" }
        return "设置声音 Out 点"
    }

    private func setNextAudioSelectionPoint() {
        if audioInPoint == nil || audioOutPoint != nil {
            setAudioInPoint()
        } else {
            setAudioOutPoint()
        }
    }

    private func setAudioInPoint() {
        audioInPoint = controller.elapsed
        audioOutPoint = nil
    }

    private func setAudioOutPoint() {
        guard audioInPoint != nil else { return }
        audioOutPoint = controller.elapsed
    }

    private func clearAudioSelection() {
        audioInPoint = nil
        audioOutPoint = nil
    }

    private func exportCurrentAudioSelection(for video: VideoItem) {
        guard let inT = audioInPoint, let outT = audioOutPoint else { return }
        guard libraryStore.audioClipExportProgressByVideoPath[video.url.path] == nil else { return }
        libraryStore.exportAudioClip(video: video, inTime: inT, outTime: outT)
        exportPanelFilter = .recent
        isExportPanelPresented = true
    }

    private func exportCurrentTranscript(for video: VideoItem) {
        guard libraryStore.exportTranscriptMarkdown(video: video) else { return }
        exportPanelFilter = .recent
        isExportPanelPresented = true
    }

    private var displayedAudioOutPoint: Double? {
        if let audioOutPoint { return audioOutPoint }
        guard audioInPoint != nil else { return nil }
        return controller.elapsed
    }

    private func trackHeaderButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: Design.timelineLaneButtonSize, height: Design.timelineLaneButtonSize)
        }
        .help(help)
    }

    private func trackHeaderTextButton(_ text: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.caption2.weight(.bold).monospaced())
                .frame(width: Design.timelineLaneButtonSize, height: Design.timelineLaneButtonSize)
        }
        .help(help)
    }

    @ViewBuilder
    private func audioSelectionActionButton(for video: VideoItem) -> some View {
        if audioInPoint != nil, audioOutPoint != nil {
            trackHeaderButton(icon: "square.and.arrow.up", help: "导出选区音频") {
                exportCurrentAudioSelection(for: video)
            }
            .disabled(libraryStore.audioClipExportProgressByVideoPath[video.url.path] != nil)
        } else {
            trackHeaderTextButton(audioSelectionButtonTitle, help: audioSelectionButtonHelp) {
                setNextAudioSelectionPoint()
            }
        }
    }


    private func toggleExpanded(_ tab: PreviewTab) {
        let nextExpandedTab: PreviewTab? = expandedPreviewTab == tab ? nil : tab

        withAnimation(timelineFadeAnimation) {
            activePreviewTab = tab
            expandedPreviewTab = nextExpandedTab
            visibleTimelineDetailTab = nextExpandedTab
            if let nextExpandedTab, isAnnotationPopoverPresented, annotationEditorAnchor.sourceTab != nextExpandedTab {
                isAnnotationPopoverPresented = false
                editingAnnotationID = nil
            }
        }

        if nextExpandedTab != nil {
            startRecognitionForVisibleTimelineIfNeeded(tab: tab)
        }
    }

    @ViewBuilder
    private func timelineDetailContent(_ tab: PreviewTab, for video: VideoItem) -> some View {
        switch tab {
        case .frames:
            ScenePanelView(
                video: video,
                controller: controller,
                sceneCuts: libraryStore.sceneCutsByVideoPath[video.url.path] ?? [],
                hasSceneRecognitionResult: libraryStore.sceneCutsByVideoPath[video.url.path] != nil,
                sceneDetectionProgress: libraryStore.sceneDetectionProgress[video.url.path],
                sceneThumbnailVersion: libraryStore.sceneThumbnailVersionsByVideoPath[video.url.path] ?? 0,
                sceneThumbnailsNeedHydration: libraryStore.sceneThumbnailsNeedHydration(for: video),
                isHydratingSceneThumbnails: libraryStore.isHydratingSceneThumbnails(for: video),
                sampledFrames: libraryStore.sampledFrames(for: video),
                activeItemID: activeSceneItemID(for: video)
            )
            .equatable()
        case .audio, .content:
            if tab == .audio {
                audioTimelineDetailContent(for: video)
            } else {
                contentTimelineDetailContent(for: video)
            }
        }
    }

    private func audioTimelineDetailContent(for video: VideoItem) -> some View {
        homeAudioClipList(for: video)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func contentTimelineDetailContent(for video: VideoItem) -> some View {
        let path = video.url.path
        let status = libraryStore.transcriptStatusByVideoPath[path]
        let segments = libraryStore.transcriptSegmentsByVideoPath[path, default: []]

        if segments.isEmpty {
            contentRecognitionStartBlock(for: video, status: status)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            HStack(alignment: .top, spacing: Self.contentTimelineDetailBlockGap) {
                subtitleTimelineBlock(for: video)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                videoNodeTimelineBlock(for: video)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func contentRecognitionStartBlock(for video: VideoItem, status: TranscriptJobStatus?) -> some View {
        if case let .running(message) = status {
            timelineProgressRow(message)
        } else if case let .failed(message) = status {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.yellow.opacity(0.82))
                .multilineTextAlignment(.center)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            timelineProgressRow("准备字幕分析…")
        }
    }

    @ViewBuilder
    private func subtitleTimelineBlock(for video: VideoItem) -> some View {
        let path = video.url.path
        let status = libraryStore.transcriptStatusByVideoPath[path]
        let segments = libraryStore.transcriptSegmentsByVideoPath[path, default: []]

        VStack(alignment: .leading, spacing: 8) {
            if case let .running(message) = status {
                timelineProgressRow(message)

                if !segments.isEmpty {
                    subtitleSegmentList(segments)
                }
            } else if segments.isEmpty {
                VStack(spacing: 10) {
                    if case let .failed(message) = status {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.yellow.opacity(0.82))
                            .multilineTextAlignment(.center)
                    } else {
                        AppEmptyState(
                            title: "暂无字幕",
                            style: .inline,
                            fillsWidth: false
                        )
                    }

                    Button {
                        libraryStore.transcribe(video: video)
                    } label: {
                        Label(statusFailed(status) ? "重试" : "生成字幕", systemImage: "text.badge.plus")
                    }
                    .buttonStyle(.borderless)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                subtitleSegmentList(segments)
            }
        }
        .padding(Self.contentTimelineDetailBlockPadding)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func videoNodeTimelineBlock(for video: VideoItem) -> some View {
        let segments = libraryStore.transcriptSegmentsByVideoPath[video.url.path, default: []]
        let chapters = loadedContentNodeChapters(for: video)

        VStack(alignment: .leading, spacing: 8) {
            switch contentNodeTimelineStatus {
            case let .running(videoPath) where videoPath == video.url.path:
                timelineProgressRow("正在整理视频节点…")
            case let .failed(videoPath, message) where videoPath == video.url.path:
                VStack(spacing: 10) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.yellow.opacity(0.82))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            default:
                if chapters.isEmpty {
                    if segments.isEmpty {
                        timelineProgressRow("等待字幕生成…")
                    } else {
                        timelineContentNodePrompt(video: video, segments: segments)
                    }
                } else {
                    videoNodeList(chapters, video: video)
                }
            }
        }
        .padding(Self.contentTimelineDetailBlockPadding)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func timelineProgressRow(_ message: String) -> some View {
        RecognitionProgressRow(
            message: message,
            progress: activityProgressValue(from: message)
        )
        .recognitionProgressCard()
    }

    private func timelineContentNodePrompt(video: VideoItem, segments: [TranscriptSegment]) -> some View {
        VStack(spacing: 10) {
            Button {
                generateContentNodeTimeline(video: video, segments: segments)
            } label: {
                Label("生成视频节点", systemImage: "sparkles")
            }
            .buttonStyle(.borderless)
            .help("使用本机 Ollama 文本模型把字幕整理成视频节点")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func subtitleSegmentList(_ segments: [TranscriptSegment]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(segments) { segment in
                        let isActive = segment.id == activeTranscriptSegmentID
                        Button {
                            controller.pause()
                            controller.seekToSeconds(segment.start)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Text(formatDuration(segment.start))
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(isActive ? Design.annotationAccent : Design.annotationAccent.opacity(0.62))
                                    .frame(width: 52, alignment: .leading)
                                Text(segment.text)
                                    .font(.caption)
                                    .foregroundStyle(isActive ? .primary : .secondary)
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 7)
                            .background(isActive ? Color.white.opacity(0.10) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .id(segment.id)
                    }
                }
            }
            .onChange(of: activeTranscriptSegmentID) { _, newID in
                if let newID {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
    }

    private func videoNodeList(_ chapters: [TranscriptTimelineChapter], video: VideoItem) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 7) {
                ForEach(chapters) { chapter in
                    let isActive = isActiveContentNode(chapter, in: chapters)
                    Button {
                        activeTranscriptSegmentID = chapter.segmentID
                        controller.pause()
                        controller.seekToSeconds(chapter.start)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text(formatDuration(chapter.start))
                                    .font(.caption2.monospacedDigit().weight(.bold))
                                    .foregroundStyle(Design.annotationAccent)
                                if let end = chapter.end {
                                    Text("- \(formatDuration(end))")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Text(chapter.type)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Text(chapter.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(chapter.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(isActive ? Color.white.opacity(0.12) : Color.white.opacity(0.055))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(.white.opacity(isActive ? 0.24 : 0.08), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(chapter.summary)
                }
            }
        }
    }

    private func loadedContentNodeChapters(for video: VideoItem) -> [TranscriptTimelineChapter] {
        if case let .loaded(videoPath, chapters) = contentNodeTimelineStatus,
           videoPath == video.url.path {
            return chapters
        }
        return []
    }

    private func isActiveContentNode(_ chapter: TranscriptTimelineChapter, in chapters: [TranscriptTimelineChapter]) -> Bool {
        let elapsed = controller.elapsed
        if elapsed >= chapter.start, elapsed <= (chapter.end ?? controller.duration) {
            return true
        }
        guard chapter.end == nil else { return false }
        return chapters.last { $0.start <= elapsed }?.id == chapter.id
    }

    private func canSeekAdjacentContentChapter(for video: VideoItem, direction: Int) -> Bool {
        adjacentContentChapter(for: video, direction: direction) != nil
    }

    private func seekAdjacentContentChapter(for video: VideoItem, direction: Int) {
        guard let chapter = adjacentContentChapter(for: video, direction: direction) else { return }
        activeTranscriptSegmentID = chapter.segmentID
        controller.seekToSeconds(chapter.start)
    }

    private func adjacentContentChapter(for video: VideoItem, direction: Int) -> TranscriptTimelineChapter? {
        let chapters = loadedContentNodeChapters(for: video).sorted { $0.start < $1.start }
        guard !chapters.isEmpty else { return nil }

        let elapsed = controller.elapsed
        let currentIndex = chapters.lastIndex { $0.start <= elapsed + 0.1 }

        if direction < 0 {
            guard let currentIndex else { return nil }
            let targetIndex = max(0, currentIndex - 1)
            return targetIndex == currentIndex ? nil : chapters[targetIndex]
        }

        if let currentIndex {
            let targetIndex = currentIndex + 1
            return chapters.indices.contains(targetIndex) ? chapters[targetIndex] : nil
        }

        return chapters.first
    }

    private func statusFailed(_ status: TranscriptJobStatus?) -> Bool {
        if case .failed = status { return true }
        return false
    }

    private func startRecognitionForVisibleTimelineIfNeeded(tab: PreviewTab? = nil) {
        guard let video = libraryStore.selectedVideo else { return }
        let timeline = tab ?? visibleTimelineDetailTab

        switch timeline {
        case .frames:
            startSceneRecognitionIfNeeded(for: video)
        case .content:
            startContentRecognitionIfNeeded(for: video)
        case .audio, .none:
            break
        }
    }

    private func hydrateSceneThumbnailsForFrameTimelineIfIdle() {
        guard
            let video = libraryStore.selectedVideo,
            !controller.isPlaying,
            activePreviewTab == .frames || visibleTimelineDetailTab == .frames
        else { return }

        libraryStore.hydrateSceneThumbnailsIfNeeded(for: video)
    }

    private func startSceneRecognitionIfNeeded(for video: VideoItem) {
        let path = video.url.path
        if libraryStore.sceneCutsByVideoPath[path] != nil {
            hydrateSceneThumbnailsForFrameTimelineIfIdle()
            return
        }

        guard
            libraryStore.sceneDetectionProgress[path] == nil
        else { return }

        libraryStore.detectSceneCuts(for: video)
    }

    private func startContentRecognitionIfNeeded(for video: VideoItem) {
        let path = video.url.path
        let segments = libraryStore.transcriptSegmentsByVideoPath[path, default: []]

        if segments.isEmpty {
            startSubtitleRecognitionIfNeeded(for: video)
        }
    }

    private func startSubtitleRecognitionIfNeeded(for video: VideoItem) {
        switch libraryStore.transcriptStatusByVideoPath[video.url.path] {
        case .running(_), .failed(_), .completed:
            return
        case .idle, .none:
            break
        }
        libraryStore.transcribe(video: video)
    }

    private func generateContentNodeTimeline(video: VideoItem, segments: [TranscriptSegment]) {
        guard !segments.isEmpty else { return }
        let authorName = libraryStore.videoAuthorName(for: video)
        contentNodeTimelineStatus = .running(videoPath: video.url.path)
        libraryStore.prepareExternalServiceWork()

        Task {
            do {
                let chapters = try await LocalTranscriptTimelineAnalyzer.analyze(
                    videoName: video.name,
                    videoAuthor: authorName,
                    segments: segments
                )
                await MainActor.run {
                    contentNodeTimelineStatus = .loaded(videoPath: video.url.path, chapters: chapters)
                }
            } catch {
                await MainActor.run {
                    contentNodeTimelineStatus = .failed(videoPath: video.url.path, message: LocalTranscriptTimelineAnalyzer.userFacingMessage(for: error))
                }
            }
        }
    }

    private func frameTimeline(for video: VideoItem, clock: PlaybackClockSnapshot) -> some View {
        let cuts = libraryStore.sceneCutsByVideoPath[video.url.path] ?? []

        return FrameScrubberView(
            frames: frameStripImages(for: video),
            progress: clock.progress,
            timecodeText: clock.timecodeText,
            sceneCuts: sceneStoryboardCuts(for: video),
            isPlaying: controller.isPlaying,
            togglePlayback: { controller.togglePlayback() },
            seek: { controller.seekToProgress($0) },
            screenshotMarkers: normalizedSampledFrames(for: video),
            annotationItems: normalizedAnnotations(for: video, kind: .frame),
            prevScene: prevSceneAction(cuts: cuts),
            nextScene: nextSceneAction(cuts: cuts),
            stepBack: { controller.stepFrame(by: -1) },
            stepForward: { controller.stepFrame(by: 1) },
            onScreenshot: { libraryStore.captureCurrentFrame(video: video, time: controller.elapsed) },
            onAnnotate: { beginAnnotation(.frame, sourceTab: .frames) },
            onAnnotationSelect: { openAnnotation($0, sourceTab: .frames) },
            viewportStart: timelineOffset,
            viewportSpan: timelineViewportSpan,
            duration: controller.duration,
            zoomLevel: timelineZoom,
            panViewport: panTimelineViewport,
            zoomViewport: zoomTimelineViewport,
            resetViewport: resetTimelineViewport,
            timelineHeight: Design.timelineLaneContentHeight,
            sceneImages: sceneStripImages(for: video)
        )
    }

    private func audioTimeline(for video: VideoItem, clock: PlaybackClockSnapshot) -> some View {
        let dur = controller.duration

        let outPoint = audioOutPoint ?? (audioInPoint == nil ? nil : clock.elapsed)

        return CenteredWaveformTimeline(
            samples: libraryStore.waveformSamplesByVideoPath[video.url.path],
            progress: clock.progress,
            seek: { controller.seekToProgress($0) },
            sceneCuts: [],
            inPoint: audioInPoint.map { dur > 0 ? $0 / dur : 0 },
            outPoint: outPoint.map { dur > 0 ? $0 / dur : 0 },
            annotationItems: normalizedAnnotations(for: video, kind: .audio),
            onAnnotationSelect: { openAnnotation($0, sourceTab: .audio) },
            onClearSelection: { clearAudioSelection() },
            viewportSpan: Design.centeredWaveformViewportSpan,
            playheadTint: timelinePlayheadTint,
            panViewport: panAudioTimelinePlayback
        )
    }

    private func contentTimeline(for video: VideoItem, clock: PlaybackClockSnapshot) -> some View {
        SimpleProgressBar(
            progress: clock.progress,
            timecodeText: clock.timecodeText,
            isPlaying: controller.isPlaying,
            togglePlayback: { controller.togglePlayback() },
            seek: { controller.seekToProgress($0) },
            chapters: loadedContentNodeChapters(for: video),
            duration: controller.duration,
            annotationItems: normalizedAnnotations(for: video),
            onAnnotationSelect: { openAnnotation($0, sourceTab: .content) },
            playheadTint: .white.opacity(0.92),
            stepBack: { controller.stepFrame(by: -1) },
            stepForward: { controller.stepFrame(by: 1) },
            onScreenshot: { libraryStore.captureCurrentFrame(video: video, time: controller.elapsed) },
            onAnnotate: { beginAnnotation(.content, sourceTab: .content) }
        )
    }

    private func openDetailWorkspace(_ workspace: AppWorkspace) {
        switch workspace {
        case .frames:
            activePreviewTab = .frames
        case .audio:
            activePreviewTab = .audio
        case .content:
            activePreviewTab = .content
        case .home, .music, .settings:
            break
        }
        openWorkspace(workspace)
    }

    private func annotationEditorView(for video: VideoItem) -> some View {
        let editingAnnotation = editingAnnotation(for: video)
        let title = editingAnnotation.map { "编辑\($0.kind.title)批注" }
            ?? "添加\(pendingAnnotationKind.title)批注 · \(previewTimecodeText)"

        return VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            TextEditor(text: $annotationText)
                .frame(width: 260, height: 88)
            HStack {
                if let editingAnnotation {
                    Button(role: .destructive) {
                        libraryStore.deleteAnnotation(editingAnnotation)
                        editingAnnotationID = nil
                        isAnnotationPopoverPresented = false
                    } label: {
                        Text("删除")
                    }
                }

                Spacer()
                Button("取消") {
                    editingAnnotationID = nil
                    isAnnotationPopoverPresented = false
                }
                Button("保存") {
                    if let editingAnnotation {
                        libraryStore.updateAnnotation(editingAnnotation, text: annotationText)
                    } else {
                        let annotationTime = controller.duration > 0
                            ? annotationEditorAnchor.progress * controller.duration
                            : controller.elapsed
                        libraryStore.addAnnotation(video: video, time: annotationTime, text: annotationText, kind: pendingAnnotationKind)
                    }
                    editingAnnotationID = nil
                    isAnnotationPopoverPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(annotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
    }

    private func beginAnnotation(_ kind: AnnotationItem.Kind, sourceTab: PreviewTab) {
        pendingAnnotationKind = kind
        editingAnnotationID = nil
        annotationText = ""
        annotationEditorAnchor = AnnotationEditorAnchor(
            progress: min(1, max(0, controller.progress)),
            kind: kind,
            sourceTab: sourceTab
        )
        isAnnotationPopoverPresented = true
    }

    private func openAnnotation(_ id: UUID, sourceTab: PreviewTab) {
        guard let annotation = libraryStore.annotations.first(where: { $0.id == id }) else { return }
        pendingAnnotationKind = annotation.kind
        editingAnnotationID = id
        annotationText = annotation.text
        let progress = controller.duration > 0 ? annotation.time / controller.duration : controller.progress
        annotationEditorAnchor = AnnotationEditorAnchor(
            progress: min(1, max(0, progress)),
            kind: annotation.kind,
            sourceTab: sourceTab
        )
        isAnnotationPopoverPresented = true
    }

    private func editingAnnotation(for video: VideoItem) -> AnnotationItem? {
        guard let editingAnnotationID else { return nil }
        return libraryStore.annotations(for: video).first { $0.id == editingAnnotationID }
    }

    // MARK: – Custom liquid-glass tab switcher

    private var previewTabSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(PreviewTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        activePreviewTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(activePreviewTab == tab ? .white : .white.opacity(0.45))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background {
                            if activePreviewTab == tab {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                .white.opacity(0.22),
                                                .white.opacity(0.12)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .overlay {
                                        Capsule()
                                            .stroke(.white.opacity(0.28), lineWidth: 0.5)
                                    }
                                    .shadow(color: .black.opacity(0.30), radius: 6, y: 2)
                                    .matchedGeometryEffect(id: "tabHighlight", in: tabNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(.black.opacity(0.32))
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.10), lineWidth: 0.5)
                }
        )
    }

    private func timelineActionButton(icon: String, label: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(.black.opacity(0.28))
                        .overlay { Capsule().stroke(.white.opacity(0.10), lineWidth: 0.5) }
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: – Timeline & content areas

    @ViewBuilder
    private func previewTimeline(for video: VideoItem) -> some View {
        PlaybackClockDrivenView(clock: controller.clock) { clock in
            switch activePreviewTab {
            case .frames:
                frameTimeline(for: video, clock: clock)
            case .audio:
                audioTimeline(for: video, clock: clock)
            case .content:
                contentTimeline(for: video, clock: clock)
            }
        }
    }

    @ViewBuilder
    private func audioSamplingBar(for video: VideoItem) -> some View {
        if activePreviewTab == .audio {
            HStack(spacing: 8) {
                Button("In") { setAudioInPoint() }
                    .help("设置声音 In 点")

                Button("Out") { setAudioOutPoint() }
                    .help("设置声音 Out 点")

                Divider().frame(height: 14)

                Button {
                    exportCurrentAudioSelection(for: video)
                } label: {
                    Label("导出声音", systemImage: "square.and.arrow.up")
                }
                .disabled(audioInPoint == nil || audioOutPoint == nil || libraryStore.audioClipExportProgressByVideoPath[video.url.path] != nil)
                .help("导出选区音频")

                Spacer()

                if let inT = audioInPoint {
                    Text("In \(formatDuration(inT))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let outT = audioOutPoint {
                    Text("Out \(formatDuration(outT))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let inT = audioInPoint, let outT = audioOutPoint {
                    Text("·  \(formatDuration(abs(outT - inT)))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.semibold))
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func previewTabContent(for video: VideoItem) -> some View {
        switch activePreviewTab {
        case .frames:
            ScenePanelView(
                video: video,
                controller: controller,
                sceneCuts: libraryStore.sceneCutsByVideoPath[video.url.path] ?? [],
                hasSceneRecognitionResult: libraryStore.sceneCutsByVideoPath[video.url.path] != nil,
                sceneDetectionProgress: libraryStore.sceneDetectionProgress[video.url.path],
                sceneThumbnailVersion: libraryStore.sceneThumbnailVersionsByVideoPath[video.url.path] ?? 0,
                sceneThumbnailsNeedHydration: libraryStore.sceneThumbnailsNeedHydration(for: video),
                isHydratingSceneThumbnails: libraryStore.isHydratingSceneThumbnails(for: video),
                sampledFrames: libraryStore.sampledFrames(for: video),
                activeItemID: activeSceneItemID(for: video)
            )
            .equatable()
        case .audio:
            homeAudioClipList(for: video)
        case .content:
            homeTranscriptSummary(for: video)
        }
    }

    @ViewBuilder
    private func homeAudioClipList(for video: VideoItem) -> some View {
        let clips = libraryStore.audioClips(for: video)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("已截取声音段")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("\(clips.count)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)

                if audioInPoint != nil || audioOutPoint != nil {
                    Button {
                        audioInPoint = nil
                        audioOutPoint = nil
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("清除当前声音选区")
                }
            }

            if let inT = audioInPoint {
                currentAudioSelectionCard(video: video, inTime: inT, outTime: displayedAudioOutPoint)
            }

            if let progress = libraryStore.audioClipExportProgressByVideoPath[video.url.path] {
                GenerationProgressRow(
                    message: "正在导出声音并生成波形",
                    progress: progress,
                    tint: .orange,
                    systemImage: "waveform.badge.plus",
                    compact: true
                )
                .padding(9)
                .background(.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if clips.isEmpty {
                AppEmptyState(
                    title: "暂无声音片段",
                    systemImage: "waveform",
                    style: .compact
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                            audioClipTimelineRow(clip, index: index + 1)
                        }
                    }
                    .padding(.trailing, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func currentAudioSelectionCard(video: VideoItem, inTime: Double, outTime: Double?) -> some View {
        let end = outTime ?? inTime
        let duration = abs(end - inTime)
        let canExport = audioOutPoint != nil && duration > 0.05
        let isExporting = libraryStore.audioClipExportProgressByVideoPath[video.url.path] != nil

        return HStack(spacing: 10) {
            Image(systemName: canExport ? "waveform.badge.plus" : "waveform")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(audioOutPoint == nil ? "当前声音选区" : "待导出声音段")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))
                Text("\(formatDuration(min(inTime, end))) - \(formatDuration(max(inTime, end))) · \(formatDuration(duration))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer(minLength: 0)

            Button {
                exportCurrentAudioSelection(for: video)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!canExport || isExporting)
            .help("导出当前声音选区")
        }
        .padding(9)
        .background(.white.opacity(0.075))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 0.7)
        }
    }

    private func audioClipTimelineRow(_ clip: AudioClipItem, index: Int) -> some View {
        let isPlaying = activeExportAudioClipID == clip.id
        let progress = isPlaying ? activeExportAudioProgress : 0
        let duration = max(0, clip.outTime - clip.inTime)

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(audioClipTitle(index: index))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(audioClipTimecode(duration: duration, progress: progress, isPlaying: isPlaying))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white.opacity(isPlaying ? 0.78 : 0.48))
                }
                .frame(height: 16, alignment: .center)

                AudioClipWaveformStrip(
                    samples: clip.waveformSamples,
                    isActive: isPlaying,
                    progress: progress
                )
                .frame(height: 58)
            }
            .frame(height: Self.exportRowContentHeight, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleExportAudioClipPlayback(clip)
            }
            .help(isPlaying ? "暂停声音片段" : "播放声音片段")
            .itemProviderDrag(audioClipDragProvider(for: clip))

            exportItemActionColumn(
                jumpHelp: "回到原视频位置",
                deleteHelp: "删除声音片段",
                onJump: {
                    audioInPoint = clip.inTime
                    audioOutPoint = clip.outTime
                    controller.pause()
                    controller.seekToSeconds(clip.inTime)
                },
                onDelete: {
                    deleteExportAudioClip(clip)
                }
            ) {
                InlineTagEditorButton(
                    title: "声音标签",
                    tags: clip.tags,
                    suggestedTags: libraryStore.allAudioTags,
                    buttonSize: 22,
                    onAdd: { libraryStore.addAudioTag($0, to: clip) },
                    onRemove: { libraryStore.removeAudioTag($0, from: clip) }
                )
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, Self.exportRowVerticalPadding)
        .frame(height: Self.exportRowHeight)
        .background(.white.opacity(isPlaying ? 0.075 : 0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isPlaying ? Color.orange.opacity(0.24) : .white.opacity(0.07), lineWidth: 0.7)
        }
        .onAppear {
            libraryStore.loadAudioClipWaveformIfNeeded(clip)
        }
        .help("选中并跳到该声音片段")
        .itemProviderDrag(audioClipDragProvider(for: clip))
    }

    private func audioClipDragProvider(for clip: AudioClipItem) -> (() -> NSItemProvider)? {
        guard libraryStore.audioClipFileURL(for: clip) != nil else { return nil }
        return {
            libraryStore.audioClipFileProvider(for: clip) ?? NSItemProvider()
        }
    }

    private func audioClipTitle(index: Int?) -> String {
        guard let index else { return "声音片段" }
        return String(format: "声音片段 %02d", index)
    }

    private func clipWidthRatio(_ clip: AudioClipItem) -> Double {
        guard controller.duration > 0 else { return 1 }
        return min(1, max(0.08, (clip.outTime - clip.inTime) / controller.duration))
    }

    @ViewBuilder
    private func homeMusicRecognitionPanel(for video: VideoItem) -> some View {
        let path = video.url.path
        let status = libraryStore.musicDetectionStatusByVideoPath[path]
        let songs = libraryStore.musicsByVideoPath[path, default: []]

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("音乐识别")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if case .running = status {
                    Button {
                        libraryStore.cancelMusicDetection(for: video)
                    } label: {
                        Image(systemName: "stop.circle")
                            .accessibilityLabel("停止")
                    }
                    .buttonStyle(.borderless)
                } else {
                    Button {
                        libraryStore.detectMusic(for: video)
                    } label: {
                        Label(songs.isEmpty ? "识别音乐" : "重新识别", systemImage: "music.note.list")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if case let .running(message) = status {
                RecognitionProgressRow(
                    message: message,
                    progress: activityProgressValue(from: message),
                    showPercent: false,
                    showStepCount: false
                )
                .recognitionProgressCard()

                if !songs.isEmpty {
                    homeMusicRows(songs: songs, videoPath: path)
                }
            } else if case .failed = status {
                AppEmptyState(
                    title: "暂无音乐识别结果",
                    systemImage: "music.note",
                    style: .compact,
                    minHeight: 82,
                    showsBackground: true
                )
            } else if status == .completed, songs.isEmpty {
                AppEmptyState(
                    title: "暂无音乐识别结果",
                    systemImage: "music.note",
                    style: .compact,
                    minHeight: 82,
                    showsBackground: true
                )
            } else if songs.isEmpty {
                AppEmptyState(
                    title: "暂无音乐识别记录",
                    systemImage: "music.note",
                    description: "识别视频中出现过的背景音乐，并显示歌名、作者、封面和 Apple Music 链接。",
                    style: .compact,
                    minHeight: 82,
                    showsBackground: true
                )
            } else {
                homeMusicRows(songs: songs, videoPath: path)
            }
        }
    }

    private func homeMusicRows(songs: [MusicRecognitionItem], videoPath: String) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(songs) { song in
                MusicRecognitionRow(song: song, videoPath: videoPath) {
                    controller.pause()
                    controller.seekToSeconds(song.detectedAt)
                }
            }
        }
    }

    @ViewBuilder
    private func homeTranscriptSummary(for video: VideoItem) -> some View {
        let segments = libraryStore.transcriptSegmentsByVideoPath[video.url.path, default: []]
        if case let .running(message) = libraryStore.transcriptStatusByVideoPath[video.url.path] {
            RecognitionProgressRow(
                message: message,
                progress: activityProgressValue(from: message)
            )
            .recognitionProgressCard()
        } else if segments.isEmpty {
            HStack(spacing: 10) {
                AppEmptyState(
                    title: "暂无字幕",
                    style: .inline,
                    fillsWidth: false
                )
                Button {
                    libraryStore.transcribe(video: video)
                } label: {
                    Label("生成字幕", systemImage: "text.badge.plus")
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 10)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(segments) { segment in
                            let isActive = segment.id == activeTranscriptSegmentID
                            Button {
                                controller.pause()
                                controller.seekToSeconds(segment.start)
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Text(formatDuration(segment.start))
                                        .font(.caption2.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(isActive ? .orange : .orange.opacity(0.55))
                                        .frame(width: 52, alignment: .leading)
                                    Text(segment.text)
                                        .font(.caption)
                                        .foregroundStyle(isActive ? .primary : .secondary)
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 7)
                                .background(isActive ? Color.white.opacity(0.10) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .id(segment.id)
                        }
                    }
                }
                .onChange(of: activeTranscriptSegmentID) { _, newID in
                    if let newID {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: – Helper views / computed properties

    private func frameStripImages(for video: VideoItem) -> [NSImage]? {
        guard let images = libraryStore.frameStripImagesByVideoPath[video.url.path],
              !images.isEmpty else { return nil }
        return images
    }

    /// 场景识别完成时返回每个场景的代表帧列表（index 0 = 片头帧，1…N = 切点首帧）。
    /// 未完成识别时返回 nil，FrameScrubberView 回退到均匀采样帧带。
    private func sceneStripImages(for video: VideoItem) -> [NSImage]? {
        guard let images = libraryStore.sceneStripImagesByVideoPath[video.url.path], !images.isEmpty else { return nil }
        return images
    }

    private func activeTranscriptSegmentID(at elapsed: Double, in segments: [TranscriptSegment]) -> UUID? {
        guard !segments.isEmpty else { return nil }
        var lower = 0
        var upper = segments.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if segments[middle].start <= elapsed {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        let index = lower - 1
        return segments.indices.contains(index) ? segments[index].id : nil
    }

    private func activeSceneItemID(for video: VideoItem) -> String? {
        guard let cuts = libraryStore.sceneCutsByVideoPath[video.url.path], !cuts.isEmpty else { return nil }
        let target = controller.elapsed
        var lower = 0
        var upper = cuts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if cuts[middle].time <= target {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        let idx = max(0, lower - 1)
        return "cut-\(cuts[idx].id)"
    }

    private var previewTimecodeText: String {
        formatDuration(controller.elapsed)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }


    private func normalizedSceneCuts(for video: VideoItem) -> [Double] {
        let path = video.url.path
        guard
            let cuts = libraryStore.sceneCutsByVideoPath[path],
            !cuts.isEmpty
        else {
            return libraryStore.sceneCutProgressesByVideoPath[path] ?? []
        }

        if let cached = libraryStore.sceneCutProgressesByVideoPath[path], !cached.isEmpty {
            return cached
        }

        guard
            controller.duration > 0
        else { return [] }
        return cuts.map { min(1, max(0, $0.time / controller.duration)) }
    }

    private func sceneStoryboardCuts(for video: VideoItem) -> [Double] {
        let cuts = normalizedSceneCuts(for: video)
        guard cuts.first.map({ $0 <= 0.001 }) == true else { return cuts }
        return Array(cuts.dropFirst())
    }

    private func normalizedSampledFrames(for video: VideoItem) -> [Double] {
        guard controller.duration > 0 else { return [] }
        return libraryStore.sampledFrames(for: video)
            .map { min(1, max(0, $0.time / controller.duration)) }
    }

    private var timelinePlayheadTint: Color {
        audioInPoint != nil && audioOutPoint == nil ? .orange : .white.opacity(0.92)
    }

    private func normalizedAnnotations(for video: VideoItem, kind: AnnotationItem.Kind? = nil) -> [TimelineAnnotationMarker] {
        guard controller.duration > 0 else { return [] }
        return libraryStore.annotations(for: video).compactMap { annotation in
            guard kind == nil || annotation.kind == kind else { return nil }
            return TimelineAnnotationMarker(
                id: annotation.id,
                progress: min(1, max(0, annotation.time / controller.duration)),
                text: annotation.text,
                kind: annotation.kind
            )
        }
    }

    private func prevSceneAction(cuts: [SceneCut]) -> (() -> Void)? {
        guard !cuts.isEmpty else { return nil }
        return {
            let t = self.controller.elapsed
            if let prev = cuts.last(where: { $0.time < t - 0.1 }) {
                self.controller.seekToSeconds(prev.time)
            } else {
                self.controller.seekToSeconds(0)
            }
        }
    }

    private func nextSceneAction(cuts: [SceneCut]) -> (() -> Void)? {
        guard !cuts.isEmpty else { return nil }
        return {
            let t = self.controller.elapsed
            if let next = cuts.first(where: { $0.time > t + 0.1 }) {
                self.controller.seekToSeconds(next.time)
            }
        }
    }

    private var timelineViewportSpan: Double {
        min(1, max(0.02, 1 / max(timelineZoom, 1)))
    }

    private func focusSceneTimelineOnOpeningIfNeeded() {
        guard
            activePreviewTab == .frames,
            let video = libraryStore.selectedVideo,
            timelineViewportSpan >= 0.999,
            timelineOffset <= 0.0005
        else { return }

        let cuts = sceneStoryboardCuts(for: video)
        guard !cuts.isEmpty else { return }

        let key = sceneTimelineOpeningFocusKey(for: video, cuts: cuts)
        guard sceneTimelineAutoFocusedKey != key else { return }

        sceneTimelineAutoFocusedKey = key
        guard let span = sceneTimelineOpeningSpan(from: cuts) else { return }

        timelineZoom = min(Design.sceneTimelineAutoMaxZoom, max(1, 1 / span))
        timelineOffset = 0
    }

    private func sceneTimelineOpeningFocusKey(for video: VideoItem, cuts: [Double]) -> String {
        let first = Int(((cuts.first ?? 0) * 1_000_000).rounded())
        let last = Int(((cuts.last ?? 0) * 1_000_000).rounded())
        return "\(libraryStore.selectedVideoSelectionID.uuidString):\(video.url.path):\(cuts.count):\(first):\(last)"
    }

    private func sceneTimelineOpeningSpan(from cuts: [Double]) -> Double? {
        let sceneCount = cuts.count + 1
        guard sceneCount > Design.sceneTimelineAutoVisibleSceneLimit else { return nil }

        let targetSpan = Double(Design.sceneTimelineAutoVisibleSceneLimit) / Double(sceneCount)
        let maxZoomSpan = 1 / Design.sceneTimelineAutoMaxZoom
        return min(1, max(maxZoomSpan, targetSpan))
    }

    private func panTimelineViewport(_ delta: Double) {
        let span = timelineViewportSpan
        let maxOffset = max(0, 1 - span)
        timelineOffset = min(maxOffset, max(0, timelineOffset + delta))
    }

    private func panAudioTimelinePlayback(_ delta: Double) {
        controller.seekToProgress(controller.progress + delta)
    }

    private func zoomTimelineViewport(_ factor: Double, anchor: Double) {
        let oldSpan = timelineViewportSpan
        let anchorProgress = timelineOffset + min(1, max(0, anchor)) * oldSpan
        let nextZoom = min(50, max(1, timelineZoom * factor))
        let nextSpan = min(1, max(0.02, 1 / nextZoom))
        let maxOffset = max(0, 1 - nextSpan)
        timelineZoom = nextZoom
        timelineOffset = min(maxOffset, max(0, anchorProgress - min(1, max(0, anchor)) * nextSpan))
    }

    private func resetTimelineViewport() {
        timelineZoom = 1
        timelineOffset = 0
    }

    private func keepTimelineProgressVisible(_ progress: Double) {
        let span = timelineViewportSpan
        guard span < 0.999 else { return }

        let clamped = min(1, max(0, progress))
        let maxOffset = max(0, 1 - span)
        let margin = min(0.08, span * 0.18)
        let visibleStart = timelineOffset
        let visibleEnd = timelineOffset + span
        let targetOffset: Double?

        if clamped < visibleStart + margin {
            targetOffset = max(0, clamped - margin)
        } else if clamped > visibleEnd - margin {
            targetOffset = min(maxOffset, clamped + margin - span)
        } else {
            targetOffset = nil
        }

        guard let targetOffset, abs(targetOffset - timelineOffset) > 0.0005 else { return }
        if controller.isPlaying || keyboardShuttleDirection != 0 {
            let now = Date()
            guard now.timeIntervalSince(lastTimelineAutoScrollAt) >= 0.18 else { return }
            lastTimelineAutoScrollAt = now
            timelineOffset = targetOffset
        } else {
            withAnimation(.easeOut(duration: 0.14)) {
                timelineOffset = targetOffset
            }
        }
    }

    private func handlePlaybackClockTick(_ elapsed: Double) {
        keepTimelineProgressVisible(controller.progress)

        guard let video = libraryStore.selectedVideo else { return }
        let segs = libraryStore.transcriptSegmentsByVideoPath[video.url.path, default: []]
        let segmentID = activeTranscriptSegmentID(at: elapsed, in: segs)
        if segmentID != activeTranscriptSegmentID {
            activeTranscriptSegmentID = segmentID
        }
    }

    private func togglePreviewPlayback() {
        stopKeyboardShuttle()
        controller.togglePlayback()
    }

    // MARK: – Keyboard control

    private func handlePreviewKeyboardCommand(_ command: PreviewKeyboardCommand) -> Bool {
        guard let selectedVideo = libraryStore.selectedVideo else { return false }

        switch command {
        case .togglePlayback:
            controller.togglePlayback()
        case .pause:
            stopKeyboardShuttle()
            controller.pause()
        case .shuttleForward:
            startKeyboardShuttle(direction: 1)
        case .shuttleBackward:
            startKeyboardShuttle(direction: -1)
        case .stopShuttle:
            stopKeyboardShuttle()
        case .increaseShuttleSpeed:
            increaseKeyboardShuttleSpeed()
        case .stepForward:
            stopKeyboardShuttle()
            controller.stepFrame(by: 1)
        case .stepBackward:
            stopKeyboardShuttle()
            controller.stepFrame(by: -1)
        case .previousSceneCut:
            stopKeyboardShuttle()
            seekSceneCut(for: selectedVideo, direction: -1)
        case .nextSceneCut:
            stopKeyboardShuttle()
            seekSceneCut(for: selectedVideo, direction: 1)
        case .setAudioIn:
            setAudioInPoint()
        case .setAudioOut:
            setAudioOutPoint()
        case .clearAudioSelection:
            clearAudioSelection()
        case .captureCurrentFrame:
            stopKeyboardShuttle()
            libraryStore.captureCurrentFrame(video: selectedVideo, time: controller.elapsed)
        case .exportAudioSelection:
            exportCurrentAudioSelection(for: selectedVideo)
        }

        return true
    }

    private func seekSceneCut(for video: VideoItem, direction: Int) {
        let cuts = libraryStore.sceneCutsByVideoPath[video.url.path] ?? []
        guard !cuts.isEmpty else { return }
        let elapsed = controller.elapsed

        if direction < 0 {
            if let previous = cuts.last(where: { $0.time < elapsed - 0.1 }) {
                controller.seekToSeconds(previous.time)
            } else {
                controller.seekToSeconds(0)
            }
            return
        }

        if let next = cuts.first(where: { $0.time > elapsed + 0.1 }) {
            controller.seekToSeconds(next.time)
        }
    }

    private func startKeyboardShuttle(direction: Int) {
        keyboardShuttleLastCommandAt = Date()
        guard keyboardShuttleDirection != direction else { return }

        stopKeyboardShuttle()
        keyboardShuttleDirection = direction
        keyboardShuttleFrameStep = 2
        controller.pause()
        controller.seekToSeconds(
            controller.elapsed + Double(direction) / max(controller.frameRate, 1),
            snapToFrame: true
        )

        keyboardShuttleTask = Task { @MainActor in
            let startedAt = Date()
            try? await Task.sleep(nanoseconds: 180_000_000)
            while !Task.isCancelled, keyboardShuttleDirection == direction {
                let now = Date()
                guard now.timeIntervalSince(startedAt) <= 8,
                      now.timeIntervalSince(keyboardShuttleLastCommandAt) <= 1.2
                else {
                    stopKeyboardShuttle()
                    break
                }

                let frameStep = Double(keyboardShuttleFrameStep) / max(controller.frameRate, 1)
                let next = controller.elapsed + Double(direction) * frameStep
                if direction > 0, next >= controller.duration {
                    controller.seekToSeconds(controller.duration, snapToFrame: true)
                    stopKeyboardShuttle()
                    break
                }
                if direction < 0, next <= 0 {
                    controller.seekToSeconds(0, snapToFrame: true)
                    stopKeyboardShuttle()
                    break
                }

                controller.seekToSeconds(next, snapToFrame: true)
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    private func increaseKeyboardShuttleSpeed() {
        guard keyboardShuttleDirection != 0 else { return }
        keyboardShuttleLastCommandAt = Date()
        keyboardShuttleFrameStep = min(keyboardShuttleFrameStep + 1, 12)
    }

    private func stopKeyboardShuttle() {
        keyboardShuttleTask?.cancel()
        keyboardShuttleTask = nil
        keyboardShuttleDirection = 0
        keyboardShuttleFrameStep = 2
        keyboardShuttleLastCommandAt = .distantPast
    }
}

// MARK: - Workspace Pages

private struct FrameStoryboardItem: Identifiable {
    let id: String
    let video: VideoItem
    let time: Double
    let cut: SceneCut?
    let sample: SampledFrame?
    let thumbnailImage: NSImage?
    let sceneIndex: Int?

    var isScreenshot: Bool {
        sample?.kind == .screenshot
    }

    var isExportedScene: Bool {
        sample?.kind == .sceneRepresentative && sample?.isExported == true
    }
}

private struct StoryboardVideoTimeline: View {
    let cuts: [Double]

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            var base = Path()
            base.addRoundedRect(
                in: CGRect(x: 0, y: size.height / 2 - 1, width: size.width, height: 2),
                cornerSize: CGSize(width: 1, height: 1)
            )
            context.fill(base, with: .color(.white.opacity(0.14)))

            for progress in cuts {
                let clamped = min(1, max(0, progress))
                let x = size.width * CGFloat(clamped)
                var line = Path()
                line.addRoundedRect(
                    in: CGRect(x: x - 0.5, y: 1, width: 1, height: size.height - 2),
                    cornerSize: CGSize(width: 0.5, height: 0.5)
                )
                context.fill(line, with: .color(.white.opacity(0.62)))
            }
        }
    }
}

private struct FullResolutionFramePreview: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let videoURL: URL
    let time: Double
    let fallbackImage: NSImage?
    let dragItemProvider: (() -> NSItemProvider)?
    @State private var fullResolutionImage: NSImage?
    @State private var isLoadingFullResolution = false

    private var previewKey: String {
        "\(videoURL.path)#\(Int((max(0, time) * 1000).rounded()))"
    }

    var body: some View {
        previewContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                if isLoadingFullResolution, fallbackImage != nil {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .background(.black.opacity(0.42))
                        .clipShape(Circle())
                        .padding(8)
                }
            }
            .fullResolutionImageDrag(dragItemProvider)
            .task(id: previewKey) {
                await loadFullResolutionImage(for: previewKey)
            }
    }

    @ViewBuilder
    private var previewContent: some View {
        if let image = fullResolutionImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else if let fallbackImage {
            Image(nsImage: fallbackImage)
                .resizable()
                .interpolation(.medium)
                .scaledToFit()
        } else {
            Color.black.opacity(0.24)
                .aspectRatio(16 / 9, contentMode: .fit)
        }
    }

    private func loadFullResolutionImage(for key: String) async {
        fullResolutionImage = nil
        isLoadingFullResolution = true
        let image = await libraryStore.fullResolutionFrameImage(videoURL: videoURL, time: time)
        guard !Task.isCancelled, key == previewKey else { return }
        fullResolutionImage = image
        isLoadingFullResolution = false
    }
}

private struct FramesWorkspaceView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Binding var selectedVideoPath: String?
    @Binding var selectedFrameID: UUID?
    let goHome: (String, Double) -> Void
    @AppStorage("frameBoardGridSize") private var frameBoardGridSize = 1
    @AppStorage("storyboardVideoPickerGridSize") private var storyboardVideoPickerGridSize = 2
    @State private var boardMode: FramesBoardMode = .storyboard
    @State private var selectedFrameTags: Set<String> = []
    @State private var isFrameTagFilterPresented = false
    @State private var isStoryboardVideoPickerPresented = false
    @State private var detailFrame: SampledFrame?
    @State private var detailStoryboardItem: FrameStoryboardItem?
    @State private var frameAnalysisState: FrameAnalysisState = .idle
    @State private var analyzedFrameID: UUID?
    @State private var frameAnalysisTask: Task<Void, Never>?

    private var storyboardVideos: [VideoItem] {
        libraryStore.videos.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var storyboardVideoPaths: [String] {
        storyboardVideos.map { $0.url.path }
    }

    private var selectedStoryboardVideo: VideoItem? {
        if let selectedVideoPath,
           let video = storyboardVideos.first(where: { $0.url.path == selectedVideoPath }) {
            return video
        }
        return storyboardVideos.first
    }

    private var allExportedFrames: [SampledFrame] {
        libraryStore.collectedFrames
    }

    private var tagFilteredFrames: [SampledFrame] {
        guard !selectedFrameTags.isEmpty else { return [] }
        let frames = libraryStore.collectedFrames.filter { frame in
            let frameTags = Set(frame.tags)
            return selectedFrameTags.allSatisfy { frameTags.contains($0) }
        }
        return sourceTimeSorted(frames)
    }

    private var tagSections: [(key: String, title: String, frames: [SampledFrame])] {
        guard !selectedFrameTags.isEmpty else { return [] }
        return selectedFrameTags.sorted().compactMap { tag -> (key: String, title: String, frames: [SampledFrame])? in
            let frames = tagFilteredFrames
                .filter { $0.tags.contains(tag) }
            guard !frames.isEmpty else { return nil }
            return (key: tag, title: tag, frames: frames)
        }
    }

    private var gridColumns: [GridItem] {
        let clampedSize = min(max(frameBoardGridSize, 0), 2)
        let count = [5, 4, 3][clampedSize]
        return Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10),
            count: count
        )
    }

    private var storyboardVideoPickerColumnCount: Int {
        let clampedSize = min(max(storyboardVideoPickerGridSize, 0), 2)
        return max(1, 3 - clampedSize)
    }

    private var storyboardVideoPickerColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8),
            count: storyboardVideoPickerColumnCount
        )
    }

    private var storyboardVideoPickerWidth: CGFloat {
        560
    }

    private var storyboardVideoPickerHeight: CGFloat {
        let maxContentHeight = (1 ... 3)
            .map { columnCount in
                let rowCount = Int(ceil(Double(storyboardVideos.count) / Double(columnCount)))
                let rowHeight = storyboardVideoPickerItemHeight(for: columnCount)
                return CGFloat(rowCount) * rowHeight + CGFloat(max(0, rowCount - 1)) * 8 + 70
            }
            .max() ?? 180
        return min(480, max(180, maxContentHeight))
    }

    var body: some View {
        ZStack {
            frameBoard

            if let frame = detailFrame {
                frameDetailOverlay(frame)
            }
            if let item = detailStoryboardItem {
                storyboardDetailOverlay(item)
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Design.sidebarBg)
        .onAppear {
            syncStoryboardSelectionIfNeeded()
        }
        .onChange(of: boardMode) { _, _ in
            syncStoryboardSelectionIfNeeded()
        }
        .onChange(of: selectedVideoPath) { _, _ in
            guard boardMode == .storyboard else { return }
            prepareStoryboard(for: selectedStoryboardVideo)
        }
        .onChange(of: storyboardVideoPaths) { _, _ in
            syncStoryboardSelectionIfNeeded()
        }
        .onDisappear {
            frameAnalysisTask?.cancel()
        }
    }

    private var frameBoard: some View {
        VStack(alignment: .leading, spacing: 12) {
            frameBoardToolbar

            switch boardMode {
            case .storyboard:
                storyboardFrameBoard
            case .collection:
                allExportedFrameBoard
            }
        }
        .padding(.top, Design.libraryToolbarTop)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var storyboardFrameBoard: some View {
        if let video = selectedStoryboardVideo {
            let items = storyboardItems(for: video)

            if items.isEmpty {
                VStack(spacing: 12) {
                    storyboardProgressView(for: video)
                    AppEmptyState(
                        title: storyboardEmptyTitle(for: video),
                        systemImage: "rectangle.stack",
                        description: storyboardEmptyDescription(for: video),
                        style: .large
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 14)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        storyboardProgressView(for: video)

                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                storyboardBoardCard(item, title: storyboardCardTitle(for: item, index: index))
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 14)
                }
                .scrollIndicators(.hidden)
                .background(HiddenScrollIndicators())
            }
        } else {
            AppEmptyState(
                title: "暂无视频",
                systemImage: "play.rectangle",
                description: "导入视频后，分镜模式会按视频展示分镜和截图。",
                style: .large
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)
        }
    }

    @ViewBuilder
    private var allExportedFrameBoard: some View {
        if allExportedFrames.isEmpty {
            AppEmptyState(
                title: "暂无收藏图片",
                systemImage: "photo.on.rectangle",
                style: .large
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
                    ForEach(Array(allExportedFrames.enumerated()), id: \.element.id) { index, frame in
                        frameBoardCard(frame, title: frameCardTitle(for: frame, index: index))
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 14)
            }
            .scrollIndicators(.hidden)
            .background(HiddenScrollIndicators())
        }
    }

    @ViewBuilder
    private var tagFilteredFrameBoard: some View {
        if selectedFrameTags.isEmpty {
            AppEmptyState(
                title: "请选择图片标签",
                systemImage: "tag",
                description: libraryStore.allFrameTags.isEmpty ? "给导出的图片添加标签后，这里会显示标签筛选。" : "点右上角标签按钮选择要查看的标签。",
                style: .large
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)
        } else if tagFilteredFrames.isEmpty {
            AppEmptyState(
                title: "没有匹配标签的画面",
                systemImage: "tag",
                style: .large
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(tagSections, id: \.key) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            frameSectionDivider(section.title)
                            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
                                ForEach(Array(section.frames.enumerated()), id: \.element.id) { index, frame in
                                    frameBoardCard(frame, title: frameCardTitle(for: frame, index: index))
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 14)
            }
            .scrollIndicators(.hidden)
            .background(HiddenScrollIndicators())
        }
    }

    private var frameBoardToolbar: some View {
        HStack(spacing: 12) {
            frameBoardModeControl

            if boardMode == .storyboard {
                storyboardVideoPicker
            }

            frameGridSizeControl

            Spacer(minLength: 4)
        }
        .frame(minHeight: Design.libraryToolbarHeight)
        .padding(.horizontal, 14)
    }

    private var frameTagFilterButton: some View {
        Button {
            isFrameTagFilterPresented.toggle()
        } label: {
            frameToolbarIcon(systemName: selectedFrameTags.isEmpty ? "tag" : "tag.fill", size: 12)
                .overlay(alignment: .topTrailing) {
                    if !selectedFrameTags.isEmpty {
                        Text("\(selectedFrameTags.count)")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -3)
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
        .contentShape(Rectangle())
        .help("图片标签筛选")
        .popover(isPresented: $isFrameTagFilterPresented, arrowEdge: .bottom) {
            frameTagFilterPopover
        }
    }

    private var frameBoardModeControl: some View {
        HStack(spacing: 3) {
            ForEach(FramesBoardMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        boardMode = mode
                    }
                } label: {
                    Label(mode.rawValue, systemImage: mode.icon)
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(boardMode == mode ? .primary : .secondary)
                        .frame(width: 74, height: 24)
                        .background(boardMode == mode ? Color.white.opacity(0.14) : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.white.opacity(0.055))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.08), lineWidth: 0.7)
        }
        .help("显示模式")
    }

    private var storyboardVideoPicker: some View {
        Button {
            isStoryboardVideoPickerPresented.toggle()
        } label: {
            toolbarMenuLabel(
                title: selectedStoryboardVideo?.name ?? "选择视频",
                systemImage: "film.stack",
                maxWidth: 260
            )
        }
        .buttonStyle(.plain)
        .frame(height: Design.libraryToolbarButtonSlotHeight)
        .disabled(storyboardVideos.isEmpty)
        .help("选择视频")
        .popover(isPresented: $isStoryboardVideoPickerPresented, arrowEdge: .bottom) {
            storyboardVideoPickerPopover
        }
    }

    private var storyboardVideoPickerPopover: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVGrid(columns: storyboardVideoPickerColumns, alignment: .leading, spacing: 8) {
                    ForEach(storyboardVideos) { video in
                        storyboardVideoPickerItem(video)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(10)
                .padding(.bottom, 42)
            }
            .scrollIndicators(.hidden)
            .background(HiddenScrollIndicators())

            storyboardVideoPickerSizeControl
                .padding(12)
        }
        .frame(width: storyboardVideoPickerWidth, height: storyboardVideoPickerHeight)
    }

    private func storyboardVideoPickerItem(_ video: VideoItem) -> some View {
        let path = video.url.path
        let isSelected = selectedStoryboardVideo?.url.path == path
        let cuts = libraryStore.sceneCutProgressesByVideoPath[path] ?? normalizedSceneCutProgresses(for: video)
        let columnCount = storyboardVideoPickerColumnCount

        return Button {
            selectedVideoPath = path
            prepareStoryboard(for: video)
            isStoryboardVideoPickerPresented = false
        } label: {
            if columnCount == 1 {
                storyboardVideoPickerListLabel(video: video, path: path, cuts: cuts, isSelected: isSelected)
            } else {
                storyboardVideoPickerGridLabel(video: video, path: path, cuts: cuts, isSelected: isSelected)
            }
        }
        .buttonStyle(.plain)
        .background(isSelected ? .white.opacity(0.08) : .white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(isSelected ? 0.14 : 0.06), lineWidth: 0.8)
        }
    }

    private func storyboardVideoPickerListLabel(
        video: VideoItem,
        path: String,
        cuts: [Double],
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 10) {
            storyboardVideoPickerThumbnail(path: path)
                .frame(width: 74, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(video.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if let duration = libraryStore.durationByVideoPath[path] {
                        Text(formatDuration(duration))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }

                StoryboardVideoTimeline(cuts: cuts)
                    .frame(height: 14)
            }

            storyboardVideoPickerSelectionIcon(isSelected: isSelected, size: 13)
        }
        .padding(8)
        .contentShape(Rectangle())
    }

    private func storyboardVideoPickerGridLabel(
        video: VideoItem,
        path: String,
        cuts: [Double],
        isSelected: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topTrailing) {
                storyboardVideoPickerThumbnail(path: path)
                    .frame(maxWidth: .infinity)
                    .frame(height: storyboardVideoPickerThumbnailHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                storyboardVideoPickerSelectionIcon(isSelected: isSelected, size: 12)
                    .padding(5)
                    .background(.black.opacity(0.34))
                    .clipShape(Circle())
                    .padding(5)
            }

            Text(video.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            if let duration = libraryStore.durationByVideoPath[path] {
                Text(formatDuration(duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            StoryboardVideoTimeline(cuts: cuts)
                .frame(height: 12)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: storyboardVideoPickerItemHeight(for: storyboardVideoPickerColumnCount), alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private func storyboardVideoPickerThumbnail(path: String) -> some View {
        ZStack {
            if let image = libraryStore.thumbnailImageByVideoPath[path] {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black.opacity(0.28)
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
        .clipped()
    }

    private func storyboardVideoPickerSelectionIcon(isSelected: Bool, size: CGFloat) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(isSelected ? .orange : .secondary)
    }

    private var storyboardVideoPickerThumbnailHeight: CGFloat {
        storyboardVideoPickerColumnCount == 2 ? 96 : 68
    }

    private func storyboardVideoPickerItemHeight(for columnCount: Int) -> CGFloat {
        columnCount == 1 ? 62 : (columnCount == 2 ? 154 : 126)
    }

    private var storyboardVideoPickerSizeControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.3x3")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { Double(storyboardVideoPickerGridSize) },
                    set: {
                        let nextSize = Int($0.rounded())
                        if storyboardVideoPickerGridSize != nextSize {
                            storyboardVideoPickerGridSize = nextSize
                        }
                    }
                ),
                in: 0...2
            )
            .frame(width: 64)
            .controlSize(.small)

            Image(systemName: "rectangle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.black.opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.24), radius: 12, y: 5)
        .help("调整下拉大小")
    }

    private var frameGridSizeControl: some View {
        HStack(spacing: 5) {
            Image(systemName: "square.grid.3x3")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { Double(frameBoardGridSize) },
                    set: {
                        let nextSize = Int($0.rounded())
                        if frameBoardGridSize != nextSize {
                            frameBoardGridSize = nextSize
                        }
                    }
                ),
                in: 0...2
            )
            .frame(width: 56)
            .controlSize(.small)
            .help("图片看板密度")

            Image(systemName: "rectangle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var frameTagFilterPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("图片标签筛选")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("全部") {
                    selectedFrameTags.removeAll()
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .disabled(selectedFrameTags.isEmpty)
            }

            if libraryStore.allFrameTags.isEmpty {
                AppEmptyState(title: "暂无图片标签", style: .inline, alignment: .leading)
                    .frame(minHeight: 36)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(libraryStore.allFrameTags, id: \.self) { tag in
                            Button {
                                toggleFrameTag(tag)
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: selectedFrameTags.contains(tag) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(selectedFrameTags.contains(tag) ? Color.orange : .secondary)
                                        .frame(width: 15)
                                    VideoTagColorDot(tag: tag)
                                    Text(tag)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(selectedFrameTags.contains(tag) ? Color.white.opacity(0.08) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 260)
                .scrollIndicators(.hidden)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private func syncStoryboardSelectionIfNeeded() {
        guard boardMode == .storyboard else { return }
        guard let video = selectedStoryboardVideo else {
            selectedVideoPath = nil
            return
        }

        if selectedVideoPath != video.url.path {
            selectedVideoPath = video.url.path
        }
        prepareStoryboard(for: video)
    }

    private func prepareStoryboard(for video: VideoItem?) {
        guard let video else { return }
        let path = video.url.path

        libraryStore.loadCachedSceneCuts(for: video)
        if libraryStore.sceneCutsByVideoPath[path] != nil {
            libraryStore.hydrateSceneThumbnailsIfNeeded(for: video)
        } else if libraryStore.sceneDetectionProgress[path] == nil {
            libraryStore.detectSceneCuts(for: video)
        }
    }

    private func storyboardItems(for video: VideoItem) -> [FrameStoryboardItem] {
        let path = video.url.path
        let samples = libraryStore.sampledFrames(for: video)
        guard let cuts = libraryStore.sceneCutsByVideoPath[path], !cuts.isEmpty else {
            return sourceTimeSorted(samples).map { sample in
                FrameStoryboardItem(
                    id: "sample-\(sample.id.uuidString)",
                    video: video,
                    time: sample.time,
                    cut: nil,
                    sample: sample,
                    thumbnailImage: libraryStore.thumbnailImage(for: sample),
                    sceneIndex: sample.sceneIndex
                )
            }
        }

        let representativeSamples = Dictionary(
            samples
                .filter { $0.kind == .sceneRepresentative }
                .map { (sceneSampleKey(for: $0.time), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var matchedSampleIDs = Set<UUID>()
        var items: [FrameStoryboardItem] = []

        for (index, cut) in cuts.enumerated() {
            let sample = representativeSamples[sceneSampleKey(for: cut.time)]
            if let sample {
                matchedSampleIDs.insert(sample.id)
            }

            items.append(FrameStoryboardItem(
                id: "cut-\(cut.id)",
                video: video,
                time: cut.time,
                cut: cut,
                sample: sample,
                thumbnailImage: sample.flatMap { libraryStore.thumbnailImage(for: $0) }
                    ?? libraryStore.displaySceneCutImage(for: video, cut: cut),
                sceneIndex: index
            ))
        }

        for sample in samples where sample.kind == .screenshot || !matchedSampleIDs.contains(sample.id) {
            items.append(FrameStoryboardItem(
                id: "sample-\(sample.id.uuidString)",
                video: video,
                time: sample.time,
                cut: nil,
                sample: sample,
                thumbnailImage: libraryStore.thumbnailImage(for: sample),
                sceneIndex: sample.sceneIndex
            ))
        }

        return items.sorted {
            if abs($0.time - $1.time) > 0.001 { return $0.time < $1.time }
            return $0.id < $1.id
        }
    }

    private func sourceTimeSorted(_ frames: [SampledFrame]) -> [SampledFrame] {
        frames.sorted {
            if $0.videoName == $1.videoName {
                if abs($0.time - $1.time) > 0.001 { return $0.time < $1.time }
                return $0.createdAt < $1.createdAt
            }
            return $0.videoName.localizedStandardCompare($1.videoName) == .orderedAscending
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

    @ViewBuilder
    private func storyboardProgressView(for video: VideoItem) -> some View {
        let path = video.url.path
        if let progress = libraryStore.sceneDetectionProgress[path] {
            RecognitionProgressRow(message: "正在识别分镜...", progress: progress)
                .recognitionProgressCard()
        } else if libraryStore.isHydratingSceneThumbnails(for: video) {
            RecognitionProgressRow(message: "正在补齐分镜缩略图...", progress: nil, showPercent: false)
                .recognitionProgressCard()
        }
    }

    private func storyboardEmptyTitle(for video: VideoItem) -> String {
        if libraryStore.sceneDetectionProgress[video.url.path] != nil {
            return "正在生成分镜"
        }
        return libraryStore.sceneCutsByVideoPath[video.url.path] == nil ? "暂无分镜" : "这个视频暂无分镜或截图"
    }

    private func storyboardEmptyDescription(for video: VideoItem) -> String? {
        if libraryStore.sceneDetectionProgress[video.url.path] != nil {
            return "识别完成后会显示这个视频的分镜和截图。"
        }
        return "切到主页截图或完成分镜识别后会出现在这里。"
    }

    private func toggleFrameTag(_ tag: String) {
        if selectedFrameTags.contains(tag) {
            selectedFrameTags.remove(tag)
        } else {
            selectedFrameTags.insert(tag)
        }
    }

    private func frameToolbarIcon(systemName: String, size: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Design.libraryToolbarIconTint)
            .frame(
                width: Design.libraryToolbarButtonSlotWidth,
                height: Design.libraryToolbarButtonSlotHeight,
                alignment: .center
            )
    }

    private func toolbarMenuLabel(title: String, systemImage: String, maxWidth: CGFloat) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Design.libraryToolbarIconTint)
                .frame(width: 14)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: maxWidth, minHeight: Design.libraryToolbarButtonSlotHeight, maxHeight: Design.libraryToolbarButtonSlotHeight)
        .background(.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.7)
        }
    }

    private func frameSectionDivider(_ title: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 10)
    }

    private func storyboardBoardCard(_ item: FrameStoryboardItem, title: String) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                activateStoryboardItem(item)
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    ZStack(alignment: .bottomTrailing) {
                        if let image = item.thumbnailImage {
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.medium)
                                .scaledToFill()
                        } else {
                            Color.black.opacity(0.26)
                        }

                        if item.isScreenshot {
                            CaptureFrameBadge()
                                .padding(.leading, 8)
                                .padding(.bottom, 7)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        }
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    Text(title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 5) {
                        Text(item.isScreenshot ? "截图" : "分镜")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let sample = item.sample {
                            ScaledCardTagCloud(tags: Array(sample.tags.prefix(3)))
                        }
                    }
                    .frame(height: 18, alignment: .leading)
                }
                .padding(8)
                .background(.white.opacity(item.isExportedScene || item.isScreenshot ? 0.055 : 0.034))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(storyboardCardStroke(for: item), lineWidth: 0.8)
                }
            }
            .buttonStyle(.plain)
            .fullResolutionImageDrag {
                storyboardDragProvider(for: item)
            }
            .help(item.sample == nil ? "回到原视频这个分镜" : "\(item.video.name) · \(clockText(item.time))")

            if let sample = item.sample {
                InlineTagEditorButton(
                    title: "图片标签",
                    tags: sample.tags,
                    suggestedTags: libraryStore.allFrameTags,
                    onAdd: { libraryStore.addFrameTag($0, to: sample) },
                    onRemove: { libraryStore.removeFrameTag($0, from: sample) }
                )
                .padding(8)
            } else if let cut = item.cut {
                Button {
                    libraryStore.markSceneFrameExported(video: item.video, cut: cut, sceneIndex: item.sceneIndex)
                } label: {
                    cardOverlayExportButtonIcon()
                }
                .buttonStyle(.plain)
                .padding(14)
                .help("导出这张分镜")
            }
        }
    }

    private func storyboardCardStroke(for item: FrameStoryboardItem) -> Color {
        if item.sample?.id == selectedFrameID {
            return .white.opacity(0.36)
        }
        if item.isScreenshot {
            return .white.opacity(0.10)
        }
        return .white.opacity(item.isExportedScene ? 0.10 : 0.07)
    }

    private func activateStoryboardItem(_ item: FrameStoryboardItem) {
        if let sample = item.sample {
            selectedFrameID = sample.id
            detailFrame = latestFrame(sample)
        } else {
            detailStoryboardItem = item
        }
    }

    private func storyboardDragProvider(for item: FrameStoryboardItem) -> NSItemProvider {
        if let sample = item.sample {
            return libraryStore.fullResolutionFrameProvider(for: sample)
        }

        return libraryStore.fullResolutionFrameProvider(
            video: item.video,
            time: storyboardOriginalFrameTime(for: item),
            kind: .sceneRepresentative,
            fallbackImage: item.thumbnailImage
        )
    }

    private func frameBoardCard(_ frame: SampledFrame, title: String) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                selectedFrameID = frame.id
                detailFrame = latestFrame(frame)
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    ZStack(alignment: .bottomTrailing) {
                        if let image = libraryStore.thumbnailImage(for: frame) {
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.medium)
                                .scaledToFill()
                        } else {
                            Color.black.opacity(0.26)
                        }
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    Text(title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 5) {
                        Text(frame.kind == .screenshot ? "截图" : "场景")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ScaledCardTagCloud(tags: Array(frame.tags.prefix(3)))
                    }
                    .frame(height: 18, alignment: .leading)
                }
                .padding(8)
                .background(.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selectedFrameID == frame.id ? .white.opacity(0.36) : .white.opacity(0.08), lineWidth: 0.8)
                }
            }
            .buttonStyle(.plain)
            .fullResolutionImageDrag {
                libraryStore.fullResolutionFrameProvider(for: frame)
            }

            InlineTagEditorButton(
                title: "图片标签",
                tags: frame.tags,
                suggestedTags: libraryStore.allFrameTags,
                onAdd: { libraryStore.addFrameTag($0, to: frame) },
                onRemove: { libraryStore.removeFrameTag($0, from: frame) }
            )
            .padding(8)
        }
    }

    private func storyboardCardTitle(for item: FrameStoryboardItem, index: Int) -> String {
        let number = String(format: "%02d", (item.sceneIndex ?? index) + 1)
        return item.isScreenshot ? "截图 \(number)" : "分镜 \(number)"
    }

    private func frameCardTitle(for frame: SampledFrame, index: Int) -> String {
        let number = String(format: "%02d", (frame.sceneIndex ?? index) + 1)
        return frame.kind == .screenshot ? "截图 \(number)" : "画面 \(number)"
    }

    private func frameDetailOverlay(_ frame: SampledFrame) -> some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture {
                    detailFrame = nil
                }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(frame.videoName)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(clockText(frame.time)) · \(frame.kind == .screenshot ? "手动截图帧" : "场景代表帧")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        detailFrame = nil
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }

                selectedFramePreview(frame)
                    .frame(maxWidth: .infinity, maxHeight: 430)
                    .background(Color.black.opacity(0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                ColorSwatches(imageData: frame.thumbnailData, orientation: .horizontal)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    InlineTagEditorButton(
                        title: "图片标签",
                        tags: latestFrame(frame).tags,
                        suggestedTags: libraryStore.allFrameTags,
                        onAdd: { libraryStore.addFrameTag($0, to: frame); detailFrame = latestFrame(frame) },
                        onRemove: { libraryStore.removeFrameTag($0, from: frame); detailFrame = latestFrame(frame) }
                    )

                    Spacer()

                    Button {
                        detailFrame = nil
                        goHome(frame.videoPath, frame.time)
                    } label: {
                        Label("回到原视频", systemImage: "arrowshape.turn.up.left.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .frame(width: 720)
            .background(Design.sidebarBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.40), radius: 26, y: 16)
        }
        .zIndex(10)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }

    private func storyboardDetailOverlay(_ item: FrameStoryboardItem) -> some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture {
                    detailStoryboardItem = nil
                }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(storyboardCardTitle(for: item, index: item.sceneIndex ?? 0))
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(item.video.name) · \(clockText(item.time))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button {
                        detailStoryboardItem = nil
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }

                storyboardItemPreview(item)
                    .frame(maxWidth: .infinity, maxHeight: 430)
                    .background(Color.black.opacity(0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                ColorSwatches(imageData: storyboardColorData(for: item), orientation: .horizontal)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    if let sample = item.sample {
                        InlineTagEditorButton(
                            title: "图片标签",
                            tags: sample.tags,
                            suggestedTags: libraryStore.allFrameTags,
                            onAdd: { libraryStore.addFrameTag($0, to: sample) },
                            onRemove: { libraryStore.removeFrameTag($0, from: sample) }
                        )
                    }

                    Spacer()

                    Button {
                        detailStoryboardItem = nil
                        goHome(item.video.url.path, item.time)
                    } label: {
                        Label("回到原视频", systemImage: "arrowshape.turn.up.left.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .frame(width: 720)
            .background(Design.sidebarBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.40), radius: 26, y: 16)
        }
        .zIndex(10)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }

    private func latestFrame(_ frame: SampledFrame) -> SampledFrame {
        libraryStore.sampledFrame(id: frame.id) ?? frame
    }

    @ViewBuilder
    private func storyboardItemPreview(_ item: FrameStoryboardItem) -> some View {
        FullResolutionFramePreview(
            videoURL: item.video.url,
            time: storyboardOriginalFrameTime(for: item),
            fallbackImage: item.sample.flatMap { libraryStore.thumbnailImage(for: $0) } ?? item.thumbnailImage,
            dragItemProvider: { storyboardDragProvider(for: item) }
        )
    }

    private func storyboardColorData(for item: FrameStoryboardItem) -> Data {
        if let data = item.sample?.thumbnailData {
            return data
        }
        return jpegData(from: item.thumbnailImage) ?? Data()
    }

    private func jpegData(from image: NSImage?) -> Data? {
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.86])
    }

    @ViewBuilder
    private func selectedFramePreview(_ frame: SampledFrame) -> some View {
        FullResolutionFramePreview(
            videoURL: URL(fileURLWithPath: frame.videoPath),
            time: frame.time,
            fallbackImage: libraryStore.thumbnailImage(for: frame),
            dragItemProvider: { libraryStore.fullResolutionFrameProvider(for: frame) }
        )
    }

    private func storyboardOriginalFrameTime(for item: FrameStoryboardItem) -> Double {
        if let sample = item.sample {
            return sample.time
        }
        return item.cut == nil ? item.time : item.time + 0.08
    }

    private func frameAnalysisView(for frame: SampledFrame) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                analyzeFrame(frame)
            } label: {
                Label(isAnalyzingCurrentFrame(frame) ? "正在分析" : "分析画面", systemImage: "sparkles")
            }
            .disabled(isAnalyzingCurrentFrame(frame))
            .buttonStyle(.bordered)
            .help("使用本机 Ollama 视觉模型分析景别、构图和色调")

            switch frameAnalysisState {
            case .idle:
                EmptyView()
            case .loading where analyzedFrameID == frame.id:
                RecognitionProgressRow(
                    message: "正在调用本机视觉模型...",
                    progress: nil,
                    showPercent: false
                )
                .recognitionProgressCard()
            case let .loaded(analysis) where analyzedFrameID == frame.id:
                FrameAnalysisSummary(analysis: analysis)
            case let .failed(message) where analyzedFrameID == frame.id:
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
            }
        }
    }

    private func isAnalyzingCurrentFrame(_ frame: SampledFrame) -> Bool {
        if case .loading = frameAnalysisState, analyzedFrameID == frame.id {
            return true
        }
        return false
    }

    private func analyzeFrame(_ frame: SampledFrame) {
        frameAnalysisTask?.cancel()
        analyzedFrameID = frame.id
        frameAnalysisState = .loading
        libraryStore.prepareExternalServiceWork()

        frameAnalysisTask = Task { @MainActor in
            do {
                let analysis = try await LocalFrameAnalyzer.analyze(imageData: frame.thumbnailData)
                guard !Task.isCancelled, analyzedFrameID == frame.id else { return }
                frameAnalysisState = .loaded(analysis)
            } catch {
                guard !Task.isCancelled, analyzedFrameID == frame.id else { return }
                frameAnalysisState = .failed(LocalFrameAnalyzer.userFacingMessage(for: error))
            }
        }
    }
}

private enum FrameAnalysisState {
    case idle
    case loading
    case loaded(FrameImageAnalysis)
    case failed(String)
}

private struct FrameImageAnalysis: Codable {
    var shotSize: String
    var composition: String
    var color: String
}

private struct FrameAnalysisSummary: View {
    let analysis: FrameImageAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            analysisRow("景别", value: analysis.shotSize)
            analysisRow("构图", value: analysis.composition)
            analysisRow("色调", value: analysis.color)
        }
        .font(.caption)
        .padding(10)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func analysisRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            Text(value.isEmpty ? "不确定" : value)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum LocalFrameAnalyzer {
    private static let endpoint = URL(string: "http://127.0.0.1:11434/api/generate")
        ?? URL(fileURLWithPath: "/dev/null")
    private static let model = "qwen3-vl:8b"

    struct RequestBody: Encodable {
        let model: String
        let prompt: String
        let images: [String]
        let stream: Bool
        let format: String
        let think: Bool
    }

    struct ResponseBody: Decodable {
        let response: String
        let thinking: String?
    }

    static func analyze(imageData: Data) async throws -> FrameImageAnalysis {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = RequestBody(
            model: model,
            prompt: prompt,
            images: [imageData.base64EncodedString()],
            stream: false,
            format: "json",
            think: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw AnalysisError.serviceUnavailable
        }

        let ollamaResponse = try JSONDecoder().decode(ResponseBody.self, from: data)
        let jsonText = ollamaResponse.response.isEmpty ? (ollamaResponse.thinking ?? "") : ollamaResponse.response
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw AnalysisError.invalidResponse
        }

        return try JSONDecoder().decode(FrameImageAnalysis.self, from: jsonData)
    }

    static func userFacingMessage(for error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .cannotConnectToHost {
            return "未连接到本机 Ollama。请先启动 Ollama，并安装视觉模型 \(model)。"
        }
        if error is DecodingError {
            return "模型返回格式无法解析，请重试或换用更稳定的视觉模型。"
        }
        if error is AnalysisError {
            return "本机视觉模型暂时不可用，请确认 Ollama 正在运行。"
        }
        return "分析失败：\(error.localizedDescription)"
    }

    private static var prompt: String {
        """
        你是影视拉片助手。请只根据这张画面本身分析三个条目，并返回严格 JSON，不要输出解释。
        不要猜导演、摄影师、作品名、真实镜头焦段、真实拍摄器材或画面外信息。
        景别只能从这些里选择：大远景、远景、全景、中全景、中景、中近景、近景、特写、大特写、不确定。
        构图从这些可见结构里选择 1 到 3 个，用中文顿号连接：中心构图、三分构图、对称构图、框中框、引导线构图、纵深构图、前景遮挡、留白构图、低角度构图、高角度构图、倾斜构图、紧密构图、开放构图、平衡构图、不确定。
        色调用一句中文概括主色、冷暖、明暗、饱和度和对比度；只描述画面可见色彩。
        JSON 格式：
        {
          "shotSize": "中景",
          "composition": "中心构图、纵深构图",
          "color": "暖色调为主，中间调，低饱和，中等对比"
        }
        """
    }

    enum AnalysisError: Error {
        case serviceUnavailable
        case invalidResponse
    }
}

private struct RecognizedMusicAsset: Identifiable {
    var videoPath: String
    var videoName: String
    var song: MusicRecognitionItem

    var id: String { "\(videoPath)-\(song.id.uuidString)" }
}

private struct MusicTagStrip: View {
    let tags: [String]

    private var visibleTags: [String] {
        Array(tags.prefix(4))
    }

    private var overflowCount: Int {
        max(0, tags.count - visibleTags.count)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visibleTags, id: \.self) { tag in
                CardInlineTagChip(tag: tag)
            }

            if overflowCount > 0 {
                VideoTagOverflowChip(count: overflowCount)
                    .frame(height: 18, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
        .clipped()
    }
}

private struct AudioWorkspaceView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let goHome: (String, Double) -> Void
    @State private var selectedAudioFilters: Set<AudioFilterOption> = []
    @State private var searchText = ""
    @State private var isAudioListScrolling = false

    var body: some View {
        let filteredLocalAssets = filteredLocalAudioAssets
        let filteredClips = filteredAudioClips

        VStack(alignment: .leading, spacing: 12) {
            audioHeader()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    audioEntriesSection(localAssets: filteredLocalAssets, clips: filteredClips)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .background(HiddenScrollIndicators())
            .onScrollPhaseChange { _, newPhase in
                let scrolling = newPhase.isScrolling
                if isAudioListScrolling != scrolling {
                    isAudioListScrolling = scrolling
                    if scrolling {
                        libraryStore.cancelPendingLocalWaveformLoads()
                    }
                }
            }
        }
        .padding(.top, Design.libraryToolbarTop)
        .padding(.bottom, 14)
        .background(Design.sidebarBg)
        .onAppear {
            libraryStore.scanResourceLibrary()
        }
    }

    private func audioHeader() -> some View {
        HStack(spacing: Design.libraryToolbarButtonGap) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("搜索名字、标签", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(.horizontal, 9)
            .frame(width: 240, height: 26)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            audioTagFilterMenu

            if !selectedAudioFilters.isEmpty {
                Button {
                    selectedAudioFilters.removeAll()
                } label: {
                    audioToolbarIcon(systemName: "xmark.circle", size: 12)
                }
                .buttonStyle(.plain)
                .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
                .contentShape(Rectangle())
                .help("清除筛选")
            }

            Spacer(minLength: 4)
        }
        .frame(minHeight: Design.libraryToolbarHeight)
        .padding(.horizontal, 14)
    }

    private var audioTagFilterMenu: some View {
        Menu {
            let tagValues = audioFilterValues(for: .tag)

            if tagValues.isEmpty {
                Button("暂无标签") {}
                    .disabled(true)
            } else {
                Button {
                    selectedAudioFilters = selectedAudioFilters.filter { $0.kind != .tag }
                } label: {
                    HStack {
                        if selectedAudioTagFilterCount == 0 { Image(systemName: "checkmark") }
                        Text("全部标签")
                    }
                }

                Divider()

                Section("标签") {
                    ForEach(tagValues, id: \.self) { value in
                        let option = AudioFilterOption(kind: .tag, value: value)
                        Button {
                            toggleAudioFilter(option)
                        } label: {
                            HStack {
                                Image(systemName: selectedAudioFilters.contains(option) ? "checkmark.square.fill" : "square")
                                VideoTagColorDot(tag: value)
                                Text(value)
                            }
                        }
                    }
                }
            }
        } label: {
            audioToolbarIcon(systemName: "tag", size: 12)
                .overlay(alignment: .topTrailing) {
                    if selectedAudioTagFilterCount > 0 {
                        Text("\(selectedAudioTagFilterCount)")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -3)
                    }
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
        .help("标签筛选")
    }

    @ViewBuilder
    private func audioFilterSection(kind: AudioFilterKind) -> some View {
        let values = audioFilterValues(for: kind)
        if !values.isEmpty {
            Divider()
            Section(kind.rawValue) {
                ForEach(values, id: \.self) { value in
                    let option = AudioFilterOption(kind: kind, value: value)
                    Button {
                        toggleAudioFilter(option)
                    } label: {
                        HStack {
                            Image(systemName: selectedAudioFilters.contains(option) ? "checkmark.square.fill" : "square")
                            if kind == .tag {
                                VideoTagColorDot(tag: value)
                            }
                            Text(value)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func audioEntriesSection(localAssets: [LocalAudioAsset], clips: [AudioClipItem]) -> some View {
        if libraryStore.localAudioAssets.isEmpty && libraryStore.audioClips.isEmpty {
            AppEmptyState(
                title: "暂无音效条目",
                systemImage: "waveform",
                style: .compact,
                minHeight: 90
            )
        } else if localAssets.isEmpty && clips.isEmpty {
            AppEmptyState(
                title: "没有匹配条目",
                systemImage: "line.3.horizontal.decrease.circle",
                style: .compact,
                minHeight: 90
            )
        } else {
            LazyVStack(spacing: 8) {
                ForEach(localAssets) { asset in
                    localAudioAssetRow(asset)
                }
                ForEach(clips) { clip in
                    audioClipAssetRow(clip)
                }
            }
        }
    }

    private func audioToolbarIcon(systemName: String, size: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Design.libraryToolbarIconTint)
            .frame(
                width: Design.libraryToolbarButtonSlotWidth,
                height: Design.libraryToolbarButtonSlotHeight,
                alignment: .center
            )
    }

    private func audioRowLayout(
        containerWidth: CGFloat,
        includesTagEditor: Bool,
        hasTags: Bool,
        prefersTimeRange: Bool
    ) -> (nameWidth: CGFloat, tagWidth: CGFloat, waveformWidth: CGFloat, timeWidth: CGFloat, showsTags: Bool) {
        let showsTags = hasTags && containerWidth >= (includesTagEditor ? 760 : 680)
        let horizontalPadding: CGFloat = includesTagEditor ? 18 : 20
        let visibleColumnCount = 3 + (showsTags ? 1 : 0) + (includesTagEditor ? 1 : 0)
        let spacingWidth = CGFloat(max(0, visibleColumnCount - 1)) * 14
        let timeWidth: CGFloat = prefersTimeRange
            ? (containerWidth < 760 ? 92 : 112)
            : (containerWidth < 640 ? 62 : 72)
        let fixedWidth = horizontalPadding + 28 + timeWidth + (includesTagEditor ? 24 : 0) + spacingWidth
        let flexibleWidth = max(0, containerWidth - fixedWidth)
        let tagWidth = showsTags ? min(170, max(84, flexibleWidth * 0.24)) : 0
        let preferredNameWidth: CGFloat = containerWidth < 760 ? 170 : 240
        let minimumNameWidth = min(100, flexibleWidth * 0.48)
        let targetNameWidth = flexibleWidth * (showsTags ? 0.34 : 0.42)
        let nameWidth = min(preferredNameWidth, max(minimumNameWidth, targetNameWidth))
        let waveformWidth = max(0, flexibleWidth - nameWidth - tagWidth)
        return (nameWidth, tagWidth, waveformWidth, timeWidth, showsTags)
    }

    private func localAudioAssetRow(_ asset: LocalAudioAsset) -> some View {
        let samples = libraryStore.localAudioWaveformSamplesByPath[asset.filePath]
        let tags = visibleTags(for: asset)

        return GeometryReader { proxy in
            let layout = audioRowLayout(
                containerWidth: proxy.size.width,
                includesTagEditor: false,
                hasTags: !tags.isEmpty,
                prefersTimeRange: false
            )

            HStack(alignment: .center, spacing: 14) {
                Button {
                    openLocalAudio(asset)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.orange)
                        .frame(width: 28, height: 28)
                        .background(.orange.opacity(0.13))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("播放音效")
                .disabled(libraryStore.localAudioFileURL(for: asset) == nil)

                Text(asset.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: layout.nameWidth, alignment: .leading)

                if layout.showsTags {
                    MusicTagStrip(tags: tags)
                        .frame(width: layout.tagWidth, alignment: .leading)
                }

                VStack(alignment: .trailing, spacing: 3) {
                    Text(asset.duration > 0 ? formatDuration(asset.duration) : asset.fileExtension.uppercased())
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(fileSizeText(asset.fileSize))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(width: layout.timeWidth, alignment: .trailing)

                audioWaveformColumn(samples: samples, width: layout.waveformWidth)
            }
            .padding(10)
            .frame(width: proxy.size.width, height: 72, alignment: .leading)
            .background(.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 0.7)
            }
        }
        .frame(height: 72)
        .task(id: "\(asset.filePath)|\(isAudioListScrolling)") {
            guard !isAudioListScrolling else { return }
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, !isAudioListScrolling else { return }
            libraryStore.loadLocalAudioWaveformIfNeeded(asset)
        }
        .onDisappear {
            libraryStore.cancelPendingLocalAudioWaveformLoad(for: asset)
        }
        .itemProviderDrag(localAudioDragProvider(for: asset))
        .help("可拖出音效文件")
    }

    private func audioClipAssetRow(_ clip: AudioClipItem) -> some View {
        let tags = visibleTags(for: clip)

        return GeometryReader { proxy in
            let layout = audioRowLayout(
                containerWidth: proxy.size.width,
                includesTagEditor: true,
                hasTags: !tags.isEmpty,
                prefersTimeRange: true
            )

            HStack(alignment: .center, spacing: 14) {
                Button {
                    openAudioClip(clip)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.orange)
                        .frame(width: 28, height: 28)
                        .background(.orange.opacity(0.13))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("播放音效")
                .disabled(libraryStore.audioClipFileURL(for: clip) == nil)

                Text(audioClipDisplayName(clip))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: layout.nameWidth, alignment: .leading)

                if layout.showsTags {
                    MusicTagStrip(tags: tags)
                        .frame(width: layout.tagWidth, alignment: .leading)
                }

                Button {
                    goHome(clip.videoPath, clip.inTime)
                } label: {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(clockText(clip.inTime)) - \(clockText(clip.outTime))")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text(formatDuration(clip.outTime - clip.inTime))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
                .buttonStyle(.plain)
                .help("跳到原视频时间段")
                .frame(width: layout.timeWidth, alignment: .trailing)

                audioWaveformColumn(samples: clip.waveformSamples, width: layout.waveformWidth)

                InlineTagEditorButton(
                    title: "声音标签",
                    tags: clip.tags,
                    suggestedTags: audioTagSuggestions(for: clip),
                    buttonSize: 24,
                    onAdd: { libraryStore.addAudioTag($0, to: clip) },
                    onRemove: { libraryStore.removeAudioTag($0, from: clip) }
                )
            }
            .padding(9)
            .frame(width: proxy.size.width, height: 72, alignment: .leading)
            .background(.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 0.7)
            }
        }
        .frame(height: 72)
        .task(id: "\(clip.id.uuidString)|\(isAudioListScrolling)") {
            guard !isAudioListScrolling else { return }
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, !isAudioListScrolling else { return }
            libraryStore.loadAudioClipWaveformIfNeeded(clip)
        }
        .itemProviderDrag(audioClipDragProvider(for: clip))
        .help("可拖出音效文件")
    }

    @ViewBuilder
    private func audioWaveformColumn(samples: [Double]?, width: CGFloat) -> some View {
        if isAudioListScrolling {
            AudioWaveformScrollPlaceholder()
                .frame(width: width, height: 42)
        } else {
            AudioClipWaveformStrip(samples: samples, isActive: false)
                .equatable()
                .frame(width: width, height: 42)
        }
    }

    private var filteredLocalAudioAssets: [LocalAudioAsset] {
        let query = normalizedSearch(searchText)
        guard !query.isEmpty || !selectedAudioFilters.isEmpty else {
            return libraryStore.localAudioAssets
        }
        return libraryStore.localAudioAssets.filter { asset in
            let tags = visibleTags(for: asset)
            let matchesSearch = query.isEmpty
                || normalizedSearch(asset.title).contains(query)
                || tags.contains { normalizedSearch($0).contains(query) }
            guard matchesSearch else { return false }
            return matchesSelectedAudioFilters(for: asset)
        }
    }

    private var filteredAudioClips: [AudioClipItem] {
        let query = normalizedSearch(searchText)
        guard !query.isEmpty || !selectedAudioFilters.isEmpty else {
            return libraryStore.audioClips.sorted { $0.createdAt > $1.createdAt }
        }
        return libraryStore.audioClips
            .filter { clip in
                let name = audioClipDisplayName(clip)
                let tags = visibleTags(for: clip)
                let matchesSearch = query.isEmpty
                    || normalizedSearch(name).contains(query)
                    || normalizedSearch(clip.videoName).contains(query)
                    || tags.contains { normalizedSearch($0).contains(query) }
                guard matchesSearch else { return false }
                return matchesSelectedAudioFilters(for: clip)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var audioFilterTags: [String] {
        let localTags = libraryStore.localAudioAssets.flatMap { visibleTags(for: $0) }
        let clipTags = libraryStore.audioClips.flatMap { visibleTags(for: $0) }
        return cleanedAudioTags(localTags + clipTags)
    }

    private var selectedAudioTagFilterCount: Int {
        selectedAudioFilters.filter { $0.kind == .tag }.count
    }

    private func audioFilterValues(for kind: AudioFilterKind) -> [String] {
        let values: [String]
        switch kind {
        case .name:
            values = libraryStore.localAudioAssets.map(\.title) + libraryStore.audioClips.map(audioClipDisplayName)
        case .tag:
            values = audioFilterTags
        }

        return cleanedAudioTags(values)
    }

    private func toggleAudioFilter(_ option: AudioFilterOption) {
        if selectedAudioFilters.contains(option) {
            selectedAudioFilters.remove(option)
        } else {
            selectedAudioFilters.insert(option)
        }
    }

    private func matchesSelectedAudioFilters(for asset: LocalAudioAsset) -> Bool {
        guard !selectedAudioFilters.isEmpty else { return true }
        let options = Set(
            [AudioFilterOption(kind: .name, value: asset.title.trimmingCharacters(in: .whitespacesAndNewlines))] +
            visibleTags(for: asset).map { AudioFilterOption(kind: .tag, value: $0) }
        )
        return selectedAudioFilters.allSatisfy { options.contains($0) }
    }

    private func matchesSelectedAudioFilters(for clip: AudioClipItem) -> Bool {
        guard !selectedAudioFilters.isEmpty else { return true }
        let options = Set(
            [AudioFilterOption(kind: .name, value: audioClipDisplayName(clip))] +
            visibleTags(for: clip).map { AudioFilterOption(kind: .tag, value: $0) }
        )
        return selectedAudioFilters.allSatisfy { options.contains($0) }
    }

    private func audioClipDisplayName(_ clip: AudioClipItem) -> String {
        let note = clip.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            return note
        }
        return clip.videoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名音效" : clip.videoName
    }

    private func visibleTags(for asset: LocalAudioAsset) -> [String] {
        cleanedAudioTags(asset.tags)
            .filter { !isAudioMetadataValue($0, names: [asset.title]) }
    }

    private func visibleTags(for clip: AudioClipItem) -> [String] {
        cleanedAudioTags(combinedTags(for: clip))
            .filter { !isAudioMetadataValue($0, names: [audioClipDisplayName(clip), clip.videoName]) }
    }

    private func isAudioMetadataValue(_ value: String, names: [String]) -> Bool {
        let valueKey = normalizedSearch(value)
        guard !valueKey.isEmpty else { return true }
        return names
            .map(normalizedSearch)
            .filter { !$0.isEmpty }
            .contains(valueKey)
    }

    private func cleanedAudioTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert(normalizedSearch($0)).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func sourceTags(for videoPath: String) -> [String] {
        libraryStore.tagsByVideoPath[videoPath, default: []]
    }

    private func combinedTags(for clip: AudioClipItem) -> [String] {
        Array(Set(clip.tags + sourceTags(for: clip.videoPath))).sorted()
    }

    private func audioTagSuggestions(for clip: AudioClipItem) -> [String] {
        Array(Set(libraryStore.allAudioTags + sourceTags(for: clip.videoPath))).sorted()
    }

    private func openAudioClip(_ clip: AudioClipItem) {
        guard let fileURL = libraryStore.audioClipFileURL(for: clip) else { return }
        NSWorkspace.shared.open(fileURL)
    }

    private func openLocalAudio(_ asset: LocalAudioAsset) {
        guard let fileURL = libraryStore.localAudioFileURL(for: asset) else { return }
        NSWorkspace.shared.open(fileURL)
    }

    private func audioClipDragProvider(for clip: AudioClipItem) -> (() -> NSItemProvider)? {
        guard libraryStore.audioClipFileURL(for: clip) != nil else { return nil }
        return {
            libraryStore.audioClipFileProvider(for: clip) ?? NSItemProvider()
        }
    }

    private func localAudioDragProvider(for asset: LocalAudioAsset) -> (() -> NSItemProvider)? {
        guard let fileURL = libraryStore.localAudioFileURL(for: asset) else { return nil }
        return { fileDragProvider(for: fileURL, suggestedName: fileURL.lastPathComponent) }
    }
}

private struct MusicWorkspaceView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let goHome: (String, Double) -> Void

    @State private var searchText = ""
    @State private var searchResults: [AppleMusicSearchResult] = []
    @State private var isSearching = false
    @State private var searchMessage: String?
    @State private var selectedMusicFilters: Set<MusicFilterOption> = []
    @State private var isMusicListScrolling = false

    var body: some View {
        let recognizedAssets = musicAssets
        let filteredRecognizedAssets = filteredRecognizedMusicAssets(from: recognizedAssets)
        let filteredSearchItems = filteredSearchResults
        let filterValues = musicFilterValues(from: recognizedAssets)
        let folderRecognitionID = libraryStore.localMusicAssets
            .map(\.filePath)
            .joined(separator: "|")

        VStack(alignment: .leading, spacing: 12) {
            musicHeader(filterValues: filterValues)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    searchSection(results: filteredSearchItems)
                    recognizedMusicSection(allAssets: recognizedAssets, filteredAssets: filteredRecognizedAssets)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .background(HiddenScrollIndicators())
            .onScrollPhaseChange { _, newPhase in
                let scrolling = newPhase.isScrolling
                if isMusicListScrolling != scrolling {
                    isMusicListScrolling = scrolling
                }
            }
        }
        .padding(.top, Design.libraryToolbarTop)
        .padding(.bottom, 14)
        .background(Design.sidebarBg)
        .onAppear {
            libraryStore.enrichMusicTagsIfNeeded()
            libraryStore.scanResourceLibrary()
            libraryStore.prepareExternalServiceWork()
        }
        .task(id: folderRecognitionID) {
            libraryStore.recognizeLocalMusicAssetsIfNeeded()
        }
        .task(id: searchText) {
            await runAppleMusicSearch()
        }
    }

    private func musicHeader(filterValues: [MusicFilterKind: [String]]) -> some View {
        HStack(spacing: Design.libraryToolbarButtonGap) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("搜索标题、作者、标签", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(.horizontal, 9)
            .frame(width: 280, height: 26)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            musicTagFilterMenu(filterValues: filterValues)
            musicMetadataFilterMenu(filterValues: filterValues)

            if !selectedMusicFilters.isEmpty {
                Button {
                    selectedMusicFilters.removeAll()
                } label: {
                    toolbarIcon(systemName: "xmark.circle", size: 12)
                }
                .buttonStyle(.plain)
                .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
                .contentShape(Rectangle())
                .help("清除筛选")
            }

            Spacer(minLength: 4)
        }
        .frame(minHeight: Design.libraryToolbarHeight)
        .padding(.horizontal, 14)
    }

    private func musicTagFilterMenu(filterValues: [MusicFilterKind: [String]]) -> some View {
        Menu {
            let tagValues = filterValues[.tag, default: []]

            if tagValues.isEmpty {
                Button("暂无标签") {}
                    .disabled(true)
            } else {
                Button {
                    selectedMusicFilters = selectedMusicFilters.filter { $0.kind != .tag }
                } label: {
                    HStack {
                        if selectedMusicTagFilterCount == 0 { Image(systemName: "checkmark") }
                        Text("全部标签")
                    }
                }

                Divider()

                Section("标签") {
                    ForEach(tagValues, id: \.self) { value in
                        let option = MusicFilterOption(kind: .tag, value: value)
                        Button {
                            toggleMusicFilter(option)
                        } label: {
                            HStack {
                                Image(systemName: selectedMusicFilters.contains(option) ? "checkmark.square.fill" : "square")
                                VideoTagColorDot(tag: value)
                                Text(value)
                            }
                        }
                    }
                }
            }
        } label: {
            toolbarIcon(systemName: "tag", size: 12)
                .overlay(alignment: .topTrailing) {
                    if selectedMusicTagFilterCount > 0 {
                        Text("\(selectedMusicTagFilterCount)")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -3)
                    }
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
        .help("标签筛选")
    }

    private func musicMetadataFilterMenu(filterValues: [MusicFilterKind: [String]]) -> some View {
        Menu {
            Button {
                selectedMusicFilters = selectedMusicFilters.filter { $0.kind == .tag }
            } label: {
                HStack {
                    if selectedMusicMetadataFilterCount == 0 { Image(systemName: "checkmark") }
                    Text("全部标题和作者")
                }
            }

            musicFilterSection(kind: .title, filterValues: filterValues)
            musicFilterSection(kind: .artist, filterValues: filterValues)
        } label: {
            toolbarIcon(systemName: "line.3.horizontal.decrease.circle", size: 12)
                .overlay(alignment: .topTrailing) {
                    if selectedMusicMetadataFilterCount > 0 {
                        Text("\(selectedMusicMetadataFilterCount)")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -3)
                    }
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
        .help("标题和作者筛选")
    }

    @ViewBuilder
    private func musicFilterSection(
        kind: MusicFilterKind,
        filterValues: [MusicFilterKind: [String]]
    ) -> some View {
        let values = filterValues[kind, default: []]
        if !values.isEmpty {
            Divider()
            Section(kind.rawValue) {
                ForEach(values, id: \.self) { value in
                    let option = MusicFilterOption(kind: kind, value: value)
                    Button {
                        toggleMusicFilter(option)
                    } label: {
                        HStack {
                            Image(systemName: selectedMusicFilters.contains(option) ? "checkmark.square.fill" : "square")
                            if kind == .tag {
                                VideoTagColorDot(tag: value)
                            }
                            Text(value)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func searchSection(results: [AppleMusicSearchResult]) -> some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty || isSearching || searchMessage != nil {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(title: "AM 搜索", count: results.count, icon: "magnifyingglass")

                if isSearching {
                    GenerationProgressRow(
                        message: "正在搜索 AM",
                        progress: nil,
                        tint: .white,
                        systemImage: "magnifyingglass",
                        compact: true,
                        showPercent: false
                    )
                } else if let searchMessage {
                    AppEmptyState(
                        title: searchMessage,
                        systemImage: "magnifyingglass",
                        style: .compact,
                        minHeight: 86
                    )
                } else if results.isEmpty {
                    AppEmptyState(
                        title: "没有匹配条目",
                        systemImage: "line.3.horizontal.decrease.circle",
                        style: .compact,
                        minHeight: 86
                    )
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(results) { item in
                            appleMusicResultRow(item)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recognizedMusicSection(
        allAssets: [RecognizedMusicAsset],
        filteredAssets: [RecognizedMusicAsset]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if allAssets.isEmpty {
                AppEmptyState(
                    title: folderMusicRecognitionStatusText ?? "暂无 AM 条目",
                    systemImage: "sparkles",
                    style: .compact,
                    minHeight: 90
                )
            } else if filteredAssets.isEmpty {
                AppEmptyState(
                    title: "没有匹配条目",
                    systemImage: "line.3.horizontal.decrease.circle",
                    style: .compact,
                    minHeight: 90
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredAssets) { asset in
                        recognizedMusicAssetRow(asset)
                    }
                }
            }
        }
    }

    private func musicRowLayout(
        containerWidth: CGFloat,
        hasTags: Bool,
        hasDownloadStatus: Bool,
        includesSafari: Bool
    ) -> (
        infoWidth: CGFloat,
        tagWidth: CGFloat,
        statusWidth: CGFloat,
        timeWidth: CGFloat,
        showsTags: Bool,
        showsDownloadStatus: Bool
    ) {
        let showsDownloadStatus = hasDownloadStatus && containerWidth >= 760
        let showsTags = hasTags && containerWidth >= (showsDownloadStatus ? 900 : 760)
        let timeWidth: CGFloat = 56
        let buttonsWidth: CGFloat = 160
        let safariWidth: CGFloat = includesSafari ? 24 : 0
        let visibleColumnCount = 4
            + (showsTags ? 1 : 0)
            + (showsDownloadStatus ? 1 : 0)
            + (includesSafari ? 1 : 0)
        let spacingWidth = CGFloat(max(0, visibleColumnCount - 1)) * 14
        let fixedWidth = 18 + 56 + timeWidth + buttonsWidth + safariWidth + spacingWidth
        let flexibleWidth = max(0, containerWidth - fixedWidth)
        let tagWidth = showsTags ? min(160, max(96, flexibleWidth * 0.22)) : 0
        let statusWidth = showsDownloadStatus ? min(300, max(132, flexibleWidth * 0.34)) : 0
        let remainingWidth = max(0, flexibleWidth - tagWidth - statusWidth)
        let infoWidth = min(containerWidth < 820 ? 210 : 270, max(120, remainingWidth))
        return (infoWidth, tagWidth, statusWidth, timeWidth, showsTags, showsDownloadStatus)
    }

    private func appleMusicResultRow(_ item: AppleMusicSearchResult) -> some View {
        let song = item.asMusicRecognitionItem()
        let downloadJobs = musicDownloadJobs(for: song, in: libraryStore.musicDownloadJobs)
        let visibleTags = visibleTags(for: song)

        return GeometryReader { proxy in
            let layout = musicRowLayout(
                containerWidth: proxy.size.width,
                hasTags: !visibleTags.isEmpty,
                hasDownloadStatus: !downloadJobs.isEmpty,
                includesSafari: URL(string: item.appleMusicURL) != nil
            )

            HStack(alignment: .center, spacing: 14) {
                musicArtwork(urlString: item.artworkURL, title: item.title, artist: item.artist)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title.isEmpty ? "未知曲目" : item.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(item.artist.isEmpty ? "未知作者" : item.artist)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: layout.infoWidth, alignment: .leading)

                if layout.showsTags {
                    MusicTagStrip(tags: visibleTags)
                        .frame(width: layout.tagWidth, alignment: .leading)
                }

                Text(item.duration > 0 ? formatDuration(item.duration) : "--:--")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .frame(width: layout.timeWidth, alignment: .trailing)

                if layout.showsDownloadStatus {
                    MusicDownloadInlineStatusStack(downloadJobs: downloadJobs)
                        .frame(width: layout.statusWidth, alignment: .leading)
                }

                musicDownloadButtons(song: song)

                if let url = URL(string: item.appleMusicURL) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "safari")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help("打开 AM 页面")
                }
            }
            .padding(9)
            .frame(width: proxy.size.width, height: 86, alignment: .leading)
            .background(.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 0.7)
            }
        }
        .frame(height: 86)
    }

    private func recognizedMusicAssetRow(_ asset: RecognizedMusicAsset) -> some View {
        let downloadJobs = musicDownloadJobs(for: asset.song, in: libraryStore.musicDownloadJobs)
        let visibleTags = visibleTags(for: asset.song)

        return GeometryReader { proxy in
            let layout = musicRowLayout(
                containerWidth: proxy.size.width,
                hasTags: !visibleTags.isEmpty,
                hasDownloadStatus: !downloadJobs.isEmpty,
                includesSafari: false
            )

            HStack(alignment: .center, spacing: 14) {
                Button {
                    goHome(asset.videoPath, asset.song.detectedAt)
                } label: {
                    HStack(spacing: 10) {
                        musicArtwork(
                            urlString: asset.song.artworkURL,
                            title: asset.song.title,
                            artist: asset.song.artist
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(asset.song.title.isEmpty ? "未知曲目" : asset.song.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(asset.song.artist.isEmpty ? "未知作者" : asset.song.artist)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(asset.videoName)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(width: layout.infoWidth, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("跳到视频中此段落")

                if layout.showsTags {
                    MusicTagStrip(tags: visibleTags)
                        .frame(width: layout.tagWidth, alignment: .leading)
                }

                Button {
                    goHome(asset.videoPath, asset.song.detectedAt)
                } label: {
                    Text(clockText(asset.song.detectedAt))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .frame(width: layout.timeWidth, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .help("跳到原视频时间点")

                if layout.showsDownloadStatus {
                    MusicDownloadInlineStatusStack(downloadJobs: downloadJobs)
                        .frame(width: layout.statusWidth, alignment: .leading)
                }

                musicDownloadButtons(song: asset.song)
            }
            .padding(9)
            .frame(width: proxy.size.width, height: 86, alignment: .leading)
            .background(.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 0.7)
            }
        }
        .frame(height: 86)
    }

    private func musicDownloadButtons(song: MusicRecognitionItem) -> some View {
        let jobs = musicDownloadJobs(for: song, in: libraryStore.musicDownloadJobs)
        let originalJob = jobs.first { $0.type == .original }
        let instrumentalJob = jobs.first { $0.type == .instrumental }

        return HStack(spacing: 6) {
            musicDownloadButton(song: song, type: .original, job: originalJob)
            musicDownloadButton(song: song, type: .instrumental, job: instrumentalJob)
        }
        .frame(width: 160, alignment: .trailing)
    }

    private func musicDownloadButton(
        song: MusicRecognitionItem,
        type: MusicDownloadJob.DownloadType,
        job: MusicDownloadJob?
    ) -> some View {
        let isDownloaded = completedMusicFileURL(for: job) != nil
        let isActive = job.map { isActiveDownloadStatus($0.status) } ?? false

        return Button {
            if let url = completedMusicFileURL(for: job) {
                NSWorkspace.shared.open(url)
            } else {
                libraryStore.downloadMusic(song: song, type: type)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: musicDownloadIcon(type: type, job: job))
                    .font(.system(size: 11, weight: .semibold))
                Text(musicDownloadTitle(type: type, job: job))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .foregroundStyle(isDownloaded ? .white.opacity(0.94) : .white.opacity(isActive ? 0.86 : 0.56))
            .frame(width: 76, height: 28)
            .background(.white.opacity(isDownloaded ? 0.15 : (isActive ? 0.10 : 0.045)))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.white.opacity(isDownloaded ? 0.18 : 0.07), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .disabled(isActive)
        .help(musicDownloadHelp(type: type, job: job))
        .contextMenu {
            Button {
                libraryStore.downloadMusic(song: song, type: type)
            } label: {
                Label("重新下载\(type.label)", systemImage: "arrow.clockwise")
            }
        }
    }

    private func sectionHeader(title: String, count: Int, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
            Text(title)
                .font(.headline.weight(.semibold))
            Text("\(count)")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.white.opacity(0.08))
                .clipShape(Capsule())
            Spacer()
        }
    }

    private func toolbarIcon(systemName: String, size: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Design.libraryToolbarIconTint)
            .frame(
                width: Design.libraryToolbarButtonSlotWidth,
                height: Design.libraryToolbarButtonSlotHeight,
                alignment: .center
            )
    }

    private func musicArtwork(urlString: String, title: String = "", artist: String = "") -> some View {
        MusicArtworkView(
            urlString: urlString,
            title: title,
            artist: artist,
            shouldLoad: !isMusicListScrolling
        )
            .frame(width: 56, height: 56)
    }

    private var musicAssets: [RecognizedMusicAsset] {
        let videoNameByPath = Dictionary(
            uniqueKeysWithValues: libraryStore.videos.map { ($0.url.path, $0.name) }
        )
        let localNameByPath = Dictionary(
            uniqueKeysWithValues: libraryStore.localMusicAssets.map { ($0.filePath, $0.title) }
        )

        return libraryStore.musicsByVideoPath.flatMap { path, songs in
            guard videoNameByPath[path] != nil || localNameByPath[path] != nil else {
                return [RecognizedMusicAsset]()
            }
            let videoName = videoNameByPath[path]
                ?? localNameByPath[path]
                ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            return songs
                .filter(isAMReadySong)
                .map { song in
                    RecognizedMusicAsset(videoPath: path, videoName: videoName, song: song)
                }
        }
        .sorted { lhs, rhs in
            if lhs.videoName == rhs.videoName {
                return lhs.song.detectedAt < rhs.song.detectedAt
            }
            return lhs.videoName.localizedStandardCompare(rhs.videoName) == .orderedAscending
        }
    }

    private var folderMusicRecognitionStatusText: String? {
        let assets = libraryStore.localMusicAssets
        guard !assets.isEmpty else { return nil }

        let unresolved = assets.filter { asset in
            let songs = libraryStore.musicsByVideoPath[asset.filePath, default: []]
            return songs.allSatisfy { !isAMReadySong($0) }
        }
        guard !unresolved.isEmpty else { return nil }

        if unresolved.contains(where: { asset in
            if case .running = libraryStore.musicDetectionStatusByVideoPath[asset.filePath] {
                return true
            }
            return false
        }) {
            return "正在识别文件夹内音乐"
        }

        let failedCount = unresolved.filter { asset in
            if case .failed = libraryStore.musicDetectionStatusByVideoPath[asset.filePath] {
                return true
            }
            return false
        }.count

        if failedCount == unresolved.count {
            return "文件夹内音乐暂未识别成功"
        }
        return "等待识别文件夹内音乐"
    }

    private var filteredSearchResults: [AppleMusicSearchResult] {
        searchResults.filter { item in
            let song = item.asMusicRecognitionItem()
            guard isAMReadySong(song) else { return false }
            return matchesSelectedMusicFilters(for: song)
        }
    }

    private func filteredRecognizedMusicAssets(from assets: [RecognizedMusicAsset]) -> [RecognizedMusicAsset] {
        let query = normalizedSearch(searchText)
        guard !query.isEmpty || !selectedMusicFilters.isEmpty else {
            return assets
        }
        return assets.filter { asset in
            let matchesSearch = query.isEmpty
                || normalizedSearch(asset.song.title).contains(query)
                || normalizedSearch(asset.song.artist).contains(query)
                || normalizedSearch(asset.videoName).contains(query)
                || visibleTags(for: asset.song).contains { normalizedSearch($0).contains(query) }
            guard matchesSearch else { return false }
            return matchesSelectedMusicFilters(for: asset)
        }
    }

    private func musicFilterValues(from assets: [RecognizedMusicAsset]) -> [MusicFilterKind: [String]] {
        let titleValues = assets.map(\.song.title)
        let artistValues = assets.map(\.song.artist)
        let tagValues = assets.flatMap { visibleTags(for: $0.song) }

        return [
            .title: cleanedMusicFilterValues(titleValues),
            .artist: cleanedMusicFilterValues(artistValues),
            .tag: cleanedMusicFilterValues(tagValues)
        ]
    }

    private func cleanedMusicFilterValues(_ values: [String]) -> [String] {
        Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var selectedMusicTagFilterCount: Int {
        selectedMusicFilters.filter { $0.kind == .tag }.count
    }

    private var selectedMusicMetadataFilterCount: Int {
        selectedMusicFilters.filter { $0.kind != .tag }.count
    }

    private func toggleMusicFilter(_ option: MusicFilterOption) {
        if selectedMusicFilters.contains(option) {
            selectedMusicFilters.remove(option)
        } else {
            selectedMusicFilters.insert(option)
        }
    }

    private func matchesSelectedMusicFilters(for asset: RecognizedMusicAsset) -> Bool {
        matchesSelectedMusicFilters(for: asset.song)
    }

    private func matchesSelectedMusicFilters(for song: MusicRecognitionItem) -> Bool {
        guard !selectedMusicFilters.isEmpty else { return true }
        let options = Set(filterOptions(for: song))
        return selectedMusicFilters.allSatisfy { options.contains($0) }
    }

    private func filterOptions(for song: MusicRecognitionItem) -> [MusicFilterOption] {
        let metadata = [
            MusicFilterOption(kind: .title, value: song.title.trimmingCharacters(in: .whitespacesAndNewlines)),
            MusicFilterOption(kind: .artist, value: song.artist.trimmingCharacters(in: .whitespacesAndNewlines))
        ]
        let tags = visibleTags(for: song).map { MusicFilterOption(kind: .tag, value: $0) }
        return (metadata + tags).filter { !$0.value.isEmpty }
    }

    private func visibleTags(for song: MusicRecognitionItem) -> [String] {
        MusicRecognitionItem.cleanedTags(song.tags)
            .filter { !isMetadataValue($0, for: song) }
    }

    private func isMetadataValue(_ value: String, for song: MusicRecognitionItem) -> Bool {
        let valueKey = normalizedSearch(value)
        guard !valueKey.isEmpty else { return true }

        let titleKey = normalizedSearch(song.title)
        let artistKey = normalizedSearch(song.artist)
        if valueKey == titleKey || valueKey == artistKey {
            return true
        }

        let separators = CharacterSet(charactersIn: ",，/、·&")
        let artistParts = song.artist
            .components(separatedBy: separators)
            .map(normalizedSearch)
            .filter { !$0.isEmpty }
        return artistParts.contains(valueKey)
    }

    private func isAMReadySong(_ song: MusicRecognitionItem) -> Bool {
        let hasTitle = !song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasArtist = !song.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasArtwork = normalizedMusicArtworkURL(song.artworkURL) != nil
            || !song.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAMLink = !song.appleMusicURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasTitle && hasArtist && hasArtwork && hasAMLink
    }

    private func runAppleMusicSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            searchMessage = nil
            isSearching = false
            return
        }

        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }

        isSearching = true
        searchMessage = nil
        libraryStore.prepareExternalServiceWork()
        do {
            let results = try await LibraryStore.searchAppleMusic(query: query)
            guard !Task.isCancelled else { return }
            searchResults = results
            searchMessage = results.isEmpty ? "没有搜索结果" : nil
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            searchMessage = "搜索失败"
        }
        isSearching = false
    }

}

nonisolated private func normalizedSearch(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
}

private func fileSizeText(_ size: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
}

private func fileDragProvider(for fileURL: URL, suggestedName: String) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.suggestedName = suggestedName
    let typeIdentifier = UTType(filenameExtension: fileURL.pathExtension)?.identifier ?? UTType.data.identifier

    provider.registerFileRepresentation(
        forTypeIdentifier: typeIdentifier,
        fileOptions: .openInPlace,
        visibility: .all
    ) { completion in
        let progress = Progress(totalUnitCount: 1)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            completion(nil, true, NSError(
                domain: "LapianBao.FileDrag",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "文件不存在"]
            ))
            return progress
        }

        progress.completedUnitCount = 1
        completion(fileURL, true, nil)
        return progress
    }

    provider.registerObject(fileURL as NSURL, visibility: .all)
    return provider
}

private enum AudioFilterKind: String, CaseIterable, Hashable {
    case name = "名字"
    case tag = "标签"
}

private struct AudioFilterOption: Identifiable, Hashable {
    var kind: AudioFilterKind
    var value: String

    var id: String { "\(kind.rawValue)|\(value)" }
}

private enum MusicFilterKind: String, CaseIterable, Hashable {
    case title = "标题"
    case artist = "作者"
    case tag = "标签"

    var sortOrder: Int {
        switch self {
        case .title: return 0
        case .artist: return 1
        case .tag: return 2
        }
    }
}

private struct MusicFilterOption: Identifiable, Hashable {
    var kind: MusicFilterKind
    var value: String

    var id: String { "\(kind.rawValue)|\(value)" }
}

private func completedMusicFileURL(for job: MusicDownloadJob?) -> URL? {
    guard
        let job,
        case .succeeded = job.status,
        let filePath = job.filePath,
        FileManager.default.fileExists(atPath: filePath)
    else { return nil }
    return URL(fileURLWithPath: filePath)
}

private func isActiveDownloadStatus(_ status: RemoteImportJob.Status) -> Bool {
    switch status {
    case .importing, .transcoding, .finalizing:
        return true
    default:
        return false
    }
}

private func musicDownloadIcon(type: MusicDownloadJob.DownloadType, job: MusicDownloadJob?) -> String {
    guard let job else {
        return type == .original ? "arrow.down.circle" : "waveform"
    }
    switch job.status {
    case .succeeded:
        return type == .original ? "play.circle.fill" : "waveform.circle.fill"
    case .importing, .transcoding, .finalizing:
        return "arrow.down.circle.fill"
    case .failed:
        return "exclamationmark.circle.fill"
    case .paused:
        return "pause.circle.fill"
    case .idle:
        return type == .original ? "arrow.down.circle" : "waveform"
    }
}

private func musicDownloadTitle(type: MusicDownloadJob.DownloadType, job: MusicDownloadJob?) -> String {
    guard let job else { return type.label }
    switch job.status {
    case .succeeded:
        return type.label
    case .importing, .transcoding, .finalizing:
        if let progress = job.downloadProgress {
            return "\(Int((normalizedProgressFraction(progress) * 100).rounded()))%"
        }
        return "下载中"
    case .failed:
        return "失败"
    case .paused:
        return "暂停"
    case .idle:
        return type.label
    }
}

private func musicDownloadHelp(type: MusicDownloadJob.DownloadType, job: MusicDownloadJob?) -> String {
    guard let job else { return "下载\(type.label)" }
    switch job.status {
    case .succeeded:
        return "播放已下载\(type.label)"
    case .importing, .transcoding, .finalizing:
        return "正在下载\(type.label)"
    case .failed(let message):
        return message.isEmpty ? "\(type.label)下载失败" : message
    case .paused:
        return "\(type.label)下载已暂停"
    case .idle:
        return "下载\(type.label)"
    }
}

private enum MusicRecognitionLayout {
    static let actionButtonSize: CGFloat = 22
    static let actionIconSize: CGFloat = 16
    static let actionGlyphSize: CGFloat = 16
    static let primaryContentHeight: CGFloat = 48
}

private struct MusicRecognitionActionColumn: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    let song: MusicRecognitionItem

    private let actionTint = Color.white.opacity(0.72)

    var body: some View {
        VStack(spacing: 4) {
            Button {
                libraryStore.prepareExternalServiceWork()
                openFirstYouTubeVideo(for: song)
            } label: {
                actionIcon("play.rectangle.fill", glyphWidth: 18, glyphHeight: 14)
            }
            .buttonStyle(.plain)
            .help("在浏览器中打开 YouTube 第一个视频")

            Menu {
                Button {
                    libraryStore.downloadMusic(song: song, type: .original)
                } label: {
                    Label("下载原曲", systemImage: "arrow.down.circle")
                }

                Button {
                    libraryStore.downloadMusic(song: song, type: .instrumental)
                } label: {
                    Label("下载伴奏", systemImage: "waveform")
                }
            } label: {
                actionIcon("arrow.down", glyphWidth: 14, glyphHeight: 16)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(
                width: MusicRecognitionLayout.actionButtonSize,
                height: MusicRecognitionLayout.actionButtonSize
            )
            .help("下载原曲或伴奏")
        }
        .frame(width: MusicRecognitionLayout.actionButtonSize)
        .frame(height: MusicRecognitionLayout.primaryContentHeight, alignment: .center)
    }

    private func actionIcon(
        _ systemImage: String,
        glyphWidth: CGFloat = MusicRecognitionLayout.actionGlyphSize,
        glyphHeight: CGFloat = MusicRecognitionLayout.actionGlyphSize
    ) -> some View {
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .font(.system(size: MusicRecognitionLayout.actionIconSize, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(actionTint)
            .frame(width: glyphWidth, height: glyphHeight)
            .frame(
                width: MusicRecognitionLayout.actionButtonSize,
                height: MusicRecognitionLayout.actionButtonSize
            )
            .contentShape(Rectangle())
    }
}

private struct ExportMusicRecognitionRow: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    let song: MusicRecognitionItem
    let videoPath: String
    let onJump: () -> Void

    var body: some View {
        let downloadJobs = musicDownloadJobs(for: song, in: libraryStore.musicDownloadJobs)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 9) {
                Button(action: onJump) {
                    HStack(spacing: 9) {
                        artwork

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title.isEmpty ? "未知音乐" : song.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            if !song.artist.isEmpty {
                                Text(song.artist)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Text("出现于 \(clockText(song.detectedAt))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                            let musicTags = song.displayTags
                            if !musicTags.isEmpty {
                                MusicTagStrip(tags: musicTags)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("跳到视频中此段落")
                .frame(maxWidth: .infinity, alignment: .leading)

                MusicRecognitionActionColumn(song: song)
            }

            MusicDownloadExtensionStack(downloadJobs: downloadJobs)
        }
        .padding(7)
        .background(.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var artwork: some View {
        MusicArtworkView(urlString: song.artworkURL, title: song.title, artist: song.artist)
        .frame(width: 42, height: 42)
    }
}

private struct MusicRecognitionRow: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    let song: MusicRecognitionItem
    let videoPath: String
    let onJump: () -> Void

    var body: some View {
        let downloadJobs = musicDownloadJobs(for: song, in: libraryStore.musicDownloadJobs)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 9) {
                Button(action: onJump) {
                    HStack(spacing: 9) {
                        MusicArtworkView(urlString: song.artworkURL, title: song.title, artist: song.artist)
                        .frame(width: 42, height: 42)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title.isEmpty ? "未知音乐" : song.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            if !song.artist.isEmpty {
                                Text(song.artist)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Text("出现于 \(clockText(song.detectedAt))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                            let musicTags = song.displayTags
                            if !musicTags.isEmpty {
                                MusicTagStrip(tags: musicTags)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("跳到视频中此段落")
                .frame(maxWidth: .infinity, alignment: .leading)

                MusicRecognitionActionColumn(song: song)
            }
            .frame(minHeight: 56)

            MusicDownloadExtensionStack(downloadJobs: downloadJobs)
        }
        .padding(7)
        .background(.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 0.7)
        }
    }

}

private enum MusicArtworkCache {
    static let shared: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 256
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()
}

private actor MusicArtworkLoadGate {
    static let shared = MusicArtworkLoadGate()

    private let limit = 6
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if activeCount < limit {
            activeCount += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard let nextWaiter = waiters.first else {
            activeCount = max(0, activeCount - 1)
            return
        }

        waiters.removeFirst()
        nextWaiter.resume()
    }
}

private actor MusicArtworkFallbackResolver {
    static let shared = MusicArtworkFallbackResolver()

    private var cachedURLs: [String: URL?] = [:]

    func artworkURL(title rawTitle: String, artist rawArtist: String) async -> URL? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = rawArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = [normalizedSearch(artist), normalizedSearch(title)].joined(separator: "|")
        guard key != "|" else { return nil }

        if cachedURLs.keys.contains(key) {
            return cachedURLs[key] ?? nil
        }

        let query = [artist, title]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else {
            cachedURLs[key] = nil
            return nil
        }

        do {
            let results = try await LibraryStore.searchAppleMusic(query: query)
            let url = bestArtworkURL(in: results, title: title, artist: artist)
            cachedURLs[key] = url
            return url
        } catch {
            cachedURLs[key] = nil
            return nil
        }
    }

    private func bestArtworkURL(
        in results: [AppleMusicSearchResult],
        title: String,
        artist: String
    ) -> URL? {
        results
            .compactMap { result -> (score: Int, url: URL)? in
                guard let url = normalizedMusicArtworkURL(result.artworkURL) else { return nil }
                return (musicArtworkMatchScore(result: result, title: title, artist: artist), url)
            }
            .sorted { lhs, rhs in lhs.score > rhs.score }
            .first?
            .url
    }

    private func musicArtworkMatchScore(
        result: AppleMusicSearchResult,
        title: String,
        artist: String
    ) -> Int {
        let targetTitle = normalizedSearch(title)
        let targetArtist = normalizedSearch(artist)
        let resultTitle = normalizedSearch(result.title)
        let resultArtist = normalizedSearch(result.artist)
        var score = 0

        if !targetTitle.isEmpty {
            if resultTitle == targetTitle {
                score += 8
            } else if !resultTitle.isEmpty,
                      resultTitle.contains(targetTitle) || targetTitle.contains(resultTitle) {
                score += 4
            }
        }

        if !targetArtist.isEmpty {
            if resultArtist == targetArtist {
                score += 6
            } else if !resultArtist.isEmpty,
                      resultArtist.contains(targetArtist) || targetArtist.contains(resultArtist) {
                score += 3
            }
        }

        return score
    }
}

private struct MusicArtworkView: View {
    let urlString: String
    var title: String = ""
    var artist: String = ""
    var cornerRadius: CGFloat = 5
    var shouldLoad = true

    @State private var image: NSImage?
    @State private var didFail = false

    private var artworkURL: URL? {
        normalizedMusicArtworkURL(urlString)
    }

    private var loadKey: String {
        [urlString, title, artist, shouldLoad ? "load" : "pause"].joined(separator: "|")
    }

    private var hasPotentialArtwork: Bool {
        artworkURL != nil
            || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
                    .redacted(reason: hasPotentialArtwork && !didFail ? .placeholder : [])
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: loadKey) {
            guard shouldLoad else {
                image = nil
                didFail = false
                return
            }
            await loadArtwork()
        }
    }

    private var placeholder: some View {
        Image(systemName: "music.note")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.pink.opacity(0.86))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.pink.opacity(0.12))
    }

    private func loadArtwork() async {
        image = nil
        didFail = false

        if let artworkURL, await loadImage(from: artworkURL) {
            return
        }

        if let fallbackURL = await MusicArtworkFallbackResolver.shared.artworkURL(title: title, artist: artist),
           fallbackURL != artworkURL,
           await loadImage(from: fallbackURL) {
            return
        }

        guard !Task.isCancelled else { return }
        image = nil
        didFail = true
    }

    private func loadImage(from artworkURL: URL) async -> Bool {
        if let cached = MusicArtworkCache.shared.object(forKey: artworkURL as NSURL) {
            image = cached
            didFail = false
            return true
        }

        do {
            var request = URLRequest(url: artworkURL)
            request.timeoutInterval = 12
            request.cachePolicy = .returnCacheDataElseLoad
            request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            await MusicArtworkLoadGate.shared.acquire()
            defer {
                Task {
                    await MusicArtworkLoadGate.shared.release()
                }
            }
            guard !Task.isCancelled else { return false }

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                throw URLError(.badServerResponse)
            }
            guard let loadedImage = NSImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            MusicArtworkCache.shared.setObject(loadedImage, forKey: artworkURL as NSURL, cost: data.count)
            guard !Task.isCancelled else { return false }
            image = loadedImage
            didFail = false
            return true
        } catch {
            return false
        }
    }
}

nonisolated private func normalizedMusicArtworkURL(_ rawURLString: String) -> URL? {
    var text = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }

    if text.hasPrefix("//") {
        text = "https:" + text
    } else if text.hasPrefix("http://") {
        text = "https://" + String(text.dropFirst("http://".count))
    }

    text = text.replacingOccurrences(
        of: #"(\d+)x(\d+)bb(\.[A-Za-z0-9]+)$"#,
        with: "512x512bb$3",
        options: .regularExpression
    )

    if let url = URL(string: text) {
        return url
    }

    return URL(string: text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
}

private func youTubeMusicQuery(for song: MusicRecognitionItem) -> String {
    [song.artist, song.title]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

private func youTubeSearchURL(for query: String) -> URL? {
    guard
        !query.isEmpty,
        var components = URLComponents(string: "https://www.youtube.com/results")
    else { return nil }
    components.queryItems = [URLQueryItem(name: "search_query", value: query)]
    return components.url
}

private func openFirstYouTubeVideo(for song: MusicRecognitionItem) {
    let query = youTubeMusicQuery(for: song)
    guard !query.isEmpty else { return }

    Task {
        let firstResultURL = await LibraryStore.firstYouTubeSearchResultURL(for: query)
        guard let url = firstResultURL ?? youTubeSearchURL(for: query) else { return }
        await MainActor.run {
            _ = NSWorkspace.shared.open(url)
        }
    }
}

private func latestMusicDownloadJobs(_ jobs: [MusicDownloadJob]) -> [MusicDownloadJob] {
    MusicDownloadJob.DownloadType.allCases.compactMap { type in
        jobs.last { $0.type == type }
    }
}

private func musicDownloadJobs(for song: MusicRecognitionItem, in jobs: [MusicDownloadJob]) -> [MusicDownloadJob] {
    let songKey = "\(song.title)|\(song.artist)"
    return latestMusicDownloadJobs(jobs.filter { $0.songKey == songKey })
}

private struct MusicDownloadExtensionStack: View {
    let downloadJobs: [MusicDownloadJob]

    var body: some View {
        if !downloadJobs.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(downloadJobs) { job in
                    MusicDownloadStatusView(job: job, isCompact: true)
                }
            }
            .padding(.top, 7)
        }
    }
}

private struct MusicDownloadInlineStatusStack: View {
    let downloadJobs: [MusicDownloadJob]

    var body: some View {
        if downloadJobs.isEmpty {
            Color.clear
                .frame(height: 42)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(downloadJobs) { job in
                    MusicDownloadStatusView(job: job, isCompact: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AudioWaveformScrollPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.black.opacity(0.14))
            .overlay {
                Capsule()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 10)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.white.opacity(0.06), lineWidth: 0.8)
            }
            .allowsHitTesting(false)
    }
}

private struct AudioClipWaveformStrip: View, Equatable {
    let samples: [Double]?
    let isActive: Bool
    var progress: Double = 0

    private static let placeholderSamples: [Double] = (0..<72).map { index in
        0.13 + 0.17 * abs(sin(Double(index) * 0.58))
    }

    private var displayedSamples: [Double] {
        guard let samples, !samples.isEmpty else { return Self.placeholderSamples }
        return samples
    }

    private var isPlaceholder: Bool {
        samples?.isEmpty != false
    }

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            let values = displayedSamples
            let step = size.width / CGFloat(values.count)
            let barWidth = max(1, min(2.2, step * 0.72))
            let midY = size.height / 2
            let baseOpacity = isPlaceholder ? 0.18 : (isActive ? 0.86 : 0.48)
            let tint = isActive ? Color.orange : Color.white
            let clampedProgress = min(1, max(0, progress))
            var basePath = Path()
            var playedPath = Path()

            for (index, sample) in values.enumerated() {
                let value = min(1, max(0.04, sample))
                let barHeight = max(2, CGFloat(value) * size.height * 0.82)
                let rect = CGRect(
                    x: CGFloat(index) * step + (step - barWidth) / 2,
                    y: midY - barHeight / 2,
                    width: barWidth,
                    height: barHeight
                )
                var path = Path()
                path.addRoundedRect(
                    in: rect,
                    cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
                )
                let sampleProgress = Double(index + 1) / Double(values.count)
                let played = isActive && sampleProgress <= clampedProgress
                if played {
                    playedPath.addPath(path)
                } else {
                    basePath.addPath(path)
                }
            }

            context.fill(basePath, with: .color(tint.opacity(baseOpacity)))
            if isActive {
                context.fill(playedPath, with: .color(Color.white.opacity(0.92)))
            }

            if isActive {
                let headX = size.width * CGFloat(clampedProgress)
                var head = Path()
                head.addRoundedRect(
                    in: CGRect(x: headX - 1, y: 2, width: 2, height: size.height - 4),
                    cornerSize: CGSize(width: 1, height: 1)
                )
                context.fill(head, with: .color(Color.white.opacity(0.96)))
            }
        }
        .background(Color.black.opacity(isActive ? 0.22 : 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isActive ? Color.orange.opacity(0.22) : .white.opacity(0.08), lineWidth: 0.8)
        }
        .allowsHitTesting(false)
    }
}

private struct MusicDownloadStatusView: View {
    let job: MusicDownloadJob
    var isCompact = false

    @State private var previewPlayer: AVPlayer?
    @State private var previewTimeObserver: Any?
    @State private var previewEndObserver: NSObjectProtocol?
    @State private var previewProgress: Double = 0
    @State private var previewDuration: Double = 0
    @State private var previewScrubProgress: Double?
    @State private var loadedAudioDuration: Double = 0

    private var previewFileURL: URL? {
        guard
            let filePath = job.filePath,
            FileManager.default.fileExists(atPath: filePath)
        else { return nil }
        return URL(fileURLWithPath: filePath)
    }

    private var canPreviewAudio: Bool {
        guard previewFileURL != nil else { return false }
        if case .succeeded = job.status { return true }
        return false
    }

    private var cleanedDisplayName: String {
        let title = job.songKey
            .split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fallbackName: String
        if case let .succeeded(filename) = job.status {
            fallbackName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        } else {
            fallbackName = job.type.label
        }

        let baseName = title.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
        return job.type == .instrumental ? "\(baseName)（伴奏版）" : baseName
    }

    private var cleanedSuggestedFilename: String? {
        guard let previewFileURL else { return nil }
        let stem = sanitizedMusicFilenameStem(cleanedDisplayName)
        let fileExtension = previewFileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return fileExtension.isEmpty ? stem : "\(stem).\(fileExtension)"
    }

    private var audioFileDragProvider: (() -> NSItemProvider)? {
        guard canPreviewAudio, let previewFileURL else { return nil }
        let suggestedName = cleanedSuggestedFilename ?? previewFileURL.lastPathComponent
        return {
            let provider = NSItemProvider()
            provider.suggestedName = suggestedName
            let typeIdentifier = UTType(filenameExtension: previewFileURL.pathExtension)?.identifier ?? UTType.audio.identifier

            provider.registerFileRepresentation(
                forTypeIdentifier: typeIdentifier,
                fileOptions: .openInPlace,
                visibility: .all
            ) { completion in
                let progress = Progress(totalUnitCount: 1)
                guard FileManager.default.fileExists(atPath: previewFileURL.path) else {
                    completion(nil, true, NSError(
                        domain: "LapianBao.MusicDragExport",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "音频文件不存在"]
                    ))
                    return progress
                }

                progress.completedUnitCount = 1
                completion(previewFileURL, true, nil)
                return progress
            }

            provider.registerObject(previewFileURL as NSURL, visibility: .all)
            return provider
        }
    }

    private var isPreviewing: Bool {
        previewPlayer != nil
    }

    private var effectiveAudioDuration: Double {
        [loadedAudioDuration, previewDuration]
            .filter { $0.isFinite && $0 > 0 }
            .max() ?? 0
    }

    private var audioTimeText: String? {
        let duration = effectiveAudioDuration
        guard duration > 0 else { return nil }

        if isPreviewing || previewScrubProgress != nil {
            let progress = min(1, max(0, previewScrubProgress ?? previewProgress))
            return clockText(duration * progress)
        }

        return clockText(duration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 5 : 7) {
            switch job.status {
            case .importing:
                progressHeader(text: "正在下载\(job.type.label)…", systemImage: "arrow.down.circle.fill")
                if let progress = job.downloadProgress {
                    ProgressView(value: normalizedProgressFraction(progress))
                        .controlSize(.mini)
                        .tint(.white)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                }
            case .transcoding:
                progressHeader(text: "正在处理\(job.type.label)…", systemImage: "waveform")
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
            case .finalizing:
                progressHeader(text: "正在整理\(job.type.label)…", systemImage: "checkmark.seal.fill")
                if let progress = job.downloadProgress {
                    ProgressView(value: normalizedProgressFraction(progress))
                        .controlSize(.mini)
                        .tint(.white)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                }
            case .paused:
                progressHeader(text: "\(job.type.label)已暂停", systemImage: "pause.circle.fill")
            case .succeeded:
                HStack(spacing: 6) {
                    Button {
                        toggleAudioPreview()
                    } label: {
                        Image(systemName: canPreviewAudio ? (isPreviewing ? "pause.circle.fill" : "play.circle.fill") : "checkmark.circle.fill")
                            .font(.system(size: isCompact ? 18 : 20, weight: .semibold))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.white.opacity(canPreviewAudio ? 0.86 : 0.72))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canPreviewAudio)
                    Text(cleanedDisplayName)
                        .font(isCompact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if let audioTimeText {
                        Text(audioTimeText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(isPreviewing || previewScrubProgress != nil ? .secondary : .tertiary)
                            .lineLimit(1)
                    }
                }

                if job.isPreparingWaveform {
                    GenerationProgressRow(
                        message: "正在生成波形",
                        progress: nil,
                        tint: .white,
                        systemImage: "waveform",
                        compact: true,
                        showPercent: false
                    )
                } else if let samples = job.waveformSamples, !samples.isEmpty {
                    DownloadedMusicWaveformView(
                        samples: samples,
                        isCompact: isCompact,
                        isActive: isPreviewing || previewScrubProgress != nil,
                        progress: previewScrubProgress ?? previewProgress,
                        onScrubChanged: { progress in
                            guard canPreviewAudio else { return }
                            previewScrubProgress = progress
                            previewProgress = progress
                        },
                        onScrubEnded: { progress in
                            guard canPreviewAudio else { return }
                            previewScrubProgress = progress
                            previewProgress = progress
                            seekAudioPreview(to: progress)
                        }
                    )
                }
            case let .failed(message):
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                    Text("\(job.type.label)下载失败")
                        .font(isCompact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer(minLength: 6)
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, isCompact ? 0 : 9)
        .padding(.vertical, isCompact ? 6 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(isCompact ? 0 : (isPreviewing ? 0.075 : 0.055)))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(isCompact ? 0 : (isPreviewing ? 0.20 : 0.06)), lineWidth: 0.8)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if canPreviewAudio {
                toggleAudioPreview()
            }
        }
        .itemProviderDrag(audioFileDragProvider)
        .help(canPreviewAudio ? (isPreviewing ? "暂停\(job.type.label)预览，可拖出音频文件" : "播放\(job.type.label)预览，可拖出音频文件") : (job.filePath ?? ""))
        .onDisappear {
            stopAudioPreview()
        }
        .onChange(of: job.filePath) { _, _ in
            stopAudioPreview()
            loadedAudioDuration = 0
        }
        .onChange(of: job.status) { _, _ in
            if !canPreviewAudio {
                stopAudioPreview()
            }
        }
        .task(id: previewFileURL?.path) {
            await loadAudioDuration()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lapianBaoMusicPreviewStarted)) { notification in
            guard
                let activeID = notification.userInfo?["id"] as? UUID,
                activeID != job.id
            else { return }
            stopAudioPreview()
        }
        .animation(.easeInOut(duration: 0.18), value: job.downloadProgress)
        .animation(.easeInOut(duration: 0.22), value: job.waveformSamples)
        .animation(.easeInOut(duration: 0.18), value: isPreviewing)
    }

    private func progressHeader(text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
            Text(text)
                .font(isCompact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            if let progress = job.downloadProgress {
                Text(progressPercentText(progress))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func loadAudioDuration() async {
        guard let previewFileURL else {
            loadedAudioDuration = 0
            return
        }

        do {
            let asset = AVURLAsset(url: previewFileURL)
            let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            loadedAudioDuration = seconds.isFinite && seconds > 0 ? seconds : 0
        } catch {
            loadedAudioDuration = 0
        }
    }

    private func sanitizedMusicFilenameStem(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let sanitized = name
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? job.type.label : sanitized
    }

    private func toggleAudioPreview() {
        if isPreviewing {
            stopAudioPreview()
        } else {
            startAudioPreview()
        }
    }

    private func startAudioPreview(at initialProgress: Double = 0) {
        guard let previewFileURL else { return }
        let clampedProgress = min(1, max(0, initialProgress))
        stopAudioPreview()
        NotificationCenter.default.post(name: .lapianBaoPausePreviewRequest, object: nil)
        NotificationCenter.default.post(
            name: .lapianBaoMusicPreviewStarted,
            object: nil,
            userInfo: ["id": job.id, "type": job.type.rawValue]
        )

        let item = AVPlayerItem(url: previewFileURL)
        let player = AVPlayer(playerItem: item)
        previewPlayer = player
        previewProgress = clampedProgress
        previewDuration = 0

        previewTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.08, preferredTimescale: 600),
            queue: .main
        ) { time in
            let elapsed = time.seconds
            guard elapsed.isFinite else { return }
            let duration = item.duration.seconds
            if duration.isFinite, duration > 0 {
                previewDuration = duration
                previewProgress = min(1, max(0, elapsed / duration))
            }
        }

        previewEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            stopAudioPreview()
        }

        if clampedProgress > 0 {
            seekAudioPreview(to: clampedProgress)
        } else {
            player.play()
        }
    }

    private func stopAudioPreview() {
        if let previewTimeObserver, let previewPlayer {
            previewPlayer.removeTimeObserver(previewTimeObserver)
        }
        previewTimeObserver = nil

        previewPlayer?.pause()
        previewPlayer = nil
        previewProgress = 0
        previewDuration = 0
        previewScrubProgress = nil

        if let previewEndObserver {
            NotificationCenter.default.removeObserver(previewEndObserver)
            self.previewEndObserver = nil
        }
    }

    private func seekAudioPreview(to progress: Double) {
        let clampedProgress = min(1, max(0, progress))

        if previewPlayer == nil {
            startAudioPreview(at: clampedProgress)
            return
        }

        guard let player = previewPlayer, let item = player.currentItem else { return }
        previewProgress = clampedProgress

        Task { @MainActor in
            do {
                let duration = try await item.asset.load(.duration)
                let durationSeconds = duration.seconds
                guard durationSeconds.isFinite, durationSeconds > 0 else {
                    previewScrubProgress = nil
                    return
                }

                let target = CMTime(seconds: durationSeconds * clampedProgress, preferredTimescale: 600)
                player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    DispatchQueue.main.async {
                        previewProgress = clampedProgress
                        previewScrubProgress = nil
                        player.play()
                    }
                }
            } catch {
                previewScrubProgress = nil
            }
        }
    }
}

private struct DownloadedMusicWaveformView: View {
    let samples: [Double]
    var isCompact = false
    var isActive = false
    var progress: Double = 0
    var onScrubChanged: ((Double) -> Void)?
    var onScrubEnded: ((Double) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard !samples.isEmpty, size.width > 0, size.height > 0 else { return }

                let step = size.width / CGFloat(samples.count)
                let barWidth = max(1, min(isCompact ? 1.8 : 2.4, step * 0.72))
                let midY = size.height / 2
                let clampedProgress = min(1, max(0, progress))

                for (index, sample) in samples.enumerated() {
                    let value = min(1, max(0.04, sample))
                    let barHeight = max(2, CGFloat(value) * size.height * 0.82)
                    let rect = CGRect(
                        x: CGFloat(index) * step + (step - barWidth) / 2,
                        y: midY - barHeight / 2,
                        width: barWidth,
                        height: barHeight
                    )
                    var path = Path()
                    path.addRoundedRect(
                        in: rect,
                        cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
                    )
                    let sampleProgress = Double(index + 1) / Double(samples.count)
                    let played = isActive && sampleProgress <= clampedProgress
                    let opacity = played ? 0.94 : (isActive ? 0.74 : 0.56)
                    context.fill(path, with: .color(Color.white.opacity(opacity)))
                }

                if isActive {
                    let headX = size.width * CGFloat(clampedProgress)
                    var head = Path()
                    head.addRoundedRect(
                        in: CGRect(x: headX - 1, y: 2, width: 2, height: size.height - 4),
                        cornerSize: CGSize(width: 1, height: 1)
                    )
                    context.fill(head, with: .color(Color.white.opacity(0.96)))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onScrubChanged?(scrubProgress(at: value.location.x, width: proxy.size.width))
                    }
                    .onEnded { value in
                        onScrubEnded?(scrubProgress(at: value.location.x, width: proxy.size.width))
                    }
            )
        }
        .frame(height: isCompact ? 32 : 38)
        .background(Color.black.opacity(isActive ? 0.24 : 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.white.opacity(isActive ? 0.20 : 0.09), lineWidth: 1)
        }
    }

    private func scrubProgress(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(1, max(0, Double(x / width)))
    }
}

private enum TranscriptTimelineStatus: Equatable {
    case idle
    case running(videoPath: String)
    case loaded(videoPath: String, chapters: [TranscriptTimelineChapter])
    case failed(videoPath: String, message: String)
}

private struct TranscriptTimelineChapter: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var start: Double
    var end: Double?
    var segmentID: UUID
    var type: String
    var summary: String
    var isModelGenerated: Bool
}

private enum LocalTranscriptTimelineAnalyzer {
    private static let endpoint = URL(string: "http://127.0.0.1:11434/api/generate")
        ?? URL(fileURLWithPath: "/dev/null")
    private static let model = "qwen3:4b-instruct"

    private struct RequestBody: Encodable {
        let model: String
        let prompt: String
        let stream: Bool
        let format: String
        let think: Bool
        let options: Options
    }

    private struct Options: Encodable {
        let temperature: Double
        let numCtx: Int

        enum CodingKeys: String, CodingKey {
            case temperature
            case numCtx = "num_ctx"
        }
    }

    private struct ResponseBody: Decodable {
        let response: String
        let thinking: String?
    }

    private struct TimelineResponse: Decodable {
        let chapters: [TimelineChapterDTO]
    }

    private struct TimelineChapterDTO: Decodable {
        let start: Double
        let end: Double?
        let title: String
        let type: String
        let summary: String
    }

    private struct SourceLine {
        let start: Double
        let end: Double
        let text: String
    }

    static func analyze(videoName: String, videoAuthor: String? = nil, segments: [TranscriptSegment]) async throws -> [TranscriptTimelineChapter] {
        guard let firstSegment = segments.first, let lastSegment = segments.last else { return [] }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = RequestBody(
            model: model,
            prompt: prompt(videoName: videoName, videoAuthor: videoAuthor, sourceLines: sourceLines(from: segments)),
            stream: false,
            format: "json",
            think: false,
            options: Options(temperature: 0.2, numCtx: 8192)
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw AnalysisError.serviceUnavailable
        }

        let ollamaResponse = try JSONDecoder().decode(ResponseBody.self, from: data)
        let rawText = ollamaResponse.response.isEmpty ? (ollamaResponse.thinking ?? "") : ollamaResponse.response
        guard let jsonData = extractJSON(from: rawText).data(using: .utf8) else {
            throw AnalysisError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(TimelineResponse.self, from: jsonData)
        let chapters = decoded.chapters
            .compactMap { dto in
                chapter(from: dto, segments: segments, minStart: firstSegment.start, maxEnd: lastSegment.end)
            }
            .sorted { $0.start < $1.start }

        guard !chapters.isEmpty else { throw AnalysisError.invalidResponse }
        return Array(chapters.prefix(12))
    }

    static func userFacingMessage(for error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .cannotConnectToHost {
            return "未连接到本机 Ollama。请先启动 Ollama，并安装文本模型 \(model)。"
        }
        if error is DecodingError {
            return "模型返回的时间线格式无法解析，请重试一次。"
        }
        if error is AnalysisError {
            return "本机文本模型暂时不可用，请确认 Ollama 正在运行。"
        }
        return "生成失败：\(error.localizedDescription)"
    }

    private static func prompt(videoName: String, videoAuthor: String?, sourceLines: [SourceLine]) -> String {
        let transcript = sourceLines.map {
            "[\(clockText($0.start))-\(clockText($0.end))] \($0.text)"
        }.joined(separator: "\n")
        let authorLine = videoAuthor
            .map { "视频作者：\($0)\n" }
            ?? ""

        return """
        你是剪辑师和口播稿结构分析助手。请根据带时间戳的口播转录稿，为视频《\(videoName)》生成内容时间线。
        \(authorLine)视频作者只作为来源上下文，不要把作者名当作转录稿内容。
        只使用转录稿信息，不要猜画面、导演、摄影或外部资料。
        输出 4 到 12 个章节；如果内容很短，可以输出更少。
        每章 start 和 end 必须落在转录稿时间范围内，单位为秒；title 不超过 12 个中文字符；summary 不超过 45 个中文字符。
        type 只能从这些里选择：开场、铺垫、观点、案例、解释、转折、情绪点、金句、总结、行动提示。
        只返回严格 JSON，不要 Markdown，不要解释。
        JSON 格式：
        {"chapters":[{"start":0.0,"end":12.3,"title":"核心标题","type":"观点","summary":"这一段在说什么"}]}

        转录稿：
        \(transcript)
        """
    }

    private static func sourceLines(from segments: [TranscriptSegment]) -> [SourceLine] {
        var lines: [SourceLine] = []
        var currentStart: Double?
        var currentEnd: Double = 0
        var currentText = ""

        func appendCurrent() {
            guard let start = currentStart else { return }
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            lines.append(SourceLine(start: start, end: currentEnd, text: trimmed))
        }

        for segment in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if currentStart == nil {
                currentStart = segment.start
                currentEnd = segment.end
            }

            let start = currentStart ?? segment.start
            let wouldBeLong = currentText.count + text.count > 280
            let wouldBeWide = segment.end - start > 35
            if !currentText.isEmpty, wouldBeLong || wouldBeWide {
                appendCurrent()
                currentStart = segment.start
                currentEnd = segment.end
                currentText = text
            } else {
                currentEnd = max(currentEnd, segment.end)
                currentText = currentText.isEmpty ? text : "\(currentText) \(text)"
            }
        }
        appendCurrent()

        guard lines.count > 220 else { return lines }
        let stride = Double(lines.count) / 220.0
        return (0 ..< 220).map { index in
            lines[min(Int(Double(index) * stride), lines.count - 1)]
        }
    }

    private static func chapter(
        from dto: TimelineChapterDTO,
        segments: [TranscriptSegment],
        minStart: Double,
        maxEnd: Double
    ) -> TranscriptTimelineChapter? {
        let start = min(max(dto.start, minStart), maxEnd)
        guard let nearest = nearestSegment(in: segments, to: start) else { return nil }
        let rawEnd = dto.end ?? nearest.end
        let end = min(max(rawEnd, start), maxEnd)

        return TranscriptTimelineChapter(
            title: clean(dto.title, fallback: "内容段落", maxLength: 12),
            start: start,
            end: end,
            segmentID: nearest.id,
            type: clean(dto.type, fallback: "观点", maxLength: 6),
            summary: clean(dto.summary, fallback: nearest.text, maxLength: 45),
            isModelGenerated: true
        )
    }

    private static func nearestSegment(in segments: [TranscriptSegment], to time: Double) -> TranscriptSegment? {
        segments.min { lhs, rhs in
            abs(lhs.start - time) < abs(rhs.start - time)
        }
    }

    private static func clean(_ value: String, fallback: String, maxLength: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.isEmpty ? fallback.trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
        return String(text.prefix(maxLength))
    }

    private static func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end else {
            return trimmed
        }
        return String(trimmed[start ... end])
    }

    enum AnalysisError: Error {
        case serviceUnavailable
        case invalidResponse
    }
}

private struct ContentWorkspaceView: View {
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
                            Label("导出字幕", systemImage: "square.and.arrow.up")
                        }
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
                                .foregroundStyle(isSelected ? .white : .orange)
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
                                    .foregroundStyle(.orange)
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
                .foregroundStyle(.orange)
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
                                    .foregroundStyle(.orange)
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

private struct SettingsWorkspaceView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @AppStorage(LibraryStore.autoSceneBatchKey) private var autoSceneBatch = false
    @AppStorage(LibraryStore.autoTranscriptBatchKey) private var autoTranscriptBatch = false
    @AppStorage(LibraryStore.autoMusicDownloadBatchKey) private var autoMusicDownloadBatch = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                downloaderSelfCheckCard()

                settingsTaskCard(
                    title: "画面切分",
                    icon: "rectangle.on.rectangle",
                    countText: sceneCountText,
                    job: libraryStore.sceneBatchJob,
                    autoEnabled: $autoSceneBatch,
                    startTitle: "开始切分",
                    start: { libraryStore.startSceneBatch(onlyMissing: true) },
                    stop: { libraryStore.cancelSceneBatch() },
                    clear: { libraryStore.deleteAllSceneRecognitions() }
                )

                settingsTaskCard(
                    title: "字幕识别",
                    icon: "text.bubble",
                    countText: transcriptCountText,
                    job: libraryStore.transcriptBatchJob,
                    autoEnabled: $autoTranscriptBatch,
                    startTitle: "开始识别",
                    start: { libraryStore.startTranscriptBatch(onlyMissing: true) },
                    stop: { libraryStore.cancelTranscriptBatch() },
                    clear: { libraryStore.deleteAllTranscripts() }
                )

                settingsTaskCard(
                    title: "音乐下载",
                    icon: "music.note.list",
                    countText: musicDownloadCountText,
                    job: libraryStore.musicDownloadBatchJob,
                    autoEnabled: $autoMusicDownloadBatch,
                    startTitle: "全下载",
                    start: { libraryStore.startMusicDownloadBatch(types: MusicDownloadJob.DownloadType.allCases) },
                    stop: { libraryStore.cancelMusicDownloads() },
                    clear: { libraryStore.clearMusicDownloadState() }
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scrollIndicators(.hidden)
        .onAppear {
            removeExternalAPISettings()
        }
    }

    private func downloaderSelfCheckCard() -> some View {
        let report = libraryStore.downloaderSelfCheckReport
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: downloaderSelfCheckIcon(for: report))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(downloaderSelfCheckColor(for: report))
                    .frame(width: 18)
                Text("外部服务自检")
                    .font(.headline.weight(.semibold))
                Text(downloaderSelfCheckDateText(report))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { libraryStore.startExternalServiceSelfCheck() }) {
                    Label("立即自检", systemImage: "arrow.clockwise")
                }
                .disabled(report.isRunning)
            }

            if report.isRunning {
                ProgressView()
                    .controlSize(.small)
                    .progressViewStyle(.linear)
                    .tint(.orange)
            }

            Text(downloaderSelfCheckStatusText(report))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(5)

            if !report.serviceChecks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(report.serviceChecks) { item in
                        HStack(spacing: 7) {
                            Image(systemName: externalServiceCheckIcon(for: item.status))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(externalServiceCheckColor(for: item.status))
                                .frame(width: 14)
                            Text(item.title)
                                .font(.caption2.weight(.semibold))
                                .frame(width: 110, alignment: .leading)
                            Text(item.message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func settingsTaskCard(
        title: String,
        icon: String,
        countText: String,
        job: TranscriptBatchJob,
        autoEnabled: Binding<Bool>,
        startTitle: String,
        start: @escaping () -> Void,
        stop: @escaping () -> Void,
        clear: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 18)
                Text(title)
                    .font(.headline.weight(.semibold))
                Text(countText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle(isOn: Binding(
                    get: { autoEnabled.wrappedValue },
                    set: { enabled in
                        autoEnabled.wrappedValue = enabled
                        if enabled { start() }
                    }
                )) {
                    Text("启动自动")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
            }

            HStack(spacing: 8) {
                Button(action: start) {
                    Label(startTitle, systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBatchRunning(job))

                Spacer()

                Button(action: stop) {
                    Label("停止", systemImage: "stop.fill")
                }
                .disabled(!isBatchRunning(job) && !isBatchPaused(job))

                Button(role: .destructive, action: clear) {
                    Label("清空状态", systemImage: "trash")
                }
            }

            if shouldShowProgress(job) {
                ProgressView(value: normalizedProgressFraction(job.progress))
                    .progressViewStyle(.linear)
                    .tint(.orange)
            }

            Text(batchStatusText(job, title: title))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func downloaderSelfCheckIcon(for report: DownloaderSelfCheckReport) -> String {
        switch report.status {
        case .idle: return "arrow.down.circle"
        case .running: return "clock.arrow.circlepath"
        case .succeeded: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func downloaderSelfCheckColor(for report: DownloaderSelfCheckReport) -> Color {
        switch report.status {
        case .idle, .running: return .orange
        case .succeeded: return .green
        case .failed: return .red
        }
    }

    private func downloaderSelfCheckDateText(_ report: DownloaderSelfCheckReport) -> String {
        guard let checkedAt = report.checkedAt else { return "未检查" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: checkedAt)
    }

    private func downloaderSelfCheckStatusText(_ report: DownloaderSelfCheckReport) -> String {
        var parts = [report.message]
        if let version = report.ytdlpVersion {
            parts.append("yt-dlp \(version)")
        }
        if let title = report.youtubeProbeTitle {
            parts.append(title)
        }
        return parts.joined(separator: " · ")
    }

    private func externalServiceCheckIcon(for status: ExternalServiceSelfCheckItem.Status) -> String {
        switch status {
        case .succeeded: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func externalServiceCheckColor(for status: ExternalServiceSelfCheckItem.Status) -> Color {
        switch status {
        case .succeeded: return .green
        case .warning: return .orange
        case .failed: return .red
        }
    }

    private var sceneCountText: String {
        let completed = libraryStore.videos.filter { libraryStore.sceneCutsByVideoPath[$0.url.path] != nil }.count
        return "\(completed)/\(libraryStore.videos.count)"
    }

    private var transcriptCountText: String {
        let completed = libraryStore.videos.filter { !libraryStore.transcriptSegmentsByVideoPath[$0.url.path, default: []].isEmpty }.count
        return "\(completed)/\(libraryStore.videos.count)"
    }

    private var musicDownloadCountText: String {
        let completed = libraryStore.musicDownloadJobs.filter { job in
            if case .succeeded = job.status { return true }
            return false
        }.count
        return "\(completed) 个文件"
    }

    private func shouldShowProgress(_ job: TranscriptBatchJob) -> Bool {
        switch job.status {
        case .idle:
            return false
        default:
            return true
        }
    }

    private func isBatchRunning(_ job: TranscriptBatchJob) -> Bool {
        if case .running = job.status { return true }
        return false
    }

    private func isBatchPaused(_ job: TranscriptBatchJob) -> Bool {
        if case .paused = job.status { return true }
        return false
    }

    private func batchStatusText(_ job: TranscriptBatchJob, title: String) -> String {
        switch job.status {
        case .idle:
            return "未开始"
        case .running:
            let name = job.currentVideoName ?? "准备中"
            return "\(title)进行中：\(name) · \(job.completed)/\(job.total)"
        case .paused:
            return "已暂停 · \(job.completed)/\(job.total)"
        case .completed:
            return job.total == 0 ? "暂无需要处理的项目" : "\(title)完成"
        case .failed(let message):
            return "\(title)失败：\(message)"
        }
    }

    private func removeExternalAPISettings() {
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
        ].forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}

private struct LuminanceHistogram: View {
    let imageData: Data

    var body: some View {
        let buckets = luminanceBuckets()
        VStack(alignment: .leading, spacing: 6) {
            Text("亮度分布")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Canvas { context, size in
                guard !buckets.isEmpty else { return }
                let maxVal = buckets.max() ?? 1
                let barW = size.width / CGFloat(buckets.count)
                for (i, val) in buckets.enumerated() {
                    let h = maxVal > 0 ? CGFloat(val) / CGFloat(maxVal) * size.height : 0
                    let rect = CGRect(x: CGFloat(i) * barW, y: size.height - h, width: max(1, barW - 0.5), height: h)
                    var path = Path()
                    path.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1))
                    let brightness = Double(i) / Double(buckets.count)
                    context.fill(path, with: .color(Color.white.opacity(0.25 + brightness * 0.65)))
                }
            }
            .frame(height: 44)
            .background(Color.black.opacity(0.28))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func luminanceBuckets(count: Int = 32) -> [Int] {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return Array(repeating: 0, count: count)
        }
        let w = 64, h = 36
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Array(repeating: 0, count: count) }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var buckets = Array(repeating: 0, count: count)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let idx = min(count - 1, Int(luma / 255.0 * Double(count)))
            buckets[idx] += 1
        }
        return buckets
    }
}

private struct ColorSwatches: View {
    enum Orientation {
        case horizontal
        case vertical
    }

    private struct SwatchColor {
        let color: Color
        let hexCode: String
    }

    let imageData: Data
    var orientation: Orientation = .horizontal

    var body: some View {
        let colors = regionAverageColors()
        swatches(colors)
    }

    @ViewBuilder
    private func swatches(_ colors: [SwatchColor]) -> some View {
        switch orientation {
        case .horizontal:
            HStack(spacing: 5) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, swatch in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(swatch.color)
                        .frame(height: 24)
                        .help(swatch.hexCode)
                }
            }
        case .vertical:
            VStack(spacing: 6) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, swatch in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(swatch.color)
                        .frame(width: 72, height: 42)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(.white.opacity(0.10), lineWidth: 0.7)
                        }
                        .help(swatch.hexCode)
                }
            }
        }
    }

    // Divides image into a 3×2 grid (16:9 friendly), returns average color per region.
    private func regionAverageColors() -> [SwatchColor] {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return placeholderColors()
        }
        let w = 48, h = 27
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return placeholderColors() }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        let cols = 3, rows = 2
        let cellW = w / cols, cellH = h / rows
        return (0 ..< rows).flatMap { row in
            (0 ..< cols).map { col in
                var rSum = 0.0, gSum = 0.0, bSum = 0.0
                let count = Double(cellW * cellH)
                for py in (row * cellH) ..< ((row + 1) * cellH) {
                    for px in (col * cellW) ..< ((col + 1) * cellW) {
                        let o = (py * w + px) * 4
                        rSum += Double(pixels[o])
                        gSum += Double(pixels[o + 1])
                        bSum += Double(pixels[o + 2])
                    }
                }
                let red = UInt8((rSum / count).rounded())
                let green = UInt8((gSum / count).rounded())
                let blue = UInt8((bSum / count).rounded())
                return swatchColor(red: red, green: green, blue: blue)
            }
        }
    }

    private func placeholderColors() -> [SwatchColor] {
        Array(repeating: swatchColor(red: 128, green: 128, blue: 128), count: 6)
    }

    private func swatchColor(red: UInt8, green: UInt8, blue: UInt8) -> SwatchColor {
        SwatchColor(
            color: Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255),
            hexCode: String(format: "#%02X%02X%02X", red, green, blue)
        )
    }
}

private func clockText(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
}

private func formatDuration(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    let m = total / 60
    let s = total % 60
    return m > 0 ? "\(m) 分 \(s) 秒" : "\(s) 秒"
}

private extension Notification.Name {
    static let lapianBaoSeekRequest = Notification.Name("lapianBaoSeekRequest")
    static let lapianBaoPausePreviewRequest = Notification.Name("lapianBaoPausePreviewRequest")
    static let lapianBaoMusicPreviewStarted = Notification.Name("lapianBaoMusicPreviewStarted")
}

// MARK: - ResizeLeftRightCursorView

private struct ResizeLeftRightCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorNSView { CursorNSView() }
    func updateNSView(_ nsView: CursorNSView, context: Context) { nsView.window?.invalidateCursorRects(for: nsView) }

    class CursorNSView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }
    }
}

// MARK: - View extensions

private extension View {
    func contentPanel() -> some View {
        self.background(Design.contentBg)
    }

    func glassPanel() -> some View {
        self.background(Design.sidebarBg)
    }
}
