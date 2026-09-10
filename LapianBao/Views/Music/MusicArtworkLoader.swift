import Foundation

/// Multiple visible rows sharing an album cover share one bounded request.
actor MusicArtworkLoader {
    static let shared = MusicArtworkLoader()
    typealias Fetch = @Sendable (URL) async throws -> Data
    private let fetch: Fetch
    private let retryDelay: TimeInterval
    private var inFlight: [URL: Task<Data?, Never>] = [:]
    private var retryAfter: [URL: Date] = [:]

    init(retryDelay: TimeInterval = 30, fetch: @escaping Fetch = MusicArtworkLoader.fetchData) {
        self.retryDelay = retryDelay
        self.fetch = fetch
    }

    func data(for url: URL) async -> Data? {
        if let task = inFlight[url] { return await task.value }
        if let deadline = retryAfter[url], deadline > Date() { return nil }
        let fetch = self.fetch
        let task = Task<Data?, Never> {
            do { return try await fetch(url) }
            catch { return nil }
        }
        inFlight[url] = task
        let data = await task.value
        inFlight[url] = nil
        if data == nil {
            retryAfter = retryAfter.filter { $0.value > Date() }
            retryAfter[url] = Date().addingTimeInterval(retryDelay)
        } else {
            retryAfter[url] = nil
        }
        return data
    }

    private static func fetchData(_ url: URL) async throws -> Data {
        await MusicArtworkLoadGate.shared.acquire()
        defer { Task { await MusicArtworkLoadGate.shared.release() } }
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode), !data.isEmpty, data.count <= 12 * 1024 * 1024
        else { throw URLError(.badServerResponse) }
        return data
    }
}
