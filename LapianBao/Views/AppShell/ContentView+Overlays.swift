//
//  ContentView+Overlays.swift
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

extension ContentView {
    func importOverlay(containerSize: CGSize) -> some View {
        let panelWidth = max(560, min(containerSize.width - 48, 980))
        let panelHeight = max(430, min(containerSize.height - 56, 720))

        return ZStack {
            Color.black.opacity(0.44)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    // 打开面板的那次点击会被手势系统对更新后的视图树重新命中,
                    // 落在遮罩上当场关闭面板;打开后的短窗口内忽略遮罩点击。
                    guard Date().timeIntervalSince(importPanelPresentedAt) > 0.35 else { return }
                    closeImportPanel()
                }
                .accessibilityHidden(true)

            importSheet
                .frame(width: panelWidth, height: panelHeight)
                .background(Design.sidebarBg)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.38), radius: 28, y: 18)
                .zIndex(1)
                .accessibilityLabel(L10n.text("导入面板"))
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .zIndex(20)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }

}
