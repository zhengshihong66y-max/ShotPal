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

private enum AccountLoginTarget: String, Identifiable {
    case instagram
    case xiaohongshu
    case youtube
    case bilibili
    case douyin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instagram: return "Instagram 登录"
        case .xiaohongshu: return "小红书登录"
        case .youtube: return "YouTube 登录"
        case .bilibili: return "Bilibili 登录"
        case .douyin: return "抖音登录"
        }
    }

    var buttonTitle: String {
        switch self {
        case .instagram: return "IG"
        case .xiaohongshu: return "小红书"
        case .youtube: return "YouTube"
        case .bilibili: return "B站"
        case .douyin: return "抖音"
        }
    }

    var buttonWidth: CGFloat {
        switch self {
        case .xiaohongshu, .douyin:
            return 42
        case .youtube:
            return 50
        case .instagram, .bilibili:
            return 44
        }
    }

    var startURL: URL {
        switch self {
        case .instagram:
            return URL(string: "https://www.instagram.com/accounts/login/")!
        case .xiaohongshu:
            return URL(string: "https://www.xiaohongshu.com/explore")!
        case .youtube:
            return URL(string: "https://accounts.google.com/ServiceLogin?service=youtube")!
        case .bilibili:
            return URL(string: "https://passport.bilibili.com/login")!
        case .douyin:
            return URL(string: "https://www.douyin.com/")!
        }
    }

    static let allLoginTargets: [AccountLoginTarget] = [
        .instagram,
        .xiaohongshu,
        .youtube,
        .bilibili,
        .douyin
    ]
}

struct SettingsWorkspaceView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var shortcutRevision = 0

    private static let rowHeight: CGFloat = MusicRowMetrics.rowHeight
    private static let rowHorizontalPadding: CGFloat = MusicRowMetrics.contentInsetX
    private static let rowVerticalPadding: CGFloat = MusicRowMetrics.contentInsetY
    private static let rowColumnSpacing: CGFloat = MusicRowMetrics.columnSpacing
    private static let rowIconSize: CGFloat = MusicRowMetrics.artworkSize
    private static let rowActionButtonSize: CGFloat = MusicRowMetrics.actionButtonSize
    private static let rowContentHeight: CGFloat = MusicRowMetrics.artworkSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                accountLoginCard()
                downloaderSelfCheckCard()
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
            libraryStore.refreshAccountCookieSummary()
            libraryStore.prewarmSavedCollectionCookieCache()
        }
    }

    private func accountLoginCard() -> some View {
        HStack(alignment: .center, spacing: Self.rowColumnSpacing) {
            settingsRowIcon(
                libraryStore.accountCookieSummary.hasAnySession ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.exclamationmark",
                tint: libraryStore.accountCookieSummary.hasAnySession ? .green : Design.annotationAccent
            )

            settingsInfoColumn(
                title: "账号登录",
                detail: libraryStore.accountCookieSummary.detailText,
                detailColor: libraryStore.accountCookieSummary.hasAnySession ? .secondary : Color.orange.opacity(0.92)
            )

            HStack(spacing: 6) {
                ForEach(AccountLoginTarget.allLoginTargets) { target in
                    Button {
                        openAccountLogin(target)
                    } label: {
                        Text(target.buttonTitle)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(width: target.buttonWidth, height: Self.rowActionButtonSize)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.78))
                    .background(.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .help("用默认浏览器打开\(target.title)")
                }

                accountLoginRefreshButton()
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, Self.rowHorizontalPadding)
        .padding(.vertical, Self.rowVerticalPadding)
        .frame(height: Self.rowHeight, alignment: .center)
        .settingsRowBackground()
    }

    private func accountLoginRefreshButton() -> some View {
        Button {
            refreshAccountLoginStatus(forceRefresh: true)
        } label: {
            ZStack {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(libraryStore.isRefreshingAccountCookieSummary ? 0 : 0.70))
                if libraryStore.isRefreshingAccountCookieSummary {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white.opacity(0.72))
                }
            }
            .frame(width: Self.rowActionButtonSize, height: Self.rowActionButtonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(libraryStore.isRefreshingAccountCookieSummary)
        .help("检测最新登录状态")
    }

    private func downloaderSelfCheckCard() -> some View {
        let report = libraryStore.downloaderSelfCheckReport
        return settingsCompactRow(
            icon: downloaderSelfCheckIcon(for: report),
            iconTint: downloaderSelfCheckColor(for: report),
            title: "YTDLP 自检",
            detail: downloaderSelfCheckVersionText(report),
            actionIcon: "arrow.clockwise",
            help: "刷新 YTDLP 自检",
            isDisabled: report.isRunning,
            action: { libraryStore.startExternalServiceSelfCheck() }
        )
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
        detail: String,
        actionIcon: String,
        help: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: Self.rowColumnSpacing) {
            settingsRowIcon(icon, tint: iconTint)

            settingsInfoColumn(title: title, detail: detail)

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
        detail: String,
        detailColor: Color = .secondary
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
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
        .help(help)
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

    private func downloaderSelfCheckVersionText(_ report: DownloaderSelfCheckReport) -> String {
        if report.isRunning {
            return "当前版本：检查中"
        }
        guard let version = report.ytdlpVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty
        else {
            return "当前版本：未检测"
        }
        return "当前版本：\(version)"
    }

    private func openAccountLogin(_ target: AccountLoginTarget) {
        NSWorkspace.shared.open(target.startURL)
        refreshAccountLoginStatus(after: 2.0, forceRefresh: true)
    }

    private func refreshAccountLoginStatus(after delay: TimeInterval = 0, forceRefresh: Bool = false) {
        if delay <= 0 {
            libraryStore.refreshAccountCookieSummary(forceRefresh: forceRefresh)
            libraryStore.prewarmSavedCollectionCookieCache()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            libraryStore.refreshAccountCookieSummary(forceRefresh: forceRefresh)
            libraryStore.prewarmSavedCollectionCookieCache()
        }
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
