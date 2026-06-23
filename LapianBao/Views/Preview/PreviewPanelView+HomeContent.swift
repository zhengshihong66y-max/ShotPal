//
//  PreviewPanelView+HomeContent.swift
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

extension PreviewPanelView {
    // MARK: – Custom liquid-glass tab switcher

    var previewTabSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(PreviewTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        activePreviewTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(activePreviewTab == tab ? .white : .white.opacity(0.45))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background {
                            if activePreviewTab == tab {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                .white.opacity(0.22),
                                                .white.opacity(0.12)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .overlay {
                                        Capsule()
                                            .stroke(.white.opacity(0.28), lineWidth: 0.5)
                                    }
                                    .shadow(color: .black.opacity(0.30), radius: 6, y: 2)
                                    .matchedGeometryEffect(id: "tabHighlight", in: tabNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(.black.opacity(0.32))
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.10), lineWidth: 0.5)
                }
        )
    }

    func timelineActionButton(icon: String, label: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(.black.opacity(0.28))
                        .overlay { Capsule().stroke(.white.opacity(0.10), lineWidth: 0.5) }
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: – Timeline & content areas

    @ViewBuilder
    func previewTimeline(for video: VideoItem) -> some View {
        PlaybackClockDrivenView(
            clock: controller.clock,
            duration: controller.duration,
            playbackRate: controller.playbackRate,
            isPlaying: controller.isPlaying
        ) { clock in
            switch activePreviewTab {
            case .frames:
                frameTimeline(for: video, clock: clock)
            case .audio:
                audioTimeline(for: video, clock: clock)
            case .content:
                contentTimeline(for: video, clock: clock)
            }
        }
    }

    @ViewBuilder
    func audioSamplingBar(for video: VideoItem) -> some View {
        if activePreviewTab == .audio {
            HStack(spacing: 8) {
                Button("In") { setAudioInPoint() }

                Button("Out") { setAudioOutPoint() }

                Divider().frame(height: 14)

                Button {
                    exportCurrentAudioSelection(for: video)
                } label: {
                    floatingExportButtonIcon(
                        size: Design.timelineLaneButtonSize,
                        iconSize: 11
                    )
                }
                .buttonStyle(.plain)
                .disabled(audioInPoint == nil || audioOutPoint == nil || libraryStore.audioClipExportProgressByVideoPath[video.url.path] != nil)

                Spacer()

                if let inT = audioInPoint {
                    Text("In \(formatDuration(inT))")
                        .font(Design.numericCaption2())
                        .foregroundStyle(.secondary)
                }
                if let outT = audioOutPoint {
                    Text("Out \(formatDuration(outT))")
                        .font(Design.numericCaption2())
                        .foregroundStyle(.secondary)
                }
                if let inT = audioInPoint, let outT = audioOutPoint {
                    Text("·  \(formatDuration(abs(outT - inT)))")
                        .font(Design.numericCaption2())
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.semibold))
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    func previewTabContent(for video: VideoItem) -> some View {
        switch activePreviewTab {
        case .frames:
            ScenePanelView(
                video: video,
                controller: controller,
                sceneCuts: libraryStore.sceneCutsByVideoPath[video.url.path] ?? [],
                hasSceneRecognitionResult: libraryStore.sceneCutsByVideoPath[video.url.path] != nil,
                sceneDetectionProgress: libraryStore.sceneDetectionProgress[video.url.path],
                sceneDetectionError: libraryStore.sceneDetectionErrorByVideoPath[video.url.path],
                sceneThumbnailVersion: libraryStore.sceneThumbnailVersionsByVideoPath[video.url.path] ?? 0,
                sceneThumbnailsNeedHydration: libraryStore.sceneThumbnailsNeedHydration(for: video),
                isHydratingSceneThumbnails: libraryStore.isHydratingSceneThumbnails(for: video),
                sampledFrames: libraryStore.sampledFrames(for: video),
                activeItemID: activeSceneItemID(for: video),
                playbackDuration: controller.duration,
                playbackRate: controller.playbackRate,
                isPlaybackPlaying: controller.isPlaying,
                openStoryboardBoard: { openStoryboardBoard(video) },
                exportStoryboard: { exportCurrentStoryboard(for: video) },
                storyboardExportTitle: storyboardExportButtonTitle(for: video)
            )
            .equatable()
        case .audio:
            homeAudioClipList(for: video)
        case .content:
            homeTranscriptSummary(for: video)
        }
    }

    @ViewBuilder
    func homeAudioClipList(for video: VideoItem) -> some View {
        let clips = libraryStore.audioClips(for: video)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("已截取声音段")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("\(clips.count)")
                    .font(Design.numericCaption2(weight: .semibold))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)

                if audioInPoint != nil || audioOutPoint != nil {
                    Button {
                        audioInPoint = nil
                        audioOutPoint = nil
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let inT = audioInPoint {
                currentAudioSelectionCard(video: video, inTime: inT, outTime: displayedAudioOutPoint)
            }

            if let progress = libraryStore.audioClipExportProgressByVideoPath[video.url.path] {
                GenerationProgressRow(
                    message: "正在导出声音并生成波形",
                    progress: progress,
                    tint: Design.annotationAccent,
                    systemImage: "waveform.badge.plus",
                    compact: true
                )
                .padding(9)
                .background(.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let message = libraryStore.audioClipExportErrorByVideoPath[video.url.path],
               libraryStore.audioClipExportProgressByVideoPath[video.url.path] == nil {
                RecognitionFailureIndicator(message: message, minHeight: 28)
                    .onTapGesture {
                        libraryStore.audioClipExportErrorByVideoPath[video.url.path] = nil
                    }
            }

            if clips.isEmpty {
                AppEmptyState(
                    title: "暂无声音片段",
                    systemImage: "waveform",
                    style: .compact
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                            audioClipTimelineRow(clip, index: index + 1)
                        }
                    }
                    .padding(.trailing, 2)
                }
                .fadingVerticalScrollIndicators()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func currentAudioSelectionCard(video: VideoItem, inTime: Double, outTime: Double?) -> some View {
        let end = outTime ?? inTime
        let duration = abs(end - inTime)
        let canExport = audioOutPoint != nil && duration > 0.05
        let isExporting = libraryStore.audioClipExportProgressByVideoPath[video.url.path] != nil

        return HStack(spacing: 10) {
            Image(systemName: canExport ? "waveform.badge.plus" : "waveform")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(audioOutPoint == nil ? "当前声音选区" : "待导出声音段")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))
                Text("\(formatDuration(min(inTime, end))) - \(formatDuration(max(inTime, end))) · \(formatDuration(duration))")
                    .font(Design.numericCaption2())
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer(minLength: 0)

            Button {
                exportCurrentAudioSelection(for: video)
            } label: {
                floatingExportButtonIcon(size: 26, iconSize: 12)
            }
            .buttonStyle(.plain)
            .disabled(!canExport || isExporting)
        }
        .padding(9)
        .background(.white.opacity(0.075))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 0.7)
        }
    }

    func audioClipTimelineRow(_ clip: AudioClipItem, index: Int) -> some View {
        let isPlaying = activeExportAudioClipID == clip.id
        let progress = isPlaying ? activeExportAudioProgress : 0
        let duration = max(0, clip.outTime - clip.inTime)

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    exportAudioTagPreview(for: clip)
                        .layoutPriority(1)

                    Spacer(minLength: 0)
                }
                .frame(height: 16, alignment: .center)

                exportAudioWaveformWithTimecode(
                    samples: clip.waveformSamples,
                    isPlaying: isPlaying,
                    progress: progress,
                    duration: duration,
                    height: 58
                )
            }
            .frame(height: Self.exportRowContentHeight, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleExportAudioClipPlayback(clip)
            }
            .itemProviderDrag(audioClipDragProvider(for: clip))

            exportItemActionColumn(
                showInFinderURL: libraryStore.audioClipFileURL(for: clip),
                jumpHelp: "回到原视频位置",
                deleteHelp: "删除声音片段",
                onJump: {
                    audioInPoint = clip.inTime
                    audioOutPoint = clip.outTime
                    controller.pause()
                    controller.seekToSeconds(clip.inTime)
                },
                onDelete: {
                    deleteExportAudioClip(clip)
                }
            )
        }
        .padding(.horizontal, 9)
        .padding(.vertical, Self.exportRowVerticalPadding)
        .frame(height: Self.exportRowHeight)
        .background(.white.opacity(isPlaying ? 0.075 : 0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isPlaying ? .white.opacity(0.20) : .white.opacity(0.07), lineWidth: 0.7)
        }
        .onAppear {
            libraryStore.loadAudioClipWaveformIfNeeded(clip)
        }
        .itemProviderDrag(audioClipDragProvider(for: clip))
    }

    func audioClipDragProvider(for clip: AudioClipItem) -> (() -> NSItemProvider)? {
        guard libraryStore.audioClipFileURL(for: clip) != nil else { return nil }
        return {
            libraryStore.audioClipFileProvider(for: clip) ?? NSItemProvider()
        }
    }

    func audioClipTitle(index: Int?) -> String {
        guard let index else { return "声音片段" }
        return String(format: "声音片段 %02d", index)
    }

    func clipWidthRatio(_ clip: AudioClipItem) -> Double {
        guard controller.duration > 0 else { return 1 }
        return min(1, max(0.08, (clip.outTime - clip.inTime) / controller.duration))
    }

    @ViewBuilder
    func homeMusicRecognitionPanel(for video: VideoItem) -> some View {
        let path = video.url.path
        let status = libraryStore.musicDetectionStatusByVideoPath[path]
        let songs = libraryStore.musicsByVideoPath[path, default: []]

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("音乐识别")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if case .running = status {
                    Button {
                        libraryStore.cancelMusicDetection(for: video)
                    } label: {
                        Image(systemName: "stop.circle")
                            .accessibilityLabel("停止")
                    }
                    .buttonStyle(.borderless)
                } else {
                    Button {
                        libraryStore.detectMusic(for: video)
                    } label: {
                        Label(songs.isEmpty ? "识别音乐" : "重新识别", systemImage: "music.note.list")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if case let .running(message) = status {
                RecognitionProgressRow(
                    message: message,
                    progress: activityProgressValue(from: message),
                    showPercent: false,
                    showStepCount: false
                )
                .recognitionProgressCard()

                if !songs.isEmpty {
                    homeMusicRows(songs: songs, videoPath: path)
                }
            } else if case let .failed(message) = status {
                RecognitionFailureIndicator(message: message, minHeight: 82)
            } else if status == .completed, songs.isEmpty {
                AppEmptyState(
                    title: "暂无音乐识别结果",
                    style: .compact,
                    minHeight: 82,
                    showsBackground: true
                )
            } else if songs.isEmpty {
                AppEmptyState(
                    title: "暂无音乐识别记录",
                    systemImage: "music.note",
                    description: "识别视频中出现过的背景音乐，并显示歌名、作者、封面和 Apple Music 链接。",
                    style: .compact,
                    minHeight: 82,
                    showsBackground: true
                )
            } else {
                homeMusicRows(songs: songs, videoPath: path)
            }
        }
    }

    func homeMusicRows(songs: [MusicRecognitionItem], videoPath: String) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(songs) { song in
                MusicRecognitionRow(song: song, videoPath: videoPath) {
                    controller.pause()
                    controller.seekToSeconds(song.detectedAt)
                }
            }
        }
    }

    @ViewBuilder
    func homeTranscriptSummary(for video: VideoItem) -> some View {
        let segments = libraryStore.transcriptSegmentsByVideoPath[video.url.path, default: []]
        if case let .running(message) = libraryStore.transcriptStatusByVideoPath[video.url.path] {
            RecognitionProgressRow(
                message: message,
                progress: activityProgressValue(from: message)
            )
            .recognitionProgressCard()
        } else if segments.isEmpty {
            HStack(spacing: 10) {
                AppEmptyState(
                    title: "暂无字幕",
                    style: .inline,
                    fillsWidth: false
                )
                Button {
                    libraryStore.transcribe(video: video)
                } label: {
                    Label("生成字幕", systemImage: "text.badge.plus")
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 10)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(segments) { segment in
                            let isActive = segment.id == activeTranscriptSegmentID
                            Button {
                                controller.pause()
                                controller.seekToSeconds(segment.start)
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Text(formatDuration(segment.start))
                                        .font(Design.numericCaption2(weight: .semibold))
                                        .foregroundStyle(isActive ? .primary : .secondary)
                                        .frame(width: 52, alignment: .leading)
                                    Text(segment.text)
                                        .font(.caption)
                                        .foregroundStyle(isActive ? .primary : .secondary)
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 7)
                                .background(isActive ? Color.white.opacity(0.10) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .id(segment.id)
                        }
                    }
                }
                .fadingVerticalScrollIndicators()
                .onChange(of: activeTranscriptSegmentID) { _, newID in
                    if let newID {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }
        }
    }

}
