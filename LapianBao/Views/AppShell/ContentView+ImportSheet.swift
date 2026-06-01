//
//  ContentView+ImportSheet.swift
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

extension ContentView {
    var importSheet: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let isNarrow = proxy.size.width < 760
                let leftColumnWidth = min(max(proxy.size.width * 0.42, 340), 430)

                if isNarrow {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            importInputSection
                            pendingImportVideosSection
                            downloadTimelineSection
                        }
                        .padding(18)
                    }
                    .scrollIndicators(.hidden)
                    .background(HiddenScrollIndicators())
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 14) {
                            importInputSection
                            pendingImportVideosSection
                        }
                        .padding(18)
                        .frame(width: leftColumnWidth, alignment: .top)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(Design.sidebarBg)

                        Rectangle()
                            .fill(.white.opacity(0.06))
                            .frame(width: 1)

                        downloadTimelineSection
                            .padding(18)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .background(Design.contentBg)
                    }
                }
            }
        }
        .onAppear {
            libraryStore.prewarmSavedCollectionCookieCache()
            refreshSavedImportCandidatesIfNeeded(force: true)
        }
    }

    var importInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("链接输入", systemImage: "link")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !importURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        importURLText = ""
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .help("清空")
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $importURLText)
                    .font(.callout)
                    .frame(minHeight: 72, maxHeight: 96)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    }

                if importURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("每行一个链接，支持 Instagram、YouTube、小红书、Bilibili、抖音…")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(14)
                        .allowsHitTesting(false)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                if !manualImportVideos.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: platformIconName)
                            .font(.caption)
                            .foregroundStyle(VideoSourcePlatform.color(for: detectedImportPlatform))
                        Text("\(manualImportVideos.count) 个输入链接")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .allowsTightening(true)
                    }
                    .layoutPriority(1)
                }

                Spacer(minLength: 10)

                Button {
                    startRemoteImport()
                } label: {
                    Label(isImporting ? "继续添加" : "下载输入链接", systemImage: "arrow.down.circle.fill")
                        .fontWeight(.semibold)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(manualImportVideos.isEmpty)

                Button {
                    closeImportPanel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("关闭")
            }
        }
    }

    var pendingImportVideosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("未添加收藏", systemImage: "bookmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button {
                    refreshSavedImportCandidates()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(isSavedImportRefreshing || libraryStore.libraryURL == nil)
                .help("重新拉取 IG 和小红书收藏")

                if !pendingImportVideos.isEmpty {
                    Text("\(pendingImportVideos.count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            if isSavedImportRefreshing && pendingImportVideos.isEmpty {
                VStack {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .tint(Color(red: 0.36, green: 0.70, blue: 1.00))
                        .frame(width: 180)
                }
                .frame(maxWidth: .infinity, minHeight: 170)
                .frame(maxHeight: .infinity)
            } else if pendingImportVideos.isEmpty {
                AppEmptyState(
                    title: "暂无未添加收藏",
                    systemImage: "tray",
                    style: .compact
                )
                .frame(maxWidth: .infinity, minHeight: 170)
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(pendingImportVideos) { video in
                            pendingImportVideoRow(video)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .background(HiddenScrollIndicators())
                .frame(maxHeight: .infinity)
            }

            HStack(alignment: .center, spacing: 10) {
                Spacer(minLength: 10)

                Button {
                    startAllSavedImportCandidates()
                } label: {
                    Label(isSavedImportSerialRunning ? "逐个下载中" : "全部下载", systemImage: "arrow.down.circle.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(pendingImportVideos.isEmpty || isSavedImportSerialRunning)
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    func pendingImportVideoRow(_ video: PendingImportVideo) -> some View {
        let tint = video.isSupported
            ? VideoSourcePlatform.color(for: video.platform)
            : Color.orange.opacity(0.86)

        return HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.12))

                Image(systemName: VideoSourcePlatform.iconName(for: video.platform))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 42, height: 42)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(video.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Button {
                    startRemoteImport(video)
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(video.isSupported ? Color.accentColor : .secondary)
                .help(video.isSupported ? "加入队列" : "尝试加入队列")

                Button {
                    removePendingImportVideo(video)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("移除")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 9)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    var downloadTimelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("下载队列与记录", systemImage: "arrow.down.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(downloadTimelineSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if !activeImportJobs.isEmpty {
                if let progress = activeImportOverallProgress {
                    importLinearProgress(progress, tint: Color(red: 0.36, green: 0.70, blue: 1.00))
                } else {
                    importIndeterminateProgress(tint: Color(red: 0.36, green: 0.70, blue: 1.00))
                }
            }

            if downloadTimelineJobs.isEmpty {
                AppEmptyState(
                    title: "暂无下载任务",
                    systemImage: "tray",
                    style: .compact
                )
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(downloadTimelineJobs) { job in
                            importJobStatus(job)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .background(HiddenScrollIndicators())

                if finishedImportCount + failedImportCount > 0 {
                    Button {
                        libraryStore.clearFinishedRemoteImports()
                    } label: {
                        Label("清空已完成记录", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                    .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

}
