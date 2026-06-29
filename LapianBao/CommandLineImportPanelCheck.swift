//
//  CommandLineImportPanelCheck.swift
//  LapianBao
//

import Darwin
import Foundation

enum CommandLineImportPanelCheck {
    nonisolated static let flag = "--lapianbao-import-panel-check"

    nonisolated struct Report: Codable {
        var status: String
        var rawText: String
        var parsedURLs: [String]
        var platformNames: [String]
        var enqueuePreflightAccepted: Bool
    }

    nonisolated static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: flag) else { return }

        let rawText = arguments.dropFirst(flagIndex + 1).first
            ?? "https://www.youtube.com/watch?v=55oPmlBq3Ok"

        let report = runCheck(rawText: rawText)
        write(report)
        Darwin.exit(report.status == "succeeded" ? 0 : 1)
    }

    private nonisolated static func runCheck(rawText: String) -> Report {
        let parsedURLs = LibraryStore.remoteImportURLs(from: rawText)
        let platformNames = parsedURLs.map { rawURL in
            URL(string: rawURL).flatMap { LibraryStore.platformName(for: $0) } ?? "Unsupported"
        }
        let recognizedSupportedURL = !parsedURLs.isEmpty && platformNames.allSatisfy { $0 != "Unsupported" }

        return Report(
            status: recognizedSupportedURL ? "succeeded" : "failed",
            rawText: rawText,
            parsedURLs: parsedURLs,
            platformNames: platformNames,
            enqueuePreflightAccepted: recognizedSupportedURL
        )
    }

    private nonisolated static func write(_ report: Report) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
}
