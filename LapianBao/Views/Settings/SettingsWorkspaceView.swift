//
//  SettingsWorkspaceView.swift
//  LapianBao
//
//  Split from ContentView.swift.
//

import SwiftUI
import AVFoundation
import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

struct SettingsWorkspaceView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @AppStorage(LibraryStore.autoSceneBatchKey) private var autoSceneBatch = false
    @AppStorage(LibraryStore.autoTranscriptBatchKey) private var autoTranscriptBatch = false
    @AppStorage(LibraryStore.autoMusicDownloadBatchKey) private var autoMusicDownloadBatch = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                downloaderSelfCheckCard()

                settingsTaskCard(
                    title: "画面切分",
                    icon: "rectangle.on.rectangle",
                    countText: sceneCountText,
                    job: libraryStore.sceneBatchJob,
                    autoEnabled: $autoSceneBatch,
                    startTitle: "开始切分",
                    start: { libraryStore.startSceneBatch(onlyMissing: true) },
                    stop: { libraryStore.cancelSceneBatch() },
                    clear: { libraryStore.deleteAllSceneRecognitions() }
                )

                settingsTaskCard(
                    title: "字幕识别",
                    icon: "text.bubble",
                    countText: transcriptCountText,
                    job: libraryStore.transcriptBatchJob,
                    autoEnabled: $autoTranscriptBatch,
                    startTitle: "开始识别",
                    start: { libraryStore.startTranscriptBatch(onlyMissing: true) },
                    stop: { libraryStore.cancelTranscriptBatch() },
                    clear: { libraryStore.deleteAllTranscripts() }
                )

                settingsTaskCard(
                    title: "音乐下载",
                    icon: "music.note.list",
                    countText: musicDownloadCountText,
                    job: libraryStore.musicDownloadBatchJob,
                    autoEnabled: $autoMusicDownloadBatch,
                    startTitle: "全下载",
                    start: { libraryStore.startMusicDownloadBatch(types: MusicDownloadJob.DownloadType.allCases) },
                    stop: { libraryStore.cancelMusicDownloads() },
                    clear: { libraryStore.clearMusicDownloadState() }
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scrollIndicators(.hidden)
        .onAppear {
            removeExternalAPISettings()
        }
    }

    private func downloaderSelfCheckCard() -> some View {
        let report = libraryStore.downloaderSelfCheckReport
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: downloaderSelfCheckIcon(for: report))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(downloaderSelfCheckColor(for: report))
                    .frame(width: 18)
                Text("外部服务自检")
                    .font(.headline.weight(.semibold))
                Text(downloaderSelfCheckDateText(report))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { libraryStore.startExternalServiceSelfCheck() }) {
                    Label("立即自检", systemImage: "arrow.clockwise")
                }
                .disabled(report.isRunning)
            }

            if report.isRunning {
                ProgressView()
                    .controlSize(.small)
                    .progressViewStyle(.linear)
                    .tint(.orange)
            }

            Text(downloaderSelfCheckStatusText(report))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(5)

            if !report.serviceChecks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(report.serviceChecks) { item in
                        HStack(spacing: 7) {
                            Image(systemName: externalServiceCheckIcon(for: item.status))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(externalServiceCheckColor(for: item.status))
                                .frame(width: 14)
                            Text(item.title)
                                .font(.caption2.weight(.semibold))
                                .frame(width: 110, alignment: .leading)
                            Text(item.message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func settingsTaskCard(
        title: String,
        icon: String,
        countText: String,
        job: TranscriptBatchJob,
        autoEnabled: Binding<Bool>,
        startTitle: String,
        start: @escaping () -> Void,
        stop: @escaping () -> Void,
        clear: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 18)
                Text(title)
                    .font(.headline.weight(.semibold))
                Text(countText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle(isOn: Binding(
                    get: { autoEnabled.wrappedValue },
                    set: { enabled in
                        autoEnabled.wrappedValue = enabled
                        if enabled { start() }
                    }
                )) {
                    Text("启动自动")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
            }

            HStack(spacing: 8) {
                Button(action: start) {
                    Label(startTitle, systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBatchRunning(job))

                Spacer()

                Button(action: stop) {
                    Label("停止", systemImage: "stop.fill")
                }
                .disabled(!isBatchRunning(job) && !isBatchPaused(job))

                Button(role: .destructive, action: clear) {
                    Label("清空状态", systemImage: "trash")
                }
            }

            if shouldShowProgress(job) {
                ProgressView(value: normalizedProgressFraction(job.progress))
                    .progressViewStyle(.linear)
                    .tint(.orange)
            }

            Text(batchStatusText(job, title: title))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func downloaderSelfCheckIcon(for report: DownloaderSelfCheckReport) -> String {
        switch report.status {
        case .idle: return "arrow.down.circle"
        case .running: return "clock.arrow.circlepath"
        case .succeeded: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func downloaderSelfCheckColor(for report: DownloaderSelfCheckReport) -> Color {
        switch report.status {
        case .idle, .running: return .orange
        case .succeeded: return .green
        case .failed: return .red
        }
    }

    private func downloaderSelfCheckDateText(_ report: DownloaderSelfCheckReport) -> String {
        guard let checkedAt = report.checkedAt else { return "未检查" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: checkedAt)
    }

    private func downloaderSelfCheckStatusText(_ report: DownloaderSelfCheckReport) -> String {
        var parts = [report.message]
        if let version = report.ytdlpVersion {
            parts.append("yt-dlp \(version)")
        }
        if let title = report.youtubeProbeTitle {
            parts.append(title)
        }
        return parts.joined(separator: " · ")
    }

    private func externalServiceCheckIcon(for status: ExternalServiceSelfCheckItem.Status) -> String {
        switch status {
        case .succeeded: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func externalServiceCheckColor(for status: ExternalServiceSelfCheckItem.Status) -> Color {
        switch status {
        case .succeeded: return .green
        case .warning: return .orange
        case .failed: return .red
        }
    }

    private var sceneCountText: String {
        let completed = libraryStore.videos.filter { libraryStore.hasSceneRecognitionResult(for: $0) }.count
        return "\(completed)/\(libraryStore.videos.count)"
    }

    private var transcriptCountText: String {
        let completed = libraryStore.videos.filter { !libraryStore.transcriptSegmentsByVideoPath[$0.url.path, default: []].isEmpty }.count
        return "\(completed)/\(libraryStore.videos.count)"
    }

    private var musicDownloadCountText: String {
        let completed = libraryStore.musicDownloadJobs.filter { job in
            if case .succeeded = job.status { return true }
            return false
        }.count
        return "\(completed) 个文件"
    }

    private func shouldShowProgress(_ job: TranscriptBatchJob) -> Bool {
        switch job.status {
        case .idle:
            return false
        default:
            return true
        }
    }

    private func isBatchRunning(_ job: TranscriptBatchJob) -> Bool {
        if case .running = job.status { return true }
        return false
    }

    private func isBatchPaused(_ job: TranscriptBatchJob) -> Bool {
        if case .paused = job.status { return true }
        return false
    }

    private func batchStatusText(_ job: TranscriptBatchJob, title: String) -> String {
        switch job.status {
        case .idle:
            return "未开始"
        case .running:
            let name = job.currentVideoName ?? "准备中"
            return "\(title)进行中：\(name) · \(job.completed)/\(job.total)"
        case .paused:
            return "已暂停 · \(job.completed)/\(job.total)"
        case .completed:
            return job.total == 0 ? "暂无需要处理的项目" : "\(title)完成"
        case .failed(let message):
            return "\(title)失败：\(message)"
        }
    }

    private func removeExternalAPISettings() {
        [
            "contentAnalysisProvider",
            "openAIAPIKey",
            "openAIBaseURL",
            "openAIModel",
            "anthropicAPIKey",
            "anthropicBaseURL",
            "anthropicModel",
            "geminiAPIKey",
            "geminiModel",
            "deepSeekAPIKey",
            "deepSeekBaseURL",
            "deepSeekModel",
            "customAPIProviderName",
            "customAPIKey",
            "customAPIBaseURL",
            "customAPIModel"
        ].forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}
