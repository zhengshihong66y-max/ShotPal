//
//  FrameBoardImageTile.swift
//  LapianBao
//

import SwiftUI
import AppKit
import Foundation

struct FrameBoardImageTile<OverlayControl: View>: View {
    let image: NSImage?
    var numberText: String? = nil
    let onTap: () -> Void
    let dragItemProvider: (() -> NSItemProvider)?
    @ViewBuilder let overlayControl: (_ isHovered: Bool) -> OverlayControl

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    imageContent
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()

                    if let numberText, !numberText.isEmpty {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.56)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 48)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)

                        Text(numberText)
                            .font(Design.numericFont(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.96))
                            .shadow(color: .black.opacity(0.72), radius: 2, y: 1)
                            .padding(.leading, 9)
                            .padding(.bottom, 7)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(tileShape)
            .contentShape(tileShape)
            .highPriorityGesture(TapGesture().onEnded { onTap() })
            .fullResolutionImageDrag(dragItemProvider)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                onTap()
            }

            overlayControl(isHovered)
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
                .animation(.easeInOut(duration: 0.12), value: isHovered)
                .padding(8)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var imageContent: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .scaledToFill()
        } else {
            Color.black.opacity(0.26)
        }
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
    }
}
