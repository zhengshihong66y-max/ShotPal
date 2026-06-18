//
//  AudioWorkspaceView.swift
//  LapianBao
//
//  Split from ContentView.swift.
//

import SwiftUI

struct AudioWorkspaceView: View {
    @EnvironmentObject var libraryStore: LibraryStore
    let goHome: (String, Double) -> Void
    @State var selectedAudioTagKeys: Set<String> = []
    @State var isAudioTagFilterBarPresented = true
    @State var searchText = ""
    @StateObject var audioPreviewController = AudioPreviewController()

    var body: some View {
        let filteredLocalAssets = filteredLocalAudioAssets
        let filteredClips = filteredAudioClips

        VStack(alignment: .leading, spacing: 12) {
            audioHeader()

            TopChromeBoundedContent {
                if isAudioTagFilterBarPresented {
                    audioTagQuickFilterBar
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        audioEntriesSection(localAssets: filteredLocalAssets, clips: filteredClips)
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, Design.libraryContentInset)
                    .padding(.bottom, 12)
                }
                .fadingVerticalScrollIndicators()
            }
        }
        .padding(.top, Design.libraryToolbarTop)
        .padding(.bottom, 14)
        .background(Design.sidebarBg)
        .onDisappear {
            audioPreviewController.stop()
        }
        .onReceive(AppEventBus.musicPreviewStartedPublisher) { notification in
            let event = AppEventBus.musicPreviewStartedEvent(from: notification)
            guard event.source != AppEventBus.MusicPreviewSource.audioWorkspace else { return }
            audioPreviewController.stop()
        }
    }

}
