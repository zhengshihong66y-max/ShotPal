//
//  InlineTagRenameTextField.swift
//  LapianBao
//
//  Shared AppKit-backed inline tag rename field.
//

import AppKit
import SwiftUI

struct InlineTagRenameTextField: NSViewRepresentable {
    @Binding var text: String
    let isFocused: Bool
    let textColor: NSColor
    var fontSize: CGFloat = 10
    var fontWeight: NSFont.Weight = .semibold
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
    }

    func makeNSView(context: Context) -> InlineTagRenameNSTextField {
        let textField = InlineTagRenameNSTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: fontSize, weight: fontWeight)
        textField.textColor = textColor
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.stringValue = text
        return textField
    }

    func updateNSView(_ nsView: InlineTagRenameNSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onCommit = onCommit
        nsView.font = .systemFont(ofSize: fontSize, weight: fontWeight)
        nsView.textColor = textColor
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        guard isFocused else {
            context.coordinator.didApplyFocus = false
            return
        }
        guard !context.coordinator.didApplyFocus else { return }
        context.coordinator.didApplyFocus = true
        DispatchQueue.main.async {
            if let editor = nsView.currentEditor(), nsView.window?.firstResponder === editor {
                return
            }
            nsView.window?.makeFirstResponder(nsView)
            nsView.placeCaretAtEnd()
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onCommit: () -> Void
        var didApplyFocus = false

        init(text: Binding<String>, onCommit: @escaping () -> Void) {
            self.text = text
            self.onCommit = onCommit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text.wrappedValue = textField.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                text.wrappedValue = textView.string
                onCommit()
                return true
            }
            return false
        }
    }
}

final class InlineTagRenameNSTextField: NSTextField {
    func placeCaretAtEnd() {
        guard let editor = currentEditor() else { return }
        editor.selectedRange = NSRange(location: editor.string.count, length: 0)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            DispatchQueue.main.async { [weak self] in
                self?.placeCaretAtEnd()
            }
        }
        return result
    }
}
