import AppKit
import SwiftUI

/// Exercise the real subtitle list without opening a library or starting recognition.
@MainActor
enum CommandLineSubtitleScrollCheck {
    static func run() -> [String: Bool] {
        let controller = PreviewController()
        let panel = PreviewPanelView(controller: controller, openStoryboardBoard: { _ in },
                                     pendingSeekRequest: .constant(nil), pendingExportPanelRequest: .constant(nil))
        let segments = (0..<40).map { index in
            TranscriptSegment(videoPath: "/synthetic-fixture/subtitles.mp4", start: Double(index * 3),
                              end: Double(index * 3 + 3), text: "Subtitle \(index + 1) · 手动滚动时才显示滚动条")
        }
        let host = NSHostingView(rootView: panel.subtitleSegmentList(segments)
            .padding(8).background(Design.sidebarBg).environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 540, height: 210),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close() }
        func settle(_ seconds: TimeInterval = 0.05) {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
        }
        func findProbe(in view: NSView) -> SubtitleScrollIndicators.ProbeView? {
            if let probe = view as? SubtitleScrollIndicators.ProbeView { return probe }
            return view.subviews.lazy.compactMap { findProbe(in: $0) }.first
        }
        var checks: [String: Bool] = [:]
        func snapshot(_ name: String) {
            let args = CommandLine.arguments
            guard let index = args.firstIndex(of: "--subtitle-scroll-preview-directory"), args.count > index + 1 else { return }
            do {
                let directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: directory.appendingPathComponent(name + ".png"))
            } catch { checks["subtitle_scroll_snapshot_\(name)"] = false }
        }
        settle(0.2)
        guard let probe = findProbe(in: host), let scrollView = probe.scrollView else {
            return ["subtitle_scroll_probe_attaches_inside_real_list": false]
        }
        checks["subtitle_scroll_probe_attaches_inside_real_list"] = true
        checks["subtitle_scrollbar_hidden_when_panel_opens"] = !probe.isIndicatorVisible && !scrollView.hasVerticalScroller
        checks["subtitle_scrollbar_never_reserves_legacy_gutter"] = scrollView.scrollerStyle == .overlay
        snapshot("subtitle-scroll-idle")
        let initialWidth = scrollView.contentView.bounds.width
        let initialY = scrollView.contentView.bounds.minY
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: initialY + 150))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        settle()
        checks["subtitle_programmatic_follow_scrolls_without_showing_bar"] = scrollView.contentView.bounds.minY != initialY
            && !probe.isIndicatorVisible && !scrollView.hasVerticalScroller
        probe.configureWhenMounted()
        settle()
        checks["subtitle_layout_update_does_not_reveal_scrollbar"] = !scrollView.hasVerticalScroller
        let otherScrollView = NSScrollView()
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: otherScrollView)
        checks["subtitle_ignores_other_workspace_scroll_events"] = !probe.isIndicatorVisible

        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scrollView)
        settle()
        checks["subtitle_mouse_wheel_reveals_scrollbar_without_gesture_start"] = probe.isIndicatorVisible && scrollView.hasVerticalScroller
        checks["subtitle_active_native_scroller_is_not_hidden"] = scrollView.verticalScroller?.isHidden == false
        checks["subtitle_active_native_scroller_has_visible_alpha"] = (scrollView.verticalScroller?.alphaValue ?? 0) > 0
        checks["subtitle_active_native_scroller_has_drawable_bounds"] = (scrollView.verticalScroller?.bounds.height ?? 0) > 10
            && (scrollView.verticalScroller?.bounds.width ?? 0) > 0
        checks["subtitle_active_scroller_contrasts_with_dark_panel"] = scrollView.scrollerKnobStyle == .light
        checks["subtitle_showing_scrollbar_does_not_shift_text_width"] = abs(scrollView.contentView.bounds.width - initialWidth) < 0.5
        snapshot("subtitle-scroll-active")
        settle(SubtitleScrollIndicators.ProbeView.idleDelay + 0.1)
        checks["subtitle_mouse_wheel_scrollbar_hides_after_idle"] = !probe.isIndicatorVisible && !scrollView.hasVerticalScroller
        snapshot("subtitle-scroll-stopped")

        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scrollView)
        settle(SubtitleScrollIndicators.ProbeView.idleDelay + 0.1)
        checks["subtitle_trackpad_or_thumb_tracking_keeps_indicator"] = probe.isIndicatorVisible && scrollView.hasVerticalScroller
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        settle(SubtitleScrollIndicators.ProbeView.idleDelay + 0.1)
        checks["subtitle_gesture_end_hides_scrollbar"] = !probe.isIndicatorVisible && !scrollView.hasVerticalScroller

        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scrollView)
        settle(0.4)
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scrollView)
        settle(0.4)
        checks["subtitle_repeated_wheel_input_resets_idle_timer"] = probe.isIndicatorVisible
        settle(0.35)
        checks["subtitle_repeated_wheel_input_eventually_hides"] = !probe.isIndicatorVisible
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scrollView)
        probe.detach()
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scrollView)
        checks["subtitle_detach_removes_observers_and_pending_visibility"] = probe.scrollView == nil && !probe.isIndicatorVisible
        return checks
    }
}
