//
//  LibraryStore+BrowserCookies.swift
//  LapianBao
//
//  Browser cookie export helpers for remote imports.
//

import AppKit
import Foundation

extension LibraryStore {
    nonisolated struct BrowserCookieCandidate: Sendable, Hashable {
        var label: String
        var browserName: String
        var bundleIdentifiers: [String]
    }

    nonisolated static func exportChromeCookiesToTemporaryFile() throws -> URL {
        try exportBrowserCookiesToTemporaryFile(
            candidate: BrowserCookieCandidate(
                label: "Chrome",
                browserName: "chrome",
                bundleIdentifiers: ["com.google.Chrome"]
            )
        )
    }

    nonisolated static func exportPreferredBrowserCookiesToTemporaryFile() throws -> URL {
        var messages: [String] = []
        for candidate in browserCookieCandidates() {
            do {
                return try exportBrowserCookiesToTemporaryFile(candidate: candidate)
            } catch {
                messages.append("\(candidate.label)：\(error.localizedDescription)")
            }
        }

        let fallback = messages.isEmpty ? "无法导出浏览器 Cookie" : messages.joined(separator: "；")
        throw InstagramSavedImportError.chromeCookieUnavailable(fallback)
    }

    nonisolated static func exportBrowserCookiesToTemporaryFile(candidate: BrowserCookieCandidate) throws -> URL {
        guard let ytdlp = localYTDLPURL() else {
            throw InstagramSavedImportError.chromeCookieUnavailable("未找到 yt-dlp，无法读取浏览器 Cookie")
        }

        let cookieURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lapianbao-\(candidate.browserName)-cookies-\(UUID().uuidString).txt")

        let exportResult = runDownloaderSelfCheckProcess(
            executableURL: ytdlp,
            arguments: [
                "--cookies-from-browser", candidate.browserName,
                "--cookies", cookieURL.path,
                "--skip-download",
                "--simulate",
                "--no-warnings"
            ],
            timeout: 28
        )
        let cookieSize = ((try? cookieURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard FileManager.default.fileExists(atPath: cookieURL.path), cookieSize > 0 else {
            try? FileManager.default.removeItem(at: cookieURL)
            throw InstagramSavedImportError.chromeCookieUnavailable(
                selfCheckFailureMessage(from: exportResult, fallback: "无法导出\(candidate.label) Cookie")
            )
        }

        return cookieURL
    }

    nonisolated static func browserCookieCandidates() -> [BrowserCookieCandidate] {
        let knownCandidates = [
            BrowserCookieCandidate(
                label: "Safari",
                browserName: "safari",
                bundleIdentifiers: ["com.apple.Safari"]
            ),
            BrowserCookieCandidate(
                label: "Chrome",
                browserName: "chrome",
                bundleIdentifiers: ["com.google.Chrome"]
            ),
            BrowserCookieCandidate(
                label: "Edge",
                browserName: "edge",
                bundleIdentifiers: ["com.microsoft.edgemac"]
            ),
            BrowserCookieCandidate(
                label: "Brave",
                browserName: "brave",
                bundleIdentifiers: ["com.brave.Browser"]
            ),
            BrowserCookieCandidate(
                label: "Firefox",
                browserName: "firefox",
                bundleIdentifiers: ["org.mozilla.firefox"]
            ),
            BrowserCookieCandidate(
                label: "Chromium",
                browserName: "chromium",
                bundleIdentifiers: ["org.chromium.Chromium"]
            ),
            BrowserCookieCandidate(
                label: "Vivaldi",
                browserName: "vivaldi",
                bundleIdentifiers: ["com.vivaldi.Vivaldi"]
            )
        ]

        let defaultCandidate = defaultBrowserBundleIdentifier()
            .flatMap { bundleIdentifier in
                knownCandidates.first { candidate in
                    candidate.bundleIdentifiers.contains(bundleIdentifier)
                }
            }

        var ordered: [BrowserCookieCandidate] = []
        if let defaultCandidate {
            ordered.append(defaultCandidate)
        }
        ordered.append(contentsOf: knownCandidates)

        var seenBrowserNames = Set<String>()
        return ordered.filter { candidate in
            seenBrowserNames.insert(candidate.browserName).inserted
        }
    }

    nonisolated static func defaultBrowserBundleIdentifier() -> String? {
        guard let url = URL(string: "https://www.instagram.com/"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url),
              let bundle = Bundle(url: appURL)
        else { return nil }
        return bundle.bundleIdentifier
    }
}
