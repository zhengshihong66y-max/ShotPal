//
//  DownloaderSelfCheckStore.swift
//  LapianBao
//
//  下载器自检领域的独立状态:自检报告、进行中的自检任务和 preflight 冷却。
//  从 LibraryStore 拆出,视图单独观察本 store,自检进度更新不再触发全局重绘。
//  纯工具型静态函数(runDownloaderSelfCheck 等)仍留在 LibraryStore+DownloaderSelfCheck.swift。
//

import Combine
import Foundation

@MainActor
final class DownloaderSelfCheckStore: ObservableObject {
    @Published var downloaderSelfCheckReport = LibraryStore.loadDownloaderSelfCheckReport()

    private var downloaderSelfCheckTask: Task<Void, Never>?
    private var lastExternalSelfCheckPreflightAt: Date?

    var isRunningSelfCheck: Bool { downloaderSelfCheckTask != nil }

    func startExternalServiceSelfCheck(force: Bool = true) {
        startExternalServiceSelfCheck(
            force: force,
            repairMode: force ? .checkLatestAndRepair : .afterFailure
        )
    }

    private func startExternalServiceSelfCheck(
        force: Bool,
        repairMode: LibraryStore.DownloaderSelfCheckRepairMode
    ) {
        guard downloaderSelfCheckTask == nil else { return }
        if !force,
           LibraryStore.isDownloaderSelfCheckFresh(downloaderSelfCheckReport),
           downloaderSelfCheckReport.status == .succeeded,
           let ytdlpPath = downloaderSelfCheckReport.ytdlpPath,
           FileManager.default.isExecutableFile(atPath: ytdlpPath) {
            return
        }

        let startedAt = Date()
        updateDownloaderSelfCheckReport(DownloaderSelfCheckReport(
            status: .running,
            checkedAt: startedAt,
            message: L10n.text("正在检查 yt-dlp 可用性"),
            progress: 0.01
        ))

        downloaderSelfCheckTask = Task { [weak self] in
            let report = await LibraryStore.runDownloaderSelfCheck(
                startedAt: startedAt,
                repairMode: repairMode,
                progressHandler: { [weak self] progressReport in
                    Task { @MainActor [weak self] in
                        guard let self, self.downloaderSelfCheckReport.isRunning else { return }
                        self.updateDownloaderSelfCheckReport(progressReport)
                    }
                }
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.updateDownloaderSelfCheckReport(report)
                self.downloaderSelfCheckTask = nil
            }
        }
    }

    func startExternalServiceSelfCheckPreflightIfNeeded() {
        guard downloaderSelfCheckTask == nil else { return }
        if let lastExternalSelfCheckPreflightAt,
           Date().timeIntervalSince(lastExternalSelfCheckPreflightAt) < LibraryStore.externalSelfCheckPreflightCooldown {
            return
        }
        lastExternalSelfCheckPreflightAt = Date()
        startExternalServiceSelfCheck(force: false)
    }

    func updateDownloaderSelfCheckReport(_ report: DownloaderSelfCheckReport) {
        downloaderSelfCheckReport = report
        LibraryStore.saveDownloaderSelfCheckReport(report)
    }
}
