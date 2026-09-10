import AppKit
import ImageIO
import SwiftUI

nonisolated private enum ImportThumbnailCache {
    static let images: NSCache<NSData, NSImage> = {
        let cache = NSCache<NSData, NSImage>()
        cache.countLimit = 256
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    @concurrent static func image(for data: Data) async -> NSImage? {
        if let cached = images.object(forKey: data as NSData) { return cached }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 192,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let result = NSImage(cgImage: image, size: .zero)
        images.setObject(result, forKey: data as NSData, cost: image.bytesPerRow * image.height)
        return result
    }
}

struct ImportJobThumbnailView: View {
    let data: Data
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Color.clear }
        }
        .task(id: data) {
            let decoded = await ImportThumbnailCache.image(for: data)
            guard !Task.isCancelled else { return }
            image = decoded
        }
    }
}
