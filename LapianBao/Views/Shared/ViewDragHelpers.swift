//
//  ViewDragHelpers.swift
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

extension View {
    @ViewBuilder
    func itemProviderDrag(_ itemProvider: (() -> NSItemProvider)?) -> some View {
        if let itemProvider {
            self.onDrag {
                itemProvider()
            }
        } else {
            self
        }
    }

    func fullResolutionImageDrag(_ itemProvider: (() -> NSItemProvider)?) -> some View {
        itemProviderDrag(itemProvider)
    }

    func recognitionProgressCard() -> some View {
        self
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.078))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 0.8)
            }
    }
}

func videoDragItemProvider(for video: VideoItem) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.suggestedName = video.url.lastPathComponent

    let typeIdentifier = UTType(filenameExtension: video.url.pathExtension)?.identifier ?? UTType.movie.identifier
    provider.registerFileRepresentation(
        forTypeIdentifier: typeIdentifier,
        fileOptions: .openInPlace,
        visibility: .all
    ) { completion in
        let progress = Progress(totalUnitCount: 1)
        guard FileManager.default.fileExists(atPath: video.url.path) else {
            completion(nil, true, NSError(
                domain: "LapianBao.VideoDragExport",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "视频文件不存在"]
            ))
            return progress
        }

        progress.completedUnitCount = 1
        completion(video.url, true, nil)
        return progress
    }

    provider.registerObject(video.url as NSURL, visibility: .all)
    return provider
}
