import Darwin
import Foundation

/// Exercise the same bundle-only resolver/bootstrap as the UI. No installation
/// and no user media/network access unless an explicit fixture path is supplied.
enum CommandLineMusicRuntimeCheck {
    nonisolated static let flag = "--lapianbao-music-runtime-check"
    nonisolated static let sceneFlag = "--lapianbao-scene-runtime-check"

    nonisolated static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(where: { $0 == flag || $0 == sceneFlag }) else { return }
        let scene = arguments[index] == sceneFlag
        do {
            let pythonURL = try LibraryStore.bundledRecognitionPython(named: scene ? "scene" : "music")
            let fixture = arguments.dropFirst(index + 1).first
            if scene, let fixture, !fixture.hasPrefix("-") {
                let cuts = try LibraryStore.runTransNetSceneDetection(
                    for: URL(fileURLWithPath: fixture),
                    processRegistry: SceneDetectionProcessRegistry()
                )
                output(["status": "succeeded", "cutTimes": cuts, "pythonPath": pythonURL.path])
                Darwin.exit(0)
            }
            if !scene, let fixture, !fixture.hasPrefix("-") {
                Task.detached(priority: .utility) {
                    do {
                        let songs = try await LibraryStore.runMusicDetection(videoPath: fixture, onEvent: { _ in })
                        output(["status": "succeeded", "songs": songs.map { ["title": $0.title, "artist": $0.artist] },
                                "pythonPath": pythonURL.path])
                        Darwin.exit(0)
                    } catch {
                        output(["status": "failed", "error": error.localizedDescription])
                        Darwin.exit(1)
                    }
                }
                dispatchMain()
            }
            let probe = ExternalProcessRunner.run(
                executableURL: pythonURL,
                arguments: LibraryStore.recognitionArguments(["--probe", scene ? "scene" : "music"]),
                environment: LibraryStore.recognitionEnvironment,
                timeout: 90
            )
            output(["status": probe.succeeded ? "succeeded" : "failed",
                    "pythonPath": pythonURL.path, "probe": probe.outputText,
                    "error": probe.errorText, "timedOut": probe.didTimeOut])
            Darwin.exit(probe.succeeded ? 0 : 1)
        } catch {
            output(["status": "failed", "error": error.localizedDescription])
            Darwin.exit(1)
        }
    }

    nonisolated private static func output(_ value: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
}
