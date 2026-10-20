import AppKit
import SwiftUI

// MARK: - Model

/// One destination desktop in the space picker.
struct SpacePickerItem: Identifiable {
    let id: UInt64
    /// 1-based desktop number on its display ("Desktop 3").
    let desktopNumber: Int
    /// True for the space the window is already on.
    let isWindowSpace: Bool
    let appIcons: [NSImage]

    /// The digit that picks this desktop: 1–9, then 0 for the tenth.
    var keyLabel: String? {
        switch desktopNumber {
        case 1...9: return String(desktopNumber)
        case 10: return "0"
        default: return nil
        }
    }
}

struct SpacePickerContent {
    let appIcon: NSImage?
    let windowLabel: String
    let displayName: String
    let items: [SpacePickerItem]
    /// Shown when the system shortcuts Tiley needs are turned off.
    let warning: String?
    /// True when the window is already pinned to all Spaces.
    let isPinned: Bool
    /// Other windows pinned to all Spaces, which can be unpinned from here
    /// even though the picker targets the focused window.
    let otherPinned: [PinnedWindowItem]

    /// The key that toggles Pin to All Spaces; with Shift it unpins everything.
    static let pinKey = "p"
}

/// A pinned window listed in the picker.
struct PinnedWindowItem: Identifiable {
    let id: CGWindowID
    let appIcon: NSImage?
    let label: String
}

// MARK: - Style constants

private enum PickerStyle {
    static let tileWidth: CGFloat = 132
    static let tileHeight: CGFloat = 84
    static let tileSpacing: CGFloat = 10
    static let maxColumns = 5
    static let maxIconsPerTile = 5
    static let iconSize: CGFloat = 22
    static let cornerRadius: CGFloat = 16
    static let tileCornerRadius: CGFloat = 10
    static let padding: CGFloat = 18
}

// MARK: - Controller

/// A floating, keyboard-driven picker that lists the Mission Control desktops
/// of one display. Press a number (or click a tile) to pick; Esc cancels.
@MainActor
final class SpacePickerController {
    private var panel: SpacePickerPanel?
    private let onPick: (UInt64) -> Void
    private let onTogglePin: () -> Void
    private let onUnpin: ([CGWindowID]) -> Void
    private let onCancel: () -> Void
    private let items: [SpacePickerItem]
    private let canTogglePin: Bool
    /// Every pinned window, the target included when it is pinned.
    private let allPinnedIDs: [CGWindowID]
    private var finished = false

    init(content: SpacePickerContent, on screen: NSScreen,
         onPick: @escaping (UInt64) -> Void,
         onTogglePin: @escaping () -> Void,
         onUnpin: @escaping ([CGWindowID]) -> Void,
         targetWindowID: CGWindowID,
         onCancel: @escaping () -> Void) {
        self.onPick = onPick
        self.onTogglePin = onTogglePin
        self.onUnpin = onUnpin
        self.allPinnedIDs = content.otherPinned.map(\.id) + (content.isPinned ? [targetWindowID] : [])
        self.onCancel = onCancel
        self.items = content.items
        // Unpinning always works; pinning needs the switch shortcuts.
        self.canTogglePin = content.isPinned || content.warning == nil

        let view = SpacePickerView(
            content: content,
            onPick: { [weak self] id in self?.pick(id) },
            onTogglePin: { [weak self] in self?.togglePin() },
            onUnpin: { [weak self] id in self?.unpin([id]) },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        let panel = SpacePickerPanel(contentRect: NSRect(origin: origin, size: size))
        panel.contentView = hosting
        panel.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        panel.onResignKey = { [weak self] in self?.cancel() }
        self.panel = panel
    }

    func show() {
        panel?.makeKeyAndOrderFront(nil)
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        close()
        onCancel()
    }

    private func pick(_ id: UInt64) {
        guard !finished, let item = items.first(where: { $0.id == id }), !item.isWindowSpace else { return }
        finished = true
        close()
        onPick(id)
    }

    private func togglePin() {
        guard !finished, canTogglePin else { return }
        finished = true
        close()
        onTogglePin()
    }

    private func unpin(_ ids: [CGWindowID]) {
        guard !finished, !ids.isEmpty else { return }
        finished = true
        close()
        onUnpin(ids)
    }

    /// Closes the picker and opens the Mission Control shortcut settings.
    private func openSettings() {
        cancel()
        SpaceMover.openMissionControlShortcutSettings()
    }

    private func close() {
        panel?.onResignKey = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Escape
            cancel()
            return true
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers == "," {
            openSettings()
            return true
        }
        if modifiers == .shift, event.charactersIgnoringModifiers?.lowercased() == SpacePickerContent.pinKey {
            if allPinnedIDs.isEmpty { NSSound.beep() } else { unpin(allPinnedIDs) }
            return true
        }
        if modifiers.isEmpty, event.charactersIgnoringModifiers?.lowercased() == SpacePickerContent.pinKey {
            if canTogglePin { togglePin() } else { NSSound.beep() }
            return true
        }
        guard let chars = event.charactersIgnoringModifiers, chars.count == 1,
              let item = items.first(where: { $0.keyLabel == chars }) else {
            NSSound.beep()
            return true
        }
        pick(item.id)
        return true
    }
}

/// Borderless panel that can take keyboard focus without activating Tiley,
/// so the window being moved keeps its app frontmost.
private final class SpacePickerPanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onResignKey: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onResignKey?()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

// MARK: - Views

private struct SpacePickerView: View {
    let content: SpacePickerContent
    let onPick: (UInt64) -> Void
    let onTogglePin: () -> Void
    let onUnpin: (CGWindowID) -> Void
    let onOpenSettings: () -> Void

    /// Desktop tiles plus the All Spaces tile.
    private var tileCount: Int { content.items.count + 1 }

    private var columns: [GridItem] {
        let count = max(1, min(PickerStyle.maxColumns, tileCount))
        return Array(repeating: GridItem(.fixed(PickerStyle.tileWidth), spacing: PickerStyle.tileSpacing), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if let icon = content.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 30, height: 30)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("Move to Space", comment: "Space picker title"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(content.windowLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 16)
                Label(content.displayName, systemImage: "display")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let warning = content.warning {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11))
                .frame(maxWidth: gridWidth, alignment: .leading)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: PickerStyle.tileSpacing) {
                ForEach(content.items) { item in
                    SpaceTile(item: item, isEnabled: content.warning == nil) { onPick(item.id) }
                }
                PinTile(isPinned: content.isPinned,
                        isEnabled: content.isPinned || content.warning == nil,
                        action: onTogglePin)
            }

            if !content.otherPinned.isEmpty {
                PinnedWindowsList(items: content.otherPinned, onUnpin: onUnpin)
                    .frame(maxWidth: gridWidth, alignment: .leading)
            }

            HStack(spacing: 12) {
                Text(NSLocalizedString("Press a number to move the window · P to pin to all spaces · Esc to cancel", comment: "Space picker hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Button(action: onOpenSettings) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                        Text(NSLocalizedString("Mission Control Shortcuts…", comment: "Space picker button that opens the system keyboard shortcut settings"))
                        Text("⌘,")
                            .foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(PickerStyle.padding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: PickerStyle.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PickerStyle.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .fixedSize()
    }

    private var gridWidth: CGFloat {
        let count = CGFloat(max(1, min(PickerStyle.maxColumns, tileCount)))
        return count * PickerStyle.tileWidth + (count - 1) * PickerStyle.tileSpacing
    }
}

private struct SpaceTile: View {
    let item: SpacePickerItem
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    private var selectable: Bool { isEnabled && !item.isWindowSpace }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: PickerStyle.tileCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(isHovered && selectable ? 0.14 : 0.06))

                icons
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let key = item.keyLabel {
                    Text(key)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .frame(minWidth: 22, minHeight: 22)
                        .background(
                            selectable ? Color.accentColor : Color.secondary.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .foregroundStyle(.white)
                        .padding(6)
                }

                VStack {
                    Spacer()
                    Text(item.isWindowSpace
                         ? NSLocalizedString("Current", comment: "Space picker: the window's current space")
                         : String(format: NSLocalizedString("Desktop %d", comment: "Mission Control desktop name"), item.desktopNumber))
                        .font(.system(size: 11, weight: item.isWindowSpace ? .semibold : .regular))
                        .foregroundStyle(item.isWindowSpace ? Color.accentColor : .secondary)
                        .padding(.bottom, 6)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(width: PickerStyle.tileWidth, height: PickerStyle.tileHeight)
            .overlay(
                RoundedRectangle(cornerRadius: PickerStyle.tileCornerRadius, style: .continuous)
                    .strokeBorder(item.isWindowSpace ? Color.accentColor : Color.primary.opacity(0.1),
                                  lineWidth: item.isWindowSpace ? 2 : 1)
            )
            .opacity(selectable || item.isWindowSpace ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var icons: some View {
        let shown = item.appIcons.prefix(PickerStyle.maxIconsPerTile)
        let extra = item.appIcons.count - shown.count
        HStack(spacing: 3) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, icon in
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: PickerStyle.iconSize, height: PickerStyle.iconSize)
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }
}

/// Pins the window to all Spaces, or unpins it when it already is.
private struct PinTile: View {
    let isPinned: Bool
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: PickerStyle.tileCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(isHovered && isEnabled ? 0.14 : 0.06))

                Image(systemName: isPinned ? "pin.slash" : "pin.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isPinned ? Color.accentColor : .secondary)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(SpacePickerContent.pinKey.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(minWidth: 22, minHeight: 22)
                    .background(
                        isEnabled ? Color.accentColor : Color.secondary.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .foregroundStyle(.white)
                    .padding(6)

                VStack {
                    Spacer()
                    Text(isPinned
                         ? NSLocalizedString("Unpin", comment: "Space picker: tile that unpins the window from all spaces")
                         : NSLocalizedString("Pin This Window", comment: "Space picker: tile that pins the picker's window to all spaces"))
                        .font(.system(size: 11, weight: isPinned ? .semibold : .regular))
                        .foregroundStyle(isPinned ? Color.accentColor : .secondary)
                        .padding(.bottom, 6)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(width: PickerStyle.tileWidth, height: PickerStyle.tileHeight)
            .overlay(
                RoundedRectangle(cornerRadius: PickerStyle.tileCornerRadius, style: .continuous)
                    .strokeBorder(isPinned ? Color.accentColor : Color.primary.opacity(0.1),
                                  style: StrokeStyle(lineWidth: isPinned ? 2 : 1, dash: isPinned ? [] : [4, 3]))
            )
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .help(isPinned
              ? NSLocalizedString("Stop keeping this window on every desktop", comment: "Space picker: tooltip for the unpin tile")
              : NSLocalizedString("Keep this window on whichever desktop you're on", comment: "Space picker: tooltip for the pin tile"))
    }
}

/// The other pinned windows, each with an unpin button.
private struct PinnedWindowsList: View {
    let items: [PinnedWindowItem]
    let onUnpin: (CGWindowID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(NSLocalizedString("Also pinned to all spaces", comment: "Space picker: heading for the list of other pinned windows"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(NSLocalizedString("⇧P unpins all", comment: "Space picker: hint that Shift-P unpins every pinned window"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            ForEach(items) { item in
                PinnedWindowRow(item: item) { onUnpin(item.id) }
            }
        }
    }
}

private struct PinnedWindowRow: View {
    let item: PinnedWindowItem
    let onUnpin: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            if let icon = item.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Text(item.label)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button(action: onUnpin) {
                Label(NSLocalizedString("Unpin", comment: "Space picker: tile that unpins the window from all spaces"),
                      systemImage: "pin.slash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isHovered ? Color.accentColor : .secondary)
            .onHover { isHovered = $0 }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
