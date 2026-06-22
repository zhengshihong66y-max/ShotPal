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

struct CenteredPlusGlyph: View {
    var size: CGFloat = 8
    var thickness: CGFloat? = nil

    var body: some View {
        let lineWidth = max(1, thickness ?? size * 0.18)

        ZStack {
            Capsule()
                .frame(width: size, height: lineWidth)
            Capsule()
                .frame(width: lineWidth, height: size)
        }
        .frame(width: size, height: size, alignment: .center)
        .accessibilityHidden(true)
    }
}

struct VideoTagChip: View {
    let tag: String
    var size: VideoTagChipSize = .regular
    var onRemove: (() -> Void)? = nil

    var body: some View {
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
            }
        }
        .foregroundStyle(Design.tagChipForeground)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(Design.tagChipFill)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(Design.tagChipStroke, lineWidth: 0.8)
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
    var count: Int? = nil
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
                }

                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 164, alignment: .leading)

                if let count {
                    Text("\(count)")
                        .font(Design.numericCaption2(weight: .bold))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .white.opacity(0.86) : .secondary.opacity(0.82))
                }

            }
            .foregroundStyle(isSelected ? .white.opacity(0.94) : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(isSelected ? Design.tagChipSelectedFill : .white.opacity(0.055))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? Design.tagChipSelectedStroke : .white.opacity(0.10), lineWidth: 0.8)
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

enum TagEditorDomain {
    case video
    case frame
    case audio
    case music

    var layout: TagEditorLayoutConfiguration {
        switch self {
        case .video:
            return TagEditorLayoutConfiguration(minWidth: 250, maxWidth: 370, chipMaxWidth: 116, maxVisibleRows: 4)
        case .frame:
            return TagEditorLayoutConfiguration(minWidth: 220, maxWidth: 330, chipMaxWidth: 104, maxVisibleRows: 4)
        case .audio:
            return TagEditorLayoutConfiguration(minWidth: 220, maxWidth: 320, chipMaxWidth: 104, maxVisibleRows: 4)
        case .music:
            return TagEditorLayoutConfiguration(minWidth: 240, maxWidth: 340, chipMaxWidth: 112, maxVisibleRows: 4)
        }
    }
}

struct TagEditorLayoutConfiguration {
    var minWidth: CGFloat
    var maxWidth: CGFloat
    var chipMinWidth: CGFloat = 42
    var chipMaxWidth: CGFloat
    var maxColumns: Int = 5
    var maxVisibleRows: Int
    var rowHeight: CGFloat = 28
    var columnSpacing: CGFloat = 6
    var rowSpacing: CGFloat = 6
    var verticalPadding: CGFloat = 2

    var maxPanelHeight: CGFloat {
        panelHeight(forRows: maxVisibleRows)
    }

    func panelHeight(forRows rows: Int) -> CGFloat {
        guard rows > 0 else { return 0 }
        return verticalPadding * 2
            + CGFloat(rows) * rowHeight
            + CGFloat(max(0, rows - 1)) * rowSpacing
    }
}

private struct TagEditorChoiceChip: View {
    let title: String
    let font: Font
    let textMaxWidth: CGFloat
    let rowHeight: CGFloat
    let horizontalPadding: CGFloat
    let isSelected: Bool
    let isRecent: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .lineLimit(1)
                .truncationMode(.tail)
                .allowsTightening(true)
                .frame(maxWidth: textMaxWidth, minHeight: rowHeight, maxHeight: rowHeight, alignment: .center)
                .foregroundStyle(foreground)
                .padding(.horizontal, horizontalPadding)
                .background(fill)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(stroke, lineWidth: isSelected || isRecent ? 0.8 : 0.7)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.58)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var foreground: Color {
        if isSelected || isRecent {
            return Design.tagChipForeground
        }
        return .secondary
    }

    private var fill: Color {
        if isRecent {
            return Design.annotationAccent.opacity(0.18)
        }
        if isSelected {
            return Design.tagChipSelectedFill
        }
        return Design.tagChipFill
    }

    private var stroke: Color {
        if isRecent {
            return Design.annotationAccent.opacity(0.32)
        }
        if isSelected {
            return Design.tagChipSelectedStroke
        }
        return Design.tagChipStroke
    }
}

private struct TagChoiceGridLayout: Layout {
    let maxItemsPerRow: Int
    let spacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(for: subviews, maxWidth: proposal.width ?? intrinsicWidth(for: subviews)).size
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

    private func intrinsicWidth(for subviews: Subviews) -> CGFloat {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rowCount = min(maxItemsPerRow, sizes.count)
        return sizes.prefix(rowCount).map(\.width).reduce(0, +)
            + CGFloat(max(0, rowCount - 1)) * spacing
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
        var rowItemCount = 0
        var usedWidth: CGFloat = 0

        for size in sizes {
            let nextWidth = rowItemCount == 0 ? size.width : x + spacing + size.width
            if rowItemCount > 0, rowItemCount >= maxItemsPerRow || nextWidth > maxWidth {
                y += rowHeight + rowSpacing
                x = 0
                rowHeight = 0
                rowItemCount = 0
            }

            if rowItemCount > 0 {
                x += spacing
            }

            positions.append(CGPoint(x: x, y: y))
            usedWidth = max(usedWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width
            rowItemCount += 1
        }

        return (
            positions: positions,
            sizes: sizes,
            size: CGSize(width: usedWidth, height: y + rowHeight)
        )
    }
}

struct TagEditorSection: View {
    var title: String? = nil
    var domain: TagEditorDomain
    let tags: [String]
    let suggestedTags: [String]
    var emptyTitle = "暂无标签"
    var chipSize: VideoTagChipSize = .regular
    var suggestionLimit = 12
    var verticalSpacing: CGFloat = 10
    var inputSpacing: CGFloat = 6
    var gridVerticalPadding: CGFloat?
    var onAdd: ((String) -> Void)? = nil
    var onRemove: ((String) -> Void)? = nil

    @State private var draftTag = ""
    @State private var recentlyAddedTagKey: String?
    @State private var pendingAddedTags: [String] = []
    @FocusState private var isTagFieldFocused: Bool

    private var layout: TagEditorLayoutConfiguration {
        domain.layout
    }

    private var trimmedDraftTag: String {
        draftTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedTags: [String] {
        var seenKeys = Set(tags.map(Self.tagKey))
        var result = tags

        for tag in pendingAddedTags {
            let key = Self.tagKey(tag)
            guard !key.isEmpty, seenKeys.insert(key).inserted else { continue }
            result.append(tag)
        }

        return result
    }

    private var selectedTagKeys: Set<String> {
        Set(displayedTags.map(Self.tagKey))
    }

    private var allTagChoices: [String] {
        tagChoices(matching: "")
    }

    private var visibleTagChoices: [String] {
        tagChoices(matching: Self.tagKey(trimmedDraftTag))
    }

    private var tagPanelWidth: CGFloat {
        guard !allTagChoices.isEmpty else { return layout.minWidth }

        let maxRowWidth = estimatedTagRows(for: allTagChoices, maxWidth: layout.maxWidth).maxRowWidth
        return min(layout.maxWidth, max(layout.minWidth, maxRowWidth))
    }

    private var visibleTagRows: Int {
        estimatedTagRows(for: visibleTagChoices, maxWidth: tagPanelWidth).rows
    }

    private var visibleTagPanelHeight: CGFloat {
        tagPanelHeight(forRows: min(visibleTagRows, layout.maxVisibleRows))
    }

    private var shouldScrollVisibleTags: Bool {
        visibleTagRows > layout.maxVisibleRows
    }

    private var tagChoiceFont: Font {
        switch chipSize {
        case .mini:
            return .system(size: 10, weight: .semibold)
        case .compact, .regular:
            return .system(size: 11, weight: .semibold)
        }
    }

    private var tagChoiceHorizontalPadding: CGFloat {
        switch chipSize {
        case .mini:
            return 6
        case .compact, .regular:
            return 7
        }
    }

    private var tagChoiceRowHeight: CGFloat {
        switch chipSize {
        case .mini:
            return 16
        case .compact, .regular:
            return 18
        }
    }

    private var tagChoiceTextMaxWidth: CGFloat {
        max(24, layout.chipMaxWidth - tagChoiceHorizontalPadding * 2)
    }

    private func tagPanelHeight(forRows rows: Int) -> CGFloat {
        guard rows > 0 else { return 0 }
        return layout.verticalPadding * 2
            + CGFloat(rows) * tagChoiceRowHeight
            + CGFloat(max(0, rows - 1)) * layout.rowSpacing
    }

    private func tagChoices(matching query: String) -> [String] {
        var seenKeys = Set<String>()
        var choices: [String] = []

        func appendChoice(_ rawTag: String) {
            let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty else { return }

            let key = Self.tagKey(tag)
            guard seenKeys.insert(key).inserted else { return }
            guard query.isEmpty || key.contains(query) else { return }
            choices.append(tag)
        }

        displayedTags.forEach(appendChoice)

        let selectedCount = choices.count
        for tag in suggestedTags {
            guard choices.count - selectedCount < suggestionLimit else { break }
            appendChoice(tag)
        }

        return choices
    }

    private func estimatedTagRows(for tags: [String], maxWidth: CGFloat) -> (rows: Int, maxRowWidth: CGFloat) {
        guard !tags.isEmpty else { return (0, 0) }

        var rows = 1
        var currentRowWidth: CGFloat = 0
        var maxRowWidth: CGFloat = 0
        var rowItemCount = 0

        for tag in tags {
            let chipWidth = estimatedTagChipWidth(for: tag)
            let nextWidth = rowItemCount == 0
                ? chipWidth
                : currentRowWidth + layout.columnSpacing + chipWidth

            if rowItemCount > 0, rowItemCount >= layout.maxColumns || nextWidth > maxWidth {
                maxRowWidth = max(maxRowWidth, currentRowWidth)
                rows += 1
                currentRowWidth = chipWidth
                rowItemCount = 1
            } else {
                currentRowWidth = nextWidth
                rowItemCount += 1
            }
        }

        maxRowWidth = max(maxRowWidth, currentRowWidth)
        return (rows, maxRowWidth)
    }

    private func estimatedTagChipWidth(for tag: String) -> CGFloat {
        let estimatedTextWidth = min(tagChoiceTextMaxWidth, CGFloat(tag.count) * 11)
        return min(layout.chipMaxWidth, estimatedTextWidth + tagChoiceHorizontalPadding * 2)
    }

    private var matchingDraftTag: String? {
        let key = Self.tagKey(trimmedDraftTag)
        guard !key.isEmpty else { return nil }

        return (displayedTags + suggestedTags).first { Self.tagKey($0) == key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if onAdd != nil {
                VStack(alignment: .leading, spacing: inputSpacing) {
                    TextField("添加标签", text: $draftTag)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTagFieldFocused)
                        .onSubmit(addDraftTag)
                        .onAppear {
                            DispatchQueue.main.async {
                                isTagFieldFocused = true
                            }
                        }

                    tagChoicePanel
                }
            } else {
                tagChoicePanel
            }
        }
        .onDisappear {
            draftTag = ""
            recentlyAddedTagKey = nil
            pendingAddedTags.removeAll()
        }
        .onChange(of: tags) { _, newTags in
            let committedKeys = Set(newTags.map(Self.tagKey))
            pendingAddedTags.removeAll { committedKeys.contains(Self.tagKey($0)) }
        }
        .frame(width: tagPanelWidth, alignment: .leading)
    }

    @ViewBuilder
    private var tagChoicePanel: some View {
        if !allTagChoices.isEmpty, !visibleTagChoices.isEmpty {
            let grid = tagChoiceGrid

            if shouldScrollVisibleTags {
                ScrollView {
                    grid
                }
                .fadingVerticalScrollIndicators()
                .frame(height: visibleTagPanelHeight, alignment: .topLeading)
            } else {
                grid
            }
        }
    }

    private var tagChoiceGrid: some View {
        TagChoiceGridLayout(
            maxItemsPerRow: layout.maxColumns,
            spacing: layout.columnSpacing,
            rowSpacing: layout.rowSpacing
        ) {
            ForEach(visibleTagChoices, id: \.self) { tag in
                tagChoiceButton(for: tag)
            }
        }
        .padding(.vertical, gridVerticalPadding ?? layout.verticalPadding)
        .frame(width: tagPanelWidth, alignment: .topLeading)
    }

    private func tagChoiceButton(for tag: String) -> some View {
        let key = Self.tagKey(tag)
        let isSelected = selectedTagKeys.contains(key)
        let isRecent = recentlyAddedTagKey == key
        let canRemove = isSelected && onRemove != nil
        let isEnabled = canRemove || (!isSelected && onAdd != nil)

        return TagEditorChoiceChip(
            title: tag,
            font: tagChoiceFont,
            textMaxWidth: tagChoiceTextMaxWidth,
            rowHeight: tagChoiceRowHeight,
            horizontalPadding: tagChoiceHorizontalPadding,
            isSelected: isSelected,
            isRecent: isRecent,
            isEnabled: isEnabled
        ) {
            toggleTag(tag, isSelected: isSelected)
        }
    }

    private func addDraftTag() {
        if let matchingDraftTag {
            let key = Self.tagKey(matchingDraftTag)
            if selectedTagKeys.contains(key) {
                recentlyAddedTagKey = key
                draftTag = ""
                clearRecentHighlight(for: key)
            } else {
                addTag(matchingDraftTag)
            }
        } else {
            addTag(trimmedDraftTag)
        }
    }

    private func toggleTag(_ tag: String, isSelected: Bool) {
        if isSelected {
            let key = Self.tagKey(tag)
            pendingAddedTags.removeAll { Self.tagKey($0) == key }
            onRemove?(tag)
        } else {
            addTag(tag)
        }
    }

    private func addTag(_ rawTag: String) {
        let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }

        let key = Self.tagKey(tag)
        recentlyAddedTagKey = key
        if !selectedTagKeys.contains(key) {
            pendingAddedTags.append(tag)
        }
        onAdd?(tag)
        draftTag = ""
        clearRecentHighlight(for: key)
    }

    private func clearRecentHighlight(for key: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard recentlyAddedTagKey == key else { return }
            recentlyAddedTagKey = nil
            if !tags.map(Self.tagKey).contains(key) {
                pendingAddedTags.removeAll { Self.tagKey($0) == key }
            }
        }
    }

    nonisolated private static func tagKey(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

struct InlineTagAddButton: View {
    let title: String
    var domain: TagEditorDomain = .video
    let tags: [String]
    let suggestedTags: [String]
    var buttonSize: CGFloat = 16
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    @State private var isPresented = false
    @State private var isHovered = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            CenteredPlusGlyph(size: max(7, buttonSize * 0.48), thickness: max(1, buttonSize * 0.085))
                .foregroundStyle(isHovered ? Color.primary.opacity(0.86) : Color.secondary)
                .frame(width: buttonSize, height: buttonSize)
                .background(.white.opacity(isHovered ? 0.11 : 0.07))
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(isHovered ? 0.18 : 0.10), lineWidth: 0.7)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            TagEditorSection(
                title: title,
                domain: domain,
                tags: tags,
                suggestedTags: suggestedTags,
                chipSize: .compact,
                onAdd: onAdd,
                onRemove: onRemove
            )
            .padding(12)
        }
    }
}

struct PreviewTitleTagChip: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .allowsTightening(true)
            .frame(maxWidth: 64, minHeight: Design.previewHeaderTagRowHeight, maxHeight: Design.previewHeaderTagRowHeight, alignment: .center)
            .padding(.horizontal, 5)
            .foregroundStyle(Design.tagChipForeground)
            .background(Design.tagChipFill)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Design.tagChipStroke, lineWidth: 0.7)
            }
    }
}

struct TagStripAddButton: View {
    var height: CGFloat = Design.previewHeaderTagRowHeight
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CenteredPlusGlyph(size: min(8, height * 0.62), thickness: max(1, height * 0.11))
                .frame(width: 14, height: height)
            .foregroundStyle(.secondary)
            .background(.white.opacity(0.07))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
