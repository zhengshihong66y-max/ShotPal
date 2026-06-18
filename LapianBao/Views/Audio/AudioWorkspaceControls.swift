//
//  AudioWorkspaceControls.swift
//  LapianBao
//
//  Header and filter controls for the sound-effect workspace.
//

import SwiftUI

extension AudioWorkspaceView {
    func audioHeader() -> some View {
        LibraryToolbar(placeholder: "", text: $searchText, searchExpands: false) {
            audioTagFilterButton

            if !selectedAudioTagKeys.isEmpty {
                Button {
                    selectedAudioTagKeys.removeAll()
                } label: {
                    audioToolbarIcon(systemName: "xmark.circle", size: 12)
                }
                .buttonStyle(.plain)
                .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
                .contentShape(Rectangle())
                .help("清除筛选")
            }
        }
    }

    var audioTagFilterButton: some View {
        Button {
            isAudioTagFilterBarPresented.toggle()
        } label: {
            audioToolbarIcon(
                systemName: selectedAudioTagFilterCount == 0 ? "tag" : "tag.fill",
                size: 12,
                tint: isAudioTagFilterBarPresented || selectedAudioTagFilterCount > 0
                    ? Design.neutralStrongAccent
                    : Design.libraryToolbarIconTint
            )
                .overlay(alignment: .topTrailing) {
                    if selectedAudioTagFilterCount > 0 {
                        libraryToolbarBadge(selectedAudioTagFilterCount)
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(width: Design.libraryToolbarButtonSlotWidth, height: Design.libraryToolbarButtonSlotHeight)
        .contentShape(Rectangle())
        .help("标签筛选")
    }

    var audioTagQuickFilterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            let tagValues = audioFilterTags
            let tagCounts = audioDynamicTagCountsByName(for: tagValues)
            if tagValues.isEmpty {
                HStack(spacing: 8) {
                    Text("暂无声音标签")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 28, alignment: .leading)
            } else {
                let primaryTags = primaryAudioTagValues(from: tagValues)
                let secondaryTags = secondaryAudioTagValues(from: tagValues)
                let selectedCategoryKeys = selectedAudioCategoryTagKeys
                let availableSecondaryTagKeys = availableAudioTagKeys(matching: selectedCategoryKeys)

                WrappingFilterChipGroup {
                    ForEach(primaryTags, id: \.self) { tag in
                        audioTagChoiceChip(tag, count: tagCounts[tag])
                    }
                }
                .layoutPriority(1)

                if !secondaryTags.isEmpty {
                    WrappingFilterChipGroup {
                        ForEach(secondaryTags, id: \.self) { tag in
                            let tagKey = normalizedSearch(tag)
                            audioTagChoiceChip(
                                tag,
                                isEnabled: selectedAudioTagKeys.contains(tagKey)
                                    || selectedCategoryKeys.isEmpty
                                    || availableSecondaryTagKeys.contains(tagKey),
                                count: tagCounts[tag]
                            )
                        }
                    }
                    .padding(.top, 1)
                }
            }
        }
        .padding(.horizontal, Design.libraryContentInset)
        .padding(.vertical, 10)
    }

    func audioTagChoiceChip(_ tag: String, isEnabled: Bool = true, count: Int? = nil) -> some View {
        let tagKey = normalizedSearch(tag)
        return QuickFilterChoiceChip(
            title: tag,
            count: count,
            isSelected: selectedAudioTagKeys.contains(tagKey)
        ) {
            toggleAudioTagFilter(tag)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.34)
    }

    func audioToolbarIcon(
        systemName: String,
        size: CGFloat,
        tint: Color = Design.libraryToolbarIconTint
    ) -> some View {
        libraryToolbarIcon(systemName: systemName, size: size, tint: tint)
    }
}
