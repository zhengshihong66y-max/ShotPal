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
    @State private var shortcutRevision = 0

    private static let rowHeight: CGFloat = MusicRowMetrics.rowHeight
    private static let rowHorizontalPadding: CGFloat = MusicRowMetrics.contentInsetX
    private static let rowVerticalPadding: CGFloat = MusicRowMetrics.contentInsetY
    private static let rowColumnSpacing: CGFloat = MusicRowMetrics.columnSpacing
    private static let rowIconSize: CGFloat = MusicRowMetrics.artworkSize
    private static let rowActionButtonSize: CGFloat = MusicRowMetrics.actionButtonSize
    private static let rowContentHeight: CGFloat = MusicRowMetrics.artworkSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                downloaderSelfCheckCard()

                settingsTaskCard(
                    title: "画面切分",
                    icon: "rectangle.on.rectangle",
                    countText: sceneCountText,
                    job: libraryStore.sceneBatchJob,
                    action: continueSceneBatch
                )

                settingsTaskCard(
                    title: "字幕识别",
                    icon: "text.bubble",
                    countText: transcriptCountText,
                    job: libraryStore.transcriptBatchJob,
                    action: continueTranscriptBatch
                )

                settingsTaskCard(
                    title: "音乐下载",
                    icon: "music.note.list",
                    countText: musicDownloadCountText,
                    job: libraryStore.musicDownloadBatchJob,
                    action: continueMusicDownloadBatch
                )

                shortcutSettingsCard()
            }
            .padding(.horizontal, Design.libraryContentInset)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fadingVerticalScrollIndicators()
        .onAppear {
            removeDeprecatedSettings()
        }
    }

    private func downloaderSelfCheckCard() -> some View {
        let report = libraryStore.downloaderSelfCheckReport
        return settingsCompactRow(
            icon: downloaderSelfCheckIcon(for: report),
            iconTint: downloaderSelfCheckColor(for: report),
            title: "YTDLP 自检",
            detail: downloaderSelfCheckVersionText(report),
            actionIcon: "arrow.clockwise",
            help: "刷新 YTDLP 自检",
            isDisabled: report.isRunning,
            action: { libraryStore.startExternalServiceSelfCheck() }
        )
    }

    private func shortcutSettingsCard() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: Self.rowColumnSpacing) {
                settingsRowIcon("keyboard", tint: Design.annotationAccent)

                settingsInfoColumn(
                    title: "快捷键",
                    detail: shortcutConflictCountText,
                    detailColor: shortcutConflictCount == 0 ? .secondary : Color.red
                )

                settingsActionButton(
                    systemImage: "arrow.counterclockwise",
                    help: "恢复默认快捷键",
                    action: resetAllPreviewShortcuts
                )
                .disabled(previewShortcutActionsAreDefault)
            }
            .frame(height: Self.rowContentHeight, alignment: .center)

            VStack(spacing: 0) {
                ForEach(PreviewShortcutAction.allCases) { action in
                    shortcutRow(action)
                    if action.id != PreviewShortcutAction.allCases.last?.id {
                        Divider()
                            .overlay(.white.opacity(0.06))
                    }
                }
            }
        }
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.vertical, Self.rowVerticalPadding)
        .settingsRowBackground()
    }

    private func shortcutRow(_ action: PreviewShortcutAction) -> some View {
        let conflicts = shortcutConflicts(for: action)

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                if conflicts.isEmpty {
                    Text(PreviewShortcutKeyOption.title(for: action.defaultKeyCode))
                        .font(Design.numericCaption2())
                        .foregroundStyle(.secondary)
                } else {
                    Text("冲突：\(conflicts.map(\.title).joined(separator: "、"))")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("", selection: shortcutBinding(for: action)) {
                ForEach(PreviewShortcutKeyOption.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 86)

            settingsActionButton(
                systemImage: "arrow.uturn.backward",
                tint: action.keyCode == action.defaultKeyCode ? .white.opacity(0.22) : .white.opacity(0.70),
                help: "恢复默认",
                action: {
                    AppSettings.resetPreviewShortcutKeyCode(actionRawValue: action.rawValue)
                    shortcutRevision += 1
                }
            )
            .disabled(action.keyCode == action.defaultKeyCode)
        }
        .padding(.vertical, 7)
        .id("\(action.id)-\(shortcutRevision)")
    }

    private func shortcutBinding(for action: PreviewShortcutAction) -> Binding<UInt16> {
        Binding(
            get: { action.keyCode },
            set: { keyCode in
                action.setKeyCode(keyCode)
                shortcutRevision += 1
            }
        )
    }

    private func shortcutConflicts(for action: PreviewShortcutAction) -> [PreviewShortcutAction] {
        PreviewShortcutAction.actions(for: action.keyCode).filter { $0 != action }
    }

    private var shortcutConflictCount: Int {
        var seen = Set<UInt16>()
        return PreviewShortcutAction.allCases.reduce(0) { count, action in
            guard !seen.contains(action.keyCode) else { return count }
            seen.insert(action.keyCode)
            return count + (PreviewShortcutAction.actions(for: action.keyCode).count > 1 ? 1 : 0)
        }
    }

    private var shortcutConflictCountText: String {
        shortcutConflictCount == 0 ? "无冲突" : "\(shortcutConflictCount) 组冲突"
    }

    private var previewShortcutActionsAreDefault: Bool {
        PreviewShortcutAction.allCases.allSatisfy { $0.keyCode == $0.defaultKeyCode }
    }

    private func resetAllPreviewShortcuts() {
        PreviewShortcutAction.allCases.forEach {
            AppSettings.resetPreviewShortcutKeyCode(actionRawValue: $0.rawValue)
        }
        shortcutRevision += 1
    }

    private func settingsTaskCard(
        title: String,
        icon: String,
        countText: String,
        job: TranscriptBatchJob,
        action: @escaping () -> Void
    ) -> some View {
        let running = isBatchRunning(job)

        return settingsCompactRow(
            icon: icon,
            iconTint: Design.annotationAccent,
            title: title,
            detail: batchProgressText(job, countText: countText),
            actionIcon: "play.fill",
            help: "继续进行",
            isDisabled: running,
            action: action
        )
    }

    private func settingsCompactRow(
        icon: String,
        iconTint: Color,
        title: String,
        detail: String,
        actionIcon: String,
        help: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: Self.rowColumnSpacing) {
            settingsRowIcon(icon, tint: iconTint)

            settingsInfoColumn(title: title, detail: detail)

            settingsActionButton(
                systemImage: actionIcon,
                help: help,
                action: action
            )
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.34 : 1)
        }
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.vertical, Self.rowVerticalPadding)
        .frame(height: Self.rowHeight, alignment: .center)
        .settingsRowBackground()
    }

    private func settingsInfoColumn(
        title: String,
        detail: String,
        detailColor: Color = .secondary
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(detail.isEmpty ? " " : detail)
                .font(.caption2)
                .foregroundStyle(detailColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(" ")
                .font(Design.numericCaption2())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: Self.rowContentHeight, maxHeight: Self.rowContentHeight, alignment: .leading)
    }

    private func settingsRowIcon(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: Self.rowIconSize, height: Self.rowIconSize)
            .background(tint.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 0.7)
            }
    }

    private func settingsActionButton(
        systemImage: String,
        tint: Color = .white.opacity(0.70),
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: Self.rowActionButtonSize, height: Self.rowActionButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
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
        case .idle, .running: return Design.annotationAccent
        case .succeeded: return .green
        case .failed: return .red
        }
    }

    private func downloaderSelfCheckVersionText(_ report: DownloaderSelfCheckReport) -> String {
        if report.isRunning {
            return "当前版本：检查中"
        }
        guard let version = report.ytdlpVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty
        else {
            return "当前版本：未检测"
        }
        return "当前版本：\(version)"
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

    private func isBatchRunning(_ job: TranscriptBatchJob) -> Bool {
        if case .running = job.status { return true }
        return false
    }

    private func isBatchPaused(_ job: TranscriptBatchJob) -> Bool {
        if case .paused = job.status { return true }
        return false
    }

    private func batchProgressText(_ job: TranscriptBatchJob, countText: String) -> String {
        switch job.status {
        case .idle:
            return "进度：\(countText)"
        case .running:
            return "进度：\(batchCompletionText(job)) · \(batchPercentText(job))"
        case .paused:
            return "进度：\(batchCompletionText(job)) · 已暂停"
        case .completed:
            return job.total == 0 ? "进度：无需处理" : "进度：已完成"
        case .failed(let message):
            return message.isEmpty ? "进度：失败" : "进度：失败：\(message)"
        }
    }

    private func batchCompletionText(_ job: TranscriptBatchJob) -> String {
        "\(job.completed)/\(max(job.total, job.completed))"
    }

    private func batchPercentText(_ job: TranscriptBatchJob) -> String {
        "\(Int((normalizedProgressFraction(job.progress) * 100).rounded()))%"
    }

    private func continueSceneBatch() {
        if isBatchPaused(libraryStore.sceneBatchJob) {
            libraryStore.resumeSceneBatch()
        } else {
            libraryStore.startSceneBatch(onlyMissing: true)
        }
    }

    private func continueTranscriptBatch() {
        if isBatchPaused(libraryStore.transcriptBatchJob) {
            libraryStore.resumeTranscriptBatch()
        } else {
            libraryStore.startTranscriptBatch(onlyMissing: true)
        }
    }

    private func continueMusicDownloadBatch() {
        libraryStore.startMusicDownloadBatch(types: MusicDownloadJob.DownloadType.allCases)
    }

    private func removeDeprecatedSettings() {
        AppSettings.removeExternalAPISettings()
        AppSettings.removeDeprecatedBatchAutomationSettings()
    }
}

private extension View {
    func settingsRowBackground() -> some View {
        background(.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 0.7)
            }
    }
}
