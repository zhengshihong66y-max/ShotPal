//
//  Design.swift
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

enum Design {
    static let minimumWindowWidth: CGFloat = 960
    static let minimumWindowHeight: CGFloat = 720
    static let windowInset: CGFloat = 0
    // macOS 标准窗口圆角约 10pt（Big Sur+），这里用 10 与系统保持一致
    static let windowRadius: CGFloat = 10
    static let panelSpacing: CGFloat = 0
    static let panelRadius: CGFloat = 0
    static let innerRadius: CGFloat = 6
    static let itemRadius: CGFloat = 6
    static let railWidth: CGFloat = 56
    static let railIconInset: CGFloat = 8
    static let railButtonHeight: CGFloat = 34
    static let railIconBoxSize: CGFloat = 24
    static let railIconAlignmentOffsetX: CGFloat = -2.5
    static let railButtonVisualOffsetX: CGFloat = 3.5
    static let railSelectionGuideX: CGFloat = railIconInset + railButtonVisualOffsetX
    static let railIconVisualGuideX: CGFloat = (railWidth - railIconBoxSize) / 2
    // Pixel-locked to the home toolbar. Do not change without explicit user approval.
    static let libraryContentInset: CGFloat = 14
    static let libraryToolbarElementGap: CGFloat = 8
    static let libraryToolbarVisualGap: CGFloat = 14
    static let libraryToolbarHeight: CGFloat = 26
    static let libraryToolbarButtonSlotWidth: CGFloat = 18
    static let libraryToolbarButtonSlotHeight: CGFloat = 22
    static let libraryToolbarButtonGap: CGFloat = libraryContentInset
    static let libraryToolbarActionSlotCount: CGFloat = 3
    static let libraryToolbarActionRowWidth: CGFloat =
        libraryToolbarButtonSlotWidth * libraryToolbarActionSlotCount
        + libraryToolbarButtonGap * (libraryToolbarActionSlotCount - 1)
    static let libraryToolbarSearchMinWidth: CGFloat = 110
    static let libraryToolbarSearchWidth: CGFloat = 280
    static let libraryToolbarSearchHeight: CGFloat = 26
    static let libraryDateDividerTopInset: CGFloat = 10
    static let libraryDateDividerBottomInset: CGFloat = 10
    static let libraryHeaderDateDividerTopInset: CGFloat = 3
    static let libraryHeaderDateDividerBottomInset: CGFloat = 17
    static let previewHeaderTagRowHeight: CGFloat = 12
    static let previewHeaderTopInset: CGFloat = libraryToolbarVisualGap
    static let previewHeaderTitleTagGap: CGFloat = 8
    static let previewHeaderBottomInset: CGFloat = 0
    static let previewHeaderTitleLineHeight: CGFloat = 22
    static let previewHeaderHeight: CGFloat = previewHeaderTopInset + previewHeaderTitleLineHeight + previewHeaderTitleTagGap + previewHeaderTagRowHeight + previewHeaderBottomInset
    static let trafficLightSize: CGFloat = 12
    static let trafficLightGap: CGFloat = 5
    static let trafficLightClusterWidth: CGFloat = trafficLightSize * 3 + trafficLightGap * 2
    static let libraryToolbarTop: CGFloat = libraryToolbarVisualGap
    static let railTopChromeHeight: CGFloat = libraryToolbarTop + libraryToolbarHeight
    static let trafficLightGuideX: CGFloat = railIconVisualGuideX
    static let trafficLightGuideY: CGFloat = libraryToolbarTop + (libraryToolbarHeight - trafficLightSize) / 2
    static let libraryToolbarLeadingInset: CGFloat = libraryContentInset
    static let libraryToolbarTrailingInset: CGFloat = libraryContentInset
    static let settingsRailWidth: CGFloat = max(railWidth, trafficLightGuideX + trafficLightClusterWidth)
    static let timelineLaneHeight: CGFloat = 100
    static let collapsedTimelineLaneHeight: CGFloat = 40
    static let timelineLaneButtonSize: CGFloat = 24
    static let timelineLaneIconSize: CGFloat = 22
    static let timelineLaneVisualGap: CGFloat = (timelineLaneHeight - timelineLaneButtonSize * 3) / 4
    static let timelineLaneContentHeight: CGFloat = timelineLaneHeight - timelineLaneVisualGap * 2
    static let expandedTimelineDetailHeight: CGFloat = 280
    static let sceneTimelineAutoVisibleSceneLimit = 15
    static let sceneTimelineAutoMaxZoom: Double = 240
    static let centeredWaveformViewportSpan: Double = 0.22
    static let previewExportOverlayWidthRatio: CGFloat = 1.0 / 3.0
    static let previewExportOverlayMinWidth: CGFloat = 260
    static let previewExportOverlayButtonSize: CGFloat = 28
    static let previewExportOverlayButtonIconSize: CGFloat = 13
    static let previewExportOverlayButtonInset: CGFloat = 10
    static let previewExportPanelPadding: CGFloat = 10
    static let libraryToolbarIconTint = Color.white.opacity(0.72)

    // 侧边栏（icon rail + 内容区）统一同色，主内容略亮，形成嵌套层次感
    static let sidebarBg = Color(red: 0.118, green: 0.118, blue: 0.129)
    static let contentBg = Color(red: 0.149, green: 0.149, blue: 0.165)

    static let neutralAccent = Color.white.opacity(0.72)
    static let neutralStrongAccent = Color.white.opacity(0.88)
    static let neutralBadgeFill = Color.white.opacity(0.18)
    static let tagChipForeground = Color.white.opacity(0.88)
    static let tagChipFill = Color.white.opacity(0.075)
    static let tagChipProminentFill = Color.white.opacity(0.12)
    static let tagChipStroke = Color.white.opacity(0.13)
    static let tagChipSelectedFill = Color.white.opacity(0.16)
    static let tagChipSelectedStroke = Color.white.opacity(0.26)
    static let timelineIOAccent = Color(red: 1.00, green: 0.50, blue: 0.18)
    static let timelinePlayheadAccent = Color.white.opacity(0.92)
    static let screenshotFrameAccent = Color(red: 1.00, green: 0.50, blue: 0.18)
    static let currentFrameAccent = Color(red: 1.00, green: 0.16, blue: 0.12)
    static let captureFrameAccent = neutralAccent
    static let annotationAccent = Color(red: 0.68, green: 0.72, blue: 0.72)

    static func numericFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static func numericCaption(weight: Font.Weight = .regular) -> Font {
        numericFont(size: 12, weight: weight)
    }

    static func numericCaption2(weight: Font.Weight = .regular) -> Font {
        numericFont(size: 11, weight: weight)
    }
}

struct SearchFieldPopover {
    var content: AnyView
    var size: NSSize
}

struct LibraryToolbarSearchField: View {
    let placeholder: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    @Binding var text: String
    var searchPopover: SearchFieldPopover? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ClickActivatedSearchTextField(
                placeholder: placeholder,
                text: $text,
                accessibilityLabel: accessibilityLabel,
                accessibilityIdentifier: accessibilityIdentifier,
                searchPopover: searchPopover
            )
        }
        .padding(.horizontal, 9)
        .frame(
            minWidth: Design.libraryToolbarSearchMinWidth,
            idealWidth: Design.libraryToolbarSearchWidth,
            maxWidth: Design.libraryToolbarSearchWidth,
            minHeight: Design.libraryToolbarSearchHeight,
            maxHeight: Design.libraryToolbarSearchHeight
        )
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct LibraryToolbar<Actions: View>: View {
    let placeholder: String
    let searchAccessibilityLabel: String
    let searchAccessibilityIdentifier: String
    @Binding private var text: String
    private let actions: () -> Actions
    private let searchPopover: SearchFieldPopover?

    init(
        placeholder: String,
        text: Binding<String>,
        searchAccessibilityLabel: String = L10n.text("搜索"),
        searchAccessibilityIdentifier: String = "library_toolbar_search_field",
        searchPopover: SearchFieldPopover? = nil,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.placeholder = placeholder
        self.searchAccessibilityLabel = searchAccessibilityLabel
        self.searchAccessibilityIdentifier = searchAccessibilityIdentifier
        self._text = text
        self.actions = actions
        self.searchPopover = searchPopover
    }

    var body: some View {
        HStack(spacing: Design.libraryToolbarButtonGap) {
            LibraryToolbarSearchField(
                placeholder: placeholder,
                accessibilityLabel: searchAccessibilityLabel,
                accessibilityIdentifier: searchAccessibilityIdentifier,
                text: $text,
                searchPopover: searchPopover
            )

            LibraryToolbarActionRow {
                actions()
            }
        }
        .frame(maxWidth: .infinity, minHeight: Design.libraryToolbarHeight, alignment: .leading)
        .padding(.horizontal, Design.libraryContentInset)
    }
}

struct LibraryToolbarActionRow<Actions: View>: View {
    private let actions: () -> Actions

    init(@ViewBuilder actions: @escaping () -> Actions) {
        self.actions = actions
    }

    var body: some View {
        HStack(spacing: Design.libraryToolbarButtonGap) {
            actions()
        }
        .frame(
            width: Design.libraryToolbarActionRowWidth,
            height: Design.libraryToolbarButtonSlotHeight,
            alignment: .leading
        )
    }
}

struct LibraryToolbarActionPlaceholder: View {
    var body: some View {
        Color.clear
            .frame(
                width: Design.libraryToolbarButtonSlotWidth,
                height: Design.libraryToolbarButtonSlotHeight
            )
            .accessibilityHidden(true)
    }
}

struct TopChromeBoundedContent<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }
}

func libraryToolbarIcon(
    systemName: String,
    size: CGFloat,
    opticalOffsetX: CGFloat = 0,
    tint: Color = Design.libraryToolbarIconTint
) -> some View {
    Image(systemName: systemName)
        .font(.system(size: size, weight: .semibold))
        .symbolRenderingMode(.monochrome)
        .foregroundStyle(tint)
        .frame(
            width: Design.libraryToolbarButtonSlotWidth,
            height: Design.libraryToolbarButtonSlotHeight,
            alignment: .center
        )
        .offset(x: opticalOffsetX)
}

func libraryToolbarBadge(_ count: Int) -> some View {
    Text("\(count)")
        .font(.system(size: 8, weight: .bold))
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .background(Design.neutralBadgeFill)
        .clipShape(Capsule())
        .offset(x: 4, y: -3)
}

struct ClickActivatedSearchTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    var searchPopover: SearchFieldPopover? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> SearchNSTextField {
        let textField = SearchNSTextField()
        if searchPopover != nil { textField.cell = SearchPopoverTextFieldCell(textCell: "") }
        textField.isEditable = true
        textField.isSelectable = true
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        textField.textColor = .labelColor
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.setAccessibilityLabel(accessibilityLabel)
        textField.setAccessibilityIdentifier(accessibilityIdentifier)
        context.coordinator.configure(searchPopover, field: textField)
        return textField
    }

    func updateNSView(_ nsView: SearchNSTextField, context: Context) {
        context.coordinator.text = $text
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        nsView.setAccessibilityLabel(accessibilityLabel)
        nsView.setAccessibilityIdentifier(accessibilityIdentifier)
        context.coordinator.configure(searchPopover, field: nsView)
    }

    static func dismantleNSView(_ nsView: SearchNSTextField, coordinator: Coordinator) {
        coordinator.popover.close()
        nsView.onActivate = nil
    }

    final class Coordinator: NSObject, NSTextFieldDelegate, NSPopoverDelegate {
        var text: Binding<String>
        let popover = NSPopover()
        private var configuration: SearchFieldPopover?
        private weak var field: SearchNSTextField?
        private var host: NSHostingController<AnyView>?

        init(text: Binding<String>) {
            self.text = text
            super.init()
            popover.behavior = .semitransient
            popover.animates = false
            popover.delegate = self
        }

        func configure(_ configuration: SearchFieldPopover?, field: SearchNSTextField) {
            self.configuration = configuration
            self.field = field
            field.onActivate = { [weak self] in self?.showPopover() }
            field.onDetach = { [weak self] in self?.popover.close() }
            guard let configuration else {
                popover.close()
                return
            }
            if popover.isShown {
                host?.rootView = popoverContent(configuration)
                popover.contentSize = configuration.size
            }
        }

        private func popoverContent(_ configuration: SearchFieldPopover) -> AnyView {
            AnyView(configuration.content.onExitCommand { [weak self] in self?.popover.close() })
        }

        func showPopover() {
            guard !popover.isShown, let configuration, let field, let window = field.window else { return }
            // Keep the original editor and selection: the popover contains results, not a second input.
            let editor = field.currentEditor()
            let selection = editor?.selectedRange
            let controller = NSHostingController(rootView: popoverContent(configuration))
            host = controller
            popover.contentViewController = controller
            popover.contentSize = configuration.size
            popover.appearance = field.effectiveAppearance
            popover.show(relativeTo: field.bounds, of: field, preferredEdge: .maxY)
            if editor != nil {
                window.makeKey()
                field.restoreSearchEditor()
                if let selection { field.currentEditor()?.selectedRange = selection }
            }
        }

        func popoverShouldClose(_ popover: NSPopover) -> Bool {
            guard let field, let event = NSApp.currentEvent, event.window === field.window else { return true }
            if event.type == .keyDown || event.type == .keyUp {
                return event.keyCode == 53 || field.currentEditor() == nil
            }
            // Native dismissal must not consume clicks/drags in the anchoring editor.
            return !field.bounds.contains(field.convert(event.locationInWindow, from: nil))
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)), popover.isShown else { return false }
            popover.close()
            return true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text.wrappedValue = textField.stringValue
            showPopover()
        }
    }
}

// AppKit routes clicks to the field editor once editing has begun. Keep this editor local
// to popover-enabled fields so reopening never needs an application-wide mouse monitor.
final class SearchPopoverTextFieldCell: NSTextFieldCell {
    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        (controlView as? SearchNSTextField)?.popoverFieldEditor
    }
}

final class SearchPopoverFieldEditor: NSTextView {
    var onActivate: (() -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onActivate?()
    }
}

final class SearchNSTextField: NSTextField {
    private var isMouseActivating = false
    var onActivate: (() -> Void)?
    var onDetach: (() -> Void)?
    lazy var popoverFieldEditor: SearchPopoverFieldEditor = {
        let editor = SearchPopoverFieldEditor()
        editor.isFieldEditor = true
        editor.onActivate = { [weak self] in self?.onActivate?() }
        return editor
    }()

    func restoreSearchEditor() {
        isMouseActivating = true
        defer { isMouseActivating = false }
        window?.makeFirstResponder(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { onDetach?() }
    }

    // Borderless text fields must still own mouse drags for text selection.
    override var mouseDownCanMoveWindow: Bool { false }

    override var acceptsFirstResponder: Bool {
        isMouseActivating || currentEditor() != nil
    }

    override func mouseDown(with event: NSEvent) {
        isMouseActivating = true
        defer { isMouseActivating = false }
        super.mouseDown(with: event)
        onActivate?()
    }
}

@ViewBuilder
func floatingExportButtonIcon(
    systemImage: String = "square.and.arrow.up",
    size: CGFloat = 24,
    iconSize: CGFloat? = nil
) -> some View {
    if systemImage.hasPrefix("square.and.arrow") {
        Image(systemName: "ellipsis")
            .font(.system(size: iconSize ?? min(13, size * 0.48), weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
    } else {
        Image(systemName: systemImage)
            .font(.system(size: iconSize ?? min(13, size * 0.48), weight: .semibold))
            .foregroundStyle(.white.opacity(0.94))
            .frame(width: size, height: size)
            .background(.white.opacity(0.16))
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.28), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .contentShape(Circle())
    }
}
