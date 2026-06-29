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

nonisolated let legacyFilenamesPasteboardTypeIdentifier = "NSFilenamesPboardType"

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

nonisolated func externalAudioDragFileURL(for fileURL: URL, suggestedName: String) -> URL {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return fileURL }

    let exportDirectory = fileURL
        .deletingLastPathComponent()
        .appendingPathComponent(".lapianbao_drag_exports", isDirectory: true)
    let cleanFilename = externalDragFilename(
        suggestedName: suggestedName,
        fallbackName: fileURL.lastPathComponent,
        sourcePath: fileURL.path
    )
    let exportURL = exportDirectory.appendingPathComponent(cleanFilename, isDirectory: false)

    do {
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        try? (exportDirectory as NSURL).setResourceValue(true, forKey: .isHiddenKey)

        if FileManager.default.fileExists(atPath: exportURL.path) {
            if externalDragFileMatchesSource(exportURL, sourceURL: fileURL) {
                return exportURL
            }
            try FileManager.default.removeItem(at: exportURL)
        }

        do {
            try FileManager.default.linkItem(at: fileURL, to: exportURL)
        } catch {
            try FileManager.default.copyItem(at: fileURL, to: exportURL)
        }
        return exportURL
    } catch {
        return fileURL
    }
}

nonisolated func existingFileItemProvider(
    for fileURL: URL,
    suggestedName: String,
    fallbackTypeIdentifier: String,
    errorDomain: String,
    missingFileMessage: String
) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.suggestedName = suggestedName
    let typeIdentifier = UTType(filenameExtension: fileURL.pathExtension)?.identifier ?? fallbackTypeIdentifier

    provider.registerFileRepresentation(
        forTypeIdentifier: typeIdentifier,
        fileOptions: .openInPlace,
        visibility: .all
    ) { completion in
        let progress = Progress(totalUnitCount: 1)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            completion(nil, true, NSError(
                domain: errorDomain,
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: missingFileMessage]
            ))
            return progress
        }

        progress.completedUnitCount = 1
        completion(fileURL, true, nil)
        return progress
    }

    registerFileImportRepresentations(on: provider, fileURL: fileURL)
    return provider
}

nonisolated func registerFileImportRepresentations(on provider: NSItemProvider, fileURL: URL) {
    registerFileImportRepresentations(on: provider) { completion in
        completion(.success(fileURL))
        return nil
    }
    provider.registerObject(fileURL as NSURL, visibility: .all)
}

nonisolated func registerFileImportRepresentations(
    on provider: NSItemProvider,
    resolveFileURL: @escaping (@escaping (Result<URL, Error>) -> Void) -> Progress?
) {
    registerResolvedFileDataRepresentation(on: provider, forTypeIdentifier: UTType.fileURL.identifier, resolveFileURL: resolveFileURL) { fileURL in
        fileURL.absoluteString.data(using: .utf8)
    }
    registerResolvedFileDataRepresentation(on: provider, forTypeIdentifier: UTType.url.identifier, resolveFileURL: resolveFileURL) { fileURL in
        fileURL.absoluteString.data(using: .utf8)
    }
    registerResolvedFileDataRepresentation(on: provider, forTypeIdentifier: legacyFilenamesPasteboardTypeIdentifier, resolveFileURL: resolveFileURL) { fileURL in
        legacyFilenamesPasteboardData(for: fileURL)
    }
}

nonisolated private func registerResolvedFileDataRepresentation(
    on provider: NSItemProvider,
    forTypeIdentifier typeIdentifier: String,
    resolveFileURL: @escaping (@escaping (Result<URL, Error>) -> Void) -> Progress?,
    data: @escaping (URL) -> Data?
) {
    provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion in
        return resolveFileURL { result in
            switch result {
            case .success(let fileURL):
                if let payload = data(fileURL) {
                    completion(payload, nil)
                } else {
                    completion(nil, NSError(
                        domain: "LapianBao.DragFileRepresentation",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "无法生成拖拽文件路径数据"]
                    ))
                }
            case .failure(let error):
                completion(nil, error)
            }
        }
    }
}

nonisolated private func legacyFilenamesPasteboardData(for fileURL: URL) -> Data? {
    try? PropertyListSerialization.data(
        fromPropertyList: [fileURL.path],
        format: .xml,
        options: 0
    )
}

nonisolated private func externalDragFilename(suggestedName: String, fallbackName: String, sourcePath: String) -> String {
    let suggestedURL = URL(fileURLWithPath: suggestedName)
    let fallbackURL = URL(fileURLWithPath: fallbackName)
    let fileExtension = (suggestedURL.pathExtension.isEmpty ? fallbackURL.pathExtension : suggestedURL.pathExtension)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let suggestedStem = suggestedURL.deletingPathExtension().lastPathComponent
    let fallbackStem = fallbackURL.deletingPathExtension().lastPathComponent
    let stem = externalDragSafeStem(suggestedStem.isEmpty ? fallbackStem : suggestedStem)
    let hash = externalDragPathHash(sourcePath)
    let baseName = "\(stem)-\(hash)"
    return fileExtension.isEmpty ? baseName : "\(baseName).\(fileExtension)"
}

nonisolated private func externalDragSafeStem(_ name: String) -> String {
    let folded = name.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
    var scalars: [UnicodeScalar] = []
    var lastWasSeparator = false

    for scalar in folded.unicodeScalars {
        let value = scalar.value
        let isAllowed =
            (48...57).contains(value) ||
            (65...90).contains(value) ||
            (97...122).contains(value) ||
            scalar == "'" ||
            scalar == "." ||
            scalar == "_" ||
            scalar == "-" ||
            scalar == "(" ||
            scalar == ")" ||
            scalar == "[" ||
            scalar == "]"

        if isAllowed {
            scalars.append(scalar)
            lastWasSeparator = false
        } else if !lastWasSeparator {
            scalars.append("-")
            lastWasSeparator = true
        }
    }

    let cleaned = String(String.UnicodeScalarView(scalars))
        .trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
    let fallback = cleaned.isEmpty ? "audio" : cleaned
    return String(fallback.prefix(96))
}

nonisolated private func externalDragPathHash(_ path: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in path.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return String(format: "%08llx", hash & 0xffff_ffff)
}

nonisolated private func externalDragFileMatchesSource(_ exportURL: URL, sourceURL: URL) -> Bool {
    guard
        let exportValues = try? exportURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
        let sourceValues = try? sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
        exportValues.fileSize == sourceValues.fileSize
    else { return false }

    guard
        let exportModifiedAt = exportValues.contentModificationDate,
        let sourceModifiedAt = sourceValues.contentModificationDate
    else { return true }

    return abs(exportModifiedAt.timeIntervalSince(sourceModifiedAt)) < 1
}

nonisolated func videoDragItemProvider(for video: VideoItem) -> NSItemProvider {
    existingFileItemProvider(
        for: video.url,
        suggestedName: video.url.lastPathComponent,
        fallbackTypeIdentifier: UTType.movie.identifier,
        errorDomain: "LapianBao.VideoDragExport",
        missingFileMessage: "视频文件不存在"
    )
}
