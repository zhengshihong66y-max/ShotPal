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
        libraryURL _: URL
    ) -> [LocalMusicAsset] {
        var visibleAssets: [LocalMusicAsset] = []
        var visiblePaths = Set<String>()
        for asset in assets {
            guard FileManager.default.fileExists(atPath: asset.filePath) else { continue }
            if visiblePaths.insert(asset.filePath).inserted {
                visibleAssets.append(asset)
            }
        }

        return visibleAssets
    }

    private func recognizedMusicDownloadLookup() -> RecognizedMusicDownloadLookup {
        let jobs = musicDownloadJobs.filter { job in
            if Self.isActiveDownloadStatus(job.status) { return true }
            if case .succeeded = job.status { return true }
            return job.filePath.map { FileManager.default.fileExists(atPath: $0) } ?? false
        }
        return RecognizedMusicDownloadLookup(jobs: jobs, filenameCandidates: { [weak self] job in
            self?.musicDownloadFilenameCandidates(for: job) ?? []
        })
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
        for (oldPath, _) in movedPaths {
            musicsByVideoPath.removeValue(forKey: oldPath)
            musicDetectionStatusByVideoPath.removeValue(forKey: oldPath)
            localMusicWaveformSamplesByPath.removeValue(forKey: oldPath)
            localMusicWaveformTasks[oldPath]?.cancel()
            localMusicWaveformTasks[oldPath] = nil
            localMusicWaveformRenderingPaths.remove(oldPath)
            localMusicWaveformQueuedPaths.remove(oldPath)
            queuedLocalMusicWaveformAssets.removeAll { $0.filePath == oldPath }
            localMusicWaveformProgressByPath.removeValue(forKey: oldPath)
            knownLocalResourcePaths.remove(oldPath)
            let normalizedOldPath = Self.normalizedLocalFilePath(oldPath)
            musicFileDurationsByPath.removeValue(forKey: normalizedOldPath)
            musicFileDurationTasks.cancel(normalizedOldPath)
        }
        saveProjectData()
    }

    @discardableResult
    private func restorePackagedMusicDownloadsIfNeeded(
        libraryURL: URL,
        packageRoot: URL
    ) -> [LocalMusicAsset] {
        let packageRootPath = packageRoot.standardizedFileURL.path
        let packageRootPrefix = packageRootPath.hasSuffix("/") ? packageRootPath : packageRootPath + "/"
        let musicRoot = Self.mediaFolder(in: libraryURL, named: Self.musicExportFolderName)
        let packageFileLookup = Self.musicPackageFileLookup(in: packageRoot)
        var restoredAssets: [LocalMusicAsset] = []
        var movedPaths: [String: String] = [:]

        for index in musicDownloadJobs.indices {
            let sourceURL: URL?
            if let filePath = musicDownloadJobs[index].filePath,
               Self.normalizedLocalFilePath(filePath).hasPrefix(packageRootPrefix),
               FileManager.default.fileExists(atPath: filePath) {
                sourceURL = URL(fileURLWithPath: filePath)
            } else {
                sourceURL = packagedMusicDownloadURL(
                    for: musicDownloadJobs[index],
                    packageFileLookup: packageFileLookup
                )
            }
            guard let sourceURL else { continue }

            do {
                try FileManager.default.createDirectory(at: musicRoot, withIntermediateDirectories: true)
                let destinationURL = Self.availableMusicPackageURL(for: sourceURL, packageRoot: musicRoot)
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                musicDownloadJobs[index].filePath = destinationURL.path
                musicDownloadJobs[index].status = .succeeded(destinationURL.lastPathComponent)
                musicDownloadJobs[index].downloadProgress = 1
                movedPaths[sourceURL.path] = destinationURL.path
                restoredAssets.append(restoredMusicAsset(for: musicDownloadJobs[index], fileURL: destinationURL))
            } catch {
                continue
            }
        }

        guard !movedPaths.isEmpty else { return restoredAssets }
        Self.removeEmptyDirectories(under: packageRoot, preserving: [])
        updateMovedMusicMetadataPaths(movedPaths)
        saveProjectData()
        return restoredAssets
    }

    private func packagedMusicDownloadURL(
        for job: MusicDownloadJob,
        packageFileLookup: MusicPackageFileLookup
    ) -> URL? {
        for candidate in musicDownloadFilenameCandidates(for: job) {
            if let url = packageFileLookup.urlByFilename[candidate] {
                return url
            }

            let stem = URL(fileURLWithPath: candidate).deletingPathExtension().lastPathComponent
            guard !stem.isEmpty else { continue }
            if let url = packageFileLookup.urlByStem[stem] {
                return url
            }
        }
        return nil
    }

    private func restoredMusicAsset(for job: MusicDownloadJob, fileURL: URL) -> LocalMusicAsset {
        let values = try? fileURL.resourceValues(forKeys: [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey
        ])
        let song = Self.musicRecognitionItem(fromSongKey: job.songKey, tags: [])
        let filenameTitle = fileURL.deletingPathExtension().lastPathComponent
        let title = song?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.flatMap { $0.isEmpty ? nil : $0 } ?? filenameTitle
        let tags = MusicRecognitionItem.cleanedMusicTags(
            song?.displayTags ?? [],
            title: song?.title ?? displayTitle,
            artist: song?.artist ?? ""
        )
        let normalizedPath = Self.normalizedLocalFilePath(fileURL.path)
        return LocalMusicAsset(
            filePath: fileURL.path,
            title: displayTitle,
            fileExtension: fileURL.pathExtension.lowercased(),
            role: Self.localMusicRole(for: job.type),
            tags: tags,
            duration: musicFileDurationsByPath[normalizedPath] ?? 0,
            fileSize: Int64(values?.fileSize ?? 0),
            createdAt: values?.creationDate ?? job.createdAt,
            modifiedAt: values?.contentModificationDate,
            recognizedSong: song
        )
    }

    private func updateMusicDownloadJobPaths(_ movedPaths: [String: String]) {
        guard !movedPaths.isEmpty else { return }
        var didChange = false
        let normalizedMovedPaths = Dictionary(uniqueKeysWithValues: movedPaths.map {
            (Self.normalizedLocalFilePath($0.key), $0.value)
        })
        for index in musicDownloadJobs.indices {
            guard let filePath = musicDownloadJobs[index].filePath,
                  let newPath = normalizedMovedPaths[Self.normalizedLocalFilePath(filePath)]
            else { continue }
            musicDownloadJobs[index].filePath = newPath
            didChange = true
        }
        if didChange {
            updateMovedMusicMetadataPaths(movedPaths)
            saveProjectData()
        }
    }

    private func updateMovedMusicMetadataPaths(_ movedPaths: [String: String]) {
        for (oldPath, newPath) in movedPaths {
            if let songs = musicsByVideoPath.removeValue(forKey: oldPath) {
                musicsByVideoPath[newPath] = songs
            }
            if let status = musicDetectionStatusByVideoPath.removeValue(forKey: oldPath) {
                musicDetectionStatusByVideoPath[newPath] = status
            }
            if let samples = localMusicWaveformSamplesByPath.removeValue(forKey: oldPath) {
                localMusicWaveformSamplesByPath[newPath] = samples
            }
            localMusicWaveformTasks[oldPath]?.cancel()
            localMusicWaveformTasks[oldPath] = nil
            localMusicWaveformRenderingPaths.remove(oldPath)
            localMusicWaveformQueuedPaths.remove(oldPath)
            queuedLocalMusicWaveformAssets.removeAll { $0.filePath == oldPath }
            localMusicWaveformProgressByPath.removeValue(forKey: oldPath)
            knownLocalResourcePaths.remove(oldPath)
            knownLocalResourcePaths.insert(newPath)

            let oldKey = Self.normalizedLocalFilePath(oldPath)
            let newKey = Self.normalizedLocalFilePath(newPath)
            if let duration = musicFileDurationsByPath.removeValue(forKey: oldKey) {
                musicFileDurationsByPath[newKey] = duration
            }
            musicFileDurationTasks.cancel(oldKey)
        }
    }

    nonisolated static func migrateLegacyNonRecognizedMusicPackageIfNeeded(
        libraryURL: URL,
        packageRoot: URL
    ) -> [String: String] {
        let legacyRoot = legacyNonRecognizedMusicPackageFolder(in: libraryURL)
        guard legacyRoot.standardizedFileURL.path != packageRoot.standardizedFileURL.path,
              directoryExists(legacyRoot)
        else { return [:] }

        let fm = FileManager.default
        try? fm.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        let urls = fm.enumerator(
            at: legacyRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )?.compactMap { $0 as? URL } ?? []
        var movedPaths: [String: String] = [:]

        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let destinationURL = availableMusicPackageURL(for: url, packageRoot: packageRoot)
            do {
                try fm.moveItem(at: url, to: destinationURL)
                movedPaths[url.path] = destinationURL.path
            } catch {
                continue
            }
        }

        removeEmptyDirectories(under: legacyRoot, preserving: [])
        try? fm.removeItem(at: legacyRoot)
        return movedPaths
    }

    static func musicPackageFileLookup(in packageRoot: URL) -> MusicPackageFileLookup {
        let fm = FileManager.default
        guard directoryExists(packageRoot) else { return MusicPackageFileLookup() }
        let urls = fm.enumerator(
            at: packageRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )?.compactMap { $0 as? URL } ?? []

        var lookup = MusicPackageFileLookup()
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            lookup.urlByFilename[url.lastPathComponent] = lookup.urlByFilename[url.lastPathComponent] ?? url
            let stem = url.deletingPathExtension().lastPathComponent
            if !stem.isEmpty {
                lookup.urlByStem[stem] = lookup.urlByStem[stem] ?? url
            }
        }
        return lookup
    }
}

struct MusicPackageFileLookup: Sendable {
    var urlByFilename: [String: URL] = [:]
    var urlByStem: [String: URL] = [:]
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
