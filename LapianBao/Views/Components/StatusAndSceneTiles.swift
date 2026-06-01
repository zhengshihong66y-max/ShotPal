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

func normalizedProgressFraction(_ progress: Double) -> Double {
    guard progress.isFinite else { return 0 }
    return min(1, max(0, progress))
}

func progressPercentText(_ progress: Double) -> String {
    "\(Int((normalizedProgressFraction(progress) * 100).rounded()))%"
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

struct SceneCutTile: View {
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
                            .foregroundStyle(Design.screenshotFrameAccent)
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
            floatingExportButtonIcon(
                systemImage: "plus",
                size: 24,
                iconSize: 12
            )
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
        if isScreenshot { return Design.screenshotFrameAccent.opacity(0.92) }
        if isExported { return .white.opacity(0.18) }
        return .white.opacity(0.10)
    }

    private var borderWidth: CGFloat {
        if isActive { return 2 }
        if isSelected { return 1.2 }
        return isExported ? 1.7 : 1
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
