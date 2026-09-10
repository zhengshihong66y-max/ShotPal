//
//  StatusAndSceneTiles.swift
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

struct AppEmptyState: View {
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
        Text(title)
            .font(titleFont)
            .foregroundStyle(style == .inline ? .tertiary : .secondary)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, minHeight: minHeight ?? defaultMinHeight, alignment: .center)
    }

    private var titleFont: Font {
        style == .large ? .callout.weight(.medium) : .caption
    }

    private var defaultMinHeight: CGFloat {
        switch style {
        case .large:
            return 136
        case .compact:
            return 82
        case .inline:
            return 24
        }
    }
}

struct GenerationProgressRow: View {
    let message: String
    var progress: Double?
    var tint: Color = Design.annotationAccent
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
                        .font(Design.numericCaption2(weight: .semibold))
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

extension LibraryScanProgress {
    var isMusicWaveformCacheProgress: Bool {
        message.contains("音乐缓存")
            || message.contains("音乐波形")
            || message.contains("识别音乐素材")
            || message.localizedCaseInsensitiveContains("music cache")
            || message.localizedCaseInsensitiveContains("music waveform")
            || message.localizedCaseInsensitiveContains("identifying music files")
    }
}

struct RecognitionProgressRow: View {
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

struct RecognitionFailureIndicator: View {
    var message: String? = nil
    var minHeight: CGFloat = 32

    private var displayMessage: String {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? L10n.text("识别失败") : trimmed
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("!")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
            Text(displayMessage)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
            .foregroundStyle(Color.red.opacity(0.88))
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .center)
            .accessibilityLabel(displayMessage)
    }
}

nonisolated func normalizedProgressFraction(_ progress: Double) -> Double {
    guard progress.isFinite else { return 0 }
    return min(1, max(0, progress))
}

func progressPercentText(_ progress: Double) -> String {
    let percent = Int((normalizedProgressFraction(progress) * 100).rounded())
    return "\(percent)%"
}

func activityProgressValue(from message: String) -> Double? {
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

private struct SceneCardTagChip: View {
    let tag: String
    var maxTextWidth: CGFloat? = nil

    var body: some View {
        Text(tag)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white.opacity(0.94))
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.78)
            .allowsTightening(true)
            .frame(maxWidth: maxTextWidth, alignment: .center)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.62))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.20), lineWidth: 0.8)
            }
            .fixedSize(horizontal: maxTextWidth == nil, vertical: false)
    }
}

private struct SceneCardTagOverflowChip: View {
    var body: some View {
        Text("...")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.62))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.20), lineWidth: 0.8)
            }
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct SceneCutTileActivePlayback {
    let clock: PlaybackClock
    let startTime: Double
    let endTime: Double
    let duration: Double
    let playbackRate: Double
    let isPlaying: Bool
}

private struct SceneCutTileProgressOverlay: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(1, max(0, progress))
            let playheadWidth: CGFloat = 2
            let playheadX = min(
                max(0, proxy.size.width - playheadWidth),
                max(0, proxy.size.width * clamped - playheadWidth / 2)
            )

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: proxy.size.width * clamped)

                Rectangle()
                    .fill(Design.timelinePlayheadAccent)
                    .frame(width: playheadWidth)
                    .offset(x: playheadX)
                    .shadow(color: .black.opacity(0.35), radius: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .allowsHitTesting(false)
    }
}

private struct SceneCutTileActiveProgressOverlay: View {
    let playback: SceneCutTileActivePlayback

    var body: some View {
        PlaybackClockDrivenView(
            clock: playback.clock,
            duration: playback.duration,
            playbackRate: playback.playbackRate,
            isPlaying: playback.isPlaying
        ) { clock in
            SceneCutTileProgressOverlay(progress: progress(for: clock.elapsed))
        }
    }

    private func progress(for elapsed: Double) -> Double {
        let start = playback.startTime
        let end = playback.endTime
        guard end > start else { return 0 }
        return min(1, max(0, (elapsed - start) / (end - start)))
    }
}

struct SceneCutTile: View {
    let thumbnailImage: NSImage?
    let timeLabel: String
    var isExported = false
    var isScreenshot = false
    var isSelected = false
    var isActive = false
    var activePlayback: SceneCutTileActivePlayback?
    let onTap: () -> Void
    var tags: [String] = []
    var suggestedTags: [String] = []
    var onAddTag: ((String) -> Void)?
    var onRemoveTag: ((String) -> Void)?
    var onShowInFinder: (() -> Void)?
    var onDelete: (() -> Void)?
    var showsUnavailableFileActions = false
    var dragItemProvider: (() -> NSItemProvider)?

    @State private var isHovered = false
    @State private var isMorePresented = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                GeometryReader { proxy in
                    ZStack(alignment: .bottomTrailing) {
                        thumbnailContent
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()

                        if isActive, let activePlayback {
                            SceneCutTileActiveProgressOverlay(playback: activePlayback)
                        }

                        sceneTagBadges(maxSize: proxy.size)
                            .padding(.leading, 7)
                            .padding(.top, 7)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                        CardTimeBadge(text: timeLabel, placeholder: timeLabel)
                            .padding(.trailing, CardTimeBadge.edgeInset)
                            .padding(.bottom, CardTimeBadge.verticalInset)

                        if isScreenshot {
                            CaptureFrameBadge()
                                .padding(.leading, 7)
                                .padding(.bottom, 7)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        }
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(tileShape)
                .overlay {
                    if borderWidth > 0 {
                        tileShape
                            .strokeBorder(borderColor, lineWidth: borderWidth)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("scene_cut_tile_button")

            if canShowMoreMenu {
                moreButton
                    .opacity(1)
                    .allowsHitTesting(true)
                    .animation(.easeInOut(duration: 0.12), value: isHovered)
                    .padding(.top, CardTimeBadge.verticalInset)
                    .padding(.trailing, CardTimeBadge.edgeInset)
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

    @ViewBuilder
    private func sceneTagBadges(maxSize: CGSize) -> some View {
        if !tags.isEmpty {
            let reservedTrailingWidth = CardOverlayMoreIcon.size + CardTimeBadge.edgeInset * 2
            let availableWidth = max(44, maxSize.width - reservedTrailingWidth)

            ViewThatFits(in: .horizontal) {
                sceneTagRow(Array(tags.prefix(4)), showsOverflow: tags.count > 4)

                if tags.count > 2 {
                    sceneTagRow(Array(tags.prefix(2)), showsOverflow: true)
                }

                if tags.count > 1 {
                    sceneTagRow(Array(tags.prefix(1)), showsOverflow: true)
                }

                SceneCardTagChip(tag: tags[0], maxTextWidth: max(24, availableWidth))
            }
            .frame(maxWidth: availableWidth, alignment: .topLeading)
            .clipped()
            .allowsHitTesting(false)
        }
    }

    private func sceneTagRow(_ rowTags: [String], showsOverflow: Bool = false) -> some View {
        HStack(spacing: 4) {
            ForEach(rowTags, id: \.self) { tag in
                SceneCardTagChip(tag: tag)
            }

            if showsOverflow {
                SceneCardTagOverflowChip()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnailImage {
            Image(nsImage: thumbnailImage)
                .resizable()
                .interpolation(.medium)
                .scaledToFill()
        } else {
            Color.white.opacity(0.08)
        }
    }

    private var canShowMoreMenu: Bool {
        onAddTag != nil
            || onRemoveTag != nil
            || onShowInFinder != nil
            || onDelete != nil
            || showsUnavailableFileActions
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    private var moreButton: some View {
        Button {
            isMorePresented.toggle()
        } label: {
            CardOverlayMoreIcon()
        }
        .buttonStyle(.plain)
        .frame(width: CardOverlayMoreIcon.size, height: CardOverlayMoreIcon.size)
        .accessibilityIdentifier("scene_cut_tile_more_button")
        .popover(isPresented: $isMorePresented, arrowEdge: .trailing) {
            morePopover
                .transaction { $0.animation = nil }
        }
    }

    private var morePopover: some View {
        let tagHorizontalInset: CGFloat = 14
        let tagVerticalInset: CGFloat = 16
        let tagContentGap: CGFloat = tagVerticalInset

        return VStack(alignment: .leading, spacing: 0) {
            if onAddTag != nil || !tags.isEmpty || !suggestedTags.isEmpty {
                TagEditorSection(
                    domain: .frame,
                    tags: tags,
                    suggestedTags: suggestedTags,
                    inputSpacing: tagContentGap,
                    gridVerticalPadding: 0,
                    onAdd: onAddTag,
                    onRemove: onRemoveTag
                )
                .padding(.horizontal, tagHorizontalInset)
                .padding(.top, tagVerticalInset)
                .padding(.bottom, tagVerticalInset)
            }

            if onShowInFinder != nil || onDelete != nil || showsUnavailableFileActions {
                if onAddTag != nil || !tags.isEmpty || !suggestedTags.isEmpty {
                    Divider()
                }

                actionSection
            }
        }
        .frame(minWidth: 220)
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            if onShowInFinder != nil || showsUnavailableFileActions {
                let isEnabled = onShowInFinder != nil

                Button {
                    guard let onShowInFinder else { return }
                    isMorePresented = false
                    onShowInFinder()
                } label: {
                    Label(L10n.text("在访达中显示"), systemImage: "folder")
                        .foregroundStyle(sceneActionForeground(isEnabled: isEnabled))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }

            if onDelete != nil || showsUnavailableFileActions {
                let isEnabled = onDelete != nil

                Button {
                    guard let onDelete else { return }
                    isMorePresented = false
                    onDelete()
                } label: {
                    Label(isScreenshot ? L10n.text("删除截图") : L10n.text("删除图片"), systemImage: "trash")
                        .foregroundStyle(sceneActionForeground(isEnabled: isEnabled, destructive: true))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }
        }
        .padding(.vertical, 6)
    }

    private func sceneActionForeground(isEnabled: Bool, destructive: Bool = false) -> Color {
        guard isEnabled else { return .white.opacity(0.34) }
        return destructive ? .red : .white.opacity(0.88)
    }

    private var borderColor: Color {
        if isActive { return Design.currentFrameAccent.opacity(0.98) }
        return .clear
    }

    private var borderWidth: CGFloat {
        if isActive { return 2 }
        return 0
    }
}

struct CaptureFrameBadge: View {
    var body: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Design.screenshotFrameAccent)
            .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
    }
}

struct CurrentFrameFocusOverlay: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .inset(by: 0.75)
            .strokeBorder(Design.currentFrameAccent.opacity(0.98), lineWidth: 2)
        .allowsHitTesting(false)
    }
}
