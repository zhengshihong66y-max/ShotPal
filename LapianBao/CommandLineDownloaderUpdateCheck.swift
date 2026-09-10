import Darwin
import Foundation

enum CommandLineDownloaderUpdateCheck {
    @concurrent nonisolated static func run() async -> [String: Bool] {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("LapianBao-update-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: folder) }
        var checks: [String: Bool] = [:]
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent("yt-dlp")
            let candidate = folder.appendingPathComponent("candidate")
            try fm.copyItem(at: YTDLPRuntime.archiveURL, to: target)
            let originalHash = YTDLPRuntime.digest(target)
            try Data("invalid archive".utf8).write(to: candidate)
            do {
                try LibraryStore.replaceAppManagedYTDLP(at: target, with: candidate)
                checks["invalidCandidateRejected"] = false
            } catch { checks["invalidCandidateRejected"] = true }
            checks["invalidCandidatePreservedOriginal"] = YTDLPRuntime.digest(target) == originalHash
            checks["invalidDigestRejected"] = !LibraryStore.verifySHA256Digest("invalid", for: target)
            checks["legacyUnverifiedUpdateIgnored"] = YTDLPRuntime.verifiedUpdate(at: target) == nil

            try fm.removeItem(at: candidate)
            try fm.copyItem(at: YTDLPRuntime.archiveURL, to: candidate)
            let observer = Task.detached(priority: .utility) {
                var missingReads = 0
                while !Task.isCancelled {
                    if !FileManager.default.fileExists(atPath: target.path) { missingReads += 1 }
                    usleep(100)
                }
                return missingReads
            }
            do {
                try LibraryStore.replaceAppManagedYTDLP(at: target, with: candidate)
                checks["validCandidateInstalled"] = YTDLPRuntime.digest(target) == originalHash
            } catch { checks["validCandidateInstalled"] = false }
            observer.cancel()
            checks["noReaderVisibleReplacementGap"] = await observer.value == 0
            checks["candidateConsumedByAtomicRename"] = !fm.fileExists(atPath: candidate.path)

            let receipt = YTDLPRuntime.UpdateReceipt(version: "2099.01.01", sha256: originalHash ?? "")
            try JSONEncoder().encode(receipt).write(to: YTDLPRuntime.receiptURL(for: target), options: .atomic)
            checks["matchingReceiptAccepted"] = YTDLPRuntime.verifiedUpdate(at: target) != nil
            try Data("corrupted after update".utf8).write(to: target)
            checks["tamperedUpdateRejected"] = YTDLPRuntime.verifiedUpdate(at: target) == nil
        } catch { checks["testSetupAndCleanup"] = false }
        return checks
    }
}
