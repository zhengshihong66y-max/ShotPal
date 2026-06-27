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
            HStack(spacing: Design.libraryToolbarButtonGap) {
                Spacer(minLength: 0)
                frameAllButton
            }
            .frame(maxWidth: .infinity, minHeight: Design.libraryToolbarHeight, alignment: .leading)
            .padding(.horizontal, Design.libraryContentInset)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(videosWithCollectedFrames) { video in
                        frameFilterVideoRow(video)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, Design.libraryContentInset)
            }
            .fadingVerticalScrollIndicators(onScroll: {
                dismissLibraryCardMenusForScroll()
            })
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
            libraryToolbarIcon(
                systemName: frameFilterVideoPath == nil ? "photo.on.rectangle.angled.fill" : "photo.on.rectangle.angled",
                size: 12
            )
                .overlay(alignment: .topTrailing) {
                    if !libraryStore.collectedFrames.isEmpty {
                        libraryToolbarBadge(libraryStore.collectedFrames.count)
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
        .contentShape(Rectangle())
    }

    func frameFilterVideoRow(_ video: VideoItem) -> some View {
        let frames = libraryStore.sampledFrames(for: video)

        return HStack(alignment: .top, spacing: 8) {
            LibraryVideoTile(
                video: video,
                displayName: videoDisplayName(for: video),
                thumbnailImage: thumbnailImage(for: video),
                thumbnailRevision: thumbnailRevision(for: video),
                durationText: durationTextIfReady(for: video),
                sourcePlatform: sourcePlatformName(for: video),
                tags: libraryStore.videoTags(for: video),
                suggestedTags: libraryStore.videoTagSuggestions(for: video),
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
                onSetSourcePlatform: { platform in
                    libraryStore.setSourcePlatform(platform, for: video)
                },
                onDelete: {
                    libraryStore.removeVideo(video)
                },
                menuIdentity: video.url.path,
                menuDismissToken: libraryCardMenuDismissToken,
                onMenuPresentationChanged: { identity, isPresented in
                    handleLibraryCardMenuPresentationChange(identity, isPresented: isPresented)
                },
                dragItemProvider: { videoDragItemProvider(for: video) }
            )
            .equatable()
            .frame(width: 122)

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
                                .foregroundStyle(.white.opacity(0.78))
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

}
