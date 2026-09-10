//
//  LibraryInfrastructureModels.swift
//  LapianBao
//
//  Lightweight infrastructure types shared by store features.
//

import Foundation

// Scene workers need the same pre-start cancellation and child-process cleanup
// as the other bundled workers.
typealias SceneDetectionProcessRegistry = ToolProcessRegistry

actor SceneDetectionGate {
    static let shared = SceneDetectionGate()

    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isRunning {
            isRunning = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard let nextWaiter = waiters.first else {
            isRunning = false
            return
        }

        waiters.removeFirst()
        nextWaiter.resume()
    }
}

nonisolated final class ToolProcessRegistry: ExternalProcessRegistry, @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func set(_ process: Process?) {
        lock.lock()
        self.process = process
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel, let process { ExternalProcessRunner.terminateTree(process) }
    }

    func cancelRunningProcess() {
        lock.lock()
        let process = process
        self.process = nil
        cancelled = true
        lock.unlock()

        if let process { ExternalProcessRunner.terminateTree(process) }
    }
}

nonisolated final class PipeDataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

nonisolated final class PipeLineCollector: @unchecked Sendable {
    private let dataCollector = PipeDataCollector()
    private let lock = NSLock()
    private var pendingData = Data()

    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return appendLocked(data)
    }

    private func appendLocked(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        dataCollector.append(data)
        pendingData.append(data)
        var lines: [String] = []
        // Pipe callbacks can split a UTF-8 character between reads. Decode only
        // complete lines so Chinese text and emoji cannot disappear at a split.
        while let boundary = pendingData.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            lines.append(String(decoding: pendingData[..<boundary], as: UTF8.self))
            pendingData.removeSubrange(...boundary)
        }
        return lines
    }

    func finish(with data: Data = Data()) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        var lines = appendLocked(data)
        if !pendingData.isEmpty {
            lines.append(String(decoding: pendingData, as: UTF8.self))
            pendingData.removeAll(keepingCapacity: true)
        }
        return lines
    }

    var data: Data {
        dataCollector.data
    }
}

actor VideoMetadataQueue {
    private let videos: [VideoItem]
    private var nextIndex = 0

    init(videos: [VideoItem]) {
        self.videos = videos
    }

    func next() -> VideoItem? {
        guard nextIndex < videos.count else { return nil }
        let video = videos[nextIndex]
        nextIndex += 1
        return video
    }
}

nonisolated struct DownloadProgressUpdate: Sendable {
    var progress: Double?
    var speed: String?
    var downloadedBytes: Double? = nil
    var totalBytes: Double? = nil
}

nonisolated struct ProjectDataFile: Codable, Sendable {
    var sampledFrames: [SampledFrame]
    var annotations: [AnnotationItem]
    var audioClips: [AudioClipItem]
    var transcripts: [String: [TranscriptSegment]]
    var transcriptExports: [TranscriptExportItem]?
    var musicsByVideoPath: [String: [MusicRecognitionItem]]?
    var musicDownloadJobs: [MusicDownloadJob]?
}

nonisolated struct LibraryScanProgress: Equatable, Sendable {
    var message: String
    var completed: Int
    var total: Int

    var fraction: Double? {
        guard total > 0 else { return nil }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

nonisolated enum ResourceLibrarySQLite {
    static func write(
        libraryURL: URL,
        music: [LocalMusicAsset],
        audio: [LocalAudioAsset],
        images: [LocalImageAsset] = []
    ) {
        let sqliteURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        guard FileManager.default.isExecutableFile(atPath: sqliteURL.path) else { return }
        let process = Process()
        let inputPipe = Pipe()
        process.executableURL = sqliteURL
        process.arguments = [libraryURL.appendingPathComponent(".lapianbao.sqlite").path]
        process.standardInput = inputPipe
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            let sqlData = sql(libraryURL: libraryURL, music: music, audio: audio, images: images).data(using: .utf8) ?? Data()
            inputPipe.fileHandleForWriting.write(sqlData)
            try? inputPipe.fileHandleForWriting.close()
            process.waitUntilExit()
        } catch {
            try? inputPipe.fileHandleForWriting.close()
        }
    }

    private static func sql(
        libraryURL: URL,
        music: [LocalMusicAsset],
        audio: [LocalAudioAsset],
        images: [LocalImageAsset]
    ) -> String {
        var lines: [String] = [
            "PRAGMA journal_mode=WAL;",
            "CREATE TABLE IF NOT EXISTS assets (kind TEXT NOT NULL, path TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, role TEXT NOT NULL, tags TEXT NOT NULL, file_extension TEXT NOT NULL, file_size INTEGER NOT NULL, modified_at REAL, duration REAL NOT NULL);",
            "BEGIN IMMEDIATE;",
            "DELETE FROM assets WHERE kind IN ('music', 'audio', 'image', '音乐', '音频', '图片');"
        ]
        lines += music.map { item in
            insertSQL(kind: "音乐", path: relativePath(item.filePath, base: libraryURL), title: item.title, role: item.role.rawValue, tags: item.tags, fileExtension: item.fileExtension, fileSize: item.fileSize, modifiedAt: item.modifiedAt, duration: item.duration)
        }
        lines += audio.map { item in
            insertSQL(kind: "音频", path: relativePath(item.filePath, base: libraryURL), title: item.title, role: "soundEffect", tags: item.tags, fileExtension: item.fileExtension, fileSize: item.fileSize, modifiedAt: item.modifiedAt, duration: item.duration)
        }
        lines += images.map { item in
            insertSQL(kind: "图片", path: relativePath(item.filePath, base: libraryURL), title: item.title, role: imageRole(width: item.width, height: item.height), tags: item.tags, fileExtension: item.fileExtension, fileSize: item.fileSize, modifiedAt: item.modifiedAt, duration: 0)
        }
        lines.append("COMMIT;")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func imageRole(width: Int?, height: Int?) -> String {
        guard let width, let height, width > 0, height > 0 else { return "image" }
        return "\(width)x\(height)"
    }

    private static func insertSQL(kind: String, path: String, title: String, role: String, tags: [String], fileExtension: String, fileSize: Int64, modifiedAt: Date?, duration: Double) -> String {
        let tagsJSON = (try? String(data: JSONEncoder().encode(tags), encoding: .utf8)) ?? "[]"
        let modifiedValue = modifiedAt.map { "\($0.timeIntervalSince1970)" } ?? "NULL"
        return "INSERT OR REPLACE INTO assets (kind, path, title, role, tags, file_extension, file_size, modified_at, duration) VALUES (\(quote(kind)), \(quote(path)), \(quote(title)), \(quote(role)), \(quote(tagsJSON)), \(quote(fileExtension)), \(fileSize), \(modifiedValue), \(duration));"
    }

    private static func relativePath(_ path: String, base libraryURL: URL) -> String {
        let base = libraryURL.path.hasSuffix("/") ? libraryURL.path : libraryURL.path + "/"
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }

    private static func quote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}

enum ProjectDataLoadState { case idle, loading, loaded, failed }
