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

struct LuminanceHistogram: View {
    let imageData: Data

    var body: some View {
        let buckets = luminanceBuckets()
        VStack(alignment: .leading, spacing: 6) {
            Text("亮度分布")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Canvas { context, size in
                guard !buckets.isEmpty else { return }
                let maxVal = buckets.max() ?? 1
                let barW = size.width / CGFloat(buckets.count)
                for (i, val) in buckets.enumerated() {
                    let h = maxVal > 0 ? CGFloat(val) / CGFloat(maxVal) * size.height : 0
                    let rect = CGRect(x: CGFloat(i) * barW, y: size.height - h, width: max(1, barW - 0.5), height: h)
                    var path = Path()
                    path.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1))
                    let brightness = Double(i) / Double(buckets.count)
                    context.fill(path, with: .color(Color.white.opacity(0.25 + brightness * 0.65)))
                }
            }
            .frame(height: 44)
            .background(Color.black.opacity(0.28))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func luminanceBuckets(count: Int = 32) -> [Int] {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return Array(repeating: 0, count: count)
        }
        let w = 64, h = 36
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Array(repeating: 0, count: count) }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var buckets = Array(repeating: 0, count: count)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let idx = min(count - 1, Int(luma / 255.0 * Double(count)))
            buckets[idx] += 1
        }
        return buckets
    }
}

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

extension Notification.Name {
    static let lapianBaoSeekRequest = Notification.Name("lapianBaoSeekRequest")
    static let lapianBaoPausePreviewRequest = Notification.Name("lapianBaoPausePreviewRequest")
    static let lapianBaoMusicPreviewStarted = Notification.Name("lapianBaoMusicPreviewStarted")
}
