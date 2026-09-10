//
//  MusicArtworkAndLookup.swift
//  LapianBao
//
//  Split from AudioMusicComponents.swift.
//

import SwiftUI
import AppKit
import Foundation
import ImageIO

nonisolated enum MusicArtworkCache {
    static let shared: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 2_048
        cache.totalCostLimit = 384 * 1024 * 1024
        return cache
    }()

    static func prewarmCachedArtwork(urls: [URL]) async {
        var seen = Set<String>()
        let uniqueURLs = urls.filter { url in
            seen.insert(url.absoluteString).inserted
        }
        guard !uniqueURLs.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for url in uniqueURLs {
                group.addTask {
                    await prewarmCachedArtwork(url)
                }
            }
            await group.waitForAll()
        }
    }

    @concurrent nonisolated private static func prewarmCachedArtwork(_ artworkURL: URL) async {
        let cacheKey = artworkURL as NSURL
        if shared.object(forKey: cacheKey) != nil {
            return
        }

        var request = URLRequest(url: artworkURL)
        request.timeoutInterval = 8
        request.cachePolicy = .returnCacheDataDontLoad
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        await MusicArtworkLoadGate.shared.acquire()
        defer {
            Task {
                await MusicArtworkLoadGate.shared.release()
            }
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return
            }
            guard let image = decodedImage(data: data) else { return }
            shared.setObject(image, forKey: cacheKey, cost: decodedCost(image))
        } catch {
            return
        }
    }

    static func decodedImage(data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }

    static func decodedCost(_ image: NSImage) -> Int {
        Int(image.size.width * image.size.height * 4)
    }
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

    private var cachedURLs: [String: (url: URL?, expires: Date)] = [:]
    private var inFlight: [String: Task<URL?, Never>] = [:]

    func artworkURL(title rawTitle: String, artist rawArtist: String) async -> URL? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = rawArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = [normalizedSearch(artist), normalizedSearch(title)].joined(separator: "|")
        guard !title.isEmpty, !artist.isEmpty else { return nil }

        if let cached = cachedURLs[key], cached.expires > Date() {
            return cached.url
        }
        if let task = inFlight[key] { return await task.value }

        let query = [artist, title]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let task = Task<URL?, Never> {
            guard let results = try? await LibraryStore.searchAppleMusic(query: query) else { return nil }
            return MusicArtworkSelection.fallbackURL(in: results, title: title, artist: artist)
        }
        inFlight[key] = task
        let url = await task.value
        inFlight[key] = nil
        cachedURLs = cachedURLs.filter { $0.value.expires > Date() }
        cachedURLs[key] = (url, Date().addingTimeInterval(url == nil ? 30 : 3600))
        return url
    }
}

struct MusicArtworkView: View {
    let urlString: String
    var title: String = ""
    var artist: String = ""
    var cornerRadius: CGFloat = 5
    var shouldLoad = true
    var allowsFallbackLookup = true

    @State private var displayState = MusicArtworkDisplayState()

    private var request: MusicArtworkRequest {
        MusicArtworkRequest(urlString: urlString, title: title, artist: artist,
                            shouldLoad: shouldLoad, allowsFallbackLookup: allowsFallbackLookup)
    }

    var body: some View {
        let request = request
        let cached = request.url.flatMap { MusicArtworkCache.shared.object(forKey: $0 as NSURL) }
        let image = cached ?? displayState.visibleImage(for: request)
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .transaction { $0.animation = nil }
        .task(id: request) {
            let generation = displayState.begin(request)
            if let cached {
                displayState.accept(cached, for: request, generation: generation)
                return
            }
            guard request.shouldLoad else { return }
            await loadArtwork(request, generation: generation)
        }
    }

    private var placeholder: some View {
        Image(systemName: "music.note")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.pink.opacity(0.86))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.pink.opacity(0.12))
    }

    private func loadArtwork(_ request: MusicArtworkRequest, generation: UInt64) async {
        if let url = request.url, let image = await loadImage(from: url) {
            guard !Task.isCancelled else { return }
            displayState.accept(image, for: request, generation: generation)
            return
        }
        guard !Task.isCancelled else { return }
        if request.allowsFallbackLookup,
           let fallbackURL = await MusicArtworkFallbackResolver.shared.artworkURL(title: request.title, artist: request.artist),
           fallbackURL != request.url {
            guard !Task.isCancelled else { return }
            if let image = await loadImage(from: fallbackURL), !Task.isCancelled {
                displayState.accept(image, for: request, generation: generation)
            }
        }
        // Keep a valid same-song cover if a refreshed URL fails; otherwise keep the stable placeholder.
    }

    private func loadImage(from artworkURL: URL) async -> NSImage? {
        guard !Task.isCancelled else { return nil }
        if let cached = MusicArtworkCache.shared.object(forKey: artworkURL as NSURL) {
            return cached
        }
        guard let data = await MusicArtworkLoader.shared.data(for: artworkURL), !Task.isCancelled else { return nil }
        _ = await Task.detached(priority: .utility) {
            guard MusicArtworkCache.shared.object(forKey: artworkURL as NSURL) == nil,
                  let image = MusicArtworkCache.decodedImage(data: data) else { return }
            MusicArtworkCache.shared.setObject(image, forKey: artworkURL as NSURL, cost: MusicArtworkCache.decodedCost(image))
        }.value
        guard !Task.isCancelled else { return nil }
        return MusicArtworkCache.shared.object(forKey: artworkURL as NSURL)
    }
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
