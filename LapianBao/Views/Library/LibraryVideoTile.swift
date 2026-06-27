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
    let thumbnailRevision: Int
    let durationText: String?
    let sourcePlatform: String?
    let tags: [String]
    let suggestedTags: [String]
    let isSelected: Bool
    let onSelect: () -> Void
    let onAddTag: (String) -> Void
    let onRemoveTag: (String) -> Void
    let onSetSourcePlatform: (String) -> Void
    let onDelete: () -> Void
    let menuIdentity: String
    let menuDismissToken: Int
    let onMenuPresentationChanged: (String, Bool) -> Void
    let dragItemProvider: (() -> NSItemProvider)?

    @State private var isHovered = false
    @State private var isMorePresented = false
    @State private var isSourcePlatformMenuPresented = false

    private let cardAspectRatio: CGFloat = 1.06
    private let infoBarMinHeight: CGFloat = 54
    private let infoBarMaxHeight: CGFloat = 72

    static func == (lhs: LibraryVideoTile, rhs: LibraryVideoTile) -> Bool {
        lhs.video == rhs.video
            && lhs.displayName == rhs.displayName
            && lhs.thumbnailRevision == rhs.thumbnailRevision
            && lhs.durationText == rhs.durationText
            && lhs.sourcePlatform == rhs.sourcePlatform
            && lhs.tags == rhs.tags
            && lhs.suggestedTags == rhs.suggestedTags
            && lhs.isSelected == rhs.isSelected
            && lhs.menuDismissToken == rhs.menuDismissToken
            && sameImage(lhs.thumbnailImage, rhs.thumbnailImage)
            // Action closures are intentionally not compared.
    }

    var body: some View {
        tileSurface
        .accessibilityLabel("视频：\(displayName)")
        .accessibilityIdentifier("library_video_tile_\(accessibilityVideoKey)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onSelect()
        }
        .overlay(alignment: .topTrailing) {
            tileActionBar
                .opacity(isHovered || isMorePresented ? 1 : 0)
                .allowsHitTesting(isHovered || isMorePresented)
                .padding(.top, CardTimeBadge.verticalInset)
                .padding(.trailing, CardTimeBadge.edgeInset)
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onChange(of: isMorePresented) { _, _ in
            notifyMenuPresentation()
        }
        .onChange(of: isSourcePlatformMenuPresented) { _, _ in
            notifyMenuPresentation()
        }
        .onChange(of: menuDismissToken) { _, _ in
            dismissTransientMenus()
        }
        .onDisappear {
            onMenuPresentationChanged(menuIdentity, false)
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

            VStack(spacing: 0) {
                thumbnailPanel
                    .frame(width: width, height: thumbnailHeight)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onSelect)
                    .overlay(alignment: .bottomTrailing) {
                        CardTimeBadge(text: durationText, placeholder: "--:--")
                            .padding(.trailing, CardTimeBadge.edgeInset)
                            .padding(.bottom, CardTimeBadge.verticalInset)
                    }
                    .overlay(alignment: .bottomLeading) {
                        sourcePlatformMenuButton
                            .padding(.leading, CardTimeBadge.edgeInset)
                            .padding(.bottom, CardTimeBadge.verticalInset)
                    }

                infoBar(metrics: metrics)
                    .frame(width: width, height: infoHeight, alignment: .topLeading)
                    .background(Color.white.opacity(isSelected ? 0.090 : 0.052))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onSelect)
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
        let titleBlockHeight: CGFloat
    }

    private func tileMetrics(width: CGFloat, height: CGFloat) -> TileMetrics {
        let compactness = min(1, max(0, (width - 118) / 140))
        let infoRatio = 0.31 - compactness * 0.03
        let titleFontSize = min(13, max(11, width * 0.095))
        let titleBlockHeight = ceil(titleFontSize * 2.72)
        let infoHeight = min(
            infoBarMaxHeight,
            max(infoBarMinHeight, max(titleBlockHeight + 16, height * infoRatio))
        )
        let verticalPadding = max(7, (infoHeight - titleBlockHeight) / 2)

        return TileMetrics(
            infoHeight: infoHeight,
            horizontalPadding: min(10, max(7, width * 0.07)),
            verticalPadding: verticalPadding,
            titleFontSize: titleFontSize,
            titleBlockHeight: titleBlockHeight
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
        .id(thumbnailRevision)
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
                minHeight: metrics.titleBlockHeight,
                maxHeight: metrics.titleBlockHeight,
                alignment: .leading
            )
            .clipped()
            .layoutPriority(1)
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var sourcePlatformMenuButton: some View {
        let platform = sourcePlatform ?? VideoSourcePlatform.other.rawValue

        return Button {
            isMorePresented = false
            isSourcePlatformMenuPresented.toggle()
        } label: {
            SourcePlatformIconBadge(platform: platform)
                .frame(width: 26, height: 26)
                .background(Color.black.opacity(0.20))
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.14), lineWidth: 0.7)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("设置视频平台：\(platform)")
        .accessibilityIdentifier("library_video_platform_button_\(accessibilityVideoKey)")
        .popover(isPresented: $isSourcePlatformMenuPresented, arrowEdge: .bottom) {
            sourcePlatformMenu
                .transaction { $0.animation = nil }
        }
    }

    private var sourcePlatformMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(sourcePlatformChoices, id: \.rawValue) { platform in
                SourcePlatformMenuRow(
                    platform: platform,
                    isSelected: platform.rawValue == sourcePlatform
                ) {
                    onSetSourcePlatform(platform.rawValue)
                    isSourcePlatformMenuPresented = false
                }
            }
        }
        .padding(8)
        .frame(width: 136, alignment: .leading)
    }

    private var tileActionBar: some View {
        moreButton
    }

    private var moreButton: some View {
        Button {
            isSourcePlatformMenuPresented = false
            isMorePresented.toggle()
        } label: {
            CardOverlayMoreIcon(shadowOpacity: 0.5, shadowRadius: 2)
        }
        .buttonStyle(.plain)
        .frame(width: CardOverlayMoreIcon.size, height: CardOverlayMoreIcon.size)
        .accessibilityLabel("打开视频操作菜单")
        .accessibilityIdentifier("library_video_more_button_\(accessibilityVideoKey)")
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
            // 标签区
            TagEditorSection(
                domain: .video,
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

            Divider()

            // 操作区
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    isMorePresented = false
                    NSWorkspace.shared.activateFileViewerSelecting([video.url])
                } label: {
                    Label("在访达中显示", systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("在访达中显示视频")
                .accessibilityIdentifier("library_video_show_in_finder_button_\(accessibilityVideoKey)")

                Button(role: .destructive) {
                    isMorePresented = false
                    onDelete()
                } label: {
                    Label("删除视频", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .accessibilityLabel("删除视频")
                .accessibilityIdentifier("library_video_delete_button_\(accessibilityVideoKey)")
            }
            .padding(.vertical, 6)
        }
        .frame(minWidth: 220)
    }

    private var accessibilityVideoKey: String {
        stableHexKey(for: video.url.path)
    }

    private func stableHexKey(for string: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private var sourcePlatformChoices: [VideoSourcePlatform] {
        VideoSourcePlatform.allCases.filter { $0 != .other }
    }

    private func notifyMenuPresentation() {
        onMenuPresentationChanged(menuIdentity, isMorePresented || isSourcePlatformMenuPresented)
    }

    private func dismissTransientMenus() {
        guard isMorePresented || isSourcePlatformMenuPresented else { return }
        isMorePresented = false
        isSourcePlatformMenuPresented = false
        onMenuPresentationChanged(menuIdentity, false)
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

private struct SourcePlatformMenuRow: View {
    let platform: VideoSourcePlatform
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: platform.iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(platform.color)
                    .frame(width: 14, height: 14)

                Text(platform.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)

                Spacer(minLength: 6)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(isSelected ? Color.white.opacity(0.10) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择平台：\(platform.rawValue)")
        .accessibilityIdentifier("source_platform_\(platformAccessibilityKey)_button")
    }

    private var platformAccessibilityKey: String {
        switch platform {
        case .instagram:
            return "instagram"
        case .youtube:
            return "youtube"
        case .xiaohongshu:
            return "xiaohongshu"
        case .bilibili:
            return "bilibili"
        case .douyin:
            return "douyin"
        case .other:
            return "other"
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
            .font(Design.numericFont(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(text == nil ? 0.62 : 0.92))
            .shadow(color: .black.opacity(0.72), radius: 2.4, x: 0, y: 1)
            .shadow(color: .black.opacity(0.38), radius: 7, x: 0, y: 2)
            .lineLimit(1)
            .minimumScaleFactor(0.84)
            .allowsTightening(true)
            .frame(width: Self.width, height: Self.height, alignment: .trailing)
    }
}

struct CardOverlayMoreIcon: View {
    static let size: CGFloat = 26

    var shadowOpacity: Double = 0.45
    var shadowRadius: CGFloat = 3

    // The tiny ellipsis sits low and centered inside its 26pt hit box; this equalizes its visible inset with the timecode.
    private let ellipsisVisualOffset = CGSize(width: 4.5, height: -7.5)

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: Self.size, height: Self.size)
            .offset(ellipsisVisualOffset)
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: 1)
            .contentShape(Rectangle())
    }
}
