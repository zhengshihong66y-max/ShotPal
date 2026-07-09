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

    private nonisolated static func write(_ report: Report) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
}
