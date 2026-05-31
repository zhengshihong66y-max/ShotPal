//
//  ContentView+FrameFilter.swift
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
    var videosWithCollectedFrames: [VideoItem] {
        libraryStore.videos.filter { !libraryStore.sampledFrames(for: $0).isEmpty }
    }

    @ViewBuilder
    func frameVideoFilterColumn(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Spacer(minLength: 4)

                HStack(spacing: 8) {
                    frameAllButton
                }
            }
            .frame(minHeight: 22)
            .padding(.horizontal, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(videosWithCollectedFrames) { video in
                        frameFilterVideoRow(video)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 14)
            }
            .scrollIndicators(.hidden)
            .background(HiddenScrollIndicators())
            .overlay {
                if videosWithCollectedFrames.isEmpty {
                    AppEmptyState(
                        title: "暂无已收集画面",
                        systemImage: "photo.on.rectangle",
                        description: "在主页截图后，这里会出现对应视频。",
                        style: .compact,
                        minHeight: 116
                    )
                    .padding(14)
                }
            }
        }
        .padding(.top, Design.libraryToolbarTop)
        .padding(.bottom, 14)
    }

    var frameAllButton: some View {
        Button {
            frameFilterVideoPath = nil
            frameSelectedFrameID = libraryStore.collectedFrames.first?.id
        } label: {
            Image(systemName: frameFilterVideoPath == nil ? "photo.on.rectangle.angled.fill" : "photo.on.rectangle.angled")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 22)
                .overlay(alignment: .topTrailing) {
                    if !libraryStore.collectedFrames.isEmpty {
                        Text("\(libraryStore.collectedFrames.count)")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .clipShape(Capsule())
                            .offset(x: 5, y: -4)
                    }
                }
        }
        .buttonStyle(.borderless)
        .help("全部画面")
    }

    func frameFilterVideoRow(_ video: VideoItem) -> some View {
        let frames = libraryStore.sampledFrames(for: video)

        return HStack(alignment: .top, spacing: 8) {
            LibraryVideoTile(
                video: video,
                displayName: videoDisplayName(for: video),
                thumbnailImage: thumbnailImage(for: video),
                durationText: durationTextIfReady(for: video),
                sourcePlatform: sourcePlatformName(for: video),
                tags: libraryStore.tagsByVideoPath[video.url.path, default: []],
                suggestedTags: libraryStore.allTags,
                analysisItems: analysisMenuItems(for: video),
                isSelected: frameFilterVideoPath == video.url.path,
                onSelect: {
                    frameFilterVideoPath = video.url.path
                    frameSelectedFrameID = frames.first?.id
                },
                onAddTag: { tag in
                    libraryStore.addTag(tag, to: video)
                },
                onRemoveTag: { tag in
                    libraryStore.removeTag(tag, from: video)
                },
                onRunAnalysis: { kind in
                    runAnalysis(kind, for: video)
                },
                onDeleteAnalysis: { kind in
                    deleteAnalysis(kind, for: video)
                },
                onDelete: {
                    libraryStore.removeVideo(video)
                },
                dragItemProvider: { videoDragItemProvider(for: video) }
            )
            .equatable()
            .frame(width: 122)
            .help("筛选这个视频的画面")

            framePreviewColumn(frames)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(7)
        .background(frameFilterVideoPath == video.url.path ? .white.opacity(0.055) : .white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(frameFilterVideoPath == video.url.path ? 0.12 : 0.05), lineWidth: 0.7)
        }
    }

    func framePreviewColumn(_ frames: [SampledFrame]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 5)], spacing: 5) {
            ForEach(frames.prefix(12)) { frame in
                Button {
                    frameFilterVideoPath = frame.videoPath
                    frameSelectedFrameID = frame.id
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        if let image = libraryStore.thumbnailImage(for: frame) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.black.opacity(0.26)
                        }

                        if frame.kind == .screenshot {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundStyle(Design.captureFrameAccent)
                                .shadow(color: .black.opacity(0.55), radius: 1)
                                .padding(3)
                        }
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(
                                frameSelectedFrameID == frame.id
                                    ? .white.opacity(0.42)
                                    : .white.opacity(0.08),
                                lineWidth: frameSelectedFrameID == frame.id ? 1.1 : 0.7
                            )
                    }
                }
                .buttonStyle(.plain)
                .fullResolutionImageDrag {
                    libraryStore.fullResolutionFrameProvider(for: frame)
                }
                .help("\(frame.videoName) · \(clockText(frame.time))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

}
