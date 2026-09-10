//
//  ContentView+ImportInput.swift
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
    var importTile: some View {
        Button {
            importEndpointText = libraryStore.instagramImportEndpoint
            autoFillClipboardURL()
            presentImportPanel()
        } label: {
            ZStack {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(.white.opacity(0.03))
            .contentShape(RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Design.itemRadius, style: .continuous)
                    .stroke(.white.opacity(0.09), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text("打开导入面板"))
        .accessibilityIdentifier("library_import_tile")
    }

    func autoFillClipboardURL() {
        guard
            let clip = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !clip.isEmpty
        else { return }
        pasteImportURLs(unqueuedClipboardImportURLs(from: clip))
    }

    func handleClipboardChangeIfNeeded() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != observedPasteboardChangeCount else { return }
        observedPasteboardChangeCount = changeCount

        guard
            let clip = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !clip.isEmpty
        else { return }

        let urls = unqueuedClipboardImportURLs(from: clip)
        guard !urls.isEmpty else { return }

        openImportPanel(with: urls)
    }

    func unqueuedClipboardImportURLs(from text: String) -> [String] {
        let existingIDs = queuedOrImportedImportCandidateIDs
        return Self.supportedImportURLs(from: text).filter {
            !existingIDs.contains(importCandidateID(for: $0))
        }
    }

    func handleImportDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        Task {
            let urls = await Self.supportedImportURLs(from: providers)
            guard !urls.isEmpty else { return }
            await MainActor.run {
                openImportPanel(with: urls)
            }
        }
        return true
    }

    func openImportPanel(with urls: [String]) {
        guard !urls.isEmpty else { return }

        pasteImportURLs(urls)
        importEndpointText = libraryStore.instagramImportEndpoint
        presentImportPanel()
        NSApp.activate(ignoringOtherApps: true)
    }

    func presentImportPanel() {
        importPanelPresentedAt = Date()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            isImportSheetPresented = true
        }
    }

    func pasteImportURLs(_ urls: [String]) {
        guard !urls.isEmpty else { return }

        var merged = importURLTokens
        for url in urls where !merged.contains(url) {
            merged.append(url)
        }
        importURLText = merged.joined(separator: "\n")
    }

    static func supportedImportURLs(from text: String) -> [String] {
        var seen = Set<String>()
        var urls: [String] = []

        func appendIfSupported(_ rawValue: String) {
            let trimmed = sanitizedURLString(rawValue)
            guard
                !trimmed.isEmpty,
                let url = URL(string: trimmed),
                LibraryStore.platformName(for: url) != nil,
                seen.insert(trimmed).inserted
            else { return }
            urls.append(trimmed)
        }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            detector.enumerateMatches(in: text, options: [], range: nsRange) { match, _, _ in
                if let url = match?.url?.absoluteString {
                    appendIfSupported(url)
                }
            }
        }

        let pattern = #"https?://[^\s<>"'，。、“”‘’（）()【】\[\]{}]+"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: nsRange) {
                guard let range = Range(match.range, in: text) else { continue }
                appendIfSupported(String(text[range]))
            }
        }

        return urls
    }

    static func supportedImportURLs(from providers: [NSItemProvider]) async -> [String] {
        var seen = Set<String>()
        var urls: [String] = []

        func append(_ candidates: [String]) {
            for candidate in candidates where seen.insert(candidate).inserted {
                urls.append(candidate)
            }
        }

        for provider in providers {
            if let text = await itemProviderString(provider, for: UTType.url.identifier) {
                append(supportedImportURLs(from: text))
            }
            if let text = await itemProviderString(provider, for: UTType.plainText.identifier) {
                append(supportedImportURLs(from: text))
            }
            if let text = await itemProviderString(provider, for: UTType.text.identifier) {
                append(supportedImportURLs(from: text))
            }
            if let text = await itemProviderString(provider, for: UTType.utf8PlainText.identifier) {
                append(supportedImportURLs(from: text))
            }
            if let text = await itemProviderString(provider, for: UTType.html.identifier) {
                append(supportedImportURLs(from: text))
            }
        }

        return urls
    }

    static func itemProviderString(_ provider: NSItemProvider, for typeIdentifier: String) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else { return nil }

        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let string = item as? String {
                    continuation.resume(returning: string)
                } else if let url = item as? URL {
                    continuation.resume(returning: url.absoluteString)
                } else if let url = item as? NSURL {
                    continuation.resume(returning: url.absoluteString)
                } else if let data = item as? Data {
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    static func sanitizedURLString(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?，。；：！？、)]}）】》>\"'“”‘’"))
    }

}
