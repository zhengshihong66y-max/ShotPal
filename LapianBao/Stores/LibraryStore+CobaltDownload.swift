//
//  LibraryStore+CobaltDownload.swift
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
    // MARK: - cobalt.tools 内置备用下载

    nonisolated struct CobaltRequest: Encodable {
        let url: String
    }

    nonisolated struct CobaltResponse: Decodable {
        let status: String
        let url: URL?
        let filename: String?
        let picker: [CobaltPickerItem]?

        struct CobaltPickerItem: Decodable {
            let type: String?
            let url: URL
        }
    }

    nonisolated static func importViaCobalt(
        sourceURL: URL,
        destinationDirectory: URL,
        progressCallback: (@Sendable (Double?, String?) -> Void)? = nil
    ) async throws -> URL {
        guard let cobaltEndpoint = URL(string: "https://api.cobalt.tools/") else {
            throw RemoteImportError.downloaderMissing
        }
        let selectedPlaylistItemIndex = instagramCarouselItemIndex(from: sourceURL)
        let requestSourceURL = ytdlpSourceURL(for: sourceURL)

        var request = URLRequest(url: cobaltEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(
            CobaltRequest(url: requestSourceURL.absoluteString)
        )

        let (data, httpResp) = try await URLSession.shared.data(for: request)
        guard
            let resp = httpResp as? HTTPURLResponse,
            (200..<300).contains(resp.statusCode)
        else {
            throw RemoteImportError.downloaderFailed("cobalt.tools 无法处理该链接，请安装 yt-dlp 后重试")
        }

        let cobalt = try JSONDecoder().decode(CobaltResponse.self, from: data)

        let downloadURL: URL
        switch cobalt.status {
        case "redirect", "tunnel", "stream":
            guard let u = cobalt.url else { throw RemoteImportError.invalidAPIResponse }
            downloadURL = u
        case "picker":
            let pickerItems = cobalt.picker ?? []
            let videoItems = pickerItems.filter { $0.type == "video" }
            let selectedItem: CobaltResponse.CobaltPickerItem?
            if let selectedPlaylistItemIndex {
                let pickerOffset = selectedPlaylistItemIndex - 1
                if pickerItems.indices.contains(pickerOffset), pickerItems[pickerOffset].type == "video" {
                    selectedItem = pickerItems[pickerOffset]
                } else if videoItems.indices.contains(pickerOffset) {
                    selectedItem = videoItems[pickerOffset]
                } else {
                    selectedItem = nil
                }
            } else {
                selectedItem = videoItems.first ?? pickerItems.first
            }
            guard let item = selectedItem
            else { throw RemoteImportError.invalidAPIResponse }
            downloadURL = item.url
        default:
            throw RemoteImportError.downloaderFailed("cobalt.tools 无法解析该链接，请安装 yt-dlp 后重试")
        }

        let fallbackName = downloadURL.lastPathComponent.isEmpty
            ? "instagram-\(UUID().uuidString).mp4"
            : downloadURL.lastPathComponent
        let sourceFilename = cobalt.filename ?? fallbackName
        let baseOutputURL = cleanedImportVideoURL(
            in: destinationDirectory,
            sourceURL: sourceURL,
            rawTitle: fileStem(from: sourceFilename),
            description: nil,
            uploader: nil,
            preferredExtension: fileExtension(from: sourceFilename, fallback: "mp4")
        )
        let outputURL = selectedPlaylistItemIndex.map {
            uniqueImportVideoURL(
                in: destinationDirectory,
                stem: "\(baseOutputURL.deletingPathExtension().lastPathComponent) 分段 \($0)",
                preferredExtension: fileExtension(from: sourceFilename, fallback: "mp4")
            )
        } ?? baseOutputURL

        var downloadRequest = URLRequest(url: downloadURL)
        downloadRequest.timeoutInterval = 180
        return try await downloadRemoteFile(
            request: downloadRequest,
            to: outputURL,
            progressCallback: progressCallback
        )
    }

    nonisolated static func sanitizedFilename(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let components = name.components(separatedBy: forbidden)
        let sanitized = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "instagram-\(UUID().uuidString).mp4" : sanitized
    }

    nonisolated static func cleanedImportVideoURL(
        in directory: URL,
        sourceURL: URL,
        rawTitle: String?,
        description: String?,
        uploader: String?,
        preferredExtension: String
    ) -> URL {
        let stem = cleanImportVideoStem(
            rawTitle: rawTitle,
            description: description,
            uploader: uploader,
            sourceURL: sourceURL
        )
        return uniqueImportVideoURL(in: directory, stem: stem, preferredExtension: preferredExtension)
    }

    nonisolated static func cleanImportVideoStem(
        rawTitle: String?,
        description: String?,
        uploader: String?,
        sourceURL: URL
    ) -> String {
        let title = stripTrailingSourceID(normalizedSpaces(rawTitle ?? ""))
        var candidate = isGenericImportTitle(title) ? "" : title

        if candidate.isEmpty {
            candidate = cleanImportDescription(description ?? "")
        }
        if candidate.isEmpty {
            candidate = stripTrailingSourceID(normalizedSpaces(uploader ?? ""))
        }
        if candidate.isEmpty {
            candidate = sourceURL.host?.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression) ?? "Imported Video"
        }

        return compactImportFileStem(sanitizeImportFileStem(candidate), maxLength: 118)
    }

    nonisolated static func cleanImportDescription(_ rawValue: String) -> String {
        let normalized = normalizedSpaces(rawValue)
        guard !normalized.isEmpty else { return "" }

        let markerPatterns = [
            #"\bcomment\s+[“"']?"#,
            #"\bkomen\s+[“"']?"#,
            #"\bdm\s+"#,
            #"\bif you don"#,
            #"\blink in (my )?bio"#,
            #"\bfollow for\b"#
        ]
        var cutIndex = normalized.endIndex
        for pattern in markerPatterns {
            if let range = normalized.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                if range.lowerBound < cutIndex {
                    cutIndex = range.lowerBound
                }
            }
        }

        var cleaned = String(normalized[..<cutIndex])
            .replacingOccurrences(of: #"@[A-Za-z0-9_.]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"#[^\s#]+"#, with: " ", options: .regularExpression)
        cleaned = normalizedSpaces(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))

        if cleaned.count < 8 {
            cleaned = usefulHashtagImportTitle(from: rawValue)
        }
        if cleaned.count > 96,
           let sentenceRange = cleaned.range(of: #"^.{12,90}?[。.!?！？]"#, options: .regularExpression) {
            cleaned = String(cleaned[sentenceRange])
        }

        return stripTrailingSourceID(String(cleaned.prefix(96))).trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))
    }

    nonisolated static func usefulHashtagImportTitle(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"#([^\s#]+)"#) else { return "" }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<String>()
        var values: [String] = []

        for match in regex.matches(in: text, range: range) {
            guard let tagRange = Range(match.range(at: 1), in: text) else { continue }
            let rawTag = String(text[tagRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?，。；：！？、)]}）】》>\"'“”‘’"))
            let lowercased = rawTag.lowercased()
            guard !rawTag.isEmpty,
                  !genericImportHashtags.contains(lowercased),
                  seen.insert(lowercased).inserted
            else { continue }
            values.append(titleCasedImportTag(rawTag))
        }

        return values.prefix(3).joined(separator: " ")
    }

    nonisolated static func titleCasedImportTag(_ tag: String) -> String {
        tag
            .replacingOccurrences(of: #"[_-]+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map { word in
                guard let first = word.first else { return "" }
                return String(first).uppercased() + String(word.dropFirst())
            }
            .joined(separator: " ")
    }

    nonisolated static func isGenericImportTitle(_ title: String) -> Bool {
        let lowercased = title.lowercased()
        return title.isEmpty
            || lowercased == "video"
            || lowercased == "untitled"
            || lowercased.hasPrefix("video by ")
            || lowercased.hasPrefix("instagram reel")
    }

    nonisolated static func sanitizeImportFileStem(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
        let sanitized = stripTrailingSourceID(name)
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .replacingOccurrences(of: "｜", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))
        return sanitized.isEmpty ? "Imported Video" : sanitized
    }

    nonisolated static func stripTrailingSourceID(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+\[(?:BV[0-9A-Za-z]+|[A-Za-z0-9_-]{11})\]\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func normalizedSpaces(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func compactImportFileStem(_ stem: String, maxLength: Int) -> String {
        guard stem.count > maxLength else { return stem }
        let suffix = stem.suffix(12)
        let prefixCount = max(1, maxLength - suffix.count - 3)
        let prefix = String(stem.prefix(prefixCount)).trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))
        return "\(prefix) - \(suffix)"
    }

    nonisolated static func uniqueImportVideoURL(in directory: URL, stem: String, preferredExtension: String) -> URL {
        let cleanExtension = preferredExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let fileExtension = cleanExtension.isEmpty ? "mp4" : cleanExtension
        var candidate = directory.appendingPathComponent("\(stem).\(fileExtension)")
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem) - \(String(format: "%02d", suffix)).\(fileExtension)")
            suffix += 1
        }

        return candidate
    }

    nonisolated static func fileStem(from filename: String) -> String {
        let lastComponent = filename.components(separatedBy: CharacterSet(charactersIn: "/\\")).last ?? filename
        return URL(fileURLWithPath: lastComponent).deletingPathExtension().lastPathComponent
    }

    nonisolated static func fileExtension(from filename: String, fallback: String) -> String {
        let lastComponent = filename.components(separatedBy: CharacterSet(charactersIn: "/\\")).last ?? filename
        let ext = URL(fileURLWithPath: lastComponent).pathExtension
        return ext.isEmpty ? fallback : ext
    }
}
