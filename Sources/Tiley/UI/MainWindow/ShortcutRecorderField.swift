import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcut: HotKeyShortcut
    var onRecordingChange: ((Bool) -> Void)?

    func makeNSView(context: Context) -> RecorderTextField {
        let field = RecorderTextField()
        field.onShortcutChange = { newShortcut in
            shortcut = newShortcut
        }
        field.onRecordingChange = onRecordingChange
        field.shortcut = shortcut
        return field
    }

    func updateNSView(_ nsView: RecorderTextField, context: Context) {
        nsView.onShortcutChange = { newShortcut in
            shortcut = newShortcut
        }
        nsView.onRecordingChange = onRecordingChange
        if nsView.shortcut != shortcut {
            nsView.applyShortcut(shortcut)
        }
    }
}

private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var titleRect = super.titleRect(forBounds: rect)
        let textHeight = cellSize(forBounds: rect).height
        titleRect.origin.y = rect.origin.y + (rect.height - textHeight) / 2
        titleRect.size.height = textHeight
        return titleRect
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: titleRect(forBounds: cellFrame), in: controlView)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }
}

final class RecorderTextField: NSTextField {
    var onShortcutChange: ((HotKeyShortcut) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    var shortcut = HotKeyShortcut.default {
        didSet {
            updateDisplay()
        }
    }
    private var recordingMonitor: Any?

    private var isRecording = false {
        didSet {
            guard oldValue != isRecording else { return }
            if isRecording {
                installRecordingMonitor()
            } else {
                removeRecordingMonitor()
                isEditable = false
                isSelectable = false
                applyLabelAppearance()
            }
            onRecordingChange?(isRecording)
            updateDisplay()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let centeredCell = VerticallyCenteredTextFieldCell()
        centeredCell.isScrollable = true
        centeredCell.sendsActionOnEndEditing = false
        cell = centeredCell
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        wantsLayer = true
        font = .systemFont(ofSize: 11, weight: .medium)
        focusRingType = .none
        alignment = .center
        applyLabelAppearance()
        updateDisplay()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 140, height: 22)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        startRecording()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        return result
    }

    override func textDidEndEditing(_ notification: Notification) {
        isRecording = false
        updateDisplay()
        super.textDidEndEditing(notification)
    }

    override func textDidChange(_ notification: Notification) {
        stringValue = ""
    }

    override func cancelOperation(_ sender: Any?) {
        isRecording = false
        updateDisplay()
        window?.makeFirstResponder(nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }
        handleRecordingEvent(event)
        return true
    }

    func applyShortcut(_ shortcut: HotKeyShortcut) {
        self.shortcut = shortcut
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    private func startRecording() {
        applyFieldAppearance()
        isEditable = true
        isSelectable = true
        stringValue = ""
        window?.makeFirstResponder(self)
        isRecording = true
    }

    private func stopRecording() {
        isRecording = false
        isEditable = false
        isSelectable = false
        applyLabelAppearance()
        window?.makeFirstResponder(nil)
    }

    private func applyLabelAppearance() {
        isBezeled = false
        drawsBackground = false
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        textColor = .labelColor
    }

    private func applyFieldAppearance() {
        layer?.backgroundColor = nil
        isBezeled = true
        bezelStyle = .roundedBezel
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        textColor = .labelColor
    }

    private func handleRecordingEvent(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        guard let shortcut = HotKeyShortcut.from(event: event) else {
            NSSound.beep()
            return
        }

        if shortcut == self.shortcut {
            stopRecording()
            return
        }

        onShortcutChange?(shortcut)
        stopRecording()
    }

    private func installRecordingMonitor() {
        guard recordingMonitor == nil else { return }
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            switch event.type {
            case .keyDown:
                self.handleRecordingEvent(event)
                return nil
            case .flagsChanged:
                return nil
            default:
                return event
            }
        }
    }

    private func removeRecordingMonitor() {
        guard let recordingMonitor else { return }
        NSEvent.removeMonitor(recordingMonitor)
        self.recordingMonitor = nil
    }

    private func updateDisplay() {
        if isRecording {
            stringValue = ""
        } else {
            stringValue = shortcut.displayString
        }
    }
}

struct CompactShortcutRecorderField: NSViewRepresentable {
    var onShortcutRecorded: (HotKeyShortcut) -> Void
    var onRecordingChange: ((Bool) -> Void)?
    var validateShortcut: ((HotKeyShortcut) -> String?)?

    func makeNSView(context: Context) -> CompactRecorderTextField {
        let field = CompactRecorderTextField()
        field.onShortcutRecorded = onShortcutRecorded
        field.onRecordingChange = onRecordingChange
        field.validateShortcut = validateShortcut
        Task { @MainActor in
            guard let window = field.window else { return }
            window.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: CompactRecorderTextField, context: Context) {
        nsView.onShortcutRecorded = onShortcutRecorded
        nsView.onRecordingChange = onRecordingChange
        nsView.validateShortcut = validateShortcut
    }
}

final class CompactRecorderTextField: NSTextField {
    var onShortcutRecorded: ((HotKeyShortcut) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    var validateShortcut: ((HotKeyShortcut) -> String?)?
    private var recordingMonitor: Any?
    private var validationPopover: NSPopover?
    private var validationDismissTask: Task<Void, Never>?

    private var isRecording = false {
        didSet {
            guard oldValue != isRecording else { return }
            if isRecording {
                installRecordingMonitor()
            } else {
                removeRecordingMonitor()
            }
            onRecordingChange?(isRecording)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stringValue = ""
        isEditable = true
        isSelectable = true
        isBezeled = true
        bezelStyle = .roundedBezel
        font = .systemFont(ofSize: 11)
        focusRingType = .default
        placeholderString = nil
        cell?.sendsActionOnEndEditing = false
        cell?.isScrollable = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 120, height: 22)
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            isRecording = true
        }
        return result
    }

    override func textDidEndEditing(_ notification: Notification) {
        isRecording = false
        stringValue = ""
        super.textDidEndEditing(notification)
    }

    override func textDidChange(_ notification: Notification) {
        // Prevent any text from being typed into the field
        stringValue = ""
    }

    override func cancelOperation(_ sender: Any?) {
        isRecording = false
        stringValue = ""
        window?.makeFirstResponder(nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }
        handleRecordingEvent(event)
        return true
    }

    private func handleRecordingEvent(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            stringValue = ""
            window?.makeFirstResponder(nil)
            return
        }

        guard let shortcut = HotKeyShortcut.from(event: event, requireModifiers: false) else {
            NSSound.beep()
            return
        }

        if let message = validateShortcut?(shortcut) {
            NSSound.beep()
            showValidationPopover(message: message)
            return
        }

        stringValue = ""
        onShortcutRecorded?(shortcut)
    }

    private func installRecordingMonitor() {
        guard recordingMonitor == nil else { return }
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            switch event.type {
            case .keyDown:
                self.handleRecordingEvent(event)
                return nil
            case .flagsChanged:
                return nil
            default:
                return event
            }
        }
    }

    private func removeRecordingMonitor() {
        guard let recordingMonitor else { return }
        NSEvent.removeMonitor(recordingMonitor)
        self.recordingMonitor = nil
    }

    private func showValidationPopover(message: String) {
        validationDismissTask?.cancel()

        let label = NSTextField(labelWithString: message)
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textColor = .labelColor
        label.font = .systemFont(ofSize: 12)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 1))
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            container.widthAnchor.constraint(equalToConstant: 220)
        ])

        let controller = NSViewController()
        controller.view = container

        let popover = validationPopover ?? NSPopover()
        popover.behavior = .semitransient
        popover.animates = true
        popover.contentSize = NSSize(width: 220, height: 44)
        popover.contentViewController = controller
        validationPopover = popover

        if popover.isShown {
            popover.close()
        }
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)

        validationDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.0))
            guard !Task.isCancelled else { return }
            self?.validationPopover?.close()
        }
    }
}
