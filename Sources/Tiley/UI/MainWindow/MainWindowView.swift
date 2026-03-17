import AppKit
import Sparkle
import SwiftUI
import UniformTypeIdentifiers

enum ScreenRole {
    case target
    case secondary(screen: NSScreen)

    var isTarget: Bool {
        if case .target = self { return true }
        return false
    }
}

struct ScreenContext {
    let visibleFrame: CGRect
    let screenFrame: CGRect
}

private struct ScreenContextKey: EnvironmentKey {
    static let defaultValue: ScreenContext? = nil
}

extension EnvironmentValues {
    var screenContext: ScreenContext? {
        get { self[ScreenContextKey.self] }
        set { self[ScreenContextKey.self] = newValue }
    }
}

struct MainWindowView: View {
    private static let windowCornerRadius: CGFloat = 14
    private static let layoutPanelHorizontalPadding: CGFloat = 28
    private static let layoutGridAspectHeightRatio: CGFloat = 0.75
    private static let footerLeadingWidth: CGFloat = 36
    private static let footerTrailingWidth: CGFloat = 88
    private static let footerHeight: CGFloat = 44
    private static let footerBottomPadding: CGFloat = 28
    private static let layoutFooterTopPadding: CGFloat = 16
    private static let layoutFooterBottomPadding: CGFloat = 8
    private static let layoutGridTopPadding: CGFloat = 8
    private static let layoutPresetsTopPadding: CGFloat = 10
    private static let presetRowHeight: CGFloat = 44
    private static let presetRowSpacing: CGFloat = 8
    private static let presetsPanelChromeHeight: CGFloat = 42
    private static let presetGridColumnWidth: CGFloat = 51
    private static let presetShortcutColumnWidth: CGFloat = 160
    private static let presetActionColumnWidth: CGFloat = 60
    private static let defaultGridColumns = 6
    private static let defaultGridRows = 6
    private static let defaultGridGap: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenContext) private var screenContext
    var appState: AppState
    var screenRole: ScreenRole
    @State private var draftSettings: AppState.SettingsSnapshot
    @State private var activeLayoutSelection: GridSelection?
    @State private var editingPresetID: UUID?
    @State private var editingPresetNameID: UUID?
    @State private var editingPresetNameDraft = ""
    @State private var isRecordingGlobalShortcut = false
    @State private var recordingPresetShortcutID: UUID?
    @State private var addingShortcutPresetID: UUID?
    @State private var addingShortcutIsGlobal = false
    @State private var replacingShortcutIndex: Int?
    @State private var nameFieldFocusTrigger: Int = 0
    @State private var hoveredPresetID: UUID?
    @State private var draggingPresetID: UUID?
    @State private var didReorderDuringDrag = false
    @State private var isPerformingDrop = false
    @State private var dragEndTask: Task<Void, Never>?
    @State private var isHoveringGridSection = false

    init(appState: AppState, screenRole: ScreenRole = .target) {
        self.appState = appState
        self.screenRole = screenRole
        _draftSettings = State(initialValue: appState.settingsSnapshot)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ThemeColors.windowBackground(for: colorScheme)
                    .opacity(appState.isEditingSettings || appState.isShowingPermissionsOnly ? 1.0 : 0.86)

                if appState.isShowingPermissionsOnly {
                    permissionsOnlyPanel(size: geometry.size)
                } else if appState.isEditingSettings {
                    settingsPanel(size: geometry.size)
                } else {
                    layoutGridPanel(size: geometry.size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: Self.windowCornerRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if appState.isEditingSettings, isHoveringGridSection {
                appState.updateSettingsPreview(draftSettings)
            }
        }
        .onChange(of: appState.isEditingSettings) { _, isEditing in
            if isEditing {
                draftSettings = appState.settingsSnapshot
            } else {
                appState.hidePreviewOverlay()
                isHoveringGridSection = false
            }
        }
        .onChange(of: appState.isShowingLayoutGrid) { _, isShowing in
            if !isShowing {
                dismissShortcutEditingIfNeeded()
            }
        }
        .onChange(of: appState.isEditingLayoutPresets) { _, isEditing in
            if !isEditing {
                dismissShortcutEditingIfNeeded()
                dismissPresetNameEditingIfNeeded()
                editingPresetID = nil
            }
        }
        .onChange(of: draftSettings) { _, newValue in
            guard appState.isEditingSettings, isHoveringGridSection else { return }
            appState.updateSettingsPreview(newValue)
        }
        .onChange(of: appState.selectedLayoutPresetID) { _, selectedID in
            if let hoveredPresetID, selectedID != hoveredPresetID {
                appState.selectLayoutPreset(hoveredPresetID)
                return
            }
            // Only the view that owns the hover should drive the preview,
            // so the preview appears on the correct screen. For keyboard-
            // driven selection (no view hovering), the view whose screen
            // contains the mouse cursor handles the preview.
            if let selectedID {
                let thisViewOwnsHover = (hoveredPresetID == selectedID)
                let isKeyboardDriven = (hoveredPresetID == nil && isMouseOnThisScreen)
                guard thisViewOwnsHover || isKeyboardDriven else { return }
            }
            updatePresetSelectionPreview(for: selectedID)
        }
    }

    private func settingsPanel(size: CGSize) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    HStack(alignment: .bottom, spacing: 10) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Text("Tiley")
                            .font(.system(size: 30, weight: .bold, design: .rounded))

                        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                            Text("v\(version)")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button("Back") {
                        dismissPresetNameEditingIfNeeded()
                        appState.apply(settings: draftSettings)
                        draftSettings = appState.settingsSnapshot
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Quit Tiley") {
                        appState.quitApp()
                    }
                }

                settingsEditor
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private static let permissionsImageLocale: String = {
        let lang = Locale.preferredLanguages.first ?? "en"
        return lang.hasPrefix("ja") ? "ja" : "en"
    }()

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    private static func permissionsImage(named name: String) -> NSImage? {
        let fileName = "\(name)-\(permissionsImageLocale)"
        let url = resourceBundle.url(forResource: fileName, withExtension: "png", subdirectory: "Images")
            ?? resourceBundle.url(forResource: fileName, withExtension: "png")
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }

    private func permissionsOnlyPanel(size: CGSize) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    HStack(alignment: .bottom, spacing: 10) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Text("Tiley")
                            .font(.system(size: 30, weight: .bold, design: .rounded))

                        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                            Text("v\(version)")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button("Quit Tiley") {
                        appState.quitApp()
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(
                                appState.accessibilityGranted ? "Accessibility enabled" : "Accessibility required",
                                systemImage: appState.accessibilityGranted ? "checkmark.shield" : "exclamationmark.shield"
                            )
                            Spacer()
                            Button("Open Prompt") {
                                appState.requestAccessibilityAccess()
                            }
                        }
                        Text("Window movement on macOS requires Accessibility permission.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        permissionsScreenshot(named: "dialog")
                        permissionsScreenshot(named: "system")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Permissions")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .font(.system(size: 14))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func permissionsScreenshot(named name: String) -> some View {
        if let nsImage = Self.permissionsImage(named: name) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(ThemeColors.screenshotBorder(for: colorScheme), lineWidth: 1)
                )
        }
    }

    private func layoutGridPanel(size: CGSize) -> some View {
        let gridWidth = size.width - (Self.layoutPanelHorizontalPadding * 2)
        let gridHeight = gridWidth * Self.layoutGridAspectHeightRatio
        let availablePresetsHeight = max(
            0,
            size.height
                - Self.layoutFooterTopPadding
                - Self.footerHeight
                - Self.layoutFooterBottomPadding
                - Self.layoutGridTopPadding
                - gridHeight
                - Self.layoutPresetsTopPadding
                - Self.footerBottomPadding
        )

        return VStack(spacing: 0) {
            layoutGridFooterBar
                .padding(.horizontal, Self.layoutPanelHorizontalPadding)
                .padding(.top, Self.layoutFooterTopPadding)
                .padding(.bottom, Self.layoutFooterBottomPadding)

            LayoutGridWorkspaceView(
                rows: appState.rows,
                columns: appState.columns,
                gap: appState.gap,
                highlightSelection: editingPresetHighlightSelection,
                onSelectionChange: { selection in
                    if editingPresetID == nil {
                        dismissPresetNameEditingIfNeeded()
                        dismissShortcutEditingIfNeeded()
                        hoveredPresetID = nil
                        appState.selectedLayoutPresetID = nil
                    }
                    activeLayoutSelection = selection
                    if let ctx = screenContext {
                        appState.updateLayoutPreview(selection, screenContext: ctx)
                    } else {
                        appState.updateLayoutPreview(selection)
                    }
                },
                onHoverChange: { selection in
                    guard activeLayoutSelection == nil else { return }
                    if let ctx = screenContext {
                        appState.updateLayoutPreview(selection, screenContext: ctx)
                    } else {
                        appState.updateLayoutPreview(selection)
                    }
                },
                onSelectionCommit: { selection in
                    activeLayoutSelection = nil
                    if let editingID = editingPresetID {
                        appState.updateLayoutPreset(editingID) { preset in
                            preset.selection = selection
                            preset.baseRows = appState.rows
                            preset.baseColumns = appState.columns
                        }
                        appState.updateLayoutPreview(nil)
                    } else if let ctx = screenContext {
                        appState.commitLayoutSelectionOnScreen(selection, visibleFrame: ctx.visibleFrame, screenFrame: ctx.screenFrame)
                    } else {
                        appState.commitLayoutSelection(selection)
                    }
                }
            )
            .frame(width: gridWidth, height: gridHeight, alignment: .topLeading)
            .padding(.horizontal, Self.layoutPanelHorizontalPadding)
            .padding(.top, 8)

            layoutPresetsPanel(availableHeight: availablePresetsHeight)
                .padding(.horizontal, Self.layoutPanelHorizontalPadding)
                .padding(.top, Self.layoutPresetsTopPadding)
                .padding(.bottom, Self.footerBottomPadding)

            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var layoutGridFooterBar: some View {
        HStack(spacing: 16) {
            if screenRole.isTarget {
                Button {
                    dismissPresetNameEditingIfNeeded()
                    draftSettings = appState.settingsSnapshot
                    appState.beginSettingsEditing()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .help("Edit Settings")
                .frame(width: Self.footerLeadingWidth, alignment: .leading)
            } else {
                Color.clear
                    .frame(width: Self.footerLeadingWidth, alignment: .leading)
            }

            Spacer(minLength: 0)

            layoutTargetInfoView

            Spacer(minLength: 0)

            Color.clear
                .frame(width: Self.footerTrailingWidth, alignment: .trailing)
        }
        .frame(height: Self.footerHeight)
    }

    private func layoutPresetsPanel(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Layouts")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 12) {
                Text("Grid")
                    .frame(width: Self.presetGridColumnWidth, alignment: .center)
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("Shortcut")
                    .frame(width: Self.presetShortcutColumnWidth, alignment: .center)
                Color.clear
                    .frame(width: Self.presetActionColumnWidth)
            }
            .padding(.horizontal, 10)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: Self.presetRowSpacing) {
                    ForEach(appState.displayedLayoutPresets) { preset in
                        layoutPresetRow(preset)
                    }
                }
                .padding(.bottom, Self.presetRowHeight)
                .contentShape(Rectangle())
                .onDrop(of: [UTType.text, UTType.plainText], delegate: PresetListDropDelegate(
                    appState: appState,
                    sourcePresetID: { draggingPresetID },
                    setDidReorderDuringDrag: { didReorderDuringDrag = $0 },
                    setIsPerformingDrop: { isPerformingDrop = $0 }
                ))
            }
            .frame(height: min(presetsListHeight, max(0, availableHeight - Self.presetsPanelChromeHeight)), alignment: .top)
        }
        .frame(height: min(presetsPanelHeight, availableHeight), alignment: .top)
    }

    private var presetsPanelHeight: CGFloat {
        Self.presetsPanelChromeHeight + presetsListHeight
    }

    private var presetsListHeight: CGFloat {
        let rowCount = CGFloat(appState.displayedLayoutPresets.count)
        let rowsHeight = rowCount * Self.presetRowHeight
        let spacingHeight = max(0, rowCount - 1) * Self.presetRowSpacing
        return rowsHeight + spacingHeight
    }

    @ViewBuilder
    private var layoutTargetInfoView: some View {
        if screenRole.isTarget {
            layoutTargetDropdownView
        } else {
            layoutTargetStaticView
        }
    }

    private var layoutTargetDropdownView: some View {
        WindowTargetDropdownButton(appState: appState) {
            HStack(spacing: 6) {
                targetInfoContent
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 260)
    }

    private var layoutTargetStaticView: some View {
        targetInfoContent
            .frame(maxWidth: 260)
    }

    private var targetInfoContent: some View {
        HStack(spacing: 10) {
            if let icon = appState.currentLayoutTargetIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            VStack(spacing: 1) {
                Text(appState.currentLayoutTargetPrimaryText)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if let secondary = appState.currentLayoutTargetSecondaryText {
                    Text(secondary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
        }
    }

    private var settingsEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Launch at login", isOn: Binding(
                        get: { draftSettings.launchAtLoginEnabled },
                        set: { newValue in
                            _ = appState.setLaunchAtLoginEnabled(newValue)
                            draftSettings.launchAtLoginEnabled = appState.launchAtLoginEnabled
                        }
                    ))
                    .toggleStyle(.switch)

                    Toggle("Show menu icon", isOn: Binding(
                        get: { draftSettings.menuIconVisible },
                        set: { newValue in
                            appState.setMenuIconVisible(newValue)
                            draftSettings.menuIconVisible = appState.menuIconVisible
                        }
                    ))
                    .toggleStyle(.switch)

                    Toggle("Show Dock icon", isOn: Binding(
                        get: { draftSettings.dockIconVisible },
                        set: { newValue in
                            appState.setDockIconVisible(newValue)
                            draftSettings.dockIconVisible = appState.dockIconVisible
                        }
                    ))
                    .toggleStyle(.switch)

                    Text("Changes are applied immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Startup")
                    .font(.system(size: 16, weight: .semibold))
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Global shortcut")
                        Spacer()
                        ShortcutRecorderField(
                            shortcut: $draftSettings.hotKeyShortcut,
                            onRecordingChange: { isRecording in
                                isRecordingGlobalShortcut = isRecording
                                appState.setShortcutRecordingActive(isRecording)
                            }
                        )
                            .frame(width: 220, height: 32)
                    }
                    HStack {
                        Spacer()
                        Button("Reset to Default") {
                            dismissPresetNameEditingIfNeeded()
                            draftSettings.hotKeyShortcut = .default
                        }
                    }
                    Text("Click the field, then press the new shortcut.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Shortcut")
                    .font(.system(size: 16, weight: .semibold))
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Stepper("Columns: \(draftSettings.columns)", value: $draftSettings.columns, in: 2...12)
                    Stepper("Rows: \(draftSettings.rows)", value: $draftSettings.rows, in: 2...12)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Gap")
                            Spacer()
                            Text("\(Int(draftSettings.gap)) pt")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $draftSettings.gap, in: 0...24, step: 1)
                    }
                    HStack {
                        Spacer()
                        Button("Reset Grid to Default") {
                            draftSettings.columns = Self.defaultGridColumns
                            draftSettings.rows = Self.defaultGridRows
                            draftSettings.gap = Self.defaultGridGap
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Grid")
                    .font(.system(size: 16, weight: .semibold))
            }
            .onHover { hovering in
                isHoveringGridSection = hovering
                if hovering {
                    appState.updateSettingsPreview(draftSettings)
                } else {
                    appState.hidePreviewOverlay()
                }
            }

            GroupBox {
                HStack {
                    Text("Reset the layout preset list to the defaults.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults") {
                        dismissPresetNameEditingIfNeeded()
                        appState.resetLayoutPresetsToDefault()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Layouts")
                    .font(.system(size: 16, weight: .semibold))
            }

            if let updater = appState.updater {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Automatically check for updates", isOn: Binding(
                            get: { updater.automaticallyChecksForUpdates },
                            set: { updater.automaticallyChecksForUpdates = $0 }
                        ))
                        .toggleStyle(.switch)

                        HStack {
                            Spacer()
                            CheckForUpdatesView(updater: updater)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Updates")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .font(.system(size: 14))
    }

    @ViewBuilder
    private func layoutPresetRow(_ preset: LayoutPreset) -> some View {
        let isInEditMode = editingPresetID == preset.id
        HStack(spacing: 12) {
            PresetGridPreviewView(
                rows: appState.rows,
                columns: appState.columns,
                selection: preset.scaledSelection(toRows: appState.rows, columns: appState.columns)
            )
            .frame(width: Self.presetGridColumnWidth, height: 26, alignment: .center)

            presetNameCell(for: preset)

            presetShortcutsCell(for: preset)
                .frame(width: Self.presetShortcutColumnWidth, alignment: .center)

            presetActionCell(for: preset, isInEditMode: isInEditMode)
                .frame(width: Self.presetActionColumnWidth, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isInEditMode else { return }
            if editingPresetID != nil {
                dismissEditingPresetIfNeeded(except: preset.id)
                appState.selectLayoutPreset(preset.id)
                return
            }
            handlePresetTap(preset)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(height: Self.presetRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ThemeColors.presetRowBackground(selected: isPresetSelected(preset.id), for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ThemeColors.presetRowBorder(selected: isPresetSelected(preset.id), for: colorScheme), lineWidth: 1)
        )
        .onHover { isHovering in
            guard draggingPresetID == nil else { return }
            if isHovering {
                hoveredPresetID = preset.id
                appState.selectLayoutPreset(preset.id)
            } else if hoveredPresetID == preset.id {
                hoveredPresetID = nil
                appState.selectedLayoutPresetID = nil
            }
        }
        .onDrag {
            guard appState.isPersistedLayoutPreset(preset.id) else { return NSItemProvider() }
            startDraggingPreset(preset.id)
            let provider = NSItemProvider(object: preset.id.uuidString as NSString)
            provider.suggestedName = preset.id.uuidString
            return provider
        } preview: {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    @ViewBuilder
    private func presetNameCell(for preset: LayoutPreset) -> some View {
        if editingPresetNameID == preset.id {
            InlinePresetNameField(
                text: $editingPresetNameDraft,
                focusTrigger: nameFieldFocusTrigger,
                onCommit: {
                    commitPresetNameEdit(for: preset.id)
                },
                onExplicitCommit: {
                    commitPresetNameEditAndFinish(for: preset.id)
                },
                onCancel: {
                    cancelPresetNameEdit()
                }
            )
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Text(preset.name)
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private func presetActionCell(for preset: LayoutPreset, isInEditMode: Bool) -> some View {
        HStack(spacing: 4) {
            if isInEditMode {
                Button {
                    finishEditingPreset(preset.id)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 14, height: 14)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.accentColor)
                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        )
                }
                .buttonStyle(.plain)
                .instantTooltip(NSLocalizedString("Done Editing", comment: "Tooltip for done editing button"))

                DeleteLayoutButton(colorScheme: colorScheme) {
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Delete Layout", comment: "Alert title for deleting a layout")
                    alert.informativeText = String(format: NSLocalizedString("Are you sure you want to delete the layout \"%@\"?", comment: "Alert message for deleting a layout with name"), preset.name)
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: NSLocalizedString("Delete", comment: "Delete button title"))
                    alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button title"))
                    if alert.runModal() == .alertFirstButtonReturn {
                        dismissPresetNameEditingIfNeeded(except: preset.id)
                        deletePreset(id: preset.id)
                        editingPresetID = nil
                    }
                }
            } else if editingPresetID == nil, hoveredPresetID == preset.id, draggingPresetID == nil {
                Button {
                    beginEditingPreset(preset)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 14, height: 14)
                        .foregroundStyle(.primary)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(ThemeColors.editButtonBackground(for: colorScheme))
                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(ThemeColors.presetCellBorder(for: colorScheme), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .instantTooltip(NSLocalizedString("Edit Name & Shortcuts", comment: "Tooltip for edit layout button"))

                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func presetShortcutsCell(for preset: LayoutPreset) -> some View {
        let shortcuts = preset.shortcuts
        let isEditing = editingPresetID == preset.id || recordingPresetShortcutID == preset.id
        let isAdding = addingShortcutPresetID == preset.id
        let isReplacing = isEditing && replacingShortcutIndex != nil

        VStack(alignment: .leading, spacing: 4) {
            FlowLayout(spacing: 4) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, shortcut in
                    shortcutBadge(for: preset, index: index, shortcut: shortcut, isEditing: isEditing, isAdding: isAdding, isReplacing: isReplacing)
                }

                if (isEditing || shortcuts.isEmpty) && !isAdding && !isReplacing {
                    AddShortcutButton(colorScheme: colorScheme, tooltip: NSLocalizedString("Add Shortcut", comment: "Tooltip for add shortcut button")) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    } action: {
                        addingShortcutIsGlobal = false
                        addingShortcutPresetID = preset.id
                        appState.setShortcutRecordingActive(true)
                    }

                    AddShortcutButton(colorScheme: colorScheme, tooltip: NSLocalizedString("Add Global Shortcut", comment: "Tooltip for add global shortcut button")) {
                        HStack(spacing: 2) {
                            Image(systemName: "globe")
                                .font(.system(size: 8, weight: .semibold))
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                    } action: {
                        addingShortcutIsGlobal = true
                        addingShortcutPresetID = preset.id
                        appState.setShortcutRecordingActive(true)
                    }
                }
            }

            if isAdding {
                CompactShortcutRecorderField(
                    onShortcutRecorded: { newShortcut in
                        var shortcut = newShortcut
                        shortcut.isGlobal = addingShortcutIsGlobal
                        appState.updateLayoutPreset(preset.id) { p in
                            if !p.shortcuts.contains(shortcut) {
                                p.shortcuts.append(shortcut)
                            }
                        }
                        let keepEditing = editingPresetID == preset.id
                        addingShortcutPresetID = nil
                        replacingShortcutIndex = nil
                        recordingPresetShortcutID = keepEditing ? preset.id : nil
                        appState.setShortcutRecordingActive(false)
                        if keepEditing {
                            nameFieldFocusTrigger += 1
                        } else {
                            appState.isEditingLayoutPresets = false
                        }
                    },
                    onRecordingChange: { recording in
                        if !recording {
                            let keepEditing = editingPresetID == preset.id
                            addingShortcutPresetID = nil
                            replacingShortcutIndex = nil
                            recordingPresetShortcutID = keepEditing ? preset.id : nil
                            appState.setShortcutRecordingActive(false)
                            if keepEditing {
                                nameFieldFocusTrigger += 1
                            } else {
                                appState.isEditingLayoutPresets = false
                            }
                        }
                    },
                    validateShortcut: { shortcut in
                        appState.layoutShortcutConflictMessage(for: shortcut, excluding: preset.id)
                    }
                )
                .frame(height: 22)
            }
        }
    }

    @ViewBuilder
    private func shortcutBadge(for preset: LayoutPreset, index: Int, shortcut: HotKeyShortcut, isEditing: Bool, isAdding: Bool, isReplacing: Bool) -> some View {
        if isReplacing && replacingShortcutIndex == index {
            CompactShortcutRecorderField(
                onShortcutRecorded: { newShortcut in
                    appState.updateLayoutPreset(preset.id) { p in
                        guard index < p.shortcuts.count else { return }
                        p.shortcuts[index] = newShortcut
                    }
                    let keepEditing = editingPresetID == preset.id
                    replacingShortcutIndex = nil
                    recordingPresetShortcutID = keepEditing ? preset.id : nil
                    appState.setShortcutRecordingActive(false)
                    if keepEditing {
                        nameFieldFocusTrigger += 1
                    } else {
                        appState.isEditingLayoutPresets = false
                    }
                },
                onRecordingChange: { recording in
                    if !recording {
                        let keepEditing = editingPresetID == preset.id
                        replacingShortcutIndex = nil
                        recordingPresetShortcutID = keepEditing ? preset.id : nil
                        appState.setShortcutRecordingActive(false)
                        if keepEditing {
                            nameFieldFocusTrigger += 1
                        } else {
                            appState.isEditingLayoutPresets = false
                        }
                    }
                },
                validateShortcut: { candidate in
                    appState.layoutShortcutConflictMessage(for: candidate, excluding: preset.id)
                }
            )
            .frame(height: 22)
        } else {
            shortcutBadgeLabel(for: preset, index: index, shortcut: shortcut, isEditing: isEditing, isAdding: isAdding, isReplacing: isReplacing)
        }
    }

    @ViewBuilder
    private func shortcutBadgeLabel(for preset: LayoutPreset, index: Int, shortcut: HotKeyShortcut, isEditing: Bool, isAdding: Bool, isReplacing: Bool) -> some View {
        ShortcutBadgeLabelView(shortcut: shortcut, isEditing: isEditing, showDelete: isEditing && !isReplacing, onDelete: {
            removeShortcut(at: index, from: preset.id)
        }, onTap: {
            guard !isReplacing, !isAdding else { return }
            appState.selectLayoutPreset(preset.id)
            replacingShortcutIndex = index
            addingShortcutPresetID = nil
            recordingPresetShortcutID = preset.id
            appState.setShortcutRecordingActive(true)
            appState.isEditingLayoutPresets = true
        })
        .allowsHitTesting(isEditing)
    }

    private func removeShortcut(at index: Int, from presetID: UUID) {
        appState.updateLayoutPreset(presetID) { preset in
            guard index < preset.shortcuts.count else { return }
            preset.shortcuts.remove(at: index)
        }
    }

    private func finishEditingPreset(_ id: UUID) {
        if editingPresetNameID == id {
            let trimmed = editingPresetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentName = appState.displayedLayoutPresets.first(where: { $0.id == id })?.name ?? ""
            let committedName = trimmed.isEmpty ? currentName : trimmed
            if appState.isPersistedLayoutPreset(id) || committedName != currentName {
                appState.updateLayoutPreset(id) { preset in
                    preset.name = committedName
                }
            }
            editingPresetNameID = nil
            editingPresetNameDraft = ""
        }
        dismissShortcutEditingIfNeeded()
        editingPresetID = nil
        syncEditingLayoutPresetsFlag()
    }

    private func beginEditingPreset(_ preset: LayoutPreset) {
        dismissEditingPresetIfNeeded(except: preset.id)
        appState.selectLayoutPreset(preset.id)
        editingPresetID = preset.id
        editingPresetNameID = preset.id
        editingPresetNameDraft = preset.name
        recordingPresetShortcutID = preset.id
        appState.isEditingLayoutPresets = true
    }

    private func dismissEditingPresetIfNeeded(except id: UUID? = nil) {
        guard let editingPresetID, editingPresetID != id else { return }
        // Clear editingPresetID first so commitPresetNameEdit won't keep name field alive
        self.editingPresetID = nil
        dismissPresetNameEditingIfNeeded(except: id)
        dismissShortcutEditingIfNeeded(except: id)
    }

    private func beginPresetNameEdit(for preset: LayoutPreset) {
        dismissShortcutEditingIfNeeded()
        if let editingID = editingPresetNameID, editingID != preset.id {
            commitPresetNameEdit(for: editingID)
            appState.selectLayoutPreset(preset.id)
            return
        }
        appState.selectLayoutPreset(preset.id)
        editingPresetNameID = preset.id
        editingPresetNameDraft = preset.name
        appState.isEditingLayoutPresets = true
    }

    private func commitPresetNameEdit(for id: UUID) {
        let trimmed = editingPresetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentName = appState.displayedLayoutPresets.first(where: { $0.id == id })?.name ?? ""
        let committedName = trimmed.isEmpty ? currentName : trimmed
        let inEditMode = editingPresetID == id
        if !appState.isPersistedLayoutPreset(id), committedName == currentName {
            if inEditMode {
                // In unified edit mode, keep name field active even if name unchanged
                return
            }
            cancelPresetNameEdit()
            return
        }
        appState.updateLayoutPreset(id) { preset in
            preset.name = committedName
        }
        if inEditMode {
            // In unified edit mode, save name but keep the name field editable
            editingPresetNameDraft = committedName
        } else {
            editingPresetNameID = nil
            editingPresetNameDraft = ""
        }
        syncEditingLayoutPresetsFlag()
    }

    /// Called on explicit Enter/Tab: commit name and exit edit mode entirely.
    private func commitPresetNameEditAndFinish(for id: UUID) {
        if editingPresetID == id {
            finishEditingPreset(id)
        } else {
            commitPresetNameEdit(for: id)
        }
    }

    private func cancelPresetNameEdit() {
        let wasInEditMode = editingPresetNameID != nil && editingPresetID == editingPresetNameID
        editingPresetNameID = nil
        editingPresetNameDraft = ""
        if wasInEditMode {
            // ESC in name field exits the entire edit mode
            dismissShortcutEditingIfNeeded()
            editingPresetID = nil
        }
        syncEditingLayoutPresetsFlag()
    }

    private func isShowingDeleteButton(for id: UUID) -> Bool {
        editingPresetID == id || editingPresetNameID == id || recordingPresetShortcutID == id
    }

    private func isPresetSelected(_ id: UUID) -> Bool {
        if draggingPresetID == id { return true }
        if hoveredPresetID == id { return true }
        // Only show the shared keyboard/hover selection highlight on the
        // screen where the mouse cursor currently resides.
        guard appState.selectedLayoutPresetID == id else { return false }
        return isMouseOnThisScreen
    }

    private var isMouseOnThisScreen: Bool {
        guard let ctx = screenContext else { return screenRole.isTarget }
        return ctx.screenFrame.contains(NSEvent.mouseLocation)
    }

    private var editingPresetHighlightSelection: GridSelection? {
        // Editing preset takes priority
        if let editingID = editingPresetID,
           let preset = appState.displayedLayoutPresets.first(where: { $0.id == editingID }) {
            return preset.scaledSelection(toRows: appState.rows, columns: appState.columns)
        }
        // Hovered preset
        if let hoveredID = hoveredPresetID,
           let preset = appState.displayedLayoutPresets.first(where: { $0.id == hoveredID }) {
            return preset.scaledSelection(toRows: appState.rows, columns: appState.columns)
        }
        // Keyboard-selected preset
        if let selectedID = appState.selectedLayoutPresetID, isMouseOnThisScreen,
           let preset = appState.displayedLayoutPresets.first(where: { $0.id == selectedID }) {
            return preset.scaledSelection(toRows: appState.rows, columns: appState.columns)
        }
        return nil
    }

    private func updatePresetSelectionPreview(for id: UUID?) {
        guard !appState.isEditingSettings else { return }
        guard editingPresetID == nil else { return }
        guard draggingPresetID == nil else { return }
        guard activeLayoutSelection == nil else { return }
        guard let id,
              let preset = appState.displayedLayoutPresets.first(where: { $0.id == id }) else {
            appState.updateLayoutPreview(nil)
            return
        }
        let selection = preset.scaledSelection(toRows: appState.rows, columns: appState.columns)
        if let ctx = screenContext {
            appState.updateLayoutPreview(selection, screenContext: ctx)
        } else {
            appState.updateLayoutPreview(selection)
        }
    }

    private func deletePreset(id: UUID) {
        if editingPresetNameID == id {
            cancelPresetNameEdit()
        }
        if recordingPresetShortcutID == id {
            recordingPresetShortcutID = nil
        }
        appState.removeLayoutPreset(id: id)
        syncEditingLayoutPresetsFlag()
    }

    private func handlePresetTap(_ preset: LayoutPreset) {
        let isEditing = editingPresetID != nil || editingPresetNameID != nil || isRecordingGlobalShortcut || recordingPresetShortcutID != nil || draggingPresetID != nil
        if isEditing {
            appState.selectLayoutPreset(preset.id)
            return
        }
        appState.selectLayoutPreset(preset.id)
        if let ctx = screenContext {
            appState.applyLayoutPresetOnScreen(id: preset.id, visibleFrame: ctx.visibleFrame, screenFrame: ctx.screenFrame)
        } else {
            appState.applyLayoutPreset(id: preset.id)
        }
    }

    private func startDraggingPreset(_ id: UUID) {
        dismissEditingPresetIfNeeded()
        dismissPresetNameEditingIfNeeded()
        if editingPresetNameID == id {
            commitPresetNameEdit(for: id)
        }
        dismissShortcutEditingIfNeeded()
        hoveredPresetID = nil
        appState.selectedLayoutPresetID = nil
        appState.updateLayoutPreview(nil)
        draggingPresetID = id
        didReorderDuringDrag = false
        isPerformingDrop = false
        startDragEndMonitor()
    }

    private func stopDraggingPreset(animated: Bool = false, delay: TimeInterval = 0) {
        let apply = {
            if animated {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    draggingPresetID = nil
                }
            } else {
                draggingPresetID = nil
            }
            didReorderDuringDrag = false
            isPerformingDrop = false
            stopDragEndMonitor()
        }
        if delay <= 0 {
            apply()
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            apply()
        }
    }

    private func startDragEndMonitor() {
        stopDragEndMonitor()
        dragEndTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                if NSEvent.pressedMouseButtons == 0, !isPerformingDrop {
                    stopDraggingPreset(animated: true)
                    break
                }
            }
        }
    }

    private func stopDragEndMonitor() {
        dragEndTask?.cancel()
        dragEndTask = nil
    }

    private struct PresetListDropDelegate: DropDelegate {
        let appState: AppState
        let sourcePresetID: () -> UUID?
        let setDidReorderDuringDrag: (Bool) -> Void
        let setIsPerformingDrop: (Bool) -> Void

        func validateDrop(info: DropInfo) -> Bool {
            guard let sourceID = sourcePresetID() else { return false }
            return appState.isPersistedLayoutPreset(sourceID)
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            guard let sourceID = sourcePresetID() else {
                return DropProposal(operation: .cancel)
            }

            let targetIndex = insertionIndex(for: info.location, itemCount: appState.layoutPresets.count)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                appState.moveLayoutPreset(from: sourceID, toIndex: targetIndex)
            }
            setDidReorderDuringDrag(true)
            return DropProposal(operation: .move)
        }

        func performDrop(info: DropInfo) -> Bool {
            setIsPerformingDrop(true)
            Task { @MainActor in
                setIsPerformingDrop(false)
            }
            return true
        }

        private func insertionIndex(for location: CGPoint, itemCount: Int) -> Int {
            let step = MainWindowView.presetRowHeight + MainWindowView.presetRowSpacing
            let endThreshold = (CGFloat(max(0, itemCount - 1)) * step) + (MainWindowView.presetRowHeight / 2)
            if location.y >= endThreshold {
                return itemCount
            }

            let rawIndex = Int((location.y / step).rounded(.down))
            return min(max(0, rawIndex), itemCount)
        }
    }

    private func dismissPresetNameEditingIfNeeded(except id: UUID? = nil) {
        guard let editingPresetNameID, editingPresetNameID != id else { return }
        commitPresetNameEdit(for: editingPresetNameID)
    }


    private func syncEditingLayoutPresetsFlag() {
        let isEditing = editingPresetID != nil || recordingPresetShortcutID != nil || editingPresetNameID != nil
        if appState.isEditingLayoutPresets != isEditing {
            appState.isEditingLayoutPresets = isEditing
        }
    }

    private func dismissShortcutEditingIfNeeded(except id: UUID? = nil) {
        if let addingShortcutPresetID, addingShortcutPresetID != id {
            self.addingShortcutPresetID = nil
            appState.setShortcutRecordingActive(false)
        }
        if let recordingPresetShortcutID, recordingPresetShortcutID != id {
            self.recordingPresetShortcutID = nil
        }
        replacingShortcutIndex = nil
        syncEditingLayoutPresetsFlag()
    }

}

private struct InlinePresetNameField: NSViewRepresentable {
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

private final class InlinePresetNameTextField: NSTextField {
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

private struct ShortcutBadgeLabelView: View {
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
                    Image(systemName: "trash")
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

private struct EditingTooltipModifier: ViewModifier {
    let isEditing: Bool
    let shortcutName: String

    func body(content: Content) -> some View {
        if isEditing {
            content.instantTooltip(String(format: NSLocalizedString("Click to change \"%@\"", comment: "Tooltip for clicking shortcut badge to edit with name"), shortcutName))
        } else {
            content
        }
    }
}

private struct AddShortcutButton<Label: View>: View {
    let colorScheme: ColorScheme
    let tooltip: String
    @ViewBuilder let label: Label
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label
                .frame(minHeight: ShortcutBadgeLabelView.badgeContentHeight)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovered ? ThemeColors.presetCellBackground(for: colorScheme).opacity(0.8) : ThemeColors.presetCellBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(isHovered ? Color.accentColor.opacity(0.5) : ThemeColors.presetCellBorder(for: colorScheme), lineWidth: isHovered ? 1 : 0.5)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .instantTooltip(tooltip)
    }
}

private struct DeleteLayoutButton: View {
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

private struct FlowLayout: Layout {
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

private struct PresetGridPreviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    let rows: Int
    let columns: Int
    let selection: GridSelection

    var body: some View {
        GeometryReader { geometry in
            let gap: CGFloat = 2
            let cellWidth = max(2, (geometry.size.width - gap * CGFloat(max(0, columns - 1))) / CGFloat(max(columns, 1)))
            let cellHeight = max(2, (geometry.size.height - gap * CGFloat(max(0, rows - 1))) / CGFloat(max(rows, 1)))

            ZStack(alignment: .topLeading) {
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<columns, id: \.self) { column in
                        let selected = selection.startRow...selection.endRow ~= row && selection.startColumn...selection.endColumn ~= column
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(selected ? Color.accentColor : ThemeColors.presetGridUnselectedFill(for: colorScheme))
                            .frame(width: cellWidth, height: cellHeight)
                            .position(
                                x: CGFloat(column) * (cellWidth + gap) + (cellWidth / 2),
                                y: CGFloat(row) * (cellHeight + gap) + (cellHeight / 2)
                            )
                    }
                }
            }
        }
    }
}

private struct InstantBubbleTooltip: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content
            .background(TooltipTriggerView(text: text))
    }
}

private struct TooltipTriggerView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TooltipHoverView {
        let view = TooltipHoverView()
        view.tooltipText = text
        return view
    }

    func updateNSView(_ nsView: TooltipHoverView, context: Context) {
        nsView.tooltipText = text
    }
}

private final class TooltipHoverView: NSView {
    var tooltipText = ""
    private var popover: NSPopover?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        showTooltip()
    }

    override func mouseExited(with event: NSEvent) {
        dismissTooltip()
    }

    override func removeFromSuperview() {
        dismissTooltip()
        super.removeFromSuperview()
    }

    private func showTooltip() {
        guard popover == nil else { return }
        let p = NSPopover()
        p.behavior = .semitransient
        p.animates = false
        let hostingController = NSHostingController(rootView:
            Text(tooltipText)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .fixedSize()
        )
        hostingController.view.setFrameSize(hostingController.view.fittingSize)
        p.contentSize = hostingController.view.fittingSize
        p.contentViewController = hostingController
        p.show(relativeTo: bounds, of: self, preferredEdge: .minY)
        popover = p
    }

    private func dismissTooltip() {
        popover?.close()
        popover = nil
    }
}

extension View {
    fileprivate func instantTooltip(_ text: String) -> some View {
        modifier(InstantBubbleTooltip(text: text))
    }
}

// MARK: - Window Target Dropdown Button

private struct WindowTargetDropdownButton<Label: View>: NSViewRepresentable {
    let appState: AppState
    @ViewBuilder let label: Label

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    func makeNSView(context: Context) -> WindowTargetDropdownContainerView {
        let container = WindowTargetDropdownContainerView()
        container.onMouseDown = { [coordinator = context.coordinator] view in
            coordinator.showMenu(from: view)
        }
        let hostingView = NSHostingView(rootView: label)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.hostingView = hostingView
        return container
    }

    func updateNSView(_ nsView: WindowTargetDropdownContainerView, context: Context) {
        context.coordinator.appState = appState
        context.coordinator.hostingView?.rootView = label
    }

    @MainActor final class Coordinator: NSObject {
        var appState: AppState
        var hostingView: NSHostingView<Label>?

        init(appState: AppState) {
            self.appState = appState
            super.init()
        }

        func showMenu(from view: NSView) {
            appState.refreshAvailableWindows()
            let targets = appState.windowTargetList
            let currentIndex = appState.currentWindowTargetIndex
            let menu = NSMenu()
            menu.autoenablesItems = false

            if targets.isEmpty {
                let item = NSMenuItem(
                    title: NSLocalizedString("No windows available", comment: "Empty window target menu"),
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                menu.addItem(item)
            } else {
                for (index, target) in targets.enumerated() {
                    let title: String
                    if let windowTitle = target.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !windowTitle.isEmpty {
                        title = "\(target.appName) — \(windowTitle)"
                    } else {
                        title = target.appName
                    }
                    let item = NSMenuItem(
                        title: title,
                        action: #selector(menuItemSelected(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.tag = index
                    if let icon = NSRunningApplication(processIdentifier: target.processIdentifier)?.icon {
                        let resizedIcon = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                            icon.draw(in: rect)
                            return true
                        }
                        item.image = resizedIcon
                    }
                    if index == currentIndex {
                        item.state = .on
                    }
                    menu.addItem(item)
                }
            }

            let position = NSPoint(x: 0, y: view.bounds.height)
            menu.popUp(positioning: nil, at: position, in: view)
        }

        @objc func menuItemSelected(_ sender: NSMenuItem) {
            appState.selectWindowTarget(at: sender.tag)
        }
    }
}

private final class WindowTargetDropdownContainerView: NSView {
    var onMouseDown: ((NSView) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(self)
    }
}
