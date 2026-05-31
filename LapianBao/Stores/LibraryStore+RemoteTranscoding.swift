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
