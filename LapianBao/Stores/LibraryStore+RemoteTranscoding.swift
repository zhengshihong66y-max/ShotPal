//
//  LibraryStore+RemoteTranscoding.swift
//  LapianBao
//
//  Split from LibraryStore.swift.
//

import AppKit
import AVFoundation
import Combine
import Darwin
import Foundation
import UniformTypeIdentifiers

extension LibraryStore {
    // MARK: - VP9/AV1 → H.264 转码（解决 macOS 播放兼容性）

    nonisolated struct FFProbeStreamsResponse: Decodable {
        var streams: [FFProbeStream]
    }

    nonisolated struct FFProbeStream: Decodable {
        var codecType: String?
        var width: Int?
        var height: Int?
        var rFrameRate: String?

        enum CodingKeys: String, CodingKey {
            case codecType = "codec_type"
            case width, height
            case rFrameRate = "r_frame_rate"
        }
    }

    nonisolated struct VideoConcatProbe {
        var width: Int
        var height: Int
        var frameRate: String
        var hasAudio: Bool
    }

    nonisolated static func concatenateVideosWithFFmpeg(
        _ inputURLs: [URL],
        outputURL: URL
    ) async throws -> URL {
        try await Task.detached(priority: .utility) {
            guard inputURLs.count > 1 else {
                guard let firstURL = inputURLs.first else {
                    throw RemoteImportError.invalidAPIResponse
                }
                return firstURL
            }
            guard let ffmpegURL = localFFmpegURL() else {
                throw RemoteImportError.downloaderFailed("未找到 ffmpeg，无法合并 Instagram 轮播视频")
            }

            let probes = try inputURLs.map { try videoConcatProbe(for: $0) }
            let firstProbe = probes[0]
            let includeAudio = probes.allSatisfy(\.hasAudio)
            let tmpURL = outputURL.deletingLastPathComponent()
                .appendingPathComponent(".\(outputURL.deletingPathExtension().lastPathComponent).carousel.tmp.mp4")
            try? FileManager.default.removeItem(at: tmpURL)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            var arguments = ["-hide_banner", "-loglevel", "error", "-y"]
            for inputURL in inputURLs {
                arguments += ["-i", inputURL.path]
            }

            var filters: [String] = []
            var concatInputs: [String] = []
            for index in inputURLs.indices {
                let videoLabel = "v\(index)"
                filters.append(
                    "[\(index):v]scale=\(firstProbe.width):\(firstProbe.height):force_original_aspect_ratio=decrease," +
                    "pad=\(firstProbe.width):\(firstProbe.height):(ow-iw)/2:(oh-ih)/2:color=black," +
                    "fps=\(sanitizedFFmpegFrameRate(firstProbe.frameRate)),setsar=1,format=yuv420p[\(videoLabel)]"
                )
                concatInputs.append("[\(videoLabel)]")

                if includeAudio {
                    let audioLabel = "a\(index)"
                    filters.append("[\(index):a]aresample=44100,aformat=sample_rates=44100:channel_layouts=stereo[\(audioLabel)]")
                    concatInputs.append("[\(audioLabel)]")
                }
            }
            if includeAudio {
                filters.append("\(concatInputs.joined())concat=n=\(inputURLs.count):v=1:a=1[outv][outa]")
            } else {
                filters.append("\(concatInputs.joined())concat=n=\(inputURLs.count):v=1:a=0[outv]")
            }

            arguments += [
                "-filter_complex", filters.joined(separator: ";"),
                "-map", "[outv]",
                "-c:v", "libx264",
                "-crf", "20",
                "-preset", "medium"
            ]
            if includeAudio {
                arguments += ["-map", "[outa]", "-c:a", "aac", "-b:a", "192k"]
            } else {
                arguments += ["-an"]
            }
            arguments += ["-movflags", "+faststart", tmpURL.path]

            let process = Process()
            process.executableURL = ffmpegURL
            process.environment = downloaderProcessEnvironment()
            process.arguments = arguments
            let errorPipe = Pipe()
            let errorCollector = PipeDataCollector()
            process.standardError = errorPipe
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                errorCollector.append(handle.availableData)
            }

            do {
                try process.run()
            } catch {
                errorPipe.fileHandleForReading.readabilityHandler = nil
                throw RemoteImportError.downloaderFailed("无法启动 ffmpeg 合并 Instagram 轮播：\(error.localizedDescription)")
            }
            process.waitUntilExit()
            errorPipe.fileHandleForReading.readabilityHandler = nil
            errorCollector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

            guard process.terminationStatus == 0,
                  FileManager.default.fileExists(atPath: tmpURL.path)
            else {
                let message = String(data: errorCollector.data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                try? FileManager.default.removeItem(at: tmpURL)
                throw RemoteImportError.downloaderFailed(
                    message?.isEmpty == false
                        ? "Instagram 轮播合并失败：\(message!)"
                        : "Instagram 轮播合并失败"
                )
            }

            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.moveItem(at: tmpURL, to: outputURL)
            return outputURL
        }.value
    }

    nonisolated static func videoConcatProbe(for url: URL) throws -> VideoConcatProbe {
        let ffprobePath = "/opt/homebrew/bin/ffprobe"
        guard FileManager.default.isExecutableFile(atPath: ffprobePath) else {
            throw RemoteImportError.downloaderFailed("未找到 ffprobe，无法检查 Instagram 轮播视频")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "error",
            "-show_entries", "stream=codec_type,width,height,r_frame_rate",
            "-of", "json",
            url.path
        ]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        guard (try? process.run()) != nil else {
            throw RemoteImportError.downloaderFailed("无法启动 ffprobe 检查 Instagram 轮播视频")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RemoteImportError.downloaderFailed("无法读取 Instagram 轮播视频参数")
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let response = try JSONDecoder().decode(FFProbeStreamsResponse.self, from: data)
        guard let video = response.streams.first(where: { $0.codecType == "video" }),
              let width = video.width,
              let height = video.height,
              width > 0,
              height > 0
        else {
            throw RemoteImportError.downloaderFailed("Instagram 轮播视频缺少可合并的视频轨")
        }

        return VideoConcatProbe(
            width: width,
            height: height,
            frameRate: video.rFrameRate ?? "30",
            hasAudio: response.streams.contains { $0.codecType == "audio" }
        )
    }

    nonisolated static func sanitizedFFmpegFrameRate(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "0/0" else { return "30" }
        return trimmed
    }

    nonisolated static func transcodeToH264IfNeeded(
        _ url: URL,
        progressCallback: (@Sendable (Double?) -> Void)? = nil
    ) async -> URL? {
        await Task.detached(priority: .utility) {
            let ffprobePath = "/opt/homebrew/bin/ffprobe"
            guard FileManager.default.isExecutableFile(atPath: ffprobePath) else { return nil }

            // 用 ffprobe 探测视频流编码
            let probeProcess = Process()
            probeProcess.executableURL = URL(fileURLWithPath: ffprobePath)
            probeProcess.arguments = [
                "-v", "quiet",
                "-select_streams", "v:0",
                "-show_entries", "stream=codec_name",
                "-of", "default=noprint_wrappers=1:nokey=1",
                url.path
            ]
            let probePipe = Pipe()
            let probeErrorPipe = Pipe()
            probeProcess.standardOutput = probePipe
            probeProcess.standardError = probeErrorPipe
            probeErrorPipe.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }

            guard (try? probeProcess.run()) != nil else {
                probeErrorPipe.fileHandleForReading.readabilityHandler = nil
                return nil
            }
            probeProcess.waitUntilExit()
            probeErrorPipe.fileHandleForReading.readabilityHandler = nil

            let codec = (String(
                data: probePipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            // macOS AVFoundation 在 MP4 容器中不支持 VP9 / AV1 / VP8
            let unsupported = ["vp9", "vp09", "av1", "av01", "vp8"]
            guard unsupported.contains(codec) else { return nil }

            // 通知 UI 进入转码阶段
            progressCallback?(nil)

            // 找 ffmpeg
            let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
            guard FileManager.default.isExecutableFile(atPath: ffmpegPath) else { return nil }
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0

            // 先输出到临时文件，避免和原文件重名冲突
            let stem = url.deletingPathExtension().lastPathComponent
            let tmpURL = url.deletingLastPathComponent()
                .appendingPathComponent("\(stem).transcoding.tmp.mp4")

            let ffmpegProcess = Process()
            ffmpegProcess.executableURL = URL(fileURLWithPath: ffmpegPath)
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            ffmpegProcess.environment = env
            ffmpegProcess.arguments = [
                "-i", url.path,
                "-c:v", "libx264",
                "-crf", "23",
                "-preset", "fast",
                "-c:a", "aac",
                "-b:a", "192k",
                "-movflags", "+faststart",
                "-progress", "pipe:1",
                "-nostats",
                "-y",
                tmpURL.path
            ]
            let progressPipe = Pipe()
            let ffmpegErrorPipe = Pipe()
            ffmpegProcess.standardOutput = progressPipe
            ffmpegProcess.standardError = ffmpegErrorPipe

            let progressCollector = PipeDataCollector()
            progressPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                progressCollector.append(chunk)
                guard duration.isFinite, duration > 0,
                      let text = String(data: chunk, encoding: .utf8) else { return }
                for line in text.components(separatedBy: .newlines) {
                    guard line.hasPrefix("out_time_ms="),
                          let rawValue = Double(line.dropFirst("out_time_ms=".count)) else { continue }
                    progressCallback?(min(0.995, max(0, rawValue / 1_000_000 / duration)))
                }
            }
            ffmpegErrorPipe.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }

            guard (try? ffmpegProcess.run()) != nil else {
                progressPipe.fileHandleForReading.readabilityHandler = nil
                ffmpegErrorPipe.fileHandleForReading.readabilityHandler = nil
                return nil
            }
            ffmpegProcess.waitUntilExit()
            progressPipe.fileHandleForReading.readabilityHandler = nil
            ffmpegErrorPipe.fileHandleForReading.readabilityHandler = nil
            progressCollector.append(progressPipe.fileHandleForReading.readDataToEndOfFile())

            guard
                ffmpegProcess.terminationStatus == 0,
                FileManager.default.fileExists(atPath: tmpURL.path)
            else {
                try? FileManager.default.removeItem(at: tmpURL)
                return nil
            }
            progressCallback?(1)

            let finalURL = url.deletingLastPathComponent()
                .appendingPathComponent("\(stem).mp4")
            if finalURL.path != url.path {
                try? FileManager.default.removeItem(at: finalURL)
            }
            try? FileManager.default.removeItem(at: url)
            if (try? FileManager.default.moveItem(at: tmpURL, to: finalURL)) != nil {
                return finalURL
            }
            try? FileManager.default.removeItem(at: tmpURL)
            return nil
        }.value
    }

}
