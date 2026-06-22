//
//  LibraryStore+PythonRuntimes.swift
//  LapianBao
//
//  Installs optional Python helper environments into Application Support.
//

import CryptoKit
import Foundation

nonisolated enum PythonRuntimeError: LocalizedError {
    case requirementsMissing(String)
    case applicationSupportUnavailable
    case hostPythonMissing
    case commandFailed(String, String)
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .requirementsMissing(path):
            return "缺少 Python 依赖清单：\(path)"
        case .applicationSupportUnavailable:
            return "无法定位 Application Support 目录，不能安装 Python 运行环境"
        case .hostPythonMissing:
            return "未找到可用的 Python 3.11 以上版本，不能自动安装识别环境"
        case let .commandFailed(step, message):
            return message.isEmpty ? "\(step)失败" : "\(step)失败：\(message)"
        case let .validationFailed(message):
            return message.isEmpty ? "Python 运行环境校验失败" : "Python 运行环境校验失败：\(message)"
        }
    }
}

extension LibraryStore {
    nonisolated static func ensurePythonRuntime(
        named runtimeName: String,
        requirementsRelativePath: String,
        probeModules: [String]
    ) throws -> URL {
        if let existingPythonURL = existingPythonRuntimeURL(
            named: runtimeName,
            probeModules: probeModules
        ) {
            return existingPythonURL
        }

        guard let requirementsURL = localToolURL(relativePath: requirementsRelativePath) else {
            throw PythonRuntimeError.requirementsMissing(requirementsRelativePath)
        }
        guard FileManager.default.fileExists(atPath: requirementsURL.path) else {
            throw PythonRuntimeError.requirementsMissing(requirementsURL.path)
        }

        let runtimeURL = try appManagedPythonRuntimeURL(named: runtimeName)
        let pythonURL = runtimeURL
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python3")
        let stampURL = runtimeURL.appendingPathComponent(".lapianbao-runtime-stamp")
        let expectedStamp = try pythonRuntimeStamp(for: requirementsURL)

        if FileManager.default.isExecutableFile(atPath: pythonURL.path),
           (try? String(contentsOf: stampURL, encoding: .utf8)) == expectedStamp,
           pythonRuntimeImportsAvailable(pythonURL, modules: probeModules) {
            return pythonURL
        }

        try installPythonRuntime(
            at: runtimeURL,
            requirementsURL: requirementsURL,
            expectedStamp: expectedStamp,
            probeModules: probeModules
        )
        return pythonURL
    }

    nonisolated private static func existingPythonRuntimeURL(
        named runtimeName: String,
        probeModules: [String]
    ) -> URL? {
        let relativePaths = [
            "Tools/\(runtimeName)/bin/python3",
            "Tools/\(runtimeName)/bin/python"
        ]
        for relativePath in relativePaths {
            guard let pythonURL = localToolURL(
                relativePath: relativePath,
                mustBeExecutable: true
            ) else { continue }
            if pythonRuntimeImportsAvailable(pythonURL, modules: probeModules) {
                return pythonURL
            }
        }
        return nil
    }

    nonisolated private static func installPythonRuntime(
        at runtimeURL: URL,
        requirementsURL: URL,
        expectedStamp: String,
        probeModules: [String]
    ) throws {
        guard let hostPythonURL = hostPython3URL() else {
            throw PythonRuntimeError.hostPythonMissing
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: runtimeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fileManager.removeItem(at: runtimeURL)

        var environment = pythonRuntimeProcessEnvironment(runtimeURL: runtimeURL)
        environment["LAPIANBAO_RUNTIME_REQUIREMENTS"] = requirementsURL.path

        let venvResult = ExternalProcessRunner.run(
            executableURL: hostPythonURL,
            arguments: ["-m", "venv", runtimeURL.path],
            environment: environment,
            qualityOfService: .utility,
            timeout: 180
        )
        guard venvResult.succeeded else {
            throw PythonRuntimeError.commandFailed(
                "创建 Python 虚拟环境",
                concisePythonRuntimeError(venvResult)
            )
        }

        let pythonURL = runtimeURL
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python3")
        guard fileManager.isExecutableFile(atPath: pythonURL.path) else {
            throw PythonRuntimeError.validationFailed("虚拟环境里没有可执行的 python3")
        }

        let upgradePipResult = ExternalProcessRunner.run(
            executableURL: pythonURL,
            arguments: ["-m", "pip", "install", "--upgrade", "pip", "setuptools", "wheel"],
            environment: environment,
            qualityOfService: .utility,
            timeout: 600
        )
        guard upgradePipResult.succeeded else {
            throw PythonRuntimeError.commandFailed(
                "升级 pip",
                concisePythonRuntimeError(upgradePipResult)
            )
        }

        let installResult = ExternalProcessRunner.run(
            executableURL: pythonURL,
            arguments: ["-m", "pip", "install", "--requirement", requirementsURL.path],
            environment: environment,
            qualityOfService: .utility,
            timeout: 1_800
        )
        guard installResult.succeeded else {
            throw PythonRuntimeError.commandFailed(
                "安装 Python 依赖",
                concisePythonRuntimeError(installResult)
            )
        }

        guard pythonRuntimeImportsAvailable(pythonURL, modules: probeModules) else {
            throw PythonRuntimeError.validationFailed("依赖安装后仍无法导入需要的模块")
        }

        try expectedStamp.write(to: runtimeURL.appendingPathComponent(".lapianbao-runtime-stamp"), atomically: true, encoding: .utf8)
    }

    nonisolated private static func appManagedPythonRuntimeURL(named runtimeName: String) throws -> URL {
        guard let supportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw PythonRuntimeError.applicationSupportUnavailable
        }
        return supportURL
            .appendingPathComponent("LapianBao", isDirectory: true)
            .appendingPathComponent("PythonRuntimes", isDirectory: true)
            .appendingPathComponent(runtimeName, isDirectory: true)
    }

    nonisolated private static func hostPython3URL() -> URL? {
        if let bundledPythonURL = bundledStandalonePythonURL() {
            return bundledPythonURL
        }

        let candidateNames = ["python3.12", "python3.11", "python3.13", "python3"]
        let candidateURLs = pythonExecutableCandidateURLs(names: candidateNames)
        for candidateURL in candidateURLs where FileManager.default.isExecutableFile(atPath: candidateURL.path) {
            guard let version = pythonVersion(at: candidateURL),
                  version.major == 3,
                  version.minor >= 11
            else { continue }
            return candidateURL
        }
        return nil
    }

    nonisolated private static func bundledStandalonePythonURL() -> URL? {
#if arch(arm64)
        let pythonRelativePath = "Tools/python/cpython-3.11-aarch64-apple-darwin/bin/python3.11"
#elseif arch(x86_64)
        let pythonRelativePath = "Tools/python/cpython-3.11-x86_64-apple-darwin/bin/python3.11"
#else
        let pythonRelativePath = ""
#endif
        guard !pythonRelativePath.isEmpty,
              let pythonURL = localToolURL(
                relativePath: pythonRelativePath,
                mustBeExecutable: true
              ),
              pythonVersion(at: pythonURL)?.major == 3
        else {
            return nil
        }
        return pythonURL
    }

    nonisolated private static func pythonExecutableCandidateURLs(names: [String]) -> [URL] {
        var urls = [URL]()
        if let override = ProcessInfo.processInfo.environment["LAPIANBAO_PYTHON"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            urls.append(URL(fileURLWithPath: override))
        }

        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let commonDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        let directories = pathDirectories + commonDirectories

        for name in names {
            if name.contains("/") {
                urls.append(URL(fileURLWithPath: name))
                continue
            }
            for directory in directories {
                urls.append(URL(fileURLWithPath: directory).appendingPathComponent(name))
            }
        }
        return deduplicatedURLs(urls)
    }

    nonisolated private static func pythonVersion(at pythonURL: URL) -> (major: Int, minor: Int, patch: Int)? {
        let result = ExternalProcessRunner.run(
            executableURL: pythonURL,
            arguments: [
                "-c",
                "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')"
            ],
            timeout: 5
        )
        guard result.succeeded else { return nil }
        let parts = result.outputText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".")
            .compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1], parts.count > 2 ? parts[2] : 0)
    }

    nonisolated private static func pythonRuntimeImportsAvailable(
        _ pythonURL: URL,
        modules: [String]
    ) -> Bool {
        guard !modules.isEmpty else { return true }
        let code = modules
            .map { "__import__('\($0)')" }
            .joined(separator: "; ")
        return ExternalProcessRunner.run(
            executableURL: pythonURL,
            arguments: ["-c", code],
            environment: pythonRuntimeProcessEnvironment(runtimeURL: pythonURL.deletingLastPathComponent().deletingLastPathComponent()),
            timeout: 45
        ).succeeded
    }

    nonisolated private static func pythonRuntimeProcessEnvironment(runtimeURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let binURL = runtimeURL.appendingPathComponent("bin", isDirectory: true)
        var pathParts = [binURL.path]
        if let ffmpegDirectoryPath = localFFmpegDirectoryPath() {
            pathParts.append(ffmpegDirectoryPath)
        }
        pathParts += [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        if let currentPath = environment["PATH"], !currentPath.isEmpty {
            pathParts.append(currentPath)
        }

        environment["VIRTUAL_ENV"] = runtimeURL.path
        environment["PATH"] = pathParts.joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONIOENCODING"] = "utf-8"
        environment["PYTHONNOUSERSITE"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["PIP_DISABLE_PIP_VERSION_CHECK"] = "1"
        environment.removeValue(forKey: "PYTHONPATH")
        return environment
    }

    nonisolated private static func pythonRuntimeStamp(for requirementsURL: URL) throws -> String {
        let data = try Data(contentsOf: requirementsURL)
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return "python-runtime-v1\nrequirements=\(requirementsURL.lastPathComponent)\nsha256=\(digest)\n"
    }

    nonisolated private static func concisePythonRuntimeError(_ result: ExternalProcessRunner.Result) -> String {
        let text = [result.errorText, result.outputText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        if result.didTimeOut {
            return text.isEmpty ? "命令超时" : "命令超时：\(text)"
        }
        return text
            .split(whereSeparator: \.isNewline)
            .suffix(8)
            .joined(separator: "\n")
    }

    nonisolated private static func deduplicatedURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
