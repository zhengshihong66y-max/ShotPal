//
//  LibraryStore+XiaohongshuDownload.swift
//  LapianBao
//
//  Split from LibraryStore.swift.
//

import AppKit
import AVFoundation
import Combine
import Darwin
import Foundation
import UniformTypeIdentifiers

extension LibraryStore {
    // MARK: - 小红书原生解析器

    nonisolated static func downloadRemoteFile(
        request: URLRequest,
        to outputURL: URL,
        progressCallback: (@Sendable (Double?, String?) -> Void)? = nil
    ) async throws -> URL {
        progressCallback?(nil, nil)
        let downloader = RemoteFileDownloader(destinationURL: outputURL, progressCallback: progressCallback)
        return try await downloader.download(request: request)
    }

    nonisolated static func downloadXiaoHongShuNative(
        from sourceURL: URL,
        destinationDirectory: URL,
        progressCallback: (@Sendable (Double?, String?) -> Void)? = nil
    ) async throws -> DownloadedVideoResult {
        let noteID = xiaohongshuNoteID(from: sourceURL)
        let html = try await xiaohongshuNoteHTML(from: sourceURL)
        guard let parsed = xiaohongshuParsedNoteAndVideo(
            from: html,
            noteID: noteID
        ) else {
            throw RemoteImportError.downloaderFailed("小红书：未找到视频信息，该笔记可能不是视频或需要登录")
        }
        let noteObj = parsed.note
        let videoObj = parsed.video

        guard let downloadURL = xiaohongshuVideoDownloadURL(from: videoObj) else {
            throw RemoteImportError.downloaderFailed("小红书：找不到视频下载地址，该视频可能仅限好友可见")
        }

        // 下载视频文件
        var dlReq = URLRequest(url: downloadURL)
        dlReq.setValue("https://www.xiaohongshu.com", forHTTPHeaderField: "Referer")
        dlReq.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        dlReq.setValue("*/*", forHTTPHeaderField: "Accept")
        dlReq.timeoutInterval = 180

        let authorName = xiaoHongShuAuthorName(from: noteObj)
        let sourceTitle = screenedSourceTitle(
            rawTitle: noteObj["title"] as? String,
            description: noteObj["desc"] as? String,
            sourceURL: sourceURL
        )
        let outputURL = cleanedImportVideoURL(
            in: destinationDirectory,
            sourceURL: sourceURL,
            rawTitle: noteObj["title"] as? String,
            description: noteObj["desc"] as? String,
            uploader: authorName,
            preferredExtension: "mp4"
        )
        let fileURL = try await downloadRemoteFile(
            request: dlReq,
            to: outputURL,
            progressCallback: progressCallback
        )
        return DownloadedVideoResult(
            url: fileURL,
            authorName: normalizedSourceAuthorName(authorName ?? ""),
            sourceTitle: sourceTitle
        )
    }

    nonisolated static func xiaohongshuRemoteImportCandidateMetadata(
        for sourceURL: URL
    ) async -> RemoteImportCandidateMetadata? {
        do {
            let noteID = xiaohongshuNoteID(from: sourceURL)
            let html = try await xiaohongshuNoteHTML(from: sourceURL)
            guard let parsed = xiaohongshuParsedNoteAndVideo(
                from: html,
                noteID: noteID
            ) else { return nil }

            let title = screenedSourceTitle(
                rawTitle: parsed.note["title"] as? String,
                description: parsed.note["desc"] as? String,
                sourceURL: sourceURL
            )
            let authorName = xiaoHongShuAuthorName(from: parsed.note)
            let thumbnailURL = xiaohongshuCoverURL(from: parsed.note)
                ?? xiaohongshuCoverURL(from: parsed.video)
            let thumbnailData: Data?
            if let thumbnailURL {
                thumbnailData = await fetchRemoteImageData(from: thumbnailURL)
            } else {
                thumbnailData = nil
            }

            return RemoteImportCandidateMetadata(
                title: title,
                authorName: normalizedSourceAuthorName(authorName ?? ""),
                thumbnailData: thumbnailData
            )
        } catch {
            return nil
        }
    }

    nonisolated static func xiaohongshuNoteHTML(from sourceURL: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            try withExportedChromeCookies(seedURLString: "https://www.xiaohongshu.com/") { cookieURL in
                var noteURLString = sourceURL.absoluteString
                if sourceURL.query?.contains("xsec_token=") != true,
                   let noteID = xiaohongshuNoteID(from: sourceURL),
                   let tokenizedURLString = xiaohongshuTokenizedCollectionURL(
                       for: noteID,
                       cookieURL: cookieURL
                   ) {
                    noteURLString = tokenizedURLString
                }

                let result = try runCurlFetch(
                    urlString: noteURLString,
                    cookieFileURL: cookieURL,
                    headers: [
                        ("accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"),
                        ("referer", "https://www.xiaohongshu.com/"),
                        ("user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36")
                    ],
                    timeout: 30
                )
                guard (200..<300).contains(result.statusCode),
                      let html = String(data: result.data, encoding: .utf8)
                else {
                    throw RemoteImportError.downloaderFailed("小红书页面读取失败（HTTP \(result.statusCode)）")
                }
                return html
            }
        }.value
    }

    nonisolated static func xiaohongshuTokenizedCollectionURL(
        for noteID: String,
        cookieURL: URL
    ) -> String? {
        guard let result = try? runCurlFetch(
            urlString: xiaohongshuSavedCollectionURLString,
            cookieFileURL: cookieURL,
            headers: [
                ("accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"),
                ("referer", "https://www.xiaohongshu.com/"),
                ("user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36")
            ],
            timeout: 24
        ),
              (200..<300).contains(result.statusCode),
              let html = String(data: result.data, encoding: .utf8)
        else { return nil }

        return xiaohongshuVideoLinks(fromSavedHTML: html, limit: 50)
            .first { link in
                guard let url = URL(string: link) else { return false }
                return xiaohongshuNoteID(from: url) == noteID
                    && url.query?.contains("xsec_token=") == true
            }
    }

    nonisolated static func xiaohongshuVideoLinks(fromSavedHTML html: String, limit: Int) -> [String] {
        let normalizedHTML = html
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u002f", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\u003A", with: ":")
            .replacingOccurrences(of: "\\u003a", with: ":")
            .replacingOccurrences(of: "\\u003D", with: "=")
            .replacingOccurrences(of: "\\u003d", with: "=")
            .replacingOccurrences(of: "&amp;", with: "&")
        let clampedLimit = max(1, limit)
        var videoLinks: [String] = []
        var linkIndexesByKey: [String: Int] = [:]

        appendXiaohongshuVideoLinks(
            xiaohongshuSectionVideoLinks(fromSavedHTML: normalizedHTML),
            to: &videoLinks,
            linkIndexesByKey: &linkIndexesByKey,
            limit: clampedLimit
        )
        appendXiaohongshuVideoLinks(
            xiaohongshuInitialStateVideoLinks(fromSavedHTML: normalizedHTML, limit: clampedLimit),
            to: &videoLinks,
            linkIndexesByKey: &linkIndexesByKey,
            limit: clampedLimit
        )
        appendXiaohongshuVideoLinks(
            xiaohongshuGlobalVideoLinks(fromSavedHTML: normalizedHTML),
            to: &videoLinks,
            linkIndexesByKey: &linkIndexesByKey,
            limit: clampedLimit
        )

        return videoLinks.prefix(clampedLimit).map { $0 }
    }

    nonisolated static func xiaohongshuVideoCandidates(
        fromSavedHTML html: String,
        limit: Int
    ) -> [SavedImportCandidate] {
        let links = xiaohongshuVideoLinks(fromSavedHTML: html, limit: limit)
        guard !links.isEmpty else { return [] }

        let metadataByNoteID = xiaohongshuSavedCandidateMetadataByNoteID(fromSavedHTML: html)
        return links.map { link in
            let metadata = xiaohongshuNoteID(fromRawURLString: link)
                .flatMap { metadataByNoteID[$0] }
            return SavedImportCandidate(urlString: link, metadata: metadata)
        }
    }

    nonisolated static func xiaohongshuSavedCandidateMetadataByNoteID(
        fromSavedHTML html: String
    ) -> [String: SavedImportCandidateMetadata] {
        xiaohongshuSavedCandidateMetadataByNoteID(fromSavedHTML: html, limitedTo: nil)
    }

    nonisolated static func xiaohongshuSavedCandidateMetadataByNoteID(
        fromSavedHTML html: String,
        limitedTo targetNoteIDs: Set<String>?
    ) -> [String: SavedImportCandidateMetadata] {
        if let targetNoteIDs, targetNoteIDs.isEmpty { return [:] }
        guard let root = xiaohongshuInitialStateRoot(from: html) else { return [:] }

        var metadataByNoteID: [String: SavedImportCandidateMetadata] = [:]
        collectXiaohongshuSavedCandidateMetadata(
            from: root,
            into: &metadataByNoteID,
            targetNoteIDs: targetNoteIDs
        )
        return metadataByNoteID
    }

    nonisolated static func collectXiaohongshuSavedCandidateMetadata(
        from value: Any,
        into metadataByNoteID: inout [String: SavedImportCandidateMetadata],
        targetNoteIDs: Set<String>? = nil,
        depth: Int = 0
    ) {
        guard depth < 28 else { return }
        if let targetNoteIDs, metadataByNoteID.count >= targetNoteIDs.count { return }

        if let dictionary = value as? [String: Any] {
            if xiaohongshuDictionaryLooksLikeVideoNote(dictionary),
               let noteID = xiaohongshuNoteIDValue(from: dictionary),
               targetNoteIDs == nil || targetNoteIDs?.contains(noteID) == true,
               let metadata = xiaohongshuSavedCandidateMetadata(from: dictionary, noteID: noteID) {
                if let current = metadataByNoteID[noteID] {
                    metadataByNoteID[noteID] = current.merging(metadata)
                } else {
                    metadataByNoteID[noteID] = metadata
                }
            }

            for nested in dictionary.values {
                collectXiaohongshuSavedCandidateMetadata(
                    from: nested,
                    into: &metadataByNoteID,
                    targetNoteIDs: targetNoteIDs,
                    depth: depth + 1
                )
                if let targetNoteIDs, metadataByNoteID.count >= targetNoteIDs.count { return }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                collectXiaohongshuSavedCandidateMetadata(
                    from: nested,
                    into: &metadataByNoteID,
                    targetNoteIDs: targetNoteIDs,
                    depth: depth + 1
                )
                if let targetNoteIDs, metadataByNoteID.count >= targetNoteIDs.count { return }
            }
        }
    }

    nonisolated static func xiaohongshuSavedCandidateMetadata(
        from noteObject: [String: Any],
        noteID: String
    ) -> SavedImportCandidateMetadata? {
        let sourceURL = xiaohongshuNoteURLString(
            noteID: noteID,
            xsecToken: nil,
            xsecSource: nil
        ).flatMap(URL.init(string:)) ?? URL(string: xiaohongshuSavedCollectionURLString)!

        let title = xiaohongshuCandidateTitle(from: noteObject, sourceURL: sourceURL)
        let authorName = xiaoHongShuAuthorName(from: noteObject)
        let thumbnailURL = xiaohongshuCoverURL(from: noteObject)
        let metadata = SavedImportCandidateMetadata(
            title: title,
            authorName: authorName,
            thumbnailURLString: thumbnailURL?.absoluteString
        )
        return metadata.hasAnyValue ? metadata : nil
    }

    nonisolated static func xiaohongshuCandidateTitle(
        from noteObject: [String: Any],
        sourceURL: URL
    ) -> String? {
        screenedSourceTitle(
            rawTitle: xiaohongshuFirstStringValue(
                in: noteObject,
                keys: ["title", "displayTitle", "display_title", "name"]
            ),
            description: xiaohongshuFirstStringValue(
                in: noteObject,
                keys: ["desc", "description", "content", "noteDesc", "note_desc"]
            ),
            sourceURL: sourceURL
        )
    }

    nonisolated static func xiaohongshuFirstStringValue(
        in dictionary: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = xiaohongshuStringValue(dictionary[key]) {
                return value
            }
        }
        return nil
    }

    nonisolated static func appendXiaohongshuVideoLinks(
        _ newLinks: [String],
        to links: inout [String],
        linkIndexesByKey: inout [String: Int],
        limit: Int
    ) {
        for link in newLinks {
            let key = normalizedXiaohongshuNoteURL(link) ?? link
            if let existingIndex = linkIndexesByKey[key] {
                if xiaohongshuLinkHasXsecToken(link),
                   !xiaohongshuLinkHasXsecToken(links[existingIndex]) {
                    links[existingIndex] = link
                }
                continue
            }

            guard links.count < limit else { continue }
            linkIndexesByKey[key] = links.count
            links.append(link)
        }
    }

    nonisolated static func xiaohongshuLinkHasXsecToken(_ link: String) -> Bool {
        guard let components = URLComponents(string: link) else {
            return link.contains("xsec_token=")
        }
        return components.queryItems?.contains { $0.name == "xsec_token" && ($0.value?.isEmpty == false) } == true
    }

    nonisolated static func xiaohongshuSectionVideoLinks(fromSavedHTML normalizedHTML: String) -> [String] {
        let sectionPattern = #"<section\b(?:(?!</section>).)*</section>"#
        let hrefPattern = #"href=["']([^"']+)["']"#
        guard let sectionRegex = try? NSRegularExpression(
            pattern: sectionPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ),
              let hrefRegex = try? NSRegularExpression(pattern: hrefPattern, options: [.caseInsensitive])
        else { return [] }

        let nsString = normalizedHTML as NSString
        var videoLinks: [String] = []
        let sections = sectionRegex.matches(
            in: normalizedHTML,
            options: [],
            range: NSRange(location: 0, length: nsString.length)
        )
        for section in sections {
            let sectionHTML = nsString.substring(with: section.range)
            let lowercasedSection = sectionHTML.lowercased()
            guard lowercasedSection.contains("play-icon")
                    || lowercasedSection.contains("#play-s")
                    || lowercasedSection.contains("xgplayer")
                    || lowercasedSection.contains("player-container")
            else { continue }

            let sectionNSString = sectionHTML as NSString
            let hrefMatches = hrefRegex.matches(
                in: sectionHTML,
                options: [],
                range: NSRange(location: 0, length: sectionNSString.length)
            )
            var sectionLinks: [(url: String, hasToken: Bool)] = []
            for hrefMatch in hrefMatches where hrefMatch.numberOfRanges > 1 {
                let href = sectionNSString.substring(with: hrefMatch.range(at: 1))
                    .replacingOccurrences(of: "&amp;", with: "&")
                guard let normalized = normalizedXiaohongshuNoteURL(
                    href,
                    preservingXsecToken: true
                ) else { continue }
                sectionLinks.append((url: normalized, hasToken: href.contains("xsec_token=")))
            }
            if let selectedLink = sectionLinks.first(where: { $0.hasToken })?.url ?? sectionLinks.first?.url {
                videoLinks.append(selectedLink)
            }
        }

        var seen = Set<String>()
        return videoLinks.filter { seen.insert($0).inserted }
    }

    nonisolated static func xiaohongshuInitialStateVideoLinks(
        fromSavedHTML html: String,
        limit: Int
    ) -> [String] {
        guard let root = xiaohongshuInitialStateRoot(from: html) else { return [] }

        var links: [String] = []
        var linkIndexesByKey: [String: Int] = [:]
        collectXiaohongshuVideoNoteLinks(
            from: root,
            into: &links,
            linkIndexesByKey: &linkIndexesByKey,
            limit: max(1, limit)
        )
        return links
    }

    nonisolated static func collectXiaohongshuVideoNoteLinks(
        from value: Any,
        into links: inout [String],
        linkIndexesByKey: inout [String: Int],
        limit: Int,
        depth: Int = 0
    ) {
        guard links.count < limit, depth < 28 else { return }

        if let dictionary = value as? [String: Any] {
            if xiaohongshuDictionaryLooksLikeVideoNote(dictionary) {
                appendXiaohongshuVideoLinks(
                    xiaohongshuNoteURLCandidates(from: dictionary),
                    to: &links,
                    linkIndexesByKey: &linkIndexesByKey,
                    limit: limit
                )
            }

            for nested in dictionary.values {
                collectXiaohongshuVideoNoteLinks(
                    from: nested,
                    into: &links,
                    linkIndexesByKey: &linkIndexesByKey,
                    limit: limit,
                    depth: depth + 1
                )
                if links.count >= limit { return }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                collectXiaohongshuVideoNoteLinks(
                    from: nested,
                    into: &links,
                    linkIndexesByKey: &linkIndexesByKey,
                    limit: limit,
                    depth: depth + 1
                )
                if links.count >= limit { return }
            }
        }
    }

    nonisolated static func xiaohongshuDictionaryLooksLikeVideoNote(_ dictionary: [String: Any]) -> Bool {
        for key in ["type", "noteType", "note_type", "note_type_name", "mediaType", "media_type"] {
            guard let rawValue = xiaohongshuStringValue(dictionary[key]) else { continue }
            let lowered = rawValue.lowercased()
            if lowered == "video" || lowered.contains("video") || rawValue.contains("视频") {
                return true
            }
        }

        if ["video", "videoInfo", "video_info", "videoInfoV2", "video_info_v2"].contains(where: { dictionary[$0] is [String: Any] }) {
            return true
        }

        for key in ["hasVideo", "has_video", "isVideo", "is_video"] {
            if let hasVideo = dictionary[key] as? Bool, hasVideo {
                return true
            }
        }

        return false
    }

    nonisolated static func xiaohongshuNoteURLCandidates(from dictionary: [String: Any]) -> [String] {
        var links: [String] = []
        let urlKeys = [
            "url", "link", "href", "shareLink", "shareURL", "shareUrl",
            "webUrl", "webURL", "pageUrl", "pageURL", "noteUrl", "noteURL",
            "jumpUrl", "jumpURL", "targetUrl", "targetURL"
        ]

        for key in urlKeys {
            guard let rawValue = xiaohongshuStringValue(dictionary[key]),
                  let normalized = normalizedXiaohongshuNoteURL(rawValue, preservingXsecToken: true)
            else { continue }
            links.append(normalized)
        }

        if let noteID = xiaohongshuNoteIDValue(from: dictionary),
           let noteURL = xiaohongshuNoteURLString(
               noteID: noteID,
               xsecToken: xiaohongshuStringValue(dictionary["xsecToken"])
                   ?? xiaohongshuStringValue(dictionary["xsec_token"]),
               xsecSource: xiaohongshuStringValue(dictionary["xsecSource"])
                   ?? xiaohongshuStringValue(dictionary["xsec_source"])
           ) {
            links.append(noteURL)
        }

        var seen = Set<String>()
        return links.filter { link in
            let key = normalizedXiaohongshuNoteURL(link) ?? link
            return seen.insert(key).inserted
        }
    }

    nonisolated static func xiaohongshuNoteIDValue(from dictionary: [String: Any]) -> String? {
        for key in [
            "noteId", "noteID", "note_id", "noteIdStr", "note_id_str",
            "noteCardId", "noteCardID", "note_card_id", "itemId", "itemID", "item_id", "id"
        ] {
            guard let value = xiaohongshuStringValue(dictionary[key]),
                  xiaohongshuLooksLikeNoteID(value)
            else { continue }
            return value
        }
        return nil
    }

    nonisolated static func xiaohongshuLooksLikeNoteID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (16...40).contains(trimmed.count) else { return false }
        return trimmed.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    nonisolated static func xiaohongshuStringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func xiaohongshuNoteURLString(
        noteID: String,
        xsecToken: String?,
        xsecSource: String?
    ) -> String? {
        guard var components = URLComponents(string: "https://www.xiaohongshu.com/explore/\(noteID)") else {
            return nil
        }

        var queryItems: [URLQueryItem] = []
        if let xsecToken, !xsecToken.isEmpty {
            queryItems.append(URLQueryItem(name: "xsec_token", value: xsecToken))
        }
        if let xsecSource, !xsecSource.isEmpty {
            queryItems.append(URLQueryItem(name: "xsec_source", value: xsecSource))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url?.absoluteString
    }

    nonisolated static func xiaohongshuGlobalVideoLinks(fromSavedHTML normalizedHTML: String) -> [String] {
        let hrefPattern = #"href=["']([^"']+)["']"#
        let rawURLPattern = #"(?:https?:)?//www\.xiaohongshu\.com/(?:explore|search_result|discovery/item)/[A-Za-z0-9_-]+(?:\?[^"'<>\\\s]*)?|/(?:explore|search_result|discovery/item)/[A-Za-z0-9_-]+(?:\?[^"'<>\\\s]*)?"#
        guard let hrefRegex = try? NSRegularExpression(pattern: hrefPattern, options: [.caseInsensitive]),
              let rawURLRegex = try? NSRegularExpression(pattern: rawURLPattern, options: [.caseInsensitive])
        else { return [] }

        let nsString = normalizedHTML as NSString
        var links: [String] = []

        let hrefMatches = hrefRegex.matches(
            in: normalizedHTML,
            options: [],
            range: NSRange(location: 0, length: nsString.length)
        )
        for match in hrefMatches where match.numberOfRanges > 1 {
            guard xiaohongshuSnippetLooksLikeVideo(in: nsString, near: match.range.location) else { continue }
            let href = nsString.substring(with: match.range(at: 1))
                .replacingOccurrences(of: "&amp;", with: "&")
            if let normalized = normalizedXiaohongshuNoteURL(href, preservingXsecToken: true) {
                links.append(normalized)
            }
        }

        let rawMatches = rawURLRegex.matches(
            in: normalizedHTML,
            options: [],
            range: NSRange(location: 0, length: nsString.length)
        )
        for match in rawMatches {
            guard xiaohongshuSnippetLooksLikeVideo(in: nsString, near: match.range.location) else { continue }
            let rawValue = nsString.substring(with: match.range)
                .replacingOccurrences(of: "&amp;", with: "&")
            if let normalized = normalizedXiaohongshuNoteURL(rawValue, preservingXsecToken: true) {
                links.append(normalized)
            }
        }

        var seen = Set<String>()
        return links.filter { link in
            let key = normalizedXiaohongshuNoteURL(link) ?? link
            return seen.insert(key).inserted
        }
    }

    nonisolated static func xiaohongshuSnippetLooksLikeVideo(in html: NSString, near location: Int) -> Bool {
        let start = max(0, location - 2200)
        let end = min(html.length, location + 3600)
        guard end > start else { return false }
        let snippet = html.substring(with: NSRange(location: start, length: end - start)).lowercased()
        return [
            #""type":"video""#,
            #""note_type":"video""#,
            #""notetype":"video""#,
            #""media_type":"video""#,
            #""mediatype":"video""#,
            #""hasvideo":true"#,
            #""has_video":true"#,
            "video_info",
            "videoinfo",
            "video_info_v2",
            "videoinfov2",
            "video_url",
            "play-icon",
            "play_icon",
            "#play-s",
            "xgplayer",
            "player-container"
        ].contains { snippet.contains($0) }
    }

    nonisolated static func sanitizedXiaohongshuInitialStateJSON(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutTrailingSemicolon = trimmed.hasSuffix(";") ? String(trimmed.dropLast()) : trimmed
        return withoutTrailingSemicolon.replacingOccurrences(
            of: #"\bundefined\b"#,
            with: "null",
            options: .regularExpression
        )
    }

    nonisolated static func xiaohongshuInitialStateJSON(from html: String) -> String? {
        guard let stateStart = html.range(
            of: #"window\.__INITIAL_STATE__\s*="#,
            options: .regularExpression
        ) else {
            return nil
        }

        let afterEquals = html[stateStart.upperBound...]
        let jsonRaw: String
        if let scriptEnd = afterEquals.range(of: "</script>") {
            jsonRaw = String(afterEquals[..<scriptEnd.lowerBound])
        } else if let newline = afterEquals.firstIndex(of: "\n") {
            jsonRaw = String(afterEquals[..<newline])
        } else {
            jsonRaw = String(afterEquals.prefix(512_000))
        }

        var jsonStr = sanitizedXiaohongshuInitialStateJSON(jsonRaw)
        if jsonStr.hasSuffix(";") { jsonStr.removeLast() }
        return jsonStr
    }

    nonisolated static func xiaohongshuInitialStateRoot(from html: String) -> [String: Any]? {
        guard
            let jsonStr = xiaohongshuInitialStateJSON(from: html),
            let jsonData = jsonStr.data(using: .utf8)
        else { return nil }

        return try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
    }

    nonisolated static func xiaohongshuParsedNoteAndVideo(
        from html: String,
        noteID: String?
    ) -> (note: [String: Any], video: [String: Any])? {
        guard let root = xiaohongshuInitialStateRoot(from: html) else { return nil }

        if let noteID,
           let parsed = xiaohongshuNoteAndVideo(fromRoot: root, noteID: noteID) {
            return parsed
        }

        return xiaohongshuFirstVideoNote(in: root)
    }

    nonisolated static func xiaohongshuNoteAndVideo(
        fromRoot root: [String: Any],
        noteID: String
    ) -> (note: [String: Any], video: [String: Any])? {
        if let noteSection = root["note"] as? [String: Any],
           let detailMap = noteSection["noteDetailMap"] as? [String: Any] {
            if let parsed = xiaohongshuNoteAndVideo(fromDetailEntry: detailMap[noteID]) {
                return parsed
            }

            for entry in detailMap.values {
                guard let parsed = xiaohongshuNoteAndVideo(fromDetailEntry: entry) else { continue }
                if xiaohongshuNote(parsed.note, matches: noteID) {
                    return parsed
                }
            }
        }

        return xiaohongshuMatchingVideoNote(in: root, noteID: noteID)
    }

    nonisolated static func xiaohongshuNoteAndVideo(
        fromDetailEntry entry: Any?
    ) -> (note: [String: Any], video: [String: Any])? {
        guard let dictionary = entry as? [String: Any] else { return nil }

        if let noteObject = dictionary["note"] as? [String: Any],
           let videoObject = xiaohongshuVideoObject(from: noteObject) {
            return (noteObject, videoObject)
        }

        if let videoObject = xiaohongshuVideoObject(from: dictionary) {
            return (dictionary, videoObject)
        }

        return nil
    }

    nonisolated static func xiaohongshuMatchingVideoNote(
        in value: Any,
        noteID: String
    ) -> (note: [String: Any], video: [String: Any])? {
        if let dictionary = value as? [String: Any] {
            if xiaohongshuNote(dictionary, matches: noteID),
               let videoObject = xiaohongshuVideoObject(from: dictionary) {
                return (dictionary, videoObject)
            }

            for nested in dictionary.values {
                if let parsed = xiaohongshuMatchingVideoNote(in: nested, noteID: noteID) {
                    return parsed
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let parsed = xiaohongshuMatchingVideoNote(in: nested, noteID: noteID) {
                    return parsed
                }
            }
        }

        return nil
    }

    nonisolated static func xiaohongshuFirstVideoNote(
        in value: Any
    ) -> (note: [String: Any], video: [String: Any])? {
        if let dictionary = value as? [String: Any] {
            if let videoObject = xiaohongshuVideoObject(from: dictionary) {
                return (dictionary, videoObject)
            }

            for nested in dictionary.values {
                if let parsed = xiaohongshuFirstVideoNote(in: nested) {
                    return parsed
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let parsed = xiaohongshuFirstVideoNote(in: nested) {
                    return parsed
                }
            }
        }

        return nil
    }

    nonisolated static func xiaohongshuVideoObject(from noteObject: [String: Any]) -> [String: Any]? {
        for key in ["video", "videoInfo", "video_info", "videoInfoV2", "video_info_v2"] {
            if let videoObject = noteObject[key] as? [String: Any] {
                return videoObject
            }
        }
        return nil
    }

    nonisolated static func xiaohongshuNote(
        _ noteObject: [String: Any],
        matches noteID: String
    ) -> Bool {
        for key in ["noteId", "noteID", "note_id", "id", "noteIdStr"] {
            if let value = noteObject[key] as? String,
               value == noteID {
                return true
            }
        }

        for key in ["url", "link", "shareLink", "shareURL"] {
            if let value = noteObject[key] as? String,
               xiaohongshuNoteID(fromRawURLString: value) == noteID {
                return true
            }
        }

        return false
    }

    nonisolated static func xiaohongshuVideoDownloadURL(from videoObject: [String: Any]) -> URL? {
        if let consumer = videoObject["consumer"] as? [String: Any],
           let key = consumer["originVideoKey"] as? String,
           let url = xiaohongshuOriginVideoURL(from: key) {
            return url
        }

        if let media = videoObject["media"] as? [String: Any],
           let stream = media["stream"] as? [String: Any] {
            for codec in ["h264", "h265", "av1", "h266"] {
                if let url = xiaohongshuFirstVideoURL(from: stream[codec]) {
                    return url
                }
            }

            if let url = xiaohongshuFirstVideoURL(from: stream) {
                return url
            }
        }

        for key in [
            "masterUrl",
            "mainUrl",
            "originUrl",
            "downloadUrl",
            "downloadURL",
            "downloadAddr",
            "backupUrl",
            "backupUrls",
            "url"
        ] {
            if let url = xiaohongshuFirstVideoURL(from: videoObject[key]) {
                return url
            }
        }

        return xiaohongshuFirstVideoURL(from: videoObject)
    }

    nonisolated static func xiaohongshuOriginVideoURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = xiaohongshuVideoURL(from: trimmed) {
            return url
        }
        return URL(string: "https://sns-video-bd.xhscdn.com/\(trimmed)")
    }

    nonisolated static func xiaohongshuFirstVideoURL(from value: Any?) -> URL? {
        if let string = value as? String {
            return xiaohongshuVideoURL(from: string)
        }

        if let dictionary = value as? [String: Any] {
            for key in [
                "masterUrl",
                "mainUrl",
                "originUrl",
                "downloadUrl",
                "downloadURL",
                "downloadAddr",
                "backupUrl",
                "backupUrls",
                "url"
            ] {
                if let url = xiaohongshuFirstVideoURL(from: dictionary[key]) {
                    return url
                }
            }

            for nested in dictionary.values {
                if let url = xiaohongshuFirstVideoURL(from: nested) {
                    return url
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let url = xiaohongshuFirstVideoURL(from: nested) {
                    return url
                }
            }
        }

        return nil
    }

    nonisolated static func xiaohongshuVideoURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("//") ? "https:\(trimmed)" : trimmed
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }

        let lowercased = normalized.lowercased()
        guard !lowercased.contains("sns-img"),
              !lowercased.contains("sns-webpic"),
              !lowercased.contains(".jpg"),
              !lowercased.contains(".jpeg"),
              !lowercased.contains(".png"),
              !lowercased.contains(".webp")
        else { return nil }

        guard lowercased.contains("sns-video")
                || lowercased.contains("video")
                || lowercased.contains("xhscdn")
                || lowercased.contains(".mp4")
                || lowercased.contains(".m3u8")
        else { return nil }

        return url
    }

    nonisolated static func xiaohongshuCoverURL(from value: Any) -> URL? {
        if let string = value as? String {
            return xiaohongshuImageURL(from: string)
        }

        if let dictionary = value as? [String: Any] {
            for key in [
                "urlDefault",
                "urlPre",
                "coverUrl",
                "coverURL",
                "thumbnailUrl",
                "thumbnailURL",
                "posterUrl",
                "posterURL",
                "imageUrl",
                "imageURL",
                "url",
                "cover",
                "image",
                "thumbnail",
                "poster",
                "url"
            ] {
                if let nested = dictionary[key],
                   let url = xiaohongshuCoverURL(from: nested) {
                    return url
                }
            }

            for nested in dictionary.values {
                if let url = xiaohongshuCoverURL(from: nested) {
                    return url
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let url = xiaohongshuCoverURL(from: nested) {
                    return url
                }
            }
        }

        return nil
    }

    nonisolated static func xiaohongshuImageURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("//") ? "https:\(trimmed)" : trimmed
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }

        let lowercased = normalized.lowercased()
        guard !lowercased.contains("video"),
              lowercased.contains("xhscdn")
                || lowercased.contains("sns-img")
                || lowercased.contains("sns-webpic")
                || lowercased.contains("image")
                || lowercased.contains(".jpg")
                || lowercased.contains(".jpeg")
                || lowercased.contains(".png")
                || lowercased.contains(".webp")
        else { return nil }

        return url
    }

    nonisolated static func xiaoHongShuAuthorName(from noteObject: [String: Any]) -> String? {
        for containerKey in ["user", "userInfo", "author", "owner"] {
            guard let container = noteObject[containerKey] as? [String: Any] else { continue }
            for nameKey in ["nickname", "nickName", "name", "userName", "username"] {
                if let value = container[nameKey] as? String,
                   let author = normalizedSourceAuthorName(value) {
                    return author
                }
            }
        }

        for nameKey in ["nickname", "nickName", "userName", "username"] {
            if let value = noteObject[nameKey] as? String,
               let author = normalizedSourceAuthorName(value) {
                return author
            }
        }
        return nil
    }

}
