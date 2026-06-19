//
//  LibraryStore+MusicPackaging.swift
//  LapianBao
//
//  Moves music files that are not backed by homepage recognition out of the
//  visible music library.
//

import Foundation

extension LibraryStore {
    nonisolated static func nonRecognizedMusicPackageFolder(in libraryURL: URL) -> URL {
        let libraryName = libraryURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let packageName = libraryName.isEmpty
            ? nonRecognizedMusicPackageFolderName
            : "\(libraryName)-\(nonRecognizedMusicPackageFolderName)"
        return libraryURL
            .deletingLastPathComponent()
            .appendingPathComponent(packageName, isDirectory: true)
    }

    nonisolated static func legacyNonRecognizedMusicPackageFolder(in libraryURL: URL) -> URL {
        mediaFolder(in: libraryURL, named: musicExportFolderName)
            .appendingPathComponent(nonRecognizedMusicPackageFolderName, isDirectory: true)
    }

    func visibleMusicAssetsAfterPackaging(
        _ assets: [LocalMusicAsset],
        libraryURL: URL
    ) -> [LocalMusicAsset] {
        let packageRoot = Self.nonRecognizedMusicPackageFolder(in: libraryURL)
        Self.migrateLegacyNonRecognizedMusicPackageIfNeeded(
            libraryURL: libraryURL,
            packageRoot: packageRoot
        )
        guard !assets.isEmpty else { return assets }

        let recognizedLookup = recognizedMusicDownloadLookup()
        let packageRootPath = packageRoot.standardizedFileURL.path
        let packageRootPrefix = packageRootPath.hasSuffix("/") ? packageRootPath : packageRootPath + "/"
        var visibleAssets: [LocalMusicAsset] = []
        var movedPaths: [String: String] = [:]

        for asset in assets {
            let normalizedPath = Self.normalizedLocalFilePath(asset.filePath)
            if normalizedPath.hasPrefix(packageRootPrefix) {
                continue
            }

            if recognizedLookup.shouldKeep(asset) {
                visibleAssets.append(asset)
                continue
            }

            guard FileManager.default.fileExists(atPath: asset.filePath) else {
                continue
            }

            do {
                let destinationURL = try moveMusicAssetToNonRecognizedPackage(asset, packageRoot: packageRoot)
                movedPaths[asset.filePath] = destinationURL.path
            } catch {
                visibleAssets.append(asset)
            }
        }

        if !movedPaths.isEmpty {
            finishPackagingMovedMusicFiles(movedPaths)
        }

        return visibleAssets
    }

    private func recognizedMusicDownloadLookup() -> RecognizedMusicDownloadLookup {
        let recognizedSongKeys = recognizedHomepageMusicSongKeys()
        let jobs = musicDownloadJobs.filter { job in
            recognizedSongKeys.contains(job.songKey) || Self.isActiveDownloadStatus(job.status)
        }
        return RecognizedMusicDownloadLookup(jobs: jobs, filenameCandidates: { [weak self] job in
            self?.musicDownloadFilenameCandidates(for: job) ?? []
        })
    }

    private func recognizedHomepageMusicSongKeys() -> Set<String> {
        let videoPaths = Set(videos.map(\.url.path))
        var keys = Set<String>()
        for (path, songs) in musicsByVideoPath where videoPaths.contains(path) {
            for song in songs where Self.hasRecognizedTitleAndArtist(song) {
                keys.insert("\(song.title)|\(song.artist)")
            }
        }
        return keys
    }

    private func moveMusicAssetToNonRecognizedPackage(
        _ asset: LocalMusicAsset,
        packageRoot: URL
    ) throws -> URL {
        let sourceURL = URL(fileURLWithPath: asset.filePath)
        try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        let destinationURL = Self.availableMusicPackageURL(
            for: sourceURL,
            packageRoot: packageRoot
        )
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    nonisolated static func availableMusicPackageURL(
        for sourceURL: URL,
        packageRoot: URL
    ) -> URL {
        let fm = FileManager.default
        let directURL = packageRoot.appendingPathComponent(sourceURL.lastPathComponent)
        if !fm.fileExists(atPath: directURL.path) {
            return directURL
        }

        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        var suffix = 2
        while true {
            let filename = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
            let candidate = packageRoot.appendingPathComponent(filename)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    private func finishPackagingMovedMusicFiles(_ movedPaths: [String: String]) {
        for (oldPath, newPath) in movedPaths {
            musicsByVideoPath.removeValue(forKey: oldPath)
            musicDetectionStatusByVideoPath.removeValue(forKey: oldPath)
            localMusicWaveformSamplesByPath.removeValue(forKey: oldPath)
            localMusicWaveformTasks[oldPath]?.cancel()
            localMusicWaveformTasks[oldPath] = nil
            knownLocalResourcePaths.remove(oldPath)

            let normalizedOldPath = Self.normalizedLocalFilePath(oldPath)
            for index in musicDownloadJobs.indices {
                guard let filePath = musicDownloadJobs[index].filePath,
                      Self.normalizedLocalFilePath(filePath) == normalizedOldPath
                else { continue }
                musicDownloadJobs[index].filePath = newPath
            }
        }
        saveProjectData()
    }

    nonisolated static func migrateLegacyNonRecognizedMusicPackageIfNeeded(
        libraryURL: URL,
        packageRoot: URL
    ) {
        let legacyRoot = legacyNonRecognizedMusicPackageFolder(in: libraryURL)
        guard legacyRoot.standardizedFileURL.path != packageRoot.standardizedFileURL.path,
              directoryExists(legacyRoot)
        else { return }

        let fm = FileManager.default
        try? fm.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        let urls = fm.enumerator(
            at: legacyRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )?.compactMap { $0 as? URL } ?? []

        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let destinationURL = availableMusicPackageURL(for: url, packageRoot: packageRoot)
            try? fm.moveItem(at: url, to: destinationURL)
        }

        removeEmptyDirectories(under: legacyRoot, preserving: [])
        try? fm.removeItem(at: legacyRoot)
    }
}

private struct RecognizedMusicDownloadLookup {
    var jobs: [MusicDownloadJob]
    var filenameCandidates: (MusicDownloadJob) -> [String]

    func shouldKeep(_ asset: LocalMusicAsset) -> Bool {
        let normalizedPath = LibraryStore.normalizedLocalFilePath(asset.filePath)
        let filename = URL(fileURLWithPath: asset.filePath).lastPathComponent
        return jobs.contains { job in
            if let filePath = job.filePath,
               LibraryStore.normalizedLocalFilePath(filePath) == normalizedPath {
                return true
            }
            return filenameCandidates(job).contains(filename)
        }
    }
}
