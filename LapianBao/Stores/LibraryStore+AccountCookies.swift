//
//  LibraryStore+AccountCookies.swift
//  LapianBao
//
//  Summarizes and exports account cookies used by remote imports.
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
                    "请先在设置里的账号登录中用默认浏览器登录对应平台。若仍失败，请确认 Safari、Chrome、Edge、Brave 或 Firefox 已登录并允许拉片宝读取 Cookie。"
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

    nonisolated static func currentAccountCookieSummary(forceRefresh: Bool = false) async -> AccountCookieSummary {
        let cookies = await webKitAccountCookies()
        let internalSummary = accountCookieSummary(from: cookies)
        let browserSummary = await Task.detached(priority: .utility) {
            guard let cookieURL = try? cachedOrExportedChromeCookieURL(forceRefresh: forceRefresh),
                  let cookieText = try? String(contentsOf: cookieURL, encoding: .utf8)
            else { return nil as AccountCookieSummary? }
            return accountCookieSummary(fromNetscapeCookieText: cookieText)
        }.value
        return mergedAccountCookieSummary(internalSummary, browserSummary)
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
            "google.com",
            "bilibili.com",
            "biliapi.net",
            "douyin.com",
            "iesdouyin.com",
            "snssdk.com",
            "amemv.com"
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
        let bilibiliCookies = cookies.filter { cookie in
            accountCookieDomain(cookie.domain).map { $0 == "bilibili.com" || $0 == "biliapi.net" } == true
        }
        let douyinCookies = cookies.filter { cookie in
            accountCookieDomain(cookie.domain).map {
                ["douyin.com", "iesdouyin.com", "snssdk.com", "amemv.com"].contains($0)
            } == true
        }
        return AccountCookieSummary(
            instagramCookieCount: instagramCookies.count,
            xiaohongshuCookieCount: xiaohongshuCookies.count,
            youtubeCookieCount: youtubeCookies.count,
            bilibiliCookieCount: bilibiliCookies.count,
            douyinCookieCount: douyinCookies.count,
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
            hasBilibiliSession: bilibiliCookies.contains {
                ["SESSDATA", "DedeUserID", "bili_jct"].contains($0.name)
            },
            hasDouyinSession: douyinCookies.contains {
                [
                    "sessionid",
                    "sid_guard",
                    "passport_csrf_token",
                    "s_v_web_id",
                    "LOGIN_STATUS"
                ].contains($0.name)
            },
            updatedAt: Date()
        )
    }

    nonisolated static func accountCookieSummary(fromNetscapeCookieText text: String) -> AccountCookieSummary {
        var instagramCookieCount = 0
        var xiaohongshuCookieCount = 0
        var youtubeCookieCount = 0
        var bilibiliCookieCount = 0
        var douyinCookieCount = 0
        var hasInstagramSession = false
        var hasXiaohongshuSession = false
        var hasYouTubeSession = false
        var hasBilibiliSession = false
        var hasDouyinSession = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            var line = String(rawLine)
            if line.hasPrefix("#HttpOnly_") {
                line.removeFirst("#HttpOnly_".count)
            } else if line.hasPrefix("#") {
                continue
            }

            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count >= 7 else { continue }
            let domain = columns[0]
            let name = columns[5]
            guard let supportedDomain = accountCookieDomain(domain) else { continue }

            switch supportedDomain {
            case "instagram.com", "instagr.am":
                instagramCookieCount += 1
                hasInstagramSession = hasInstagramSession || ["sessionid", "ds_user_id"].contains(name)
            case "xiaohongshu.com", "xhslink.com":
                xiaohongshuCookieCount += 1
                hasXiaohongshuSession = hasXiaohongshuSession || ["web_session", "webId"].contains(name)
            case "youtube.com", "google.com":
                youtubeCookieCount += 1
                hasYouTubeSession = hasYouTubeSession || [
                    "LOGIN_INFO",
                    "SID",
                    "HSID",
                    "SSID",
                    "APISID",
                    "SAPISID",
                    "__Secure-1PSID",
                    "__Secure-3PSID"
                ].contains(name)
            case "bilibili.com", "biliapi.net":
                bilibiliCookieCount += 1
                hasBilibiliSession = hasBilibiliSession || [
                    "SESSDATA",
                    "DedeUserID",
                    "bili_jct"
                ].contains(name)
            case "douyin.com", "iesdouyin.com", "snssdk.com", "amemv.com":
                douyinCookieCount += 1
                hasDouyinSession = hasDouyinSession || [
                    "sessionid",
                    "sid_guard",
                    "passport_csrf_token",
                    "s_v_web_id",
                    "LOGIN_STATUS"
                ].contains(name)
            default:
                continue
            }
        }

        return AccountCookieSummary(
            instagramCookieCount: instagramCookieCount,
            xiaohongshuCookieCount: xiaohongshuCookieCount,
            youtubeCookieCount: youtubeCookieCount,
            bilibiliCookieCount: bilibiliCookieCount,
            douyinCookieCount: douyinCookieCount,
            hasInstagramSession: hasInstagramSession,
            hasXiaohongshuSession: hasXiaohongshuSession,
            hasYouTubeSession: hasYouTubeSession,
            hasBilibiliSession: hasBilibiliSession,
            hasDouyinSession: hasDouyinSession,
            updatedAt: Date()
        )
    }

    nonisolated static func mergedAccountCookieSummary(
        _ lhs: AccountCookieSummary,
        _ rhs: AccountCookieSummary?
    ) -> AccountCookieSummary {
        guard let rhs else { return lhs }
        return AccountCookieSummary(
            instagramCookieCount: lhs.instagramCookieCount + rhs.instagramCookieCount,
            xiaohongshuCookieCount: lhs.xiaohongshuCookieCount + rhs.xiaohongshuCookieCount,
            youtubeCookieCount: lhs.youtubeCookieCount + rhs.youtubeCookieCount,
            bilibiliCookieCount: lhs.bilibiliCookieCount + rhs.bilibiliCookieCount,
            douyinCookieCount: lhs.douyinCookieCount + rhs.douyinCookieCount,
            hasInstagramSession: lhs.hasInstagramSession || rhs.hasInstagramSession,
            hasXiaohongshuSession: lhs.hasXiaohongshuSession || rhs.hasXiaohongshuSession,
            hasYouTubeSession: lhs.hasYouTubeSession || rhs.hasYouTubeSession,
            hasBilibiliSession: lhs.hasBilibiliSession || rhs.hasBilibiliSession,
            hasDouyinSession: lhs.hasDouyinSession || rhs.hasDouyinSession,
            updatedAt: [lhs.updatedAt, rhs.updatedAt].compactMap { $0 }.max()
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
