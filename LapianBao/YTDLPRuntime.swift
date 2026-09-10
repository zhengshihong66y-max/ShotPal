import CryptoKit
import Foundation

/// One invocation contract for video, audio, metadata, cookies and self-checks.
/// Never execute the archive's /usr/bin/env shebang or search the host's PATH.
nonisolated enum YTDLPRuntime {
    static var toolsURL: URL {
        Bundle.main.resourceURL!
            .appendingPathComponent("RuntimeTools.bundle/Contents/Resources/Tools", isDirectory: true)
    }

    static var pythonURL: URL {
#if arch(arm64)
        toolsURL.appendingPathComponent("python/cpython-3.11-aarch64-apple-darwin/bin/python3.11")
#else
        toolsURL.appendingPathComponent("python/cpython-3.11-x86_64-apple-darwin/bin/python3.11")
#endif
    }
    static var archiveURL: URL { toolsURL.appendingPathComponent("bin/yt-dlp") }
    static var denoURL: URL { toolsURL.appendingPathComponent("bin/deno") }
    static var ffmpegURL: URL { toolsURL.appendingPathComponent("bin/ffmpeg") }
    static var ffprobeURL: URL { toolsURL.appendingPathComponent("bin/ffprobe") }
    static let unavailableMessage = L10n.text("内置下载运行环境缺失或无法启动（yt-dlp / Python / Deno / FFmpeg）。请运行下载器自检；若仍失败，请重新安装完整安装包。这不是链接公开性问题。")

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = toolsURL.appendingPathComponent("bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        for key in ["PYTHONHOME", "PYTHONPATH", "PYTHONSTARTUP", "VIRTUAL_ENV", "DYLD_LIBRARY_PATH", "DYLD_INSERT_LIBRARIES"] {
            env.removeValue(forKey: key)
        }
        env["PYTHONNOUSERSITE"] = "1"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["DENO_NO_UPDATE_CHECK"] = "1"
        return env
    }

    static func arguments(archive: URL, _ arguments: [String]) -> [String] {
        ["-I", "-B", archive.path, "--ignore-config", "--no-plugin-dirs",
         "--no-js-runtimes", "--js-runtimes", "deno:" + denoURL.path,
         "--no-remote-components", "--ffmpeg-location", ffmpegURL.deletingLastPathComponent().path] + arguments
    }

    static func configure(_ process: Process, archive: URL, arguments: [String]) {
        process.executableURL = pythonURL
        process.arguments = self.arguments(archive: archive, arguments)
        process.environment = environment
    }

    static func run(
        archive: URL, arguments: [String], timeout: TimeInterval = 20,
        processRegistry: ExternalProcessRegistry? = nil
    ) -> ExternalProcessRunner.Result {
        ExternalProcessRunner.run(executableURL: pythonURL,
                                  arguments: self.arguments(archive: archive, arguments),
                                  environment: environment, qualityOfService: .utility,
                                  timeout: timeout, processRegistry: processRegistry)
    }

    static func digest(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    struct UpdateReceipt: Codable, Sendable {
        var version: String
        var sha256: String
    }

    static func receiptURL(for archive: URL) -> URL { archive.appendingPathExtension("verified.json") }

    static func verifiedUpdate(at archive: URL) -> UpdateReceipt? {
        guard let data = try? Data(contentsOf: receiptURL(for: archive)),
              let receipt = try? JSONDecoder().decode(UpdateReceipt.self, from: data),
              receipt.sha256 == digest(archive) else { return nil }
        return receipt
    }

    /// Cheap file identity invalidates successful readiness after update/deletion/corruption.
    static func fingerprint() -> String {
        var urls = [pythonURL, archiveURL, denoURL, ffmpegURL, ffprobeURL]
        if let managed = LibraryStore.appManagedYTDLPURL() {
            urls += [managed, receiptURL(for: managed)]
        }
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey])
            return "\(url.path):\(values?.fileSize ?? -1):\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0):\(String(describing: values?.fileResourceIdentifier))"
        }.joined(separator: "|")
    }

    static func dependenciesOperational(timeout: TimeInterval) -> Bool {
        guard [pythonURL, denoURL, ffmpegURL, ffprobeURL].allSatisfy({ FileManager.default.isExecutableFile(atPath: $0.path) }) else { return false }
        return ExternalProcessRunner.run(executableURL: denoURL, arguments: ["eval", "--no-config", "--no-lock", "if (1 + 1 !== 2) Deno.exit(1)"], environment: environment, timeout: timeout).succeeded
            && ExternalProcessRunner.run(executableURL: ffmpegURL, arguments: ["-version"], environment: environment, timeout: timeout).succeeded
            && ExternalProcessRunner.run(executableURL: ffprobeURL, arguments: ["-version"], environment: environment, timeout: timeout).succeeded
    }
}

/// A cold start has one shared bounded check, with no network installation.
actor DownloaderReadiness {
    static let shared = DownloaderReadiness()
    struct Info: Sendable { var url: URL; var version: String? }
    private var pending: Task<Info?, Never>?
    private(set) var validationRuns = 0
    private var cached: (info: Info, fingerprint: String, checkedAt: Date)?

    func ready() async -> Info? {
        if let pending { return await pending.value }
        let fingerprint = YTDLPRuntime.fingerprint()
        if let cached, cached.fingerprint == fingerprint,
           Date().timeIntervalSince(cached.checkedAt) < 300 { return cached.info }
        validationRuns += 1
        let task = Task.detached(priority: .utility) { () -> Info? in
            guard let info = LibraryStore.localYTDLPInfo() else { return nil }
            return Info(url: info.url, version: info.version)
        }
        pending = task
        let result = await task.value
        pending = nil
        cached = result.map { ($0, fingerprint, Date()) }
        return result
    }
}

extension LibraryStore {
    nonisolated static func readyYTDLPURL() async -> URL? {
        guard !Task.isCancelled else { return nil }
        let info = await DownloaderReadiness.shared.ready()
        return Task.isCancelled ? nil : info?.url
    }
}
