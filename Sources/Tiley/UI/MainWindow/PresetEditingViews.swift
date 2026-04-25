import AppKit
import Carbon
import SwiftUI

struct InlinePresetNameField: NSViewRepresentable {
    @Binding var text: String
    var focusTrigger: Int
    let onCommit: () -> Void
    let onExplicitCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit, onExplicitCommit: onExplicitCommit, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> InlinePresetNameTextField {
        let textField = InlinePresetNameTextField()
        textField.delegate = context.coordinator
        textField.onCommit = context.coordinator.commit
        textField.onCancel = context.coordinator.cancel
        textField.stringValue = text
        context.coordinator.lastFocusTrigger = focusTrigger
        Task { @MainActor in
            guard let window = textField.window else { return }
            window.makeFirstResponder(textField)
            textField.currentEditor()?.selectAll(nil)
        }
        return textField
    }

    func updateNSView(_ nsView: InlinePresetNameTextField, context: Context) {
        nsView.onCommit = context.coordinator.commit
        nsView.onCancel = context.coordinator.cancel
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if focusTrigger != context.coordinator.lastFocusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            Task { @MainActor in
                guard let window = nsView.window else { return }
                window.makeFirstResponder(nsView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        private let onCommit: () -> Void
        private let onExplicitCommit: () -> Void
        private let onCancel: () -> Void
        var lastFocusTrigger: Int = 0

        init(text: Binding<String>, onCommit: @escaping () -> Void, onExplicitCommit: @escaping () -> Void, onCancel: @escaping () -> Void) {
            _text = text
            self.onCommit = onCommit
            self.onExplicitCommit = onExplicitCommit
            self.onCancel = onCancel
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            text = textField.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            text = textField.stringValue
            onCommit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let textField = control as? InlinePresetNameTextField else { return false }
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                textField.suppressEndEditingCommit = true
                onExplicitCommit()
                textField.window?.makeFirstResponder(nil)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                textField.suppressEndEditingCommit = true
                onCancel()
                textField.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }

        func commit() {
            onCommit()
        }

        func cancel() {
            onCancel()
        }
    }
}

final class InlinePresetNameTextField: NSTextField {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var suppressEndEditingCommit = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = true
        isEditable = true
        isSelectable = true
        isBezeled = true
        bezelStyle = .roundedBezel
        drawsBackground = true
        lineBreakMode = .byTruncatingTail
        focusRingType = .default
        font = .systemFont(ofSize: 13)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func textDidEndEditing(_ notification: Notification) {
        if suppressEndEditingCommit {
            suppressEndEditingCommit = false
            return
        }
        super.textDidEndEditing(notification)
    }
}

struct ShortcutBadgeLabelView: View {
    /// Content height inside padding, matching the badge text line height
    static let badgeContentHeight: CGFloat = 13

    let shortcut: HotKeyShortcut
    let isEditing: Bool
    var showDelete: Bool = false
    var onDelete: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil

    @State private var isLabelHovered = false
    @State private var isDeleteHovered = false

    private var isGroupHovered: Bool { isLabelHovered || isDeleteHovered }

    var body: some View {
        HStack(spacing: 0) {
            // Shortcut label area
            HStack(spacing: 3) {
                if shortcut.isGlobal {
                    Image(systemName: "globe")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                Text(shortcut.displayString)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onHover { hovering in
                isLabelHovered = hovering
            }
            .onTapGesture {
                onTap?()
            }
            .modifier(EditingTooltipModifier(isEditing: isEditing, shortcutName: shortcut.displayString))

            if showDelete {
                // Divider
                Rectangle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: 0.5)
                    .padding(.vertical, 2)

                // Delete button area
                Button {
                    guard let onDelete else { return }
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Delete Shortcut", comment: "Alert title for deleting a shortcut")
                    alert.informativeText = String(format: NSLocalizedString("Are you sure you want to delete \"%@\"?", comment: "Alert message for deleting a shortcut with name"), shortcut.displayString)
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: NSLocalizedString("Delete", comment: "Delete button title"))
                    alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button title"))
                    if alert.runModal() == .alertFirstButtonReturn {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isDeleteHovered ? Color.red : Color.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isDeleteHovered = hovering
                }
                .instantTooltip(String(format: NSLocalizedString("Delete \"%@\"", comment: "Tooltip for delete shortcut button with name"), shortcut.displayString))
            }
        }
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.accentColor.opacity(isEditing && isGroupHovered ? 0.25 : 0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(isEditing && isGroupHovered ? Color.accentColor.opacity(0.6) : Color.accentColor.opacity(0.3), lineWidth: isEditing && isGroupHovered ? 1 : 0.5)
        )
    }
}

struct DisplayShortcutBadgeLabelView: View {
    let shortcut: HotKeyShortcut
    let isGlobal: Bool
    var onTap: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var isLabelHovered = false
    @State private var isDeleteHovered = false

    private var isGroupHovered: Bool { isLabelHovered || isDeleteHovered }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                if isGlobal {
                    Image(systemName: "globe")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Text(shortcut.displayString)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onHover { hovering in isLabelHovered = hovering }
            .onTapGesture { onTap?() }
            .instantTooltip(NSLocalizedString("Click to change", comment: "Tooltip for clicking display shortcut badge to edit"))

            // Divider
            Rectangle()
                .fill(Color.accentColor.opacity(0.3))
                .frame(width: 0.5)
                .padding(.vertical, 2)

            // Delete button
            Button {
                onDelete?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isDeleteHovered ? Color.red : Color.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in isDeleteHovered = hovering }
            .instantTooltip(NSLocalizedString("Remove Shortcut", comment: "Tooltip for remove display shortcut button"))
        }
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.accentColor.opacity(isGroupHovered ? 0.25 : 0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(isGroupHovered ? Color.accentColor.opacity(0.6) : Color.accentColor.opacity(0.3), lineWidth: isGroupHovered ? 1 : 0.5)
        )
    }
}

struct AddShortcutButton<Label: View>: View {
    let colorScheme: ColorScheme
    let tooltip: String
    @ViewBuilder let label: Label
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label
                .frame(minHeight: ShortcutBadgeLabelView.badgeContentHeight)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovered ? ThemeColors.presetCellBackground(for: colorScheme).opacity(0.8) : ThemeColors.presetCellBackground(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(isHovered ? Color.accentColor.opacity(0.5) : ThemeColors.presetCellBorder(for: colorScheme), lineWidth: isHovered ? 1 : 0.5)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .instantTooltip(tooltip)
    }
}

struct DeleteLayoutButton: View {
    let colorScheme: ColorScheme
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 14, height: 14)
                .foregroundStyle(isHovered ? .red : .primary)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? ThemeColors.deleteButtonHoverBackground(for: colorScheme) : ThemeColors.editButtonBackground(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isHovered ? Color.red.opacity(0.4) : ThemeColors.presetCellBorder(for: colorScheme), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .instantTooltip(NSLocalizedString("Delete Layout", comment: "Tooltip for delete layout button"))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalHeight = currentY + lineHeight
        }

        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
    }
}

struct PresetGridPreviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    let rows: Int
    let columns: Int
    let selection: GridSelection
    var secondarySelections: [GridSelection] = []
    /// Parallel to `[selection] + secondarySelections`. Assigned slots render
    /// with a neutral fill and an app-icon overlay instead of the indexed
    /// color.
    var rectangleApps: [String?] = []

    var body: some View {
        GeometryReader { geometry in
            let gap: CGFloat = 2
            let cellWidth = max(2, (geometry.size.width - gap * CGFloat(max(0, columns - 1))) / CGFloat(max(columns, 1)))
            let cellHeight = max(2, (geometry.size.height - gap * CGFloat(max(0, rows - 1))) / CGFloat(max(rows, 1)))
            let allSelections = [selection] + secondarySelections

            let paddedApps: [String?] = {
                if rectangleApps.count >= allSelections.count {
                    return Array(rectangleApps.prefix(allSelections.count))
                }
                return rectangleApps + Array(repeating: nil, count: allSelections.count - rectangleApps.count)
            }()

            // Color index for unassigned slots: 1-based position among
            // unassigned-only entries, so the cycle (blue/green/orange/purple)
            // is not shifted by preceding assigned slots.
            let unassignedColorIndex: [Int: Int] = {
                var result: [Int: Int] = [:]
                var cursor = 0
                for (idx, app) in paddedApps.enumerated() where app == nil {
                    result[idx] = cursor
                    cursor += 1
                }
                return result
            }()

            ZStack(alignment: .topLeading) {
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<columns, id: \.self) { column in
                        let matchIndex = allSelections.firstIndex { sel in
                            let n = sel.normalized
                            return n.startRow...n.endRow ~= row && n.startColumn...n.endColumn ~= column
                        }
                        let isAssigned = matchIndex != nil && paddedApps[matchIndex!] != nil
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(matchIndex == nil
                                  ? ThemeColors.presetGridUnselectedFill(for: colorScheme)
                                  : (isAssigned
                                     ? ThemeColors.presetGridUnselectedFill(for: colorScheme)
                                     : ThemeColors.indexedPresetGridFill(index: unassignedColorIndex[matchIndex!] ?? matchIndex!, for: colorScheme)))
                            .frame(width: cellWidth, height: cellHeight)
                            .position(
                                x: CGFloat(column) * (cellWidth + gap) + (cellWidth / 2),
                                y: CGFloat(row) * (cellHeight + gap) + (cellHeight / 2)
                            )
                    }
                }

                // App icon overlays, once per assigned selection, centered on
                // the selection's bounding box. Rendered after the per-cell
                // fills so they appear on top.
                ForEach(Array(allSelections.enumerated()), id: \.offset) { idx, sel in
                    if let bid = paddedApps[idx],
                       let icon = AppIconLookup.icon(forBundleID: bid) {
                        let n = sel.normalized
                        let width = CGFloat(n.endColumn - n.startColumn + 1) * cellWidth
                            + CGFloat(n.endColumn - n.startColumn) * gap
                        let height = CGFloat(n.endRow - n.startRow + 1) * cellHeight
                            + CGFloat(n.endRow - n.startRow) * gap
                        let centerX = CGFloat(n.startColumn) * (cellWidth + gap) + width / 2
                        let centerY = CGFloat(n.startRow) * (cellHeight + gap) + height / 2
                        let iconSide = min(width, height) * 0.6
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: iconSide, height: iconSide)
                            .position(x: centerX, y: centerY)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }
}
