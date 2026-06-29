//
//  CommandLineMusicRuntimeCheck.swift
//  LapianBao
//
//  Verifies the formal app can install and import music-recognition dependencies.
//

import Darwin
import Foundation

enum CommandLineMusicRuntimeCheck {
    nonisolated static let flag = "--lapianbao-music-runtime-check"

    nonisolated static func runIfRequested() {
        guard CommandLine.arguments.contains(flag) else { return }

        do {
            let pythonURL = try LibraryStore.ensurePythonRuntime(
                named: "music-env",
                requirementsRelativePath: "Tools/requirements-music.txt",
                probeModules: ["shazamio", "requests"]
            )
            let probe = ExternalProcessRunner.run(
                executableURL: pythonURL,
                arguments: [
                    "-c",
                    "import shazamio, requests, sys; print(sys.version.split()[0])"
                ],
                environment: probeEnvironment(for: pythonURL),
                timeout: 45
            )
            let succeeded = probe.succeeded
            let pythonVersion = probe.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            print("""
            {"status":"\(succeeded ? "succeeded" : "failed")","pythonPath":"\(jsonEscaped(pythonURL.path))","pythonVersion":"\(jsonEscaped(pythonVersion))","importsAvailable":\(succeeded),"error":"\(jsonEscaped(probe.errorText.trimmingCharacters(in: .whitespacesAndNewlines)))"}
            """)
            Darwin.exit(succeeded ? 0 : 1)
        } catch {
            print("""
            {"status":"failed","pythonPath":"","pythonVersion":"","importsAvailable":false,"error":"\(jsonEscaped(error.localizedDescription))"}
            """)
            Darwin.exit(1)
        }
    }

    nonisolated private static func probeEnvironment(for pythonURL: URL) -> [String: String] {
        let runtimeURL = pythonURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let binURL = runtimeURL.appendingPathComponent("bin", isDirectory: true)
        var environment = ProcessInfo.processInfo.environment
        var pathParts = [binURL.path]
        if let ffmpegDirectoryPath = LibraryStore.localFFmpegDirectoryPath() {
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
        environment.removeValue(forKey: "PYTHONPATH")
        return environment
    }

    nonisolated private static func jsonEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
