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
        let projection = libraryProjection
        let videos = projection.visibleVideos

        let content = VStack(alignment: .leading, spacing: 12) {
            libraryHomeToolbar

            TopChromeBoundedContent {
                if isLibrarySidebarFilterAreaPresented {
                    librarySidebarFilterArea()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let progress = libraryStore.libraryScanProgress,
                   !progress.isMusicWaveformCacheProgress {
                    libraryScanProgressCard(progress)
                        .padding(.horizontal, Design.libraryContentInset)
                        .padding(.vertical, 2)
                }

                if libraryStore.libraryURL == nil && libraryStore.libraryScanProgress == nil {
                    libraryInitialStateView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, Design.libraryContentInset)
                } else {
                    ScrollView {
                        Group {
                            if videos.isEmpty {
                                AppEmptyState(
                                    title: libraryStore.libraryScanProgress == nil ? "暂无视频素材" : "正在读取素材",
                                    systemImage: "film",
                                    style: .compact
                                )
                                .frame(maxWidth: .infinity, minHeight: 160)
                            } else if libraryStore.sortOption == .importDate {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(projection.importDateSections.enumerated()), id: \.element.id) { indexedSection in
                                        VStack(alignment: .leading, spacing: 0) {
                                            dateDivider(
                                                indexedSection.element.title,
                                                keepsHeaderPosition: indexedSection.offset == 0
                                            )

                                            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                                                ForEach(indexedSection.element.videos) { video in
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
                        .padding(.horizontal, Design.libraryContentInset)
                    }
                    .fadingVerticalScrollIndicators(onScroll: {
                        dismissLibraryCardMenusForScroll()
                    })
                }
            }
        }
        .padding(.top, Design.libraryToolbarTop)
        .padding(.bottom, 14)
        .background {
            if isLibraryTagEditing {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        exitLibraryTagEditing()
                    }
            }
        }

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

    var libraryProjection: LibraryBrowserProjection {
        libraryStore.libraryBrowserProjection(
            searchText: librarySearchText,
            selectedPlatforms: selectedLibraryPlatforms,
            selectedAuthors: selectedLibraryAuthors
        )
    }

    var libraryHomeToolbar: some View {
        LibraryToolbar(placeholder: "", text: $librarySearchText) {
            importButton
            libraryFilterVisibilityButton
            sortMenu
        }
    }

    var libraryInitialStateView: some View {
        AppEmptyState(
            title: "未选择文件夹",
            systemImage: "folder",
            style: .large
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func libraryScanProgressCard(_ progress: LibraryScanProgress) -> some View {
        GenerationProgressRow(
            message: progress.message,
            progress: progress.fraction,
            tint: Design.neutralStrongAccent,
            systemImage: "externaldrive.badge.magnifyingglass",
            compact: true,
            showStepCount: false
        )
        .padding(9)
        .background(.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.7)
        }
    }

    var visibleLibraryVideos: [VideoItem] {
        libraryProjection.visibleVideos
    }

    var libraryTagFilterOptions: [String: LibraryTagFilterOption] {
        libraryProjection.tagFilterOptions
    }

    func librarySidebarFilterArea() -> some View {
        let metrics = libraryStore.librarySidebarMetrics
        let tagOptions = libraryTagFilterOptions

        return VStack(alignment: .leading, spacing: 8) {
            libraryPlatformFilterSection(
                title: "平台",
                values: metrics.platforms,
                emptyTitle: "暂无平台"
            ) { platform in
                libraryCompactFilterChip(
                    title: platform,
                    count: metrics.platformCounts[platform, default: 0],
                    isSelected: selectedLibraryPlatforms.contains(platform),
                    tint: VideoSourcePlatform.color(for: platform)
                ) {
                    toggleLibraryPlatformFilter(platform)
                }
            }

            librarySidebarFilterSection(
                title: "作者",
                values: metrics.authors,
                emptyTitle: "暂无作者"
            ) { author in
                libraryCompactFilterChip(
                    title: author,
                    count: metrics.authorCounts[author, default: 0],
                    isSelected: selectedLibraryAuthors.contains(author),
                    tint: Design.annotationAccent
                ) {
                    toggleLibraryAuthorFilter(author)
                }
            }

            libraryTagFilterSection(
                values: libraryStore.allTags,
                emptyTitle: "暂无标签",
                tagOptions: tagOptions,
                fallbackCounts: metrics.tagCountsByKey
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, Design.libraryContentInset)
        .padding(.vertical, 2)
    }

    func libraryTagFilterSection(
        values: [String],
        emptyTitle: String,
        tagOptions: [String: LibraryTagFilterOption],
        fallbackCounts: [String: Int]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("内容")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)

            if values.isEmpty {
                Text(emptyTitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(minHeight: 28, alignment: .leading)
            } else {
                WrappingFilterChipGroup(spacing: 4, rowSpacing: 5) {
                    ForEach(values, id: \.self) { tag in
                        let option = tagOptions[tag] ?? LibraryTagFilterOption(
                            count: fallbackCounts[normalizedSearch(tag), default: 0],
                            isEnabled: true
                        )

                        if isLibraryTagEditing {
                            libraryEditableTagChip(
                                title: tag,
                                count: option.count,
                                isSelected: libraryStore.selectedTags.contains(tag)
                            )
                        } else {
                            libraryCompactFilterChip(
                                title: tag,
                                count: option.count,
                                isSelected: libraryStore.selectedTags.contains(tag),
                                isEnabled: option.isEnabled,
                                tint: Design.neutralAccent
                            ) {
                                libraryStore.toggleTagSelection(tag)
                            }
                        }
                    }

                    libraryTagEditButton
                }
                .padding(.vertical, 1)
            }
        }
    }

    func librarySidebarFilterSection<Chip: View>(
        title: String,
        values: [String],
        emptyTitle: String,
        @ViewBuilder chip: @escaping (String) -> Chip
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)

            if values.isEmpty {
                Text(emptyTitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(minHeight: 28, alignment: .leading)
            } else {
                WrappingFilterChipGroup(spacing: 4, rowSpacing: 5) {
                    ForEach(values, id: \.self) { value in
                        chip(value)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    func libraryPlatformFilterSection<Chip: View>(
        title: String,
        values: [String],
        emptyTitle: String,
        @ViewBuilder chip: @escaping (String) -> Chip
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)

            if values.isEmpty {
                Text(emptyTitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(minHeight: 28, alignment: .leading)
            } else {
                WrappingFilterChipGroup(spacing: 4, rowSpacing: 5) {
                    ForEach(values, id: \.self) { value in
                        chip(value)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    var selectedLibraryFilterCount: Int {
        selectedLibraryPlatforms.count + selectedLibraryAuthors.count + libraryStore.selectedTags.count
    }

    func libraryCompactFilterChip(
        title: String,
        count: Int,
        isSelected: Bool,
        isEnabled: Bool = true,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        let isDimmed = !isEnabled && !isSelected
        let textWidth = libraryFilterChipTextWidth(for: title)
        let countWidth = libraryFilterChipCountWidth(for: count)

        return Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: textWidth, height: 12, alignment: .leading)
                    .layoutPriority(0)

                Text("\(count)")
                    .font(Design.numericFont(size: 9, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white.opacity(0.86) : .secondary.opacity(isDimmed ? 0.34 : 0.82))
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(3)
                    .frame(width: countWidth, height: 12, alignment: .center)
            }
            .foregroundStyle(isSelected ? .white.opacity(0.94) : .secondary.opacity(isDimmed ? 0.42 : 1))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(isSelected ? Design.tagChipSelectedFill : .white.opacity(isDimmed ? 0.018 : 0.045))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? Design.tagChipSelectedStroke : .white.opacity(isDimmed ? 0.035 : 0.09), lineWidth: 0.7)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isDimmed ? 0.58 : 1)
        .fixedSize(horizontal: true, vertical: false)
    }

    func libraryEditableTagChip(
        title: String,
        count: Int,
        isSelected: Bool
    ) -> some View {
        let isRenaming = libraryTagRenameTarget == title
        let titleForeground = libraryFilterChipForeground(isSelected: isSelected)
        let textWidth = libraryFilterChipTextWidth(for: title)
        let countWidth = libraryFilterChipCountWidth(for: count)

        return HStack(spacing: 4) {
            if isRenaming {
                InlineTagRenameTextField(
                    text: $libraryTagRenameInput,
                    isFocused: focusedLibraryTagRenameTarget == title,
                    textColor: libraryFilterChipNSForeground(isSelected: isSelected),
                    onCommit: commitLibraryTagRename
                )
                .frame(width: textWidth, height: 12, alignment: .leading)
            } else {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: textWidth, height: 12, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        beginLibraryTagRename(title)
                    }
            }

            Button(role: .destructive) {
                deleteLibraryTag(title)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .heavy))
                    .foregroundStyle(libraryFilterChipCountForeground(isSelected: isSelected))
                    .frame(width: countWidth, height: 12, alignment: .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(titleForeground)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(isSelected ? Design.tagChipSelectedFill : .white.opacity(0.045))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(isSelected ? Design.tagChipSelectedStroke : .white.opacity(0.09), lineWidth: 0.7)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    var libraryTagEditButton: some View {
        Button {
            if isLibraryTagEditing {
                exitLibraryTagEditing()
            } else {
                isLibraryTagEditing = true
            }
        } label: {
            Image(systemName: isLibraryTagEditing ? "checkmark" : "pencil")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isLibraryTagEditing ? .white.opacity(0.92) : .secondary)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }

    func libraryFilterChipTextWidth(for title: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let width = (title as NSString).size(withAttributes: [.font: font]).width
        return min(116, max(1, ceil(width) + 1))
    }

    func libraryFilterChipCountWidth(for count: Int) -> CGFloat {
        let digitCount = max(1, String(count).count)
        return max(18, CGFloat(digitCount) * 7 + 8)
    }

    func libraryFilterChipForeground(isSelected: Bool) -> Color {
        isSelected ? .white.opacity(0.94) : .secondary
    }

    func libraryFilterChipCountForeground(isSelected: Bool) -> Color {
        isSelected ? .white.opacity(0.86) : .secondary.opacity(0.82)
    }

    func libraryFilterChipNSForeground(isSelected: Bool) -> NSColor {
        isSelected ? NSColor.white.withAlphaComponent(0.94) : .secondaryLabelColor
    }

    func beginLibraryTagRename(_ tag: String) {
        if libraryTagRenameTarget != nil, libraryTagRenameTarget != tag {
            commitLibraryTagRename()
        }

        isLibraryTagEditing = true
        libraryTagRenameTarget = tag
        libraryTagRenameInput = tag
        DispatchQueue.main.async {
            focusedLibraryTagRenameTarget = tag
        }
    }

    func commitLibraryTagRename() {
        guard let oldTag = libraryTagRenameTarget else { return }

        let nextTag = libraryTagRenameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nextTag.isEmpty, nextTag != oldTag {
            libraryStore.renameGlobalTag(oldTag, to: nextTag)
        }

        libraryTagRenameTarget = nil
        libraryTagRenameInput = ""
        focusedLibraryTagRenameTarget = nil
    }

    func deleteLibraryTag(_ tag: String) {
        if libraryTagRenameTarget == tag {
            libraryTagRenameTarget = nil
            libraryTagRenameInput = ""
            focusedLibraryTagRenameTarget = nil
        }

        libraryStore.removeGlobalTag(tag)
        if libraryStore.allTags.isEmpty {
            isLibraryTagEditing = false
        }
    }

    func exitLibraryTagEditing() {
        commitLibraryTagRename()
        isLibraryTagEditing = false
    }

    func sourceAuthorName(for video: VideoItem) -> String? {
        libraryStore.videoSourceAuthorName(for: video)
    }

    func toggleLibraryPlatformFilter(_ platform: String) {
        if selectedLibraryPlatforms.contains(platform) {
            selectedLibraryPlatforms.remove(platform)
        } else {
            selectedLibraryPlatforms.insert(platform)
        }
    }

    func toggleLibraryAuthorFilter(_ author: String) {
        if selectedLibraryAuthors.contains(author) {
            selectedLibraryAuthors.remove(author)
        } else {
            selectedLibraryAuthors.insert(author)
        }
    }

    var importDateVideoSections: [VideoDateSection] {
        libraryProjection.importDateSections
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

    func dateDivider(_ title: String, keepsHeaderPosition: Bool = false) -> some View {
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
        .padding(.top, keepsHeaderPosition ? Design.libraryHeaderDateDividerTopInset : Design.libraryDateDividerTopInset)
        .padding(.bottom, keepsHeaderPosition ? Design.libraryHeaderDateDividerBottomInset : Design.libraryDateDividerBottomInset)
    }

    var importButton: some View {
        Button {
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
        .accessibilityLabel("打开导入面板")
        .accessibilityIdentifier("library_import_button")
    }

    var libraryFilterVisibilityButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                isLibrarySidebarFilterAreaPresented.toggle()
            }
        } label: {
            libraryToolbarIcon(
                systemName: selectedLibraryFilterCount == 0 ? "tag" : "tag.fill",
                size: 12,
                tint: isLibrarySidebarFilterAreaPresented || selectedLibraryFilterCount > 0
                    ? Design.neutralStrongAccent
                    : Design.libraryToolbarIconTint
            )
            .overlay(alignment: .topTrailing) {
                if selectedLibraryFilterCount > 0 {
                    libraryToolbarBadge(selectedLibraryFilterCount)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
        .contentShape(Rectangle())
        .accessibilityLabel(isLibrarySidebarFilterAreaPresented ? "隐藏素材筛选" : "显示素材筛选")
        .accessibilityIdentifier("library_filter_toggle_button")
    }

    var tagFilterMenu: some View {
        Button {
            isTagFilterMenuPresented.toggle()
        } label: {
            libraryToolbarIcon(systemName: libraryStore.selectedTags.isEmpty ? "tag" : "tag.fill", size: 12)
                .overlay(alignment: .topTrailing) {
                    if !libraryStore.selectedTags.isEmpty {
                        libraryToolbarBadge(libraryStore.selectedTags.count)
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
        .contentShape(Rectangle())
        .popover(isPresented: $isTagFilterMenuPresented, arrowEdge: .bottom) {
            tagFilterPopover
        }
    }

    var tagFilterPopover: some View {
        let tagOptions = libraryTagFilterOptions

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
                            let isSelected = libraryStore.selectedTags.contains(tag)
                            let option = tagOptions[tag] ?? LibraryTagFilterOption(count: 0, isEnabled: true)
                            let isEnabled = option.isEnabled

                            HStack(spacing: 7) {
                                Button {
                                    libraryStore.toggleTagSelection(tag)
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(isSelected ? Design.neutralStrongAccent : .secondary)
                                            .frame(width: 15)
                                        Text(tag)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(!isEnabled)
                                .opacity(isEnabled ? 1 : 0.38)

                                Button {
                                    isTagFilterMenuPresented = false
                                    beginLibraryTagRename(tag)
                                } label: {
                                    Image(systemName: "pencil")
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)

                                Button(role: .destructive) {
                                    libraryStore.removeGlobalTag(tag)
                                } label: {
                                    Image(systemName: "trash")
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 260)
                .fadingVerticalScrollIndicators()
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
            libraryToolbarIcon(systemName: "arrow.up.arrow.down", size: 12, opticalOffsetX: 2)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
        .accessibilityLabel("素材排序菜单")
        .accessibilityIdentifier("library_sort_menu")
    }

}
