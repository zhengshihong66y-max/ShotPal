//
//  CommandLineDragProviderCheck.swift
//  LapianBao
//
//  Verifies drag exports expose real file paths for external import targets.
//

import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers

enum CommandLineDragProviderCheck {
    nonisolated static let flag = "--lapianbao-drag-provider-check"

    nonisolated static func runIfRequested() {
        guard CommandLine.arguments.contains(flag) else { return }

        do {
            let folderURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("LapianBaoDragProviderCheck", isDirectory: true)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let audioURL = folderURL.appendingPathComponent("drag-check.m4a")
            try Data([0, 1, 2, 3]).write(to: audioURL, options: .atomic)

            let audioProvider = existingFileItemProvider(
                for: audioURL,
                suggestedName: audioURL.lastPathComponent,
                fallbackTypeIdentifier: UTType.audio.identifier,
                errorDomain: "LapianBao.DragProviderCheck",
                missingFileMessage: "测试音频不存在"
            )
            let frameProvider = LibraryStore.savedFrameDataItemProvider(
                data: Data([0xff, 0xd8, 0xff, 0xd9]),
                suggestedName: "drag-check-frame.jpg"
            )

            let audioCheck = try dragProviderCanExposeFilePath(audioProvider, expectedPath: audioURL.path)
            let frameCheck = try dragProviderCanExposeFilePath(frameProvider, expectedPathSuffix: "drag-check-frame.jpg")
            let succeeded = audioCheck && frameCheck
            print("""
            {"status":"\(succeeded ? "succeeded" : "failed")","audioPathExport":\(audioCheck),"framePathExport":\(frameCheck)}
            """)
            Darwin.exit(succeeded ? 0 : 1)
        } catch {
            print("""
            {"status":"failed","error":"\(jsonEscaped(error.localizedDescription))"}
            """)
            Darwin.exit(1)
        }
    }

    nonisolated private static func dragProviderCanExposeFilePath(
        _ provider: NSItemProvider,
        expectedPath: String? = nil,
        expectedPathSuffix: String? = nil
    ) throws -> Bool {
        let types = Set(provider.registeredTypeIdentifiers)
        guard types.contains(UTType.fileURL.identifier),
              types.contains(UTType.url.identifier),
              types.contains(legacyFilenamesPasteboardTypeIdentifier) else {
            return false
        }

        let fileURLText = try String(
            decoding: loadData(from: provider, typeIdentifier: UTType.fileURL.identifier),
            as: UTF8.self
        )
        let filenamesData = try loadData(from: provider, typeIdentifier: legacyFilenamesPasteboardTypeIdentifier)
        let filenames = try PropertyListSerialization.propertyList(from: filenamesData, format: nil) as? [String] ?? []
        guard let path = filenames.first else { return false }

        if let expectedPath {
            return fileURLText == URL(fileURLWithPath: expectedPath).absoluteString && path == expectedPath
        }
        if let expectedPathSuffix {
            return fileURLText.hasSuffix(expectedPathSuffix) && path.hasSuffix(expectedPathSuffix)
        }
        return !fileURLText.isEmpty && !path.isEmpty
    }

    nonisolated private static func loadData(from provider: NSItemProvider, typeIdentifier: String) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        let box = DragProviderCheckBox()
        _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
            if let data {
                box.result = .success(data)
            } else {
                box.result = .failure(error ?? NSError(
                    domain: "LapianBao.DragProviderCheck",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "无法读取拖拽类型 \(typeIdentifier)"]
                ))
            }
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + 5) == .success else {
            throw NSError(
                domain: "LapianBao.DragProviderCheck",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "读取拖拽类型超时 \(typeIdentifier)"]
            )
        }
        return try box.result?.get() ?? Data()
    }

    nonisolated private static func jsonEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

nonisolated final class DragProviderCheckBox: @unchecked Sendable {
    var result: Result<Data, Error>?
}
