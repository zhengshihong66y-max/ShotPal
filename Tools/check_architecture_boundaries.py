#!/usr/bin/env python3
"""Compile real Foundation boundaries and test only disposable fixtures.

The ProjectDataFile stub isolates generic JSON I/O; app-model migration remains
covered by app-level checks. No user library or UserDefaults is opened.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HARNESS = r'''
import Foundation
import Darwin
struct ProjectDataFile: Codable { var value: String }
struct Snapshot: Codable, Sendable { var value: Int; var payload: String }
@MainActor final class Gate {
    var reached = false
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async { reached = true; await withCheckedContinuation { continuation = $0 } }
    func open() { continuation?.resume(); continuation = nil }
}
@main struct Check {
    @MainActor static func main() async throws {
        var checks: [String: Bool] = [:]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("project.json")
        try ProjectRepository.writeJSON(Snapshot(value: 1, payload: "original 中文"), to: url)
        let cancelled = Task { try ProjectRepository.writeJSON(Snapshot(value: 2, payload: "cancelled"), to: url) }
        cancelled.cancel()
        do { try await cancelled.value; checks["cancelled_write_rejected"] = false }
        catch is CancellationError { checks["cancelled_write_rejected"] = true }
        checks["cancelled_write_preserves_file"] = ProjectRepository.readJSON(Snapshot.self, from: url)?.value == 1
        let invalid = directory.appendingPathComponent("missing/invalid.json")
        do { try ProjectRepository.writeJSON(Snapshot(value: 3, payload: "error"), to: invalid); checks["write_error_propagates"] = false }
        catch { checks["write_error_propagates"] = true }
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<40 { group.addTask {
                try! ProjectRepository.writeJSON(Snapshot(value: index, payload: String(repeating: "完整中文", count: 1000)), to: url)
            } }
        }
        checks["concurrent_commits_remain_valid_json"] = ProjectRepository.readJSON(Snapshot.self, from: url)?.payload == String(repeating: "完整中文", count: 1000)
        try Data("{broken".utf8).write(to: url)
        checks["malformed_json_is_not_decoded"] = ProjectRepository.readJSON(Snapshot.self, from: url) == nil
        checks["relative_path_respects_folder_boundary"] = ProjectRepository.relativePath(for: directory.path + "-other/file", base: directory).hasPrefix(directory.path)
            && ProjectRepository.relativePath(for: directory.appendingPathComponent("clip.mp4").path, base: directory) == "clip.mp4"

        let text = "识别 🎬 complete\n下一行\rfinal é"
        let bytes = Data(text.utf8)
        var allSplitsPass = true
        for split in 0...bytes.count {
            let collector = PipeLineCollector()
            let lines = collector.append(bytes.prefix(split)) + collector.append(bytes.dropFirst(split)) + collector.finish()
            allSplitsPass = allSplitsPass && lines == ["识别 🎬 complete", "下一行", "final é"] && collector.data == bytes
        }
        checks["utf8_survives_every_byte_split"] = allSplitsPass
        let byteCollector = PipeLineCollector()
        var byteLines: [String] = []
        for byte in bytes { byteLines += byteCollector.append(Data([byte])) }
        byteLines += byteCollector.finish()
        checks["utf8_survives_one_byte_reads"] = byteLines == ["识别 🎬 complete", "下一行", "final é"]

        let runner = KeyedTaskRunner(); let oldGate = Gate(); let newGate = Gate()
        runner.start("job") { await oldGate.wait() }
        while !oldGate.reached { await Task.yield() }
        checks["same_key_deduplicates"] = !runner.start("job") {}
        runner.replace("job") { await newGate.wait() }
        while !newGate.reached { await Task.yield() }
        oldGate.open()
        for _ in 0..<20 { await Task.yield() }
        checks["old_completion_preserves_replacement"] = runner.isRunning("job")
        newGate.open(); await runner.wait(for: "job")
        checks["completed_task_clears_registration"] = runner.isEmpty
        runner.start("cancel") { await Task.yield() }
        runner.cancelAll()
        checks["cancel_all_clears_registration"] = runner.isEmpty

        let processChecks = await Task.detached { () -> [String: Bool] in
            let registry = ToolProcessRegistry()
            registry.cancelRunningProcess()
            let cancelStart = Date()
            let preCancelled = ExternalProcessRunner.run(executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"], timeout: 3, processRegistry: registry)
            let cancelledBeforeStart = !preCancelled.succeeded && Date().timeIntervalSince(cancelStart) < 2
            let failed = ExternalProcessRunner.run(executableURL: URL(fileURLWithPath: "/missing/shotpal-executable"), timeout: 1)
            let output = ExternalProcessRunner.run(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf 'stdout'; printf 'stderr' >&2; exit 7"], timeout: 2)
            let began = Date()
            let timed = ExternalProcessRunner.run(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "trap '' TERM; sleep 20 & echo $!; wait"], timeout: 0.2)
            let bounded = Date().timeIntervalSince(began) < 4
            let child = Int32(timed.outputText.trimmingCharacters(in: .whitespacesAndNewlines))
            try? await Task.sleep(for: .milliseconds(300))
            let childGone = child.map { pid in
                let state = ExternalProcessRunner.run(executableURL: URL(fileURLWithPath: "/bin/ps"), arguments: ["-o", "stat=", "-p", String(pid)], timeout: 2).outputText.trimmingCharacters(in: .whitespacesAndNewlines)
                return state.isEmpty || state.hasPrefix("Z")
            } ?? false
            return ["cancellation_before_launch_stops_worker": cancelledBeforeStart,
                    "missing_executable_returns_failure": !failed.succeeded && failed.terminationStatus == nil,
                    "nonzero_exit_preserves_both_streams": output.terminationStatus == 7 && output.outputText == "stdout" && output.errorText == "stderr",
                    "timeout_is_bounded_and_not_success": timed.didTimeOut && !timed.succeeded && bounded,
                    "timeout_stops_child_process": childGone]
        }.value
        checks.merge(processChecks) { _, new in new }
        let data = try JSONSerialization.data(withJSONObject: ["status": checks.values.allSatisfy { $0 } ? "passed" : "failed", "checks": checks], options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        if checks.values.contains(false) { exit(1) }
    }
}
'''

def main():
    with tempfile.TemporaryDirectory(prefix='shotpal-architecture-') as temp:
        work = Path(temp)
        infrastructure = (ROOT / 'LapianBao/Models/LibraryInfrastructureModels.swift').read_text()
        collectors = infrastructure[infrastructure.index('nonisolated final class ToolProcessRegistry'):infrastructure.index('actor VideoMetadataQueue')]
        (work / 'Collectors.swift').write_text('import Foundation\n' + collectors)
        (work / 'Check.swift').write_text(HARNESS)
        sources = [ROOT / 'LapianBao' / name for name in ('ProjectRepository.swift', 'KeyedTaskRunner.swift', 'ExternalProcessRunner.swift', 'ExternalProcessRunner+Termination.swift')]
        binary = work / 'check'
        subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library', *map(str, sources), str(work / 'Collectors.swift'), str(work / 'Check.swift'), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True, timeout=45)

if __name__ == '__main__':
    main()
