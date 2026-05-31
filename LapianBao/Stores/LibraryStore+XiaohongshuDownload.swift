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
        // 解析 note ID（去掉 query string）
        let noteId = sourceURL.lastPathComponent.components(separatedBy: "?").first
            ?? sourceURL.lastPathComponent

        let html = try await xiaohongshuNoteHTML(from: sourceURL)

        // 提取 window.__INITIAL_STATE__=...;
        guard let stateStart = html.range(of: "window.__INITIAL_STATE__=") else {
            throw RemoteImportError.downloaderFailed("未找到视频数据，该笔记可能需要登录才能查看")
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

        guard
            let jsonData = jsonStr.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let noteSection = root["note"] as? [String: Any],
            let detailMap = noteSection["noteDetailMap"] as? [String: Any],
            let entry = detailMap[noteId] as? [String: Any],
            let noteObj = entry["note"] as? [String: Any],
            let videoObj = noteObj["video"] as? [String: Any]
        else {
            throw RemoteImportError.downloaderFailed("小红书：未找到视频信息，该笔记可能不是视频或需要登录")
        }

        // 优先：原画直链
        var videoURL: URL?
        if let consumer = videoObj["consumer"] as? [String: Any],
           let key = consumer["originVideoKey"] as? String, !key.isEmpty {
            videoURL = URL(string: "https://sns-video-bd.xhscdn.com/\(key)")
        }

        // 回退：stream 格式（h264 > h265 > av1）
        if videoURL == nil,
           let media = videoObj["media"] as? [String: Any],
           let stream = media["stream"] as? [String: Any] {
            for codec in ["h264", "h265", "av1"] {
                if let list = stream[codec] as? [[String: Any]],
                   let first = list.first,
                   let masterUrl = first["masterUrl"] as? String,
                   let u = URL(string: masterUrl) {
                    videoURL = u
                    break
                }
            }
        }

        guard let downloadURL = videoURL else {
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
            authorName: normalizedImportTag(authorName ?? ""),
            sourceTitle: sourceTitle
        )
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

    nonisolated static func sanitizedXiaohongshuInitialStateJSON(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutTrailingSemicolon = trimmed.hasSuffix(";") ? String(trimmed.dropLast()) : trimmed
        return withoutTrailingSemicolon.replacingOccurrences(
            of: #"\bundefined\b"#,
            with: "null",
            options: .regularExpression
        )
    }

    nonisolated static func xiaoHongShuAuthorName(from noteObject: [String: Any]) -> String? {
        for containerKey in ["user", "userInfo", "author", "owner"] {
            guard let container = noteObject[containerKey] as? [String: Any] else { continue }
            for nameKey in ["nickname", "nickName", "name", "userName", "username", "userId", "user_id"] {
                if let value = container[nameKey] as? String,
                   let author = normalizedImportTag(value) {
                    return author
                }
            }
        }

        for nameKey in ["nickname", "nickName", "userName", "username"] {
            if let value = noteObject[nameKey] as? String,
               let author = normalizedImportTag(value) {
                return author
            }
        }
        return nil
    }

}
