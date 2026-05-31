//
//  Design.swift
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
    static let libraryToolbarSearchMinWidth: CGFloat = 110
    static let libraryToolbarSearchWidth: CGFloat = 280
    static let libraryToolbarSearchHeight: CGFloat = 26
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

struct LibraryToolbarSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.caption)
        }
        .padding(.horizontal, 9)
        .frame(
            minWidth: Design.libraryToolbarSearchMinWidth,
            idealWidth: Design.libraryToolbarSearchWidth,
            maxWidth: Design.libraryToolbarSearchWidth,
            minHeight: Design.libraryToolbarSearchHeight,
            maxHeight: Design.libraryToolbarSearchHeight
        )
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

func floatingExportButtonIcon(
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

func cardOverlayExportButtonIcon(
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
