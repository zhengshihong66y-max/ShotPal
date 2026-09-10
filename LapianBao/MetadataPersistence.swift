import Foundation

extension ProjectRepository {
    private final class MetadataState: @unchecked Sendable {
        let lock = NSLock()
        var pending: [URL: PendingMetadata] = [:]
        var readFailures: Set<URL> = []
        var errors: [URL: String] = [:]
    }

    private struct PendingMetadata {
        var data: Data
        var commit: (Bool) throws -> Void
    }

    private static let metadataState = MetadataState()

    private static func metadataDiskValue<Value: Codable>(
        _ type: Value.Type, at url: URL
    ) throws -> [String: Value]? {
        do {
            return try JSONDecoder().decode([String: Value].self, from: Data(contentsOf: url))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    /// Failed writes remain the authoritative in-memory snapshot until retry.
    /// An unreadable disk file is never replaced by an empty/default snapshot.
    static func readMetadata<Value: Codable>(_ type: Value.Type, from rawURL: URL) -> [String: Value]? {
        let url = rawURL.standardizedFileURL
        let state = metadataState
        state.lock.lock()
        defer { state.lock.unlock(); AppEventBus.metadataPersistenceChanged() }
        if let pending = state.pending[url] {
            return try? JSONDecoder().decode([String: Value].self, from: pending.data)
        }
        do {
            let value = try metadataDiskValue(type, at: url)
            state.readFailures.remove(url)
            state.errors[url] = nil
            return value
        } catch {
            state.readFailures.insert(url)
            state.errors[url] = url.lastPathComponent + ": " + error.localizedDescription
            return nil
        }
    }

    @discardableResult
    static func writeMetadata<Value: Codable>(
        _ value: [String: Value], to rawURL: URL,
        recoverValue: @escaping (Value, Value) -> Value = { recovered, _ in recovered }
    ) -> Bool {
        let url = rawURL.standardizedFileURL
        let state = metadataState
        state.lock.lock()
        defer { state.lock.unlock(); AppEventBus.metadataPersistenceChanged() }
        guard !Task.isCancelled else { return false }
        do {
            let data = try prettySortedEncoder.encode(value)
            state.pending[url] = PendingMetadata(data: data, commit: { mergeRecoveredFile in
                // Validate the actual file again immediately before replacement.
                // If the initial load failed, retain unrelated recovered entries.
                let disk = try metadataDiskValue(Value.self, at: url)
                var restored = value
                if mergeRecoveredFile, var existing = disk {
                    existing.merge(value, uniquingKeysWith: recoverValue)
                    restored = existing
                }
                try prettySortedEncoder.encode(restored).write(to: url, options: .atomic)
            })
            return commitMetadata(at: url)
        } catch {
            state.errors[url] = url.lastPathComponent + ": " + error.localizedDescription
            return false
        }
    }

    /// Caller holds metadataState.lock. Keeps the latest snapshot after failure.
    private static func commitMetadata(at url: URL) -> Bool {
        let state = metadataState
        guard let pending = state.pending[url] else { return true }
        do {
            try pending.commit(state.readFailures.contains(url))
            state.pending[url] = nil
            state.errors[url] = nil
            state.readFailures.remove(url)
            return true
        } catch {
            if error is DecodingError { state.readFailures.insert(url) }
            state.errors[url] = url.lastPathComponent + ": " + error.localizedDescription
            return false
        }
    }

    static func mergeRecoveredTags(_ recovered: [String], _ pending: [String]) -> [String] {
        var seen = Set(recovered)
        return recovered + pending.filter { seen.insert($0).inserted }
    }

    static func retryMetadata(in libraryURL: URL) -> Bool {
        let directory = libraryURL.standardizedFileURL.path
        let state = metadataState
        state.lock.lock()
        defer { state.lock.unlock(); AppEventBus.metadataPersistenceChanged() }
        let urls = state.pending.keys.filter { $0.deletingLastPathComponent().path == directory }
        var succeeded = true
        for url in urls { if !commitMetadata(at: url) { succeeded = false } }
        return succeeded
    }

    static func metadataFailure(in libraryURL: URL) -> String? {
        let directory = libraryURL.standardizedFileURL.path
        let state = metadataState
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.errors.keys.sorted { $0.path < $1.path }
            .first { $0.deletingLastPathComponent().path == directory }
            .flatMap { state.errors[$0] }
    }
}
