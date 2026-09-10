import AppKit
import AVFoundation
import Darwin
import Foundation

/// Real capture/audio/document exports from an explicit fixture into a disposable library.
nonisolated enum CommandLineMediaExportCheck {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--lapianbao-media-export-check"), arguments.count > index + 1 else { return }
        let source = URL(fileURLWithPath: arguments[index + 1])
        Task.detached {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shotpal-media-export-\(UUID().uuidString)")
            var checks: [String: Bool] = [:]
            var failure = ""
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let video = VideoItem(url: source)
                guard let jpeg = await LibraryStore.fullResolutionJPEGData(for: source, at: 1),
                      let image = NSBitmapImageRep(data: jpeg) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                checks["native_frame_capture"] = image.pixelsWide == 640 && image.pixelsHigh == 360
                let saved = await MainActor.run {
                    let store = LibraryStore()
                    store.libraryURL = directory
                    return store.saveImageExport(data: jpeg, video: video, time: 1, preferredExtension: "jpg")
                }
                checks["captured_frame_written"] = saved.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                let audio = try await LibraryStore.exportAudioClipFile(video: video, videoName: "Fixture", start: 1, end: 3, libraryURL: directory)
                let audioAsset = AVURLAsset(url: audio)
                let duration = try await audioAsset.load(.duration).seconds
                checks["audio_range_export_duration"] = abs(duration - 2) < 0.15
                checks["audio_range_has_track"] = !(try await audioAsset.loadTracks(withMediaType: .audio)).isEmpty
                let shot = LibraryStore.StoryboardExportShot(index: 1, start: 0, end: 4, script: "User <script> & 中文", music: "", imageData: jpeg)
                let docx = directory.appendingPathComponent("storyboard.docx")
                try LibraryStore.writeStoryboardDocx(shots: [shot], duration: 4, outputURL: docx)
                let document = ExternalProcessRunner.run(executableURL: URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-p", docx.path, "word/document.xml"], timeout: 10)
                checks["storyboard_zip_and_localized_heading"] = document.succeeded && document.outputText.contains(L10n.text("分镜填写版"))
                checks["storyboard_escapes_user_text"] = document.outputText.contains("User &lt;script&gt; &amp; 中文")
                let media = ExternalProcessRunner.run(executableURL: URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-l", docx.path], timeout: 10)
                checks["storyboard_embeds_frame"] = media.succeeded && media.outputText.contains("word/media/shot-001.jpg")
            } catch { failure = error.localizedDescription; checks["media_export_completed"] = false }
            let report: [String: Any] = ["status": checks.values.allSatisfy { $0 } ? "passed" : "failed", "checks": checks, "error": failure]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            Darwin.exit(checks.values.allSatisfy { $0 } ? 0 : 1)
        }
        dispatchMain()
    }
}
