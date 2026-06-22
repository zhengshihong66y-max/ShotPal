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
                    .fadingVerticalScrollIndicators()
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
            refreshSavedImportCandidatesIfNeeded()
            if !isSavedImportRefreshing {
                libraryStore.prewarmSavedCollectionCookieCache()
            }
        }
        .onChange(of: libraryStore.libraryURL) { _, libraryURL in
            guard libraryURL != nil else { return }
            prewarmSavedImportCandidatesIfPossible()
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
                        Text("清空")
                            .font(.caption2.weight(.semibold))
                            .frame(height: 22)
                    }
                    .buttonStyle(.borderless)
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
                    closeImportPanel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)

                Button {
                    startRemoteImport()
                } label: {
                    Label("下载", systemImage: "arrow.down.circle.fill")
                        .fontWeight(.semibold)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(manualImportVideos.isEmpty)
            }
            .frame(height: 30)
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
                    refreshSavedImportCandidates(restartExisting: true)
                } label: {
                    ZStack {
                        if isSavedImportRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.55)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(libraryStore.libraryURL == nil)
            }

            if isSavedImportRefreshing && pendingImportVideos.isEmpty {
                Text("请先在设置里完成 IG 或小红书账号登录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 170, alignment: .center)
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
                .fadingVerticalScrollIndicators()
                .frame(maxHeight: .infinity)
            }

            HStack(alignment: .center, spacing: 10) {
                savedImportRefreshStatusFooter

                Spacer(minLength: 10)

                Button {
                    startAllSavedImportCandidates()
                } label: {
                    Label("全部下载", systemImage: "arrow.down.circle.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(pendingImportVideos.isEmpty || isSavedImportSerialRunning)
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            .frame(height: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    var savedImportRefreshStatusFooter: some View {
        if !isSavedImportSerialRunning, let text = savedImportRefreshStatusText {
            Text(text)
                .font(.caption2)
                .foregroundStyle(savedImportRefreshStatusIsError ? Color.orange.opacity(0.92) : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 340, alignment: .leading)
        }
    }

    var savedImportRefreshStatusText: String? {
        if libraryStore.libraryURL == nil {
            return "请先打开素材库文件夹"
        }
        if isSavedImportRefreshing {
            return savedImportRefreshMessage ?? "正在拉取 IG 和小红书收藏..."
        }
        return savedImportRefreshMessage
    }

    var savedImportRefreshStatusIsError: Bool {
        libraryStore.libraryURL == nil || savedImportRefreshIsError
    }

    func pendingImportVideoRow(_ video: PendingImportVideo) -> some View {
        let tint = video.isSupported
            ? VideoSourcePlatform.color(for: video.platform)
            : Color.orange.opacity(0.86)

        return HStack(alignment: .center, spacing: 10) {
            pendingImportVideoCover(video, tint: tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(pendingImportVideoSubtitle(video))
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

                Button {
                    ignorePendingImportVideo(video)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
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

    func pendingImportVideoCover(_ video: PendingImportVideo, tint: Color) -> some View {
        ZStack {
            if let data = video.thumbnailData,
               let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.12))

                Image(systemName: VideoSourcePlatform.iconName(for: video.platform))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }

            if video.isMetadataLoading && video.thumbnailData == nil {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.48)
            }
        }
        .frame(width: 54, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: VideoSourcePlatform.iconName(for: video.platform))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: 15, height: 15)
                .background(tint.opacity(0.92))
                .clipShape(Circle())
                .padding(4)
                .opacity(video.thumbnailData == nil ? 0 : 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(tint.opacity(video.thumbnailData == nil ? 0.22 : 0.28), lineWidth: 1)
        }
    }

    func pendingImportVideoSubtitle(_ video: PendingImportVideo) -> String {
        guard let authorName = video.authorName,
              !authorName.isEmpty
        else { return video.subtitle }
        return "\(authorName) · \(video.subtitle)"
    }

    var downloadTimelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("下载队列与记录", systemImage: "arrow.down.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(downloadTimelineSummary)
                    .font(Design.numericCaption())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
                .fadingVerticalScrollIndicators()

                if finishedImportCount + failedImportCount > 0 {
                    Button {
                        libraryStore.clearFinishedRemoteImports()
                    } label: {
                        Text("清空已完成记录")
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
