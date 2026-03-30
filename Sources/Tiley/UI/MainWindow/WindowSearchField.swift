import AppKit
import SwiftUI

// MARK: - Window Search Field (NSViewRepresentable)

/// A search field that intercepts Tab, Shift+Tab, and Escape before the system
/// focus navigation handles them.  Focus is driven by integer triggers rather
/// than `@FocusState` because the latter does not work with NSViewRepresentable.
struct WindowSearchField: NSViewRepresentable {
    @Binding var text: String
    var focusTrigger: Int
    var blurTrigger: Int
    var onTab: (_ forward: Bool) -> Void
    var onEscape: () -> Void
    var onFocusChange: ((_ focused: Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = NSLocalizedString(
            "Type to filter", comment: "Window filter search field placeholder"
        )
        field.font = NSFont.systemFont(ofSize: 11)
        field.focusRingType = .none
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.textChanged(_:))
        context.coordinator.lastFocusTrigger = focusTrigger
        context.coordinator.lastBlurTrigger = blurTrigger
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        if focusTrigger != context.coordinator.lastFocusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            // Dispatch to next run loop so the field's window is ready.
            DispatchQueue.main.async { [onFocusChange] in
                field.window?.makeFirstResponder(field)
                onFocusChange?(true)
            }
        }
        if blurTrigger != context.coordinator.lastBlurTrigger {
            context.coordinator.lastBlurTrigger = blurTrigger
            if field.window?.firstResponder == field.currentEditor() {
                field.window?.makeFirstResponder(nil)
            }
            DispatchQueue.main.async { [onFocusChange] in
                onFocusChange?(false)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: WindowSearchField
        var lastFocusTrigger: Int = 0
        var lastBlurTrigger: Int = 0

        init(parent: WindowSearchField) {
            self.parent = parent
        }

        @objc func textChanged(_ sender: NSSearchField) {
            parent.text = sender.stringValue
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            let onFocus = parent.onFocusChange
            DispatchQueue.main.async { onFocus?(true) }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            let onFocus = parent.onFocusChange
            DispatchQueue.main.async { onFocus?(false) }
        }

        func control(
            _ control: NSControl, textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                let onTab = parent.onTab
                let onFocus = parent.onFocusChange
                DispatchQueue.main.async { onTab(true); onFocus?(false) }
                return true
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                let onTab = parent.onTab
                let onFocus = parent.onFocusChange
                DispatchQueue.main.async { onTab(false); onFocus?(false) }
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                let onTab = parent.onTab
                let onFocus = parent.onFocusChange
                DispatchQueue.main.async { onTab(true); onFocus?(false) }
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                let onTab = parent.onTab
                let onFocus = parent.onFocusChange
                DispatchQueue.main.async { onTab(false); onFocus?(false) }
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                control.window?.makeFirstResponder(nil)
                let onFocus = parent.onFocusChange
                DispatchQueue.main.async { onFocus?(false) }
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                let onEscape = parent.onEscape
                DispatchQueue.main.async { onEscape() }
                return true
            }
            return false
        }
    }
}
