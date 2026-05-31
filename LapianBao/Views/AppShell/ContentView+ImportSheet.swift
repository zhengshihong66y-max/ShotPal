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

                if isNarrow {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            importInputSection
                            activeDownloadsSection
                            importHistorySection
                        }
                        .padding(18)
                    }
                    .scrollIndicators(.hidden)
                    .background(HiddenScrollIndicators())
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 14) {
                            importInputSection
                            activeDownloadsSection
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                        VStack(alignment: .leading, spacing: 14) {
                            importHistorySection
                        }
                        .frame(width: min(360, proxy.size.width * 0.38), alignment: .top)
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .padding(18)
                }
            }
        }
        .onAppear {
            libraryStore.prewarmSavedCollectionCookieCache()
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
                    Button("清空") {
                        importURLText = ""
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $importURLText)
                    .font(.body)
                    .frame(minHeight: 138, maxHeight: 190)
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
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(14)
                        .allowsHitTesting(false)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Button {
                        syncLatestInstagramSaved()
                    } label: {
                        Label(
                            isInstagramSavedSyncing ? "同步中" : "同步 IG 新收藏",
                            systemImage: "bookmark.fill"
                        )
                        .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isInstagramSavedSyncing || libraryStore.libraryURL == nil)
                    .help("从已登录的 Google Chrome 读取 Instagram 收藏页链接")

                    Button {
                        syncLatestXiaohongshuSavedVideos()
                    } label: {
                        Label(
                            isXiaohongshuSavedSyncing ? "同步中" : "同步小红书视频前 10 条",
                            systemImage: "play.rectangle.fill"
                        )
                        .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isXiaohongshuSavedSyncing || libraryStore.libraryURL == nil)
                    .help("从已登录的 Google Chrome 读取小红书收藏页里的视频笔记链接")

                    Spacer(minLength: 0)
                }

                if let instagramSavedSyncMessage {
                    Text(instagramSavedSyncMessage)
                        .font(.caption)
                        .foregroundStyle(instagramSavedSyncIsError ? Color.red.opacity(0.86) : .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let xiaohongshuSavedSyncMessage {
                    Text(xiaohongshuSavedSyncMessage)
                        .font(.caption)
                        .foregroundStyle(xiaohongshuSavedSyncIsError ? Color.red.opacity(0.86) : .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                if !importURLTokens.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: platformIconName)
                            .font(.caption)
                            .foregroundStyle(VideoSourcePlatform.color(for: detectedImportPlatform))
                        Text(detectedImportPlatformSummary)
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
                    Label(isImporting ? "继续添加" : "加入队列", systemImage: "arrow.down.circle.fill")
                        .fontWeight(.semibold)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(importURLTokens.isEmpty)

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
        .padding(16)
    }

    var activeDownloadsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("下载进度", systemImage: "arrow.down.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(importProgressSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if activeImportJobs.isEmpty {
                AppEmptyState(
                    title: "暂无进行中的下载",
                    systemImage: "checkmark.circle",
                    style: .compact
                )
                    .frame(maxWidth: .infinity, minHeight: 132)
            } else {
                if let progress = activeImportOverallProgress {
                    importLinearProgress(progress, tint: Color(red: 0.36, green: 0.70, blue: 1.00))
                } else {
                    importIndeterminateProgress(tint: Color(red: 0.36, green: 0.70, blue: 1.00))
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(activeImportJobs) { job in
                            importJobStatus(job)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .background(HiddenScrollIndicators())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var importHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("下载记录", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if importHistoryItems.isEmpty {
                AppEmptyState(
                    title: "暂无记录",
                    systemImage: "tray",
                    style: .compact
                )
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(importHistoryItems) { item in
                            importHistoryListItem(item)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .background(HiddenScrollIndicators())

                Button {
                    libraryStore.clearFinishedRemoteImports()
                } label: {
                    Label("一键清空下载记录", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

}
