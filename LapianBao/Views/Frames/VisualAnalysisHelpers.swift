//
//  VisualAnalysisHelpers.swift
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

struct ColorSwatches: View {
    enum Orientation {
        case horizontal
        case vertical
    }

    private struct SwatchColor {
        let color: Color
        let hexCode: String
    }

    let imageData: Data
    var orientation: Orientation = .horizontal

    var body: some View {
        let colors = regionAverageColors()
        swatches(colors)
    }

    @ViewBuilder
    private func swatches(_ colors: [SwatchColor]) -> some View {
        switch orientation {
        case .horizontal:
            HStack(spacing: 5) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, swatch in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(swatch.color)
                        .frame(height: 24)
                        .help(swatch.hexCode)
                }
            }
        case .vertical:
            VStack(spacing: 6) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, swatch in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(swatch.color)
                        .frame(width: 72, height: 42)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(.white.opacity(0.10), lineWidth: 0.7)
                        }
                        .help(swatch.hexCode)
                }
            }
        }
    }

    // Divides image into a 3×2 grid (16:9 friendly), returns average color per region.
    private func regionAverageColors() -> [SwatchColor] {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return placeholderColors()
        }
        let w = 48, h = 27
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return placeholderColors() }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        let cols = 3, rows = 2
        let cellW = w / cols, cellH = h / rows
        return (0 ..< rows).flatMap { row in
            (0 ..< cols).map { col in
                var rSum = 0.0, gSum = 0.0, bSum = 0.0
                let count = Double(cellW * cellH)
                for py in (row * cellH) ..< ((row + 1) * cellH) {
                    for px in (col * cellW) ..< ((col + 1) * cellW) {
                        let o = (py * w + px) * 4
                        rSum += Double(pixels[o])
                        gSum += Double(pixels[o + 1])
                        bSum += Double(pixels[o + 2])
                    }
                }
                let red = UInt8((rSum / count).rounded())
                let green = UInt8((gSum / count).rounded())
                let blue = UInt8((bSum / count).rounded())
                return swatchColor(red: red, green: green, blue: blue)
            }
        }
    }

    private func placeholderColors() -> [SwatchColor] {
        Array(repeating: swatchColor(red: 128, green: 128, blue: 128), count: 6)
    }

    private func swatchColor(red: UInt8, green: UInt8, blue: UInt8) -> SwatchColor {
        SwatchColor(
            color: Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255),
            hexCode: String(format: "#%02X%02X%02X", red, green, blue)
        )
    }
}

func clockText(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
}

func formatDuration(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    let m = total / 60
    let s = total % 60
    return m > 0 ? "\(m) 分 \(s) 秒" : "\(s) 秒"
}
