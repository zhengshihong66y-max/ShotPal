//
//  SettingsWorkspaceView.swift
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

struct SettingsWorkspaceView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var selfCheckStore: DownloaderSelfCheckStore
    @EnvironmentObject private var youtubeCookieStore: YouTubeCookieStore
    @State private var shortcutRevision = 0

    private static let rowHeight: CGFloat = MusicRowMetrics.rowHeight
    private static let rowHorizontalPadding: CGFloat = MusicRowMetrics.contentInsetX
    private static let rowVerticalPadding: CGFloat = MusicRowMetrics.contentInsetY
    private static let rowColumnSpacing: CGFloat = MusicRowMetrics.columnSpacing
    private static let rowIconSize: CGFloat = MusicRowMetrics.artworkSize
    private static let rowActionButtonSize: CGFloat = MusicRowMetrics.actionButtonSize
    private static let rowContentHeight: CGFloat = MusicRowMetrics.artworkSize
    private static let rowTextSpacing: CGFloat = 4
    private static let rowDescriptionColor = Color.white.opacity(0.58)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                downloaderSelfCheckCard()
                youtubeCookieFileCard()
                shortcutSettingsCard()
            }
            .padding(.horizontal, Design.libraryContentInset)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fadingVerticalScrollIndicators()
        .onAppear {
            removeDeprecatedSettings()
        }
    }

    private func downloaderSelfCheckCard() -> some View {
        let report = selfCheckStore.downloaderSelfCheckReport
        return settingsCompactRow(
            icon: downloaderSelfCheckIcon(for: report),
            iconTint: downloaderSelfCheckColor(for: report),
            title: "下载器自检",
            description: "使用开源下载工具，请保证网络环境。",
            detail: downloaderSelfCheckVersionText(report),
            detailColor: downloaderSelfCheckDetailColor(for: report),
            actionIcon: "arrow.clockwise",
            help: "刷新 YTDLP 自检",
            isDisabled: report.isRunning,
            action: { selfCheckStore.startExternalServiceSelfCheck() }
        )
    }

    private func youtubeCookieFileCard() -> some View {
        let isConfigured = !(youtubeCookieStore.configuredFilePath ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isRefreshing = youtubeCookieStore.isRefreshing
        return settingsCompactRow(
            icon: youtubeCookieCardIcon(isConfigured: isConfigured),
            iconTint: youtubeCookieCardIconTint(isConfigured: isConfigured),
            title: "YouTube cookies",
            description: "仅在 YouTube 要求登录验证时使用,点击刷新可从 Chrome 一键配置。",
            detail: youtubeCookieFileDetailText,
            detailColor: youtubeCookieDetailColor(isConfigured: isConfigured),
            actionIcon: "arrow.clockwise",
            help: isConfigured ? "从 Chrome 一键更新 cookies" : "从 Chrome 一键配置 cookies",
            isDisabled: isRefreshing,
            action: { youtubeCookieStore.refreshFromBrowser() }
        )
    }

    private var youtubeCookieFileDetailText: String {
        switch youtubeCookieStore.refreshPhase {
        case .running:
            return "正在从 Chrome 读取并验证…首次会弹出钥匙串授权,请点\"允许\""
        case .failed(let message):
            return message
        case .succeeded:
            return "\(youtubeCookieConfiguredFileName ?? "cookies.txt") · 已验证通过"
        case .idle:
            return youtubeCookieConfiguredFileName.map { "\($0) · 已配置" } ?? "未配置"
        }
    }

    private var youtubeCookieConfiguredFileName: String? {
        let trimmed = (youtubeCookieStore.configuredFilePath ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    private func youtubeCookieCardIcon(isConfigured: Bool) -> String {
        switch youtubeCookieStore.refreshPhase {
        case .running: return "clock.arrow.circlepath"
        case .failed: return "exclamationmark.triangle.fill"
        case .succeeded: return "checkmark.seal.fill"
        case .idle: return isConfigured ? "doc.badge.gearshape.fill" : "doc.badge.plus"
        }
    }

    private func youtubeCookieCardIconTint(isConfigured: Bool) -> Color {
        switch youtubeCookieStore.refreshPhase {
        case .running: return Design.annotationAccent
        case .failed: return .red
        case .succeeded: return .green
        case .idle: return isConfigured ? .green : Design.annotationAccent
        }
    }

    private func youtubeCookieDetailColor(isConfigured: Bool) -> Color {
        switch youtubeCookieStore.refreshPhase {
        case .succeeded: return .green
        case .idle where isConfigured: return .green
        default: return Color.yellow.opacity(0.92)
        }
    }

    private func shortcutSettingsCard() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(PreviewShortcutAction.allCases) { action in
                    shortcutRow(action)
                    if action.id != PreviewShortcutAction.allCases.last?.id {
                        Divider()
                            .overlay(.white.opacity(0.06))
                    }
                }
            }
        }
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.vertical, Self.rowVerticalPadding)
        .settingsRowBackground()
    }

    private func shortcutRow(_ action: PreviewShortcutAction) -> some View {
        let conflicts = shortcutConflicts(for: action)

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                if conflicts.isEmpty {
                    Text(PreviewShortcutKeyOption.title(for: action.defaultKeyCode))
                        .font(Design.numericCaption2())
                        .foregroundStyle(.secondary)
                } else {
                    Text("冲突：\(conflicts.map(\.title).joined(separator: "、"))")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("", selection: shortcutBinding(for: action)) {
                ForEach(PreviewShortcutKeyOption.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 86)

            settingsActionButton(
                systemImage: "arrow.uturn.backward",
                tint: action.keyCode == action.defaultKeyCode ? .white.opacity(0.22) : .white.opacity(0.70),
                help: "恢复默认",
                action: {
                    AppSettings.resetPreviewShortcutKeyCode(actionRawValue: action.rawValue)
                    shortcutRevision += 1
                }
            )
            .disabled(action.keyCode == action.defaultKeyCode)
        }
        .padding(.vertical, 7)
        .id("\(action.id)-\(shortcutRevision)")
    }

    private func shortcutBinding(for action: PreviewShortcutAction) -> Binding<UInt16> {
        Binding(
            get: { action.keyCode },
            set: { keyCode in
                action.setKeyCode(keyCode)
                shortcutRevision += 1
            }
        )
    }

    private func shortcutConflicts(for action: PreviewShortcutAction) -> [PreviewShortcutAction] {
        PreviewShortcutAction.actions(for: action.keyCode).filter { $0 != action }
    }

    private func settingsCompactRow(
        icon: String,
        iconTint: Color,
        title: String,
        description: String,
        detail: String,
        detailColor: Color = .white,
        actionIcon: String,
        help: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: Self.rowColumnSpacing) {
            settingsRowIcon(icon, tint: iconTint)

            settingsInfoColumn(title: title, description: description, detail: detail, detailColor: detailColor)

            settingsActionButton(
                systemImage: actionIcon,
                help: help,
                action: action
            )
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.34 : 1)
        }
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.vertical, Self.rowVerticalPadding)
        .frame(height: Self.rowHeight, alignment: .center)
        .settingsRowBackground()
    }

    private func settingsInfoColumn(
        title: String,
        description: String,
        detail: String,
        detailColor: Color = .white
    ) -> some View {
        VStack(alignment: .leading, spacing: Self.rowTextSpacing) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(description)
                .font(.caption2)
                .foregroundStyle(Self.rowDescriptionColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(detail.isEmpty ? " " : detail)
                .font(.caption2)
                .foregroundStyle(detailColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, minHeight: Self.rowContentHeight, maxHeight: Self.rowContentHeight, alignment: .leading)
    }

    private func settingsRowIcon(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: Self.rowIconSize, height: Self.rowIconSize)
            .background(tint.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 0.7)
            }
    }

    private func settingsActionButton(
        systemImage: String,
        tint: Color = .white.opacity(0.70),
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: Self.rowActionButtonSize, height: Self.rowActionButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func downloaderSelfCheckIcon(for report: DownloaderSelfCheckReport) -> String {
        switch report.status {
        case .idle: return "arrow.down.circle"
        case .running: return "clock.arrow.circlepath"
        case .succeeded: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func downloaderSelfCheckColor(for report: DownloaderSelfCheckReport) -> Color {
        switch report.status {
        case .idle, .running: return Design.annotationAccent
        case .succeeded: return .green
        case .failed: return .red
        }
    }

    private func downloaderSelfCheckDetailColor(for report: DownloaderSelfCheckReport) -> Color {
        report.status == .succeeded ? .green : Color.yellow.opacity(0.92)
    }

    private func downloaderSelfCheckVersionText(_ report: DownloaderSelfCheckReport) -> String {
        if report.isRunning {
            return "当前版本：检查中"
        }
        if report.status == .failed {
            let message = report.message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty, message != "未自检" {
                return message
            }
        }
        guard let version = report.ytdlpVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty
        else {
            return "当前版本：未检测"
        }
        return "当前版本：\(version)"
    }

    private func removeDeprecatedSettings() {
        AppSettings.removeExternalAPISettings()
        AppSettings.removeDeprecatedBatchAutomationSettings()
    }
}

private extension View {
    func settingsRowBackground() -> some View {
        background(.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 0.7)
            }
    }
}
