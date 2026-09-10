import AppKit
import SwiftUI

/// Place inside the subtitle scroll content so the probe finds that exact NSScrollView.
/// Playback's scrollTo calls must not reveal the indicator; only live user scrolling does.
struct SubtitleScrollIndicators: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView { ProbeView() }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.configureWhenMounted()
    }

    static func dismantleNSView(_ nsView: ProbeView, coordinator: ()) {
        nsView.detach()
    }

    final class ProbeView: NSView {
        private(set) weak var scrollView: NSScrollView?
        private(set) var isIndicatorVisible = false
        private var isTracking = false
        private var hideWorkItem: DispatchWorkItem?
        private var visibilityGeneration: UInt64 = 0
        static let idleDelay: TimeInterval = 0.65

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { detach() } else { configureWhenMounted() }
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            configureWhenMounted()
        }

        func configureWhenMounted() {
            guard window != nil else { return }
            attachToEnclosingScrollView()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.attachToEnclosingScrollView()
            }
        }

        private func attachToEnclosingScrollView() {
            var ancestor = superview
            while let view = ancestor {
                if let enclosing = view as? NSScrollView {
                    attach(to: enclosing)
                    return
                }
                ancestor = view.superview
            }
        }

        private func attach(to enclosing: NSScrollView) {
            if scrollView !== enclosing {
                detach()
                scrollView = enclosing
                let center = NotificationCenter.default
                center.addObserver(self, selector: #selector(willStartScroll), name: NSScrollView.willStartLiveScrollNotification, object: enclosing)
                center.addObserver(self, selector: #selector(didScroll), name: NSScrollView.didLiveScrollNotification, object: enclosing)
                center.addObserver(self, selector: #selector(didEndScroll), name: NSScrollView.didEndLiveScrollNotification, object: enclosing)
            }
            applyVisibility()
        }

        private func applyVisibility() {
            guard let scrollView else { return }
            if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
            if scrollView.scrollerKnobStyle != .light { scrollView.scrollerKnobStyle = .light }
            if !scrollView.autohidesScrollers { scrollView.autohidesScrollers = true }
            if scrollView.hasVerticalScroller != isIndicatorVisible {
                scrollView.hasVerticalScroller = isIndicatorVisible
            }
            if scrollView.verticalScroller?.controlSize != .small { scrollView.verticalScroller?.controlSize = .small }
        }

        @objc private func willStartScroll(_ notification: Notification) {
            isTracking = true
            showIndicator()
        }

        @objc private func didScroll(_ notification: Notification) {
            showIndicator()
            // Wheel mice can emit didLiveScroll without a start/end gesture pair.
            if !isTracking { scheduleHide() }
        }

        @objc private func didEndScroll(_ notification: Notification) {
            isTracking = false
            scheduleHide()
        }

        private func showIndicator() {
            cancelHide()
            isIndicatorVisible = true
            applyVisibility()
            scrollView?.flashScrollers()
        }

        private func cancelHide() {
            visibilityGeneration &+= 1
            hideWorkItem?.cancel()
            hideWorkItem = nil
        }

        private func scheduleHide() {
            cancelHide()
            let generation = visibilityGeneration
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.visibilityGeneration == generation, !self.isTracking else { return }
                self.isIndicatorVisible = false
                self.applyVisibility()
                self.hideWorkItem = nil
            }
            hideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleDelay, execute: work)
        }

        func detach() {
            NotificationCenter.default.removeObserver(self)
            cancelHide()
            isTracking = false
            isIndicatorVisible = false
            scrollView?.hasVerticalScroller = false
            scrollView = nil
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
