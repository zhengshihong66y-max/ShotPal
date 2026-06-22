//
//  LibraryStore+LocalTools.swift
//  LapianBao
//
//  Resolves optional command-line helper tools without leaking release build source paths.
//

import Foundation

extension LibraryStore {
#if DEBUG
    nonisolated private static var defaultLocalToolSourceFilePath: String { #filePath }
#else
    nonisolated private static var defaultLocalToolSourceFilePath: String { "" }
#endif

    nonisolated static func localToolURL(
        relativePath: String,
        fallbackPath: String? = nil,
        mustBeExecutable: Bool = false,
        sourceFilePath: String = defaultLocalToolSourceFilePath
    ) -> URL? {
        let fm = FileManager.default
        var candidates = [URL]()
        if let fallbackPath, !fallbackPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(URL(fileURLWithPath: fallbackPath))
        }
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(contentsOf: bundledRuntimeToolCandidates(relativePath: relativePath, resourceURL: resourceURL))
            candidates.append(contentsOf: toolCandidates(relativePath: relativePath, from: resourceURL, limit: 8))
        }
        if !sourceFilePath.isEmpty {
            let sourceDirectory = URL(fileURLWithPath: sourceFilePath).deletingLastPathComponent()
            candidates.append(contentsOf: sourceRuntimeToolCandidates(relativePath: relativePath, from: sourceDirectory, limit: 6))
            candidates.append(contentsOf: toolCandidates(relativePath: relativePath, from: sourceDirectory, limit: 6))
        }
        let currentDirectory = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        candidates.append(contentsOf: sourceRuntimeToolCandidates(relativePath: relativePath, from: currentDirectory, limit: 8))
        candidates.append(contentsOf: toolCandidates(relativePath: relativePath, from: currentDirectory, limit: 8))

        var checkedPaths = Set<String>()
        for url in candidates where checkedPaths.insert(url.path).inserted {
            if mustBeExecutable {
                if fm.isExecutableFile(atPath: url.path) { return url }
            } else if fm.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    nonisolated static func localFFmpegDirectoryPath() -> String? {
        localFFmpegURL()?.deletingLastPathComponent().path
    }

    nonisolated static func localFFmpegURL() -> URL? {
        localExecutableToolURL(
            named: "ffmpeg",
            fallbackPaths: [
                "/opt/homebrew/bin/ffmpeg",
                "/usr/local/bin/ffmpeg",
                "/usr/bin/ffmpeg"
            ]
        )
    }

    nonisolated static func localFFprobeURL() -> URL? {
        localExecutableToolURL(
            named: "ffprobe",
            fallbackPaths: [
                "/opt/homebrew/bin/ffprobe",
                "/usr/local/bin/ffprobe",
                "/usr/bin/ffprobe"
            ]
        )
    }

    nonisolated private static func toolCandidates(relativePath: String, from root: URL, limit: Int) -> [URL] {
        var candidates = [URL]()
        var ancestor = root
        for _ in 0..<limit {
            candidates.append(ancestor.appendingPathComponent(relativePath))
            ancestor.deleteLastPathComponent()
        }
        return candidates
    }

    nonisolated private static func bundledRuntimeToolCandidates(relativePath: String, resourceURL: URL) -> [URL] {
        [
            resourceURL
                .appendingPathComponent("RuntimeTools.bundle", isDirectory: true)
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(relativePath)
        ]
    }

    nonisolated private static func sourceRuntimeToolCandidates(relativePath: String, from root: URL, limit: Int) -> [URL] {
        var candidates = [URL]()
        var ancestor = root
        for _ in 0..<limit {
            candidates.append(
                ancestor
                    .appendingPathComponent("LapianBao", isDirectory: true)
                    .appendingPathComponent("RuntimeTools.bundle", isDirectory: true)
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(relativePath)
            )
            ancestor.deleteLastPathComponent()
        }
        return candidates
    }

    nonisolated private static func localExecutableToolURL(
        named executableName: String,
        fallbackPaths: [String]
    ) -> URL? {
        if let bundledURL = localToolURL(
            relativePath: "Tools/bin/\(executableName)",
            mustBeExecutable: true
        ) {
            return bundledURL
        }
        return fallbackPaths
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map(URL.init(fileURLWithPath:))
    }
}
