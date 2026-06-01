//
//  TagsAndBadges.swift
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

struct VideoTagChip: View {
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

struct VideoTagOverflowChip: View {
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

struct QuickFilterChoiceChip: View {
    let title: String
    var systemImage: String? = nil
    var tagColorKey: String? = nil
    var isSelected: Bool
    var tint: Color = Design.annotationAccent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 12)
                } else if let tagColorKey {
                    VideoTagColorDot(tag: tagColorKey)
                }

                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 164, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                }
            }
            .foregroundStyle(isSelected ? .white.opacity(0.94) : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(isSelected ? tint.opacity(0.22) : .white.opacity(0.055))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? tint.opacity(0.52) : .white.opacity(0.10), lineWidth: 0.8)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct WrappingFilterChipGroup<Content: View>: View {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 7
    @ViewBuilder let content: () -> Content

    var body: some View {
        WrappingFilterChipLayout(spacing: spacing, rowSpacing: rowSpacing) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WrappingFilterChipLayout: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(for: subviews, maxWidth: maxWidth(for: proposal, subviews: subviews)).size
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

    private func maxWidth(for proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        if let width = proposal.width {
            return max(0, width)
        }

        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return sizes.map(\.width).reduce(0, +) + CGFloat(max(0, sizes.count - 1)) * spacing
    }

    private func layout(
        for subviews: Subviews,
        maxWidth: CGFloat
    ) -> (positions: [CGPoint], sizes: [CGSize], size: CGSize) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var positions: [CGPoint] = []
        positions.reserveCapacity(sizes.count)

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for size in sizes {
            if x > 0, x + spacing + size.width > maxWidth {
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
            size: CGSize(width: usedWidth, height: y + rowHeight)
        )
    }
}

struct TagSuggestionGrid: View {
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

struct InlineTagEditorButton: View {
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
                .foregroundStyle(tags.isEmpty ? .secondary : Design.neutralStrongAccent)
                .frame(width: buttonSize, height: buttonSize)
                .overlay(alignment: .topTrailing) {
                    if !tags.isEmpty {
                        Text("\(tags.count)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Design.neutralBadgeFill)
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

struct PreviewTitleTagChip: View {
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

struct VideoTagColorDot: View {
    let tag: String

    var body: some View {
        Circle()
            .fill(VideoTagPalette.color(for: tag))
            .frame(width: 7, height: 7)
    }
}

struct SourcePlatformBadge: View {
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

struct SourcePlatformIconBadge: View {
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
