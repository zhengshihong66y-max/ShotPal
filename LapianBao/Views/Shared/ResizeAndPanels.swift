//
//  ResizeAndPanels.swift
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

// MARK: - ResizeLeftRightCursorView

struct ResizeLeftRightCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorNSView { CursorNSView() }
    func updateNSView(_ nsView: CursorNSView, context: Context) { nsView.window?.invalidateCursorRects(for: nsView) }

    class CursorNSView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }
    }
}

// MARK: - View extensions

extension View {
    func contentPanel() -> some View {
        self.background(Design.contentBg)
    }

    func glassPanel() -> some View {
        self.background(Design.sidebarBg)
    }
}
