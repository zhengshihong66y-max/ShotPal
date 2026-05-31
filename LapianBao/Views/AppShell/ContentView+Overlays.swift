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
                .onTapGesture {
                    closeImportPanel()
                }

            importSheet
                .frame(width: panelWidth, height: panelHeight)
                .background(Design.sidebarBg)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.38), radius: 28, y: 18)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
        }
        .zIndex(20)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }

    func settingsOverlay(containerSize: CGSize) -> some View {
        let panelWidth = max(560, min(containerSize.width - 48, 980))
        let panelHeight = max(430, min(containerSize.height - 56, 720))

        return ZStack {
            Color.black.opacity(0.44)
                .ignoresSafeArea()
                .onTapGesture {
                    closeSettingsPanel()
                }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Label("设置", systemImage: "gearshape")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Button {
                        closeSettingsPanel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    .help("关闭")
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)

                SettingsWorkspaceView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: panelWidth, height: panelHeight)
            .background(Design.sidebarBg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.38), radius: 28, y: 18)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .zIndex(21)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }

    func closeSettingsPanel() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            isSettingsSheetPresented = false
        }
    }

}
