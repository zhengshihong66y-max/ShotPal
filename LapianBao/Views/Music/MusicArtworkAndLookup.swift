//
//  MusicArtworkAndLookup.swift
//  LapianBao
//
//  Split from AudioMusicComponents.swift.
//

import SwiftUI
import AppKit
import Foundation

enum MusicArtworkCache {
    static let shared: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 256
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()
}

actor MusicArtworkLoadGate {
    static let shared = MusicArtworkLoadGate()

    private let limit = 6
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if activeCount < limit {
            activeCount += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard let nextWaiter = waiters.first else {
            activeCount = max(0, activeCount - 1)
            return
        }

        waiters.removeFirst()
        nextWaiter.resume()
    }
}

actor MusicArtworkFallbackResolver {
    static let shared = MusicArtworkFallbackResolver()

    private var cachedURLs: [String: URL?] = [:]

    func artworkURL(title rawTitle: String, artist rawArtist: String) async -> URL? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = rawArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = [normalizedSearch(artist), normalizedSearch(title)].joined(separator: "|")
        guard key != "|" else { return nil }

        if cachedURLs.keys.contains(key) {
            return cachedURLs[key] ?? nil
        }

        let query = [artist, title]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else {
            cachedURLs[key] = nil
            return nil
        }

        do {
            let results = try await LibraryStore.searchAppleMusic(query: query)
            let url = bestArtworkURL(in: results, title: title, artist: artist)
            cachedURLs[key] = url
            return url
        } catch {
            cachedURLs[key] = nil
            return nil
        }
    }

    private func bestArtworkURL(
        in results: [AppleMusicSearchResult],
        title: String,
        artist: String
    ) -> URL? {
        results
            .compactMap { result -> (score: Int, url: URL)? in
                guard let url = normalizedMusicArtworkURL(result.artworkURL) else { return nil }
                return (musicArtworkMatchScore(result: result, title: title, artist: artist), url)
            }
            .sorted { lhs, rhs in lhs.score > rhs.score }
            .first?
            .url
    }

    private func musicArtworkMatchScore(
        result: AppleMusicSearchResult,
        title: String,
        artist: String
    ) -> Int {
        let targetTitle = normalizedSearch(title)
        let targetArtist = normalizedSearch(artist)
        let resultTitle = normalizedSearch(result.title)
        let resultArtist = normalizedSearch(result.artist)
        var score = 0

        if !targetTitle.isEmpty {
            if resultTitle == targetTitle {
                score += 8
            } else if !resultTitle.isEmpty,
                      resultTitle.contains(targetTitle) || targetTitle.contains(resultTitle) {
                score += 4
            }
        }

        if !targetArtist.isEmpty {
            if resultArtist == targetArtist {
                score += 6
            } else if !resultArtist.isEmpty,
                      resultArtist.contains(targetArtist) || targetArtist.contains(resultArtist) {
                score += 3
            }
        }

        return score
    }
}

struct MusicArtworkView: View {
    let urlString: String
    var title: String = ""
    var artist: String = ""
    var cornerRadius: CGFloat = 5
    var shouldLoad = true
    var allowsFallbackLookup = true

    @State private var image: NSImage?
    @State private var didFail = false

    private var artworkURL: URL? {
        normalizedMusicArtworkURL(urlString)
    }

    private var loadKey: String {
        [
            urlString,
            title,
            artist,
            shouldLoad ? "load" : "pause",
            allowsFallbackLookup ? "fallback" : "direct"
        ].joined(separator: "|")
    }

    private var hasPotentialArtwork: Bool {
        artworkURL != nil
            || (
                allowsFallbackLookup
                && (
                    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            )
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
                    .redacted(reason: hasPotentialArtwork && !didFail ? .placeholder : [])
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: loadKey) {
            guard shouldLoad else {
                image = nil
                didFail = false
                return
            }
            await loadArtwork()
        }
    }

    private var placeholder: some View {
        Image(systemName: "music.note")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.pink.opacity(0.86))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.pink.opacity(0.12))
    }

    private func loadArtwork() async {
        image = nil
        didFail = false

        if let artworkURL, await loadImage(from: artworkURL) {
            return
        }

        if allowsFallbackLookup,
           let fallbackURL = await MusicArtworkFallbackResolver.shared.artworkURL(title: title, artist: artist),
           fallbackURL != artworkURL,
           await loadImage(from: fallbackURL) {
            return
        }

        guard !Task.isCancelled else { return }
        image = nil
        didFail = true
    }

    private func loadImage(from artworkURL: URL) async -> Bool {
        if let cached = MusicArtworkCache.shared.object(forKey: artworkURL as NSURL) {
            image = cached
            didFail = false
            return true
        }

        do {
            var request = URLRequest(url: artworkURL)
            request.timeoutInterval = 12
            request.cachePolicy = .returnCacheDataElseLoad
            request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            await MusicArtworkLoadGate.shared.acquire()
            defer {
                Task {
                    await MusicArtworkLoadGate.shared.release()
                }
            }
            guard !Task.isCancelled else { return false }

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                throw URLError(.badServerResponse)
            }
            guard let loadedImage = NSImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            MusicArtworkCache.shared.setObject(loadedImage, forKey: artworkURL as NSURL, cost: data.count)
            guard !Task.isCancelled else { return false }
            image = loadedImage
            didFail = false
            return true
        } catch {
            return false
        }
    }
}

nonisolated func normalizedMusicArtworkURL(_ rawURLString: String) -> URL? {
    var text = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }

    if text.hasPrefix("//") {
        text = "https:" + text
    } else if text.hasPrefix("http://") {
        text = "https://" + String(text.dropFirst("http://".count))
    }

    text = text.replacingOccurrences(
        of: #"(\d+)x(\d+)bb(\.[A-Za-z0-9]+)$"#,
        with: "512x512bb$3",
        options: .regularExpression
    )

    if let url = URL(string: text) {
        return url
    }

    return URL(string: text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
}

func youTubeMusicQuery(for song: MusicRecognitionItem) -> String {
    [song.artist, song.title]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

func youTubeSearchURL(for query: String) -> URL? {
    guard
        !query.isEmpty,
        var components = URLComponents(string: "https://www.youtube.com/results")
    else { return nil }
    components.queryItems = [URLQueryItem(name: "search_query", value: query)]
    return components.url
}

func openFirstYouTubeVideo(for song: MusicRecognitionItem) {
    let query = youTubeMusicQuery(for: song)
    guard !query.isEmpty else { return }

    Task {
        let firstResultURL = await LibraryStore.firstYouTubeSearchResultURL(for: query)
        guard let url = firstResultURL ?? youTubeSearchURL(for: query) else { return }
        await MainActor.run {
            _ = NSWorkspace.shared.open(url)
        }
    }
}
