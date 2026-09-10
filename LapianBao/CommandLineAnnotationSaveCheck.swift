//
//  CommandLineAnnotationSaveCheck.swift
//  LapianBao
//

import Darwin
import AppKit
import Foundation

enum CommandLineAnnotationSaveCheck {
    nonisolated static let flag = "--lapianbao-annotation-save-check"

    nonisolated struct Report: Codable {
        var status: String
        var addReturnedSuccess: Bool
        var markedDirtyWhileLoading: Bool
        var pendingAnnotationMerged: Bool
        var emptyUpdateRejected: Bool
        var controlHitTargetProtected: Bool
        var failures: [String]
    }

    nonisolated static func runIfRequested() {
        guard CommandLine.arguments.contains(flag) else { return }

        let report = MainActor.assumeIsolated {
            runCheck()
        }
        write(report)
        Darwin.exit(report.status == "succeeded" ? 0 : 1)
    }

    @MainActor
    private static func runCheck() -> Report {
        var failures: [String] = []
        checkPersistenceFailures(failures: &failures)
        let libraryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("lapianbao-annotation-save-check", isDirectory: true)
        let videoURL = libraryURL
            .appendingPathComponent("Videos", isDirectory: true)
            .appendingPathComponent("clip.mp4")
        let video = VideoItem(url: videoURL)
        let store = LibraryStore()
        store.libraryURL = libraryURL
        store.projectDataLoadState = .loading

        let addReturnedSuccess = store.addAnnotation(
            video: video,
            time: 1.25,
            text: "  loading save  ",
            kind: .frame
        )
        let markedDirtyWhileLoading = store.projectDataDirty
        let pending = store.pendingProjectDataEditsSnapshot(resolvingRelativeTo: libraryURL)
        let base = ProjectDataFile(
            sampledFrames: [],
            annotations: [
                AnnotationItem(
                    videoPath: videoURL.path,
                    videoName: video.name,
                    time: 0.5,
                    kind: .frame,
                    text: "already loaded"
                )
            ],
            audioClips: [],
            transcripts: [:],
            transcriptExports: nil,
            musicsByVideoPath: nil,
            musicDownloadJobs: nil
        )
        let merged = LibraryStore.projectDataFile(base, mergingPendingEdits: pending)
        let pendingAnnotationMerged = merged.annotations.contains { annotation in
            annotation.videoPath == videoURL.path && annotation.text == "loading save"
        }
        let emptyUpdateRejected = store.annotations.first.map {
            store.updateAnnotation($0, text: "   ") == false
        } ?? false
        let controlHitTargetProtected = PreviewKeyboardEventRouter.hasInteractiveControlAncestor(NSButton())

        if !addReturnedSuccess {
            failures.append("adding a non-empty annotation must return success")
        }
        if !markedDirtyWhileLoading {
            failures.append("annotation save during project-data loading must mark project data dirty")
        }
        if !pendingAnnotationMerged {
            failures.append("pending annotation must be merged into loaded project data")
        }
        if !emptyUpdateRejected {
            failures.append("empty annotation update must be rejected")
        }
        if !controlHitTargetProtected {
            failures.append("keyboard focus restoration must skip clicked NSControl hit targets")
        }

        return Report(
            status: failures.isEmpty ? "succeeded" : "failed",
            addReturnedSuccess: addReturnedSuccess,
            markedDirtyWhileLoading: markedDirtyWhileLoading,
            pendingAnnotationMerged: pendingAnnotationMerged,
            emptyUpdateRejected: emptyUpdateRejected,
            controlHitTargetProtected: controlHitTargetProtected,
            failures: failures
        )
    }

    @MainActor
    private static func checkPersistenceFailures(failures: inout [String]) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ShotPalPersistence-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let url = ProjectRepository.projectDataURL(in: root)
            let original = Data("{broken project".utf8)
            try original.write(to: url)
            let store = LibraryStore()
            store.libraryURL = root
            store.loadProjectData()
            if store.projectDataLoadState != .failed || store.projectPersistenceError == nil {
                failures.append("malformed project must stop autosave and report an error")
            }
            store.projectDataDirty = true
            let didFlushMalformed = store.flushProjectDataSave()
            let preservedBytes = try Data(contentsOf: url)
            if didFlushMalformed || preservedBytes != original {
                failures.append("malformed project must survive attempted flush unchanged")
            }
            try fm.removeItem(at: url)
            try fm.createDirectory(at: url, withIntermediateDirectories: false)
            store.projectDataLoadState = .loaded
            store.projectDataDirty = true
            if store.flushProjectDataSave() || !store.projectDataDirty || store.projectPersistenceError == nil {
                failures.append("write failure must retain dirty state and report failure")
            }
            let other = root.appendingPathComponent("other")
            store.applyScannedVideos(in: other, urls: [])
            if store.libraryURL != root {
                failures.append("library switch must not discard changes after a failed flush")
            }
            try fm.removeItem(at: url)
            if !store.flushProjectDataSave() || store.projectDataDirty || ProjectRepository.readProjectData(from: url) == nil {
                failures.append("retry after storage repair must commit and clear dirty state")
            }
            store.projectDataLoadState = .loading
            store.projectDataDirty = true
            if store.flushProjectDataSave() || !store.projectDataDirty {
                failures.append("flush while loading must preserve pending edits")
            }
            store.projectDataLoadState = .loaded
            store.projectDataDirty = false
            let tagsURL = ProjectRepository.videoTagsURL(in: root)
            try fm.createDirectory(at: tagsURL, withIntermediateDirectories: false)
            store.tagsByVideoPath[root.appendingPathComponent("clip.mp4").path] = ["Custom tag"]
            store.saveTagsJSON()
            if store.metadataPersistenceError == nil || store.flushProjectDataSave() {
                failures.append("metadata failure must show an error and block flush even with a clean project")
            }
            store.applyScannedVideos(in: other, urls: [])
            if store.libraryURL != root {
                failures.append("pending metadata must prevent switching libraries")
            }
            try fm.removeItem(at: tagsURL)
            if !store.flushProjectDataSave() {
                failures.append("metadata retry after storage repair must succeed")
            }
            let savedTags = ProjectRepository.readMetadata([String].self, from: tagsURL)
            if savedTags?["clip.mp4"] != ["Custom tag"] {
                failures.append("retried metadata must preserve the edited tag")
            }
            let sourceURL = ProjectRepository.sourceInfoURL(in: root)
            let source = VideoSourceInfo(platform: "YouTube", sourceURL: "https://youtu.be/test1234567", authorName: "Fixture author")
            store.sourceInfoByVideoPath[root.appendingPathComponent("clip.mp4").path] = source
            store.saveSourceInfoJSON()
            if ProjectRepository.readMetadata(VideoSourceInfo.self, from: sourceURL)?["clip.mp4"] != source {
                failures.append("source metadata must round-trip with its actual model")
            }
            LibraryStore.saveResourceAssetTags(["audio.m4a": ["Texture"]], in: root)
            if LibraryStore.loadResourceAssetTags(in: root)["audio.m4a"] != ["Texture"] {
                failures.append("resource tag adapters must use durable metadata storage")
            }
            store.projectSaveTask?.cancel()
        } catch {
            failures.append("persistence fixture failed: \(error.localizedDescription)")
        }
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
