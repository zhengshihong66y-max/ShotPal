//
//  AudioWorkspaceComponents.swift
//  LapianBao
//
//  Reusable presentation pieces for the sound-effect workspace.
//

import SwiftUI

enum AudioRowMetrics {
    static let rowHeight: CGFloat = 72
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 10
    static let columnSpacing: CGFloat = 14
    static let previewButtonSize: CGFloat = 28
    static let actionButtonSize: CGFloat = 24
    static let actionButtonSpacing: CGFloat = 4
    static let actionColumnHeight: CGFloat = actionButtonSize * 2 + actionButtonSpacing
    static let waveformHeight: CGFloat = actionColumnHeight
    static let totalHorizontalPadding: CGFloat = horizontalPadding * 2
}

struct ActiveAudioPlaybackTime: View {
    @ObservedObject var progressStore: AudioPreviewProgressStore
    let fallbackDuration: Double

    var body: some View {
        if let duration = effectiveDuration {
            SmoothTimelineProgressReader(
                progress: progressStore.metrics.progress,
                duration: duration,
                isPlaying: true
            ) { displayedProgress in
                Text(clockText(duration * displayedProgress))
            }
        } else {
            Text(progressStore.progressText(fallbackDuration: fallbackDuration))
        }
    }

    private var effectiveDuration: Double? {
        if progressStore.metrics.duration.isFinite, progressStore.metrics.duration > 0 {
            return progressStore.metrics.duration
        }
        if fallbackDuration.isFinite, fallbackDuration > 0 {
            return fallbackDuration
        }
        return nil
    }
}

struct ActiveAudioWaveformStrip: View {
    @ObservedObject var progressStore: AudioPreviewProgressStore
    let samples: [Double]?

    var body: some View {
        AudioClipWaveformStrip(
            samples: samples,
            isActive: true,
            progress: progressStore.metrics.progress,
            playbackDuration: progressStore.metrics.duration,
            smoothsPlaybackProgress: true
        )
        .equatable()
    }
}

struct EditableAudioTagStrip: View {
    let title: String
    let tags: [String]
    let suggestedTags: [String]
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    @State private var isPresented = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ViewThatFits(in: .horizontal) {
                audioTagRow(size: .regular)
                audioTagRow(size: .compact)
                audioTagRow(size: .compact, maxChipWidth: compressedChipWidth(for: width))
                audioTagCloud(size: .compact, maxChipWidth: width)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 42, alignment: .leading)
        .clipped()
        .help(title)
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            tagEditorPopover
        }
    }

    private func audioTagRow(size: AdaptiveAudioTagChip.Size, maxChipWidth: CGFloat? = nil) -> some View {
        HStack(spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                AdaptiveAudioTagChip(tag: tag, size: size, maxChipWidth: maxChipWidth)
            }
            TagStripAddButton(height: size.height) {
                presentEditor()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func compressedChipWidth(for width: CGFloat) -> CGFloat {
        guard !tags.isEmpty else { return 0 }
        let addButtonWidth: CGFloat = 14
        let spacing = CGFloat(tags.count) * 4
        return max(34, floor((max(0, width - spacing - addButtonWidth)) / CGFloat(tags.count)))
    }

    private func audioTagCloud(size: AdaptiveAudioTagChip.Size, maxChipWidth: CGFloat) -> some View {
        AdaptiveAudioTagFlowLayout(spacing: 4, rowSpacing: 4) {
            ForEach(tags, id: \.self) { tag in
                AdaptiveAudioTagChip(tag: tag, size: size, maxChipWidth: maxChipWidth)
            }
            TagStripAddButton(height: size.height) {
                presentEditor()
            }
        }
    }

    private func presentEditor() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isPresented = true
        }
    }

    private var tagEditorPopover: some View {
        TagEditorSection(
            title: title,
            domain: .audio,
            tags: tags,
            suggestedTags: suggestedTags,
            chipSize: .compact,
            onAdd: onAdd,
            onRemove: onRemove
        )
        .padding(12)
    }
}

struct AdaptiveAudioTagChip: View {
    enum Size {
        case regular
        case compact

        var fontSize: CGFloat {
            switch self {
            case .regular: return 11
            case .compact: return 9.5
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .regular: return 7
            case .compact: return 5
            }
        }

        var height: CGFloat {
            switch self {
            case .regular: return 18
            case .compact: return 16
            }
        }
    }

    let tag: String
    var size: Size = .regular
    var maxChipWidth: CGFloat?

    var body: some View {
        let maxTextWidth = maxChipWidth.map { max(24, $0 - size.horizontalPadding * 2) }

        Text(tag)
            .font(.system(size: size.fontSize, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
            .frame(maxWidth: maxTextWidth, minHeight: size.height, maxHeight: size.height, alignment: .center)
            .padding(.horizontal, size.horizontalPadding)
            .foregroundStyle(Design.tagChipForeground)
            .background(Design.tagChipFill)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Design.tagChipStroke, lineWidth: 0.8)
            }
            .fixedSize(horizontal: maxChipWidth == nil, vertical: false)
    }
}

struct AdaptiveAudioTagFlowLayout: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(for: subviews, maxWidth: proposal.width ?? 0).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(for: subviews, maxWidth: bounds.width)
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + result.positions[index].x,
                    y: bounds.minY + result.positions[index].y
                ),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func layout(
        for subviews: Subviews,
        maxWidth: CGFloat
    ) -> (positions: [CGPoint], sizes: [CGSize], size: CGSize) {
        guard !subviews.isEmpty else {
            return ([], [], .zero)
        }

        let widthLimit = max(1, maxWidth)
        let sizes = subviews.map { subview in
            let size = subview.sizeThatFits(.unspecified)
            return CGSize(width: min(size.width, widthLimit), height: size.height)
        }
        var positions: [CGPoint] = []
        positions.reserveCapacity(sizes.count)

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for size in sizes {
            if x > 0, x + spacing + size.width > widthLimit {
                y += rowHeight + rowSpacing
                x = 0
                rowHeight = 0
            }

            if x > 0 {
                x += spacing
            }

            positions.append(CGPoint(x: x, y: y))
            usedWidth = max(usedWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width
        }

        return (
            positions: positions,
            sizes: sizes,
            size: CGSize(width: min(usedWidth, widthLimit), height: y + rowHeight)
        )
    }
}
