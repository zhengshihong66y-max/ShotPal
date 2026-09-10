#!/usr/bin/env python3
"""Exercise real metadata storage using only temporary files and directories."""
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[1]
HARNESS = r'''
import Foundation
import Darwin
struct ProjectDataFile: Codable { var value: String }
enum AppEventBus { static func metadataPersistenceChanged() {} }
@main struct Check {
    static func main() throws {
        var checks: [String: Bool] = [:]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for filename in [ProjectRepository.FileName.videoTags, ProjectRepository.FileName.sourceInfo, ProjectRepository.FileName.resourceAssetTags] {
            let folder = root.appendingPathComponent(UUID().uuidString)
            let url = folder.appendingPathComponent(filename)
            let first = ["clip": ["first"]]
            let latest = ["clip": ["latest", "中文"]]
            checks[filename + ":missing_file"] = ProjectRepository.readMetadata([String].self, from: url) == nil
            checks[filename + ":write_failure_reported"] = !ProjectRepository.writeMetadata(first, to: url) && ProjectRepository.metadataFailure(in: folder) != nil
            checks[filename + ":latest_failed_write_retained"] = !ProjectRepository.writeMetadata(latest, to: url) && ProjectRepository.readMetadata([String].self, from: url) == latest
            checks[filename + ":failed_flush_blocks_exit"] = !ProjectRepository.retryMetadata(in: folder)
            checks[filename + ":other_library_is_independent"] = ProjectRepository.retryMetadata(in: root)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            checks[filename + ":repair_and_retry"] = ProjectRepository.retryMetadata(in: folder) && ProjectRepository.metadataFailure(in: folder) == nil
            checks[filename + ":latest_snapshot_on_disk"] = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: url)) == latest
            try Data("{broken".utf8).write(to: url)
            checks[filename + ":malformed_read_reported"] = ProjectRepository.readMetadata([String].self, from: url) == nil && ProjectRepository.metadataFailure(in: folder) != nil
            let cannotWrite = !ProjectRepository.writeMetadata(["new": ["pending"], "recovered": ["incomplete"]], to: url)
            let unchanged = try Data(contentsOf: url) == Data("{broken".utf8)
            checks[filename + ":malformed_bytes_preserved"] = cannotWrite && unchanged && !ProjectRepository.retryMetadata(in: folder)
            try JSONEncoder().encode(["recovered": ["backup"]]).write(to: url)
            checks[filename + ":recovered_entries_preserved"] = ProjectRepository.retryMetadata(in: folder)
                && ProjectRepository.readMetadata([String].self, from: url) == ["recovered": ["backup"], "new": ["pending"]]
            checks[filename + ":recovered_tags_keep_both_sets"] = ProjectRepository.mergeRecoveredTags(["saved", "shared"], ["shared", "pending"]) == ["saved", "shared", "pending"]
            checks[filename + ":intentional_removal_persists"] = ProjectRepository.writeMetadata([String: [String]](), to: url)
                && ProjectRepository.readMetadata([String].self, from: url) == [:]
            try Data("[]".utf8).write(to: url)
            checks[filename + ":wrong_schema_blocked"] = !ProjectRepository.writeMetadata(latest, to: url)
            try fm.removeItem(at: url)
            checks[filename + ":explicit_file_reset_allows_retry"] = ProjectRepository.retryMetadata(in: folder)
        }
        let output: [String: Any] = ["status": checks.values.allSatisfy { $0 } ? "passed" : "failed", "checks": checks]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        if checks.values.contains(false) { exit(1) }
    }
}
'''
def main():
    with tempfile.TemporaryDirectory(prefix='shotpal-metadata-') as temp:
        folder=Path(temp);source=folder/'Check.swift';source.write_text(HARNESS);binary=folder/'check'
        subprocess.run(['xcrun','swiftc','-swift-version','6','-parse-as-library',str(ROOT/'LapianBao/ProjectRepository.swift'),str(ROOT/'LapianBao/MetadataPersistence.swift'),str(source),'-o',str(binary)],check=True)
        subprocess.run([str(binary)],check=True,timeout=30)
if __name__=='__main__': main()
