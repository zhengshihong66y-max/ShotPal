//
//  LibraryStore+AccountCookies.swift
//  LapianBao
//
//  Owns the app-local WebKit login session used by remote imports.
//

import Foundation
import WebKit

nonisolated private final class AccountCookieFileCache: @unchecked Sendable {
    private let condition = NSCondition()
    private let timeToLive: TimeInterval
    private var cachedURL: URL?
    private var cachedAt: Date?
    private var isRefreshing = false

    init(timeToLive: TimeInterval) {
        self.timeToLive = timeToLive
    }

    func validCookieURL() -> URL? {
        condition.lock()
        let url = validCookieURLLocked(now: Date())
        condition.unlock()
        return url
    }

    func tryStartRefresh() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard !isRefreshing else { return false }
        isRefreshing = true
        return true
    }

    func waitForRefresh() -> URL? {
        condition.lock()
        while isRefreshing {
            condition.wait()
        }
        let url = validCookieURLLocked(now: Date())
        condition.unlock()
        return url
    }

    func finishRefresh(with url: URL?) {
        var oldURL: URL?
        condition.lock()
        if let url {
            oldURL = cachedURL
            cachedURL = url
            cachedAt = Date()
        }
        isRefreshing = false
        condition.broadcast()
        condition.unlock()

        if let oldURL, oldURL != url {
            try? FileManager.default.removeItem(at: oldURL)
        }
    }

    func invalidate(_ url: URL? = nil) {
        var removedURL: URL?
        condition.lock()
        if url == nil || url == cachedURL {
            removedURL = cachedURL
            cachedURL = nil
            cachedAt = nil
        }
        condition.unlock()

        if let removedURL {
            try? FileManager.default.removeItem(at: removedURL)
        }
    }

    private func validCookieURLLocked(now: Date) -> URL? {
        guard let cachedURL,
              let cachedAt,
              now.timeIntervalSince(cachedAt) < timeToLive,
              FileManager.default.fileExists(atPath: cachedURL.path),
              (((try? cachedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0)
        else { return nil }
        return cachedURL
    }
}

extension LibraryStore {
    nonisolated private static let accountCookieFileCache = AccountCookieFileCache(timeToLive: 10 * 60)

    nonisolated static func withExportedAccountCookies<T>(
        seedURLString: String,
        _ body: (URL) throws -> T
    ) throws -> T {
        let cookieURL = try cachedOrExportedAccountCookieURL(seedURLString: seedURLString)
        do {
            return try body(cookieURL)
        } catch {
            guard shouldRefreshChromeCookies(after: error) else { throw error }
            accountCookieFileCache.invalidate(cookieURL)
            let freshCookieURL = try cachedOrExportedAccountCookieURL(
                forceRefresh: true,
                seedURLString: seedURLString
            )
            return try body(freshCookieURL)
        }
    }

    nonisolated static func withExportedChromeCookies<T>(
        seedURLString: String,
        _ body: (URL) throws -> T
    ) throws -> T {
        try withExportedAccountCookies(seedURLString: seedURLString, body)
    }

    nonisolated static func prewarmAccountCookieCache() {
        Task.detached(priority: .utility) {
            _ = try? cachedOrExportedAccountCookieURL(seedURLString: "https://www.instagram.com/")
        }
    }

    nonisolated static func cachedOrExportedAccountCookieURL(
        forceRefresh: Bool = false,
        seedURLString: String
    ) throws -> URL {
        _ = seedURLString
        do {
            return try cachedOrExportedInternalAccountCookieURL(forceRefresh: forceRefresh)
        } catch {
            do {
                return try cachedOrExportedChromeCookieURL(forceRefresh: forceRefresh)
            } catch {
                throw InstagramSavedImportError.chromeCookieUnavailable(
                    "请先在设置里的账号登录中登录对应平台。若仍需回退到浏览器 Cookie，请确认 Chrome 已登录并授权拉片宝读取。"
                )
            }
        }
    }

    nonisolated static func cachedOrExportedInternalAccountCookieURL(forceRefresh: Bool = false) throws -> URL {
        if forceRefresh {
            accountCookieFileCache.invalidate()
        } else if let cachedURL = accountCookieFileCache.validCookieURL() {
            return cachedURL
        }

        while !accountCookieFileCache.tryStartRefresh() {
            if let cachedURL = accountCookieFileCache.waitForRefresh() {
                return cachedURL
            }
        }

        do {
            let cookieURL = try exportInternalAccountCookiesToTemporaryFile()
            accountCookieFileCache.finishRefresh(with: cookieURL)
            return cookieURL
        } catch {
            accountCookieFileCache.finishRefresh(with: nil)
            throw error
        }
    }

    nonisolated static func exportInternalAccountCookiesToTemporaryFile() throws -> URL {
        guard let cookies = webKitCookiesSynchronously(timeout: 8) else {
            throw InstagramSavedImportError.chromeCookieUnavailable("读取拉片宝内部登录态超时")
        }
        let supportedCookies = accountCookies(from: cookies)
        guard !supportedCookies.isEmpty else {
            throw InstagramSavedImportError.chromeCookieUnavailable("拉片宝内部还没有可用的账号 Cookie")
        }

        let cookieURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lapianbao-account-cookies-\(UUID().uuidString).txt")
        let text = netscapeCookieFileText(from: supportedCookies)
        try text.write(to: cookieURL, atomically: true, encoding: .utf8)
        return cookieURL
    }

    nonisolated static func webKitCookiesSynchronously(timeout: TimeInterval) -> [HTTPCookie]? {
        if Thread.isMainThread {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: [HTTPCookie]?
        DispatchQueue.main.async {
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                result = cookies
                semaphore.signal()
            }
        }

        guard semaphore.wait(timeout: .now() + timeout) != .timedOut else { return nil }
        return result
    }

    nonisolated static func currentAccountCookieSummary() async -> AccountCookieSummary {
        let cookies = await webKitAccountCookies()
        return accountCookieSummary(from: cookies)
    }

    nonisolated static func webKitAccountCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                    continuation.resume(returning: accountCookies(from: cookies))
                }
            }
        }
    }

    nonisolated static func clearInternalAccountCookieData() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                let dataTypes: Set<String> = [
                    WKWebsiteDataTypeCookies,
                    WKWebsiteDataTypeLocalStorage,
                    WKWebsiteDataTypeSessionStorage,
                    WKWebsiteDataTypeDiskCache,
                    WKWebsiteDataTypeMemoryCache
                ]
                WKWebsiteDataStore.default().removeData(
                    ofTypes: dataTypes,
                    modifiedSince: .distantPast
                ) {
                    accountCookieFileCache.invalidate()
                    continuation.resume()
                }
            }
        }
    }

    nonisolated static func accountCookies(from cookies: [HTTPCookie]) -> [HTTPCookie] {
        cookies.filter { cookie in
            accountCookieDomain(cookie.domain) != nil
        }
    }

    nonisolated static func accountCookieDomain(_ domain: String) -> String? {
        let normalized = domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        let supportedDomains = [
            "instagram.com",
            "instagr.am",
            "xiaohongshu.com",
            "xhslink.com",
            "youtube.com",
            "google.com"
        ]
        return supportedDomains.first { normalized == $0 || normalized.hasSuffix(".\($0)") }
    }

    nonisolated static func accountCookieSummary(from cookies: [HTTPCookie]) -> AccountCookieSummary {
        let instagramCookies = cookies.filter { cookie in
            accountCookieDomain(cookie.domain).map { $0 == "instagram.com" || $0 == "instagr.am" } == true
        }
        let xiaohongshuCookies = cookies.filter { cookie in
            accountCookieDomain(cookie.domain).map { $0 == "xiaohongshu.com" || $0 == "xhslink.com" } == true
        }
        let youtubeCookies = cookies.filter { cookie in
            accountCookieDomain(cookie.domain).map { $0 == "youtube.com" || $0 == "google.com" } == true
        }
        return AccountCookieSummary(
            instagramCookieCount: instagramCookies.count,
            xiaohongshuCookieCount: xiaohongshuCookies.count,
            youtubeCookieCount: youtubeCookies.count,
            hasInstagramSession: instagramCookies.contains { ["sessionid", "ds_user_id"].contains($0.name) },
            hasXiaohongshuSession: xiaohongshuCookies.contains { ["web_session", "webId"].contains($0.name) },
            hasYouTubeSession: youtubeCookies.contains {
                [
                    "LOGIN_INFO",
                    "SID",
                    "HSID",
                    "SSID",
                    "APISID",
                    "SAPISID",
                    "__Secure-1PSID",
                    "__Secure-3PSID"
                ].contains($0.name)
            },
            updatedAt: Date()
        )
    }

    nonisolated static func cachedAccountCookieYTDLPArguments() -> [String]? {
        guard let cookieURL = accountCookieFileCache.validCookieURL() else { return nil }
        return ["--cookies", cookieURL.path]
    }

    nonisolated static func netscapeCookieFileText(from cookies: [HTTPCookie]) -> String {
        var lines = [
            "# Netscape HTTP Cookie File",
            "# Generated by LapianBao"
        ]

        for cookie in cookies.sorted(by: { ($0.domain, $0.name) < ($1.domain, $1.name) }) {
            let rawDomain = sanitizedCookieField(cookie.domain)
            guard !rawDomain.isEmpty else { continue }
            let httpOnlyPrefix = cookie.isHTTPOnly && !rawDomain.hasPrefix("#HttpOnly_") ? "#HttpOnly_" : ""
            let includeSubdomains = cookie.domain.hasPrefix(".") ? "TRUE" : "FALSE"
            let path = sanitizedCookieField(cookie.path.isEmpty ? "/" : cookie.path)
            let secure = cookie.isSecure ? "TRUE" : "FALSE"
            let expiration = Int(cookie.expiresDate?.timeIntervalSince1970 ?? 0)
            let name = sanitizedCookieField(cookie.name)
            let value = sanitizedCookieField(cookie.value)
            guard !name.isEmpty else { continue }
            lines.append([
                "\(httpOnlyPrefix)\(rawDomain)",
                includeSubdomains,
                path,
                secure,
                String(expiration),
                name,
                value
            ].joined(separator: "\t"))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    nonisolated static func sanitizedCookieField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }
}
