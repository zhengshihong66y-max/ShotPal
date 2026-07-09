//
//  FrameDetailTagStrip.swift
//  LapianBao
//

import SwiftUI
import AppKit
import Foundation

struct FrameDetailTagStrip: View {
    let tags: [String]
    let suggestedTags: [String]
    let onAdd: ((String) -> Void)?
    let onRemove: ((String) -> Void)?

    static let rowHeight: CGFloat = 24

    private let rowHeight = Self.rowHeight
    private let itemSpacing: CGFloat = 5
    private let addButtonWidth: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let items = singleLineLayout(tags: tags, maxWidth: proxy.size.width)

            HStack(alignment: .center, spacing: itemSpacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    rowItemView(item)
                }
            }
            .frame(width: proxy.size.width, height: rowHeight, alignment: .leading)
            .clipped()
        }
        .frame(height: rowHeight, alignment: .leading)
        .clipped()
    }

    @ViewBuilder
    private func rowItemView(_ item: RowItem) -> some View {
        switch item {
        case .tag(let tag):
            Button {
                onRemove?(tag)
            } label: {
                VideoTagChip(tag: tag, size: .compact)
            }
            .buttonStyle(.plain)
            .disabled(onRemove == nil)

        case .overflow(let hiddenCount):
            VideoTagOverflowChip(count: hiddenCount)

        case .add:
            if let onAdd {
                InlineTagAddButton(
                    title: nil,
                    domain: .frame,
                    tags: tags,
                    suggestedTags: suggestedTags,
                    buttonSize: addButtonWidth,
                    onAdd: onAdd,
                    onRemove: { tag in onRemove?(tag) }
                )
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("frame_detail_tag_add_button")
            }
        }
    }

    private func singleLineLayout(tags: [String], maxWidth: CGFloat) -> [RowItem] {
        let availableWidth = max(0, maxWidth)
        guard availableWidth > 0 else { return [] }

        if tags.isEmpty {
            return onAdd == nil ? [] : [.add]
        }

        for visibleCount in stride(from: tags.count, through: 1, by: -1) {
            let hiddenCount = tags.count - visibleCount
            var items = tags.prefix(visibleCount).map(RowItem.tag)
            if hiddenCount > 0 {
                items.append(.overflow(hiddenCount))
            }
            if onAdd != nil {
                items.append(.add)
            }

            if rowWidth(items) <= availableWidth {
                return items
            }
        }

        let hiddenCount = tags.count - 1
        var fallbackItems: [RowItem] = [.tag(tags[0])]
        if hiddenCount > 0 {
            fallbackItems.append(.overflow(hiddenCount))
        }
        if onAdd != nil {
            fallbackItems.append(.add)
        }
        return fallbackItems
    }

    private func rowWidth(_ items: [RowItem]) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        let itemWidths = items.reduce(CGFloat(0)) { partial, item in
            partial + itemWidth(item)
        }
        return itemWidths + itemSpacing * CGFloat(items.count - 1)
    }

    private func itemWidth(_ item: RowItem) -> CGFloat {
        switch item {
        case .tag(let tag):
            return detailTagChipWidth(for: tag)
        case .overflow(let hiddenCount):
            return detailOverflowChipWidth(for: hiddenCount)
        case .add:
            return addButtonWidth
        }
    }

    private func detailTagChipWidth(for tag: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let textWidth = (tag as NSString).size(withAttributes: [.font: font]).width
        return min(VideoTagChipSize.compact.maxTextWidth, ceil(textWidth))
            + VideoTagChipSize.compact.horizontalPadding * 2
    }

    private func detailOverflowChipWidth(for hiddenCount: Int) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: .bold)
        let textWidth = ("+\(hiddenCount)" as NSString).size(withAttributes: [.font: font]).width
        return ceil(textWidth) + 12
    }

    private enum RowItem {
        case tag(String)
        case overflow(Int)
        case add
    }
}
