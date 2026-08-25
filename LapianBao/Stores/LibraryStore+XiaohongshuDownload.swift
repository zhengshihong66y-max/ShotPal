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
            throw RemoteImportError.downloaderFailed("小红书：未找到视频信息。请确认是视频笔记；若网页要求验证，请先在 Chrome 打开该链接，再到设置同步浏览器 cookies。")
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
            var headers = [
                ("accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"),
                ("referer", "https://www.xiaohongshu.com/"),
                ("user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36")
            ]
            if let cookieHeader = xiaohongshuBrowserCookieHeader() {
                headers.append(("cookie", cookieHeader))
            }
            let result = try runCurlFetch(
                urlString: sourceURL.absoluteString,
                headers: headers,
                timeout: 30
            )
            guard (200..<300).contains(result.statusCode),
                  let html = String(data: result.data, encoding: .utf8)
            else {
                throw RemoteImportError.downloaderFailed("小红书页面读取失败（HTTP \(result.statusCode)）")
            }
            return html
        }.value
    }

    nonisolated static func xiaohongshuBrowserCookieHeader() -> String? {
        guard let cookieFileURL = configuredBrowserCookieFileURL(),
              let contents = try? String(contentsOf: cookieFileURL, encoding: .utf8)
        else { return nil }

        let now = Int(Date().timeIntervalSince1970)
        let cookiePairs = contents
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine -> String? in
                var line = String(rawLine)
                if line.hasPrefix("#HttpOnly_") {
                    line.removeFirst("#HttpOnly_".count)
                } else if line.hasPrefix("#") {
                    return nil
                }
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard fields.count >= 7 else { return nil }
                let domain = fields[0].lowercased()
                guard domain == "xiaohongshu.com"
                        || domain.hasSuffix(".xiaohongshu.com")
                        || domain == "xhslink.com"
                        || domain.hasSuffix(".xhslink.com")
                else { return nil }
                if let expiry = Int(fields[4]), expiry > 0, expiry <= now { return nil }
                let name = fields[5]
                guard !name.isEmpty else { return nil }
                return "\(name)=\(fields[6])"
            }
        guard !cookiePairs.isEmpty else { return nil }
        return cookiePairs.joined(separator: "; ")
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
