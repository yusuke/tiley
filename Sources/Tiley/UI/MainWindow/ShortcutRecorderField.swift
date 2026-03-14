import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcut: HotKeyShortcut
    var onRecordingChange: ((Bool) -> Void)?

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onShortcutChange = { newShortcut in
            shortcut = newShortcut
        }
        button.onRecordingChange = onRecordingChange
        button.shortcut = shortcut
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.onShortcutChange = { newShortcut in
            shortcut = newShortcut
        }
        nsView.onRecordingChange = onRecordingChange
        if nsView.shortcut != shortcut {
            nsView.applyShortcut(shortcut)
        }
    }
}

struct OptionalShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcut: HotKeyShortcut?
    var isRecordingActive = false
    var placeholder = NSLocalizedString("Record Global", comment: "Shortcut recorder placeholder")
    var onClick: (() -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    var validateShortcut: ((HotKeyShortcut) -> String?)?

    func makeNSView(context: Context) -> OptionalRecorderButton {
        let button = OptionalRecorderButton()
        button.onShortcutChange = { newShortcut in
            shortcut = newShortcut
        }
        button.placeholderTitle = placeholder
        button.onClick = onClick
        button.onRecordingChange = onRecordingChange
        button.validateShortcut = validateShortcut
        button.shortcut = shortcut
        return button
    }

    func updateNSView(_ nsView: OptionalRecorderButton, context: Context) {
        nsView.onShortcutChange = { newShortcut in
            shortcut = newShortcut
        }
        nsView.placeholderTitle = placeholder
        nsView.onClick = onClick
        nsView.onRecordingChange = onRecordingChange
        nsView.validateShortcut = validateShortcut
        if nsView.shortcut != shortcut {
            nsView.applyShortcut(shortcut)
        }
        if !isRecordingActive {
            nsView.stopRecording()
        }
    }
}

final class RecorderButton: NSButton {
    var onShortcutChange: ((HotKeyShortcut) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    var shortcut = HotKeyShortcut.default {
        didSet {
            updateTitle()
        }
    }
    private var recordingMonitor: Any?

    private var isRecording = false {
        didSet {
            if isRecording {
                installRecordingMonitor()
            } else {
                removeRecordingMonitor()
            }
            onRecordingChange?(isRecording)
            updateTitle()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        isBordered = true
        font = .systemFont(ofSize: 13, weight: .medium)
        focusRingType = .default
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 220, height: 32)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func resignFirstResponder() -> Bool {
        abortRecording(clearFocus: false)
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        handleRecordingEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }

        handleRecordingEvent(event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        if isRecording {
            return
        }
        super.flagsChanged(with: event)
    }

    func applyShortcut(_ shortcut: HotKeyShortcut) {
        self.shortcut = shortcut
        isRecording = false
    }

    override func cancelOperation(_ sender: Any?) {
        if isRecording {
            abortRecording()
            return
        }
        super.cancelOperation(sender)
    }

    private func abortRecording() {
        abortRecording(clearFocus: true)
    }

    private func handleRecordingEvent(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            abortRecording()
            return
        }

        guard let shortcut = HotKeyShortcut.from(event: event) else {
            NSSound.beep()
            return
        }

        if shortcut == self.shortcut {
            abortRecording()
            return
        }

        onShortcutChange?(shortcut)
        abortRecording()
    }

    private func abortRecording(clearFocus: Bool) {
        isRecording = false
        if clearFocus {
            window?.makeFirstResponder(nil)
        }
    }

    private func installRecordingMonitor() {
        guard recordingMonitor == nil else { return }
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            guard self.isRecording else { return event }

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

    private func updateTitle() {
        title = isRecording ? NSLocalizedString("Type shortcut", comment: "Shortcut recorder recording state") : shortcut.displayString
    }
}

final class OptionalRecorderButton: NSButton {
    var onShortcutChange: ((HotKeyShortcut?) -> Void)?
    var onClick: (() -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    var validateShortcut: ((HotKeyShortcut) -> String?)?
    var placeholderTitle = NSLocalizedString("Record Global", comment: "Shortcut recorder placeholder") {
        didSet {
            updateTitle()
        }
    }
    var shortcut: HotKeyShortcut? {
        didSet {
            updateTitle()
        }
    }
    private var recordingMonitor: Any?
    private var validationPopover: NSPopover?
    private var validationDismissTask: Task<Void, Never>?

    private var isRecording = false {
        didSet {
            if isRecording {
                installRecordingMonitor()
            } else {
                removeRecordingMonitor()
            }
            onRecordingChange?(isRecording)
            updateTitle()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        isBordered = true
        font = .systemFont(ofSize: 13, weight: .medium)
        focusRingType = .default
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 160, height: 28)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func resignFirstResponder() -> Bool {
        abortRecording(clearFocus: false)
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        handleRecordingEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }
        handleRecordingEvent(event)
        return true
    }

    override func cancelOperation(_ sender: Any?) {
        if isRecording {
            abortRecording(clearFocus: true)
            return
        }
        super.cancelOperation(sender)
    }

    func applyShortcut(_ shortcut: HotKeyShortcut?) {
        self.shortcut = shortcut
        isRecording = false
    }

    func stopRecording() {
        guard isRecording else { return }
        abortRecording(clearFocus: true)
    }

    private func handleRecordingEvent(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            abortRecording(clearFocus: true)
            return
        }

        guard let shortcut = HotKeyShortcut.from(event: event, requireModifiers: false) else {
            NSSound.beep()
            return
        }

        if shortcut == self.shortcut {
            abortRecording(clearFocus: true)
            return
        }

        if let message = validateShortcut?(shortcut) {
            NSSound.beep()
            showValidationPopover(message: message)
            return
        }

        onShortcutChange?(shortcut)
        abortRecording(clearFocus: true)
    }

    private func abortRecording(clearFocus: Bool) {
        isRecording = false
        if clearFocus {
            window?.makeFirstResponder(nil)
        }
    }

    private func installRecordingMonitor() {
        guard recordingMonitor == nil else { return }
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            guard self.isRecording else { return event }

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

    private func updateTitle() {
        if isRecording {
            title = NSLocalizedString("Type shortcut", comment: "Shortcut recorder recording state")
        } else {
            title = shortcut?.displayString ?? placeholderTitle
        }
    }
}
