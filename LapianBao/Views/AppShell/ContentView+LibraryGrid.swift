//
//  ContentView+LibraryGrid.swift
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
    @ViewBuilder
    func videoGrid(isCompact: Bool, framed: Bool = true) -> some View {
        let columns = libraryGridColumns
        let videos = visibleLibraryVideos

        let content = VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: Design.libraryToolbarButtonGap) {
                librarySearchField
                    .layoutPriority(1)

                importButton
                tagFilterMenu
                sortMenu
            }
            .frame(minHeight: 26)
            .padding(.horizontal, 14)

            ScrollView {
                Group {
                    if libraryStore.sortOption == .importDate {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(importDateVideoSections) { section in
                                VStack(alignment: .leading, spacing: 0) {
                                    dateDivider(section.title)

                                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                                        ForEach(section.videos) { video in
                                            videoTile(video)
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                            ForEach(videos) { video in
                                videoTile(video)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                .padding(.horizontal, 14)
            }
            .scrollIndicators(.hidden)
            .background(HiddenScrollIndicators())
        }
        .padding(.top, Design.libraryToolbarTop)
        .padding(.bottom, 14)

        if framed {
            content.contentPanel()
        } else {
            content
        }
    }

    var libraryGridColumns: [GridItem] {
        return Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10),
            count: 2
        )
    }

    var visibleLibraryVideos: [VideoItem] {
        let query = normalizedSearch(librarySearchText)
        guard !query.isEmpty else { return libraryStore.filteredVideos }

        return libraryStore.filteredVideos.filter { video in
            let tags = libraryStore.tagsByVideoPath[video.url.path, default: []]
            return normalizedSearch(videoDisplayName(for: video)).contains(query)
                || normalizedSearch(video.name).contains(query)
                || tags.contains { normalizedSearch($0).contains(query) }
                || normalizedSearch(sourcePlatformName(for: video) ?? "").contains(query)
        }
    }

    var librarySearchField: some View {
        LibraryToolbarSearchField(placeholder: "搜索视频、标签", text: $librarySearchText)
    }

    var importDateVideoSections: [VideoDateSection] {
        var sections: [VideoDateSection] = []
        var sectionIndexByID: [String: Int] = [:]

        for video in visibleLibraryVideos {
            let section = importDateSection(for: video)

            if let index = sectionIndexByID[section.id] {
                sections[index].videos.append(video)
            } else {
                sectionIndexByID[section.id] = sections.count
                sections.append(VideoDateSection(id: section.id, title: section.title, videos: [video]))
            }
        }

        return sections
    }

    func importDateSection(for video: VideoItem) -> (id: String, title: String) {
        guard let date = libraryStore.metadataByVideoPath[video.url.path]?.createdAt else {
            return ("unknown", "日期未知")
        }
        let startOfDay = Calendar.current.startOfDay(for: date)
        let id = String(Int(startOfDay.timeIntervalSince1970))
        let title = DateFormatter.localizedString(from: startOfDay, dateStyle: .medium, timeStyle: .none)
        return (id, title)
    }

    func dateDivider(_ title: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 10)
    }

    var importButton: some View {
        Button {
            libraryStore.prewarmSavedCollectionCookieCache()
            importEndpointText = libraryStore.instagramImportEndpoint
            autoFillClipboardURL()
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                isImportSheetPresented = true
            }
        } label: {
            libraryToolbarIcon(systemName: "arrow.down.circle", size: 13)
        }
        .buttonStyle(.plain)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
        .contentShape(Rectangle())
        .help("下载视频")
    }

    var tagFilterMenu: some View {
        Button {
            isTagFilterMenuPresented.toggle()
        } label: {
            libraryToolbarIcon(systemName: libraryStore.selectedTags.isEmpty ? "tag" : "tag.fill", size: 12)
                .overlay(alignment: .topTrailing) {
                    if !libraryStore.selectedTags.isEmpty {
                        Text("\(libraryStore.selectedTags.count)")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -3)
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
        .contentShape(Rectangle())
        .help("标签筛选")
        .popover(isPresented: $isTagFilterMenuPresented, arrowEdge: .bottom) {
            tagFilterPopover
        }
    }

    var tagFilterPopover: some View {
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("标签筛选")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("全部") {
                    libraryStore.selectedTags.removeAll()
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .disabled(libraryStore.selectedTags.isEmpty)
            }

            if libraryStore.allTags.isEmpty {
                AppEmptyState(title: "暂无标签", style: .inline, alignment: .leading)
                    .frame(minHeight: 36)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(libraryStore.allTags, id: \.self) { tag in
                            HStack(spacing: 7) {
                                Button {
                                    libraryStore.toggleTagSelection(tag)
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: libraryStore.selectedTags.contains(tag) ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(libraryStore.selectedTags.contains(tag) ? Color.orange : .secondary)
                                            .frame(width: 15)
                                        VideoTagColorDot(tag: tag)
                                        Text(tag)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    renamingTag = tag
                                    renameInput = tag
                                } label: {
                                    Image(systemName: "pencil")
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)
                                .help("重命名标签")

                                Button(role: .destructive) {
                                    libraryStore.removeGlobalTag(tag)
                                } label: {
                                    Image(systemName: "trash")
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)
                                .help("从所有视频中删除")
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(libraryStore.selectedTags.contains(tag) ? Color.white.opacity(0.08) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 260)
                .scrollIndicators(.hidden)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    var sortMenu: some View {
        Menu {
            Section("排序方式") {
                ForEach(VideoSortOption.allCases) { option in
                    Button {
                        libraryStore.setSort(option: option)
                    } label: {
                        Label(option.title, systemImage: libraryStore.sortOption == option ? "checkmark" : "")
                    }
                }
            }

            Section("方向") {
                ForEach(VideoSortDirection.allCases) { direction in
                    Button {
                        libraryStore.setSort(direction: direction)
                    } label: {
                        Label(direction.title, systemImage: libraryStore.sortDirection == direction ? "checkmark" : direction.systemImage)
                    }
                }
            }
        } label: {
            libraryToolbarIcon(systemName: "arrow.up.arrow.down", size: 12, opticalOffsetX: 3.5)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
        .help("排序")
    }

    func libraryToolbarIcon(systemName: String, size: CGFloat, opticalOffsetX: CGFloat = 0) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Design.libraryToolbarIconTint)
            .frame(
                width: Design.libraryToolbarButtonSlotWidth,
                height: Design.libraryToolbarButtonSlotHeight,
                alignment: .center
            )
            .offset(x: opticalOffsetX)
    }

}
