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
                            downloadProgressSection
                            downloadHistorySection
                        }
                        .padding(18)
                    }
                    .fadingVerticalScrollIndicators()
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 14) {
                            importInputSection
                            downloadProgressSection
                        }
                        .padding(18)
                        .frame(width: leftColumnWidth, alignment: .top)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(Design.sidebarBg)

                        Rectangle()
                            .fill(.white.opacity(0.06))
                            .frame(width: 1)

                        downloadHistorySection
                            .padding(18)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .background(Design.contentBg)
                    }
                }
            }
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
                    .accessibilityLabel("清空导入链接")
                    .accessibilityIdentifier("import_clear_links_button")
                }
            }

            ImportURLTextEditor(
                text: $importURLText,
                placeholder: "每行一个链接，支持 Instagram、YouTube、小红书、Bilibili、抖音…"
            )
            .frame(minHeight: 72, maxHeight: 96)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
            .accessibilityLabel("导入链接输入框")
            .accessibilityIdentifier("import_url_text_editor")

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
                .accessibilityLabel("关闭导入面板")
                .accessibilityIdentifier("import_close_button")

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
                .accessibilityLabel("开始下载导入链接")
                .accessibilityIdentifier("import_start_download_button")
            }
            .frame(height: 30)
        }
    }

    var downloadProgressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("下载进度", systemImage: "arrow.down.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(importProgressSummary)
                    .font(Design.numericCaption())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if activeImportJobs.isEmpty {
                AppEmptyState(
                    title: "暂无进行中的下载",
                    systemImage: "tray",
                    style: .compact
                )
                    .frame(maxWidth: .infinity, minHeight: 170)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(activeImportJobs) { job in
                            importProgressJobStatus(job)
                        }
                    }
                }
                .fadingVerticalScrollIndicators()
                .frame(maxHeight: .infinity)
            }

            downloadProgressFooter
                .frame(height: 30, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    var downloadProgressFooter: some View {
        if activeImportJobs.isEmpty {
            Text(libraryStore.remoteImportJobs.isEmpty ? "粘贴链接后点击下载，任务会显示在这里" : "当前没有正在下载的任务")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    var downloadHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("下载记录", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(downloadHistorySummary)
                    .font(Design.numericCaption())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if importHistoryItems.isEmpty {
                AppEmptyState(
                    title: "暂无下载记录",
                    systemImage: "clock",
                    style: .compact
                )
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(importHistoryItems) { item in
                            importHistoryListItem(item)
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
                    .accessibilityLabel("清空已完成下载记录")
                    .accessibilityIdentifier("import_clear_finished_records_button")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

}

private struct ImportURLTextEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> ImportURLTextEditorView {
        let view = ImportURLTextEditorView()
        view.textView.delegate = context.coordinator
        view.configure(text: text, placeholder: placeholder)
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ nsView: ImportURLTextEditorView, context: Context) {
        context.coordinator.text = $text
        nsView.textView.delegate = context.coordinator
        nsView.configure(text: text, placeholder: placeholder)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var view: ImportURLTextEditorView?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            view?.updatePlaceholderVisibility()
        }
    }
}

private final class ImportURLTextEditorView: NSView {
    let textView = NSTextView()

    private let scrollView = NSScrollView()
    private let placeholderView = PassthroughTextView()
    private let textInset = NSSize(width: 14, height: 12)
    private let editorFont = NSFont.systemFont(ofSize: 13, weight: .regular)

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .small

        configureTextView(textView, isPlaceholder: false)
        scrollView.documentView = textView
        addSubview(scrollView)

        configureTextView(placeholderView, isPlaceholder: true)
        addSubview(placeholderView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        placeholderView.frame = bounds
        textView.textContainer?.containerSize = NSSize(width: max(0, bounds.width), height: CGFloat.greatestFiniteMagnitude)
        placeholderView.textContainer?.containerSize = NSSize(width: max(0, bounds.width), height: CGFloat.greatestFiniteMagnitude)
    }

    func configure(text: String, placeholder: String) {
        if textView.string != text {
            textView.string = text
        }
        if placeholderView.string != placeholder {
            placeholderView.string = placeholder
        }
        configureTextView(textView, isPlaceholder: false)
        configureTextView(placeholderView, isPlaceholder: true)
        updatePlaceholderVisibility()
    }

    func updatePlaceholderVisibility() {
        placeholderView.isHidden = !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func configureTextView(_ textView: NSTextView, isPlaceholder: Bool) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = editorFont
        textView.textContainerInset = textInset
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        if isPlaceholder {
            textView.isEditable = false
            textView.isSelectable = false
            textView.textColor = NSColor.tertiaryLabelColor
            textView.insertionPointColor = .clear
        } else {
            textView.isEditable = true
            textView.isSelectable = true
            textView.allowsUndo = true
            textView.textColor = .labelColor
            textView.insertionPointColor = .labelColor
        }
    }
}

private final class PassthroughTextView: NSTextView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
