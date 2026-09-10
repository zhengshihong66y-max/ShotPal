import AppKit
import Foundation

nonisolated struct MusicArtworkRequest: Hashable, Sendable {
    let url: URL?
    let title: String
    let artist: String
    let shouldLoad: Bool
    let allowsFallbackLookup: Bool

    init(urlString: String, title: String, artist: String, shouldLoad: Bool, allowsFallbackLookup: Bool) {
        url = normalizedMusicArtworkURL(urlString)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        self.shouldLoad = shouldLoad
        self.allowsFallbackLookup = allowsFallbackLookup
    }

    var songIdentity: String {
        let parts = [normalizedSearch(title), normalizedSearch(artist)]
        return parts.allSatisfy(\.isEmpty) ? "url|\(url?.absoluteString ?? "")" : parts.joined(separator: "|")
    }
}

@MainActor
struct MusicArtworkDisplayState {
    private var identity: String?
    private var image: NSImage?
    private var generation: UInt64 = 0

    mutating func begin(_ request: MusicArtworkRequest) -> UInt64 {
        if identity != request.songIdentity { image = nil }
        identity = request.songIdentity
        generation &+= 1
        return generation
    }

    func visibleImage(for request: MusicArtworkRequest) -> NSImage? {
        identity == request.songIdentity ? image : nil
    }

    @discardableResult
    mutating func accept(_ image: NSImage, for request: MusicArtworkRequest, generation expected: UInt64) -> Bool {
        guard generation == expected, identity == request.songIdentity else { return false }
        self.image = image
        return true
    }
}

nonisolated enum MusicArtworkSelection {
    static func preferredURL(_ candidates: [String]) -> String {
        candidates.lazy.compactMap(normalizedMusicArtworkURL).first?.absoluteString ?? ""
    }

    static func fallbackURL(in results: [AppleMusicSearchResult], title: String, artist: String) -> URL? {
        let titleKey = normalizedSearch(title)
        let artistKey = normalizedSearch(artist)
        guard !titleKey.isEmpty, !artistKey.isEmpty else { return nil }
        // A vaguely related search hit is not evidence that its cover belongs to this song.
        return results.lazy.filter {
            normalizedSearch($0.title) == titleKey && normalizedSearch($0.artist) == artistKey
        }.compactMap { normalizedMusicArtworkURL($0.artworkURL) }.first
    }
}

nonisolated func normalizedMusicArtworkURL(_ rawURLString: String) -> URL? {
    var text = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    if text.hasPrefix("//") { text = "https:" + text }
    guard var components = URLComponents(string: text),
          let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
          let host = components.host, !host.isEmpty,
          components.user == nil, components.password == nil else { return nil }
    components.scheme = "https"
    if host.lowercased() == "mzstatic.com" || host.lowercased().hasSuffix(".mzstatic.com") {
        components.path = components.path.replacingOccurrences(
            of: #"(\d+)x(\d+)bb(\.[A-Za-z0-9]+)$"#, with: "512x512bb$3", options: .regularExpression
        )
    }
    return components.url
}
