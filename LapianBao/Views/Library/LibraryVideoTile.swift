//
//  LibraryVideoTile.swift
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

enum VideoAnalysisKind: String, CaseIterable, Equatable {
    case transcript
    case scene
    case music
}

enum VideoAnalysisTone: Equatable {
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
            return Color.red.opacity(0.86)
        }
    }
}

struct VideoAnalysisMenuItem: Identifiable, Equatable {
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

struct LibraryVideoTile: View, Equatable {
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
                    Label("移到废纸篓", systemImage: "trash")
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

struct CardTimeBadge: View {
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
