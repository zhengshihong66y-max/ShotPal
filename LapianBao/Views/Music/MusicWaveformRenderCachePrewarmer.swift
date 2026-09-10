//
//  MusicWaveformRenderCachePrewarmer.swift
//  LapianBao
//
//  Command-line utility for fully materializing music waveform caches.
//

import AppKit
import Foundation

nonisolated enum MusicWaveformRenderCachePrewarmer {
    struct Report: Codable, Sendable {
        var libraryPath: String
        var musicAssetCount: Int
        var projectWaveformSampleSetCount: Int
        var existingSampleCount: Int
        var generatedSampleCount: Int
        var failedSampleCount: Int
        var renderRequestCount: Int
        var renderSkippedExistingCount: Int
        var renderGeneratedCount: Int
        var renderFailedCount: Int
        var cacheDirectory: String?
        var cacheFileCountBefore: Int
        var cacheFileCountAfter: Int
        var prewarmSizes: [String]
        var prewarmScales: [Double]
        var failedSamplePaths: [String]
    }

    private struct PrewarmFailure: Error, LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    static let flag = "--lapianbao-prewarm-music-waveform-cache"

    static func shouldRun(arguments: [String]) -> Bool {
        arguments.contains(flag)
    }

    static func runAndPrintReport(arguments: [String]) async -> Int32 {
        do {
            let report = try await run(arguments: arguments)
            printJSON(report)
            return report.failedSampleCount == 0 && report.renderFailedCount == 0 ? 0 : 1
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            let payload = [
                "status": "failed",
                "error": message
            ]
            printJSONObject(payload)
            return 1
        }
    }

    static func run(arguments: [String]) async throws -> Report {
        guard let libraryURL = libraryURL(from: arguments) else {
            throw PrewarmFailure(message: L10n.text("未找到素材库路径"))
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: libraryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw PrewarmFailure(message: L10n.text("素材库路径不存在：\(libraryURL.path)"))
        }

        let snapshot = LibraryStore.quickResourceLibrarySnapshot(in: libraryURL)
        let musicAssets = snapshot.music.filter {
            FileManager.default.fileExists(atPath: $0.filePath)
        }
        var waveformCache = LibraryStore.loadLocalWaveformCache(in: libraryURL)
        var cacheChanged = false
        var existingSampleCount = 0
        var generatedSampleCount = 0
        var failedSampleCount = 0
        var failedSamplePaths: [String] = []
        var sampleSets: [[Double]] = []
        var sampleKeys = Set<String>()
        let sampleCount = LibraryStore.localMusicWaveformSampleCount
        let cacheByIdentity = LibraryStore.localWaveformIdentityCacheIndex(waveformCache)

        func appendSampleSet(_ samples: [Double]) {
            guard !samples.isEmpty else { return }
            let key = "\(samples.count)|\(DownloadedMusicWaveformRenderCache.sampleSignature(samples))"
            guard sampleKeys.insert(key).inserted else { return }
            sampleSets.append(samples)
        }

        for asset in musicAssets {
            let assetURL = URL(fileURLWithPath: asset.filePath)
            let relativePath = LibraryStore.libraryRelativePath(for: assetURL, base: libraryURL)
            let key = LibraryStore.localWaveformCacheKey(kind: "music", relativePath: relativePath)
            let fileIdentity = LibraryStore.localWaveformFileIdentity(for: assetURL)

            if let entry = LibraryStore.matchLocalWaveformCacheEntry(
                entriesByKey: waveformCache,
                entriesByIdentity: cacheByIdentity,
                kind: "music",
                relativePath: relativePath,
                fileIdentity: fileIdentity,
                fileSize: asset.fileSize,
                modifiedAt: asset.modifiedAt,
                sampleCount: sampleCount
            ) {
                if waveformCache[key] != entry {
                    cacheChanged = true
                }
                waveformCache[key] = entry
                existingSampleCount += 1
                appendSampleSet(entry.samples)
                continue
            }

            guard let generatedSamples = await LibraryStore.makeWaveformSamples(
                for: assetURL,
                sampleCount: sampleCount
            ), generatedSamples.count == sampleCount else {
                failedSampleCount += 1
                failedSamplePaths.append(asset.filePath)
                continue
            }

            waveformCache[key] = LibraryStore.LocalWaveformCacheEntry(
                kind: "music",
                relativePath: relativePath,
                fileIdentity: fileIdentity,
                fileSize: asset.fileSize,
                modificationTime: LibraryStore.localWaveformModificationTime(asset.modifiedAt),
                sampleCount: sampleCount,
                samples: generatedSamples
            )
            cacheChanged = true
            generatedSampleCount += 1
            appendSampleSet(generatedSamples)
        }

        let projectWaveformSampleSetCount = appendProjectMusicWaveformSamples(
            libraryURL: libraryURL,
            append: appendSampleSet
        )

        if cacheChanged {
            LibraryStore.saveLocalWaveformCache(waveformCache, in: libraryURL)
        }

        let renderCache = DownloadedMusicWaveformRenderCache.shared
        let cacheFileCountBefore = renderCache.diskImageFileCount()
        var diskSummary = DownloadedMusicWaveformDiskPrewarmSummary()
        let sizes = DownloadedMusicWaveformRenderCache.defaultPrewarmDisplaySizes
        let scales = DownloadedMusicWaveformRenderCache.defaultPrewarmScales

        for samples in sampleSets {
            for size in sizes {
                for scale in scales {
                    let summary = renderCache.ensureDiskImages(
                        samples: samples,
                        displaySize: size,
                        scale: scale,
                        isCompact: false
                    )
                    diskSummary.requested += summary.requested
                    diskSummary.skippedExisting += summary.skippedExisting
                    diskSummary.rendered += summary.rendered
                    diskSummary.failed += summary.failed
                }
            }
        }

        return Report(
            libraryPath: libraryURL.path,
            musicAssetCount: musicAssets.count,
            projectWaveformSampleSetCount: projectWaveformSampleSetCount,
            existingSampleCount: existingSampleCount,
            generatedSampleCount: generatedSampleCount,
            failedSampleCount: failedSampleCount,
            renderRequestCount: diskSummary.requested,
            renderSkippedExistingCount: diskSummary.skippedExisting,
            renderGeneratedCount: diskSummary.rendered,
            renderFailedCount: diskSummary.failed,
            cacheDirectory: renderCache.diskCacheURL?.path,
            cacheFileCountBefore: cacheFileCountBefore,
            cacheFileCountAfter: renderCache.diskImageFileCount(),
            prewarmSizes: sizes.map { "\(Int($0.width))x\(Int($0.height))" },
            prewarmScales: scales.map(Double.init),
            failedSamplePaths: Array(failedSamplePaths.prefix(20))
        )
    }

    private static func libraryURL(from arguments: [String]) -> URL? {
        if let value = value(after: flag, in: arguments), !value.hasPrefix("--") {
            return URL(fileURLWithPath: value).standardizedFileURL
        }

        if let libraryArgument = arguments.first(where: { $0.hasPrefix("--library=") }) {
            let value = String(libraryArgument.dropFirst("--library=".count))
            if !value.isEmpty {
                return URL(fileURLWithPath: value).standardizedFileURL
            }
        }

        if let path = AppSettings.lastLibraryPath {
            return URL(fileURLWithPath: path).standardizedFileURL
        }

        return nil
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }

    private static func appendProjectMusicWaveformSamples(
        libraryURL: URL,
        append: ([Double]) -> Void
    ) -> Int {
        guard let dataFile = ProjectRepository.readProjectData(
            from: ProjectRepository.projectDataURL(in: libraryURL)
        ) else { return 0 }

        var count = 0
        for job in dataFile.musicDownloadJobs ?? [] {
            guard let samples = job.waveformSamples, !samples.isEmpty else { continue }
            if let path = job.filePath {
                let resolvedPath = LibraryStore.projectAbsolutePath(path, libraryURL: libraryURL)
                guard FileManager.default.fileExists(atPath: resolvedPath) else { continue }
            }
            append(samples)
            count += 1
        }
        return count
    }

    private static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private static func printJSONObject(_ object: [String: String]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys]
              )
        else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
