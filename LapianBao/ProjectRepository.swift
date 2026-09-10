//
//  ProjectRepository.swift
//  LapianBao
//
//  Centralizes project-owned hidden files and JSON persistence helpers.
//

import Foundation

nonisolated enum ProjectRepository {
    // Serialize commits, including the synchronous quit/switch flush. A cancelled
    // background snapshot must check cancellation after acquiring this lock.
    private static let writeLock = NSLock()

    enum FileName {
        static let projectData = ".lapianbao_project.json"
        static let videoTags = ".lapianbaotags.json"
        static let sourceInfo = ".lapianbao_sources.json"
        static let sceneCuts = ".lapianbao_scene_cuts.json"
        static let localWaveforms = ".lapianbao_waveforms.json"
        static let videoCache = ".lapianbao_videos_cache.json"
        static let resourceCache = ".lapianbao_resource_cache.json"
        static let musicWorkspaceCache = ".lapianbao_music_workspace_cache.json"
        static let resourceAssetTags = ".lapianbao_asset_tags.json"
    }

    static func url(in libraryURL: URL, fileName: String) -> URL {
        libraryURL.appendingPathComponent(fileName)
    }

    static func projectDataURL(in libraryURL: URL) -> URL {
        url(in: libraryURL, fileName: FileName.projectData)
    }

    static func videoTagsURL(in libraryURL: URL) -> URL {
        url(in: libraryURL, fileName: FileName.videoTags)
    }

    static func sourceInfoURL(in libraryURL: URL) -> URL {
        url(in: libraryURL, fileName: FileName.sourceInfo)
    }

    static func sceneCutsURL(in libraryURL: URL) -> URL {
        url(in: libraryURL, fileName: FileName.sceneCuts)
    }

    static func localWaveformsURL(in libraryURL: URL) -> URL {
        url(in: libraryURL, fileName: FileName.localWaveforms)
    }

    static func videoCacheURL(in libraryURL: URL) -> URL {
        url(in: libraryURL, fileName: FileName.videoCache)
    }

    static func resourceCacheURL(in libraryURL: URL) -> URL {
        url(in: libraryURL, fileName: FileName.resourceCache)
    }

    static func musicWorkspaceCacheURL(in libraryURL: URL) -> URL {
        url(in: libraryURL, fileName: FileName.musicWorkspaceCache)
    }

    static func resourceAssetTagsURL(in libraryURL: URL) -> URL {
        url(in: libraryURL, fileName: FileName.resourceAssetTags)
    }

    static func relativePath(for path: String, base libraryURL: URL) -> String {
        let base = libraryURL.path.hasSuffix("/") ? libraryURL.path : libraryURL.path + "/"
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }

    static func makeEncoder(
        outputFormatting: JSONEncoder.OutputFormatting = [],
        dateEncodingStrategy: JSONEncoder.DateEncodingStrategy? = nil
    ) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = outputFormatting
        if let dateEncodingStrategy {
            encoder.dateEncodingStrategy = dateEncodingStrategy
        }
        return encoder
    }

    static func makeDecoder(
        dateDecodingStrategy: JSONDecoder.DateDecodingStrategy? = nil
    ) -> JSONDecoder {
        let decoder = JSONDecoder()
        if let dateDecodingStrategy {
            decoder.dateDecodingStrategy = dateDecodingStrategy
        }
        return decoder
    }

    static var prettySortedEncoder: JSONEncoder {
        makeEncoder(outputFormatting: [.prettyPrinted, .sortedKeys])
    }

    static func readJSON<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        decoder: JSONDecoder = JSONDecoder()
    ) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    static func writeJSON<T: Encodable>(
        _ value: T,
        to url: URL,
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        let data = try encoder.encode(value)
        writeLock.lock()
        defer { writeLock.unlock() }
        try Task.checkCancellation()
        try data.write(to: url, options: .atomic)
    }

    static func readProjectDataResult(from url: URL) -> Result<ProjectDataFile?, Error> {
        do {
            let data = try Data(contentsOf: url)
            return .success(try makeDecoder(dateDecodingStrategy: .iso8601).decode(ProjectDataFile.self, from: data))
        } catch CocoaError.fileReadNoSuchFile {
            return .success(nil)
        } catch {
            return .failure(error)
        }
    }

    static func readProjectData(from url: URL) -> ProjectDataFile? {
        readJSON(ProjectDataFile.self, from: url, decoder: makeDecoder(dateDecodingStrategy: .iso8601))
    }

    static func writeProjectData(_ dataFile: ProjectDataFile, to url: URL) throws {
        try writeJSON(
            dataFile,
            to: url,
            encoder: makeEncoder(
                outputFormatting: [.prettyPrinted, .sortedKeys],
                dateEncodingStrategy: .iso8601
            )
        )
    }

    static func readJSONObject(at url: URL) -> [String: Any] {
        guard
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else { return [:] }
        return dictionary
    }

    static func writeJSONObject(_ object: [String: Any], to url: URL) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else { return }
        writeLock.lock()
        defer { writeLock.unlock() }
        guard !Task.isCancelled else { return }
        try? data.write(to: url, options: .atomic)
    }
}
