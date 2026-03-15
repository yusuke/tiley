import AppKit
import Sparkle
import SwiftUI
import UniformTypeIdentifiers

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
    private static let defaultGridColumns = 6
    private static let defaultGridRows = 6
    private static let defaultGridGap: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme
    var appState: AppState
    @State private var draftSettings: AppState.SettingsSnapshot
    @State private var activeLayoutSelection: GridSelection?
    @State private var editingPresetNameID: UUID?
    @State private var editingPresetNameDraft = ""
    @State private var isRecordingGlobalShortcut = false
    @State private var recordingPresetShortcutID: UUID?
    @State private var addingShortcutPresetID: UUID?
    @State private var addingShortcutIsGlobal = false
    @State private var replacingShortcutIndex: Int?
    @State private var hoveredPresetID: UUID?
    @State private var draggingPresetID: UUID?
    @State private var didReorderDuringDrag = false
    @State private var isPerformingDrop = false
    @State private var dragEndTask: Task<Void, Never>?
    @State private var isHoveringGridSection = false

    init(appState: AppState) {
        self.appState = appState
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
            updatePresetSelectionPreview(for: selectedID)
        }
    }

    private func settingsPanel(size: CGSize) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .alignmentGuide(.firstTextBaseline) { d in d[.bottom] }

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
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .alignmentGuide(.firstTextBaseline) { d in d[.bottom] }

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
                onSelectionChange: { selection in
                    dismissPresetNameEditingIfNeeded()
                    dismissShortcutEditingIfNeeded()
                    hoveredPresetID = nil
                    appState.selectedLayoutPresetID = nil
                    activeLayoutSelection = selection
                    appState.updateLayoutPreview(selection)
                },
                onHoverChange: { selection in
                    guard activeLayoutSelection == nil else { return }
                    appState.updateLayoutPreview(selection)
                },
                onSelectionCommit: { selection in
                    activeLayoutSelection = nil
                    appState.commitLayoutSelection(selection)
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

    private var layoutTargetInfoView: some View {
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
        .frame(maxWidth: 260)
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
        HStack(spacing: 12) {
            ZStack(alignment: .center) {
                PresetGridPreviewView(
                    rows: appState.rows,
                    columns: appState.columns,
                    selection: preset.scaledSelection(toRows: appState.rows, columns: appState.columns)
                )
                .frame(width: Self.presetGridColumnWidth, height: 26, alignment: .center)

                if isShowingDeleteButton(for: preset.id) {
                    Button {
                        dismissPresetNameEditingIfNeeded(except: preset.id)
                        deletePreset(id: preset.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Delete Layout")
                }
            }
            .frame(width: Self.presetGridColumnWidth, height: 26, alignment: .center)

            presetNameCell(for: preset)

            presetShortcutsCell(for: preset)
                .frame(width: Self.presetShortcutColumnWidth, alignment: .center)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissPresetNameEditingIfNeeded(except: preset.id)
            dismissShortcutEditingIfNeeded(except: preset.id)
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
                onCommit: {
                    commitPresetNameEdit(for: preset.id)
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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(ThemeColors.presetCellBackground(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(ThemeColors.presetCellBorder(for: colorScheme), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                    beginPresetNameEdit(for: preset)
            }
        }
    }

    @ViewBuilder
    private func presetShortcutsCell(for preset: LayoutPreset) -> some View {
        let shortcuts = preset.shortcuts
        let isEditing = recordingPresetShortcutID == preset.id
        let isAdding = addingShortcutPresetID == preset.id
        let isReplacing = isEditing && replacingShortcutIndex != nil

        VStack(alignment: .leading, spacing: 4) {
            FlowLayout(spacing: 4) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, shortcut in
                    shortcutBadge(for: preset, index: index, shortcut: shortcut, isEditing: isEditing, isAdding: isAdding, isReplacing: isReplacing)
                }

                if (isEditing || shortcuts.isEmpty) && !isAdding && !isReplacing {
                    Button {
                        addingShortcutIsGlobal = false
                        addingShortcutPresetID = preset.id
                        appState.setShortcutRecordingActive(true)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(ThemeColors.presetCellBackground(for: colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(ThemeColors.presetCellBorder(for: colorScheme), lineWidth: 0.5)
                    )
                    .instantTooltip(NSLocalizedString("Add Shortcut", comment: "Tooltip for add shortcut button"))

                    Button {
                        addingShortcutIsGlobal = true
                        addingShortcutPresetID = preset.id
                        appState.setShortcutRecordingActive(true)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "globe")
                                .font(.system(size: 8, weight: .semibold))
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(ThemeColors.presetCellBackground(for: colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(ThemeColors.presetCellBorder(for: colorScheme), lineWidth: 0.5)
                    )
                    .instantTooltip(NSLocalizedString("Add Global Shortcut", comment: "Tooltip for add global shortcut button"))
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
                        addingShortcutPresetID = nil
                        replacingShortcutIndex = nil
                        recordingPresetShortcutID = nil
                        appState.setShortcutRecordingActive(false)
                        appState.isEditingLayoutPresets = false
                    },
                    onRecordingChange: { recording in
                        if !recording {
                            addingShortcutPresetID = nil
                            replacingShortcutIndex = nil
                            recordingPresetShortcutID = nil
                            appState.setShortcutRecordingActive(false)
                            appState.isEditingLayoutPresets = false
                        }
                    },
                    validateShortcut: { shortcut in
                        appState.layoutShortcutConflictMessage(for: shortcut, excluding: preset.id)
                    }
                )
                .frame(height: 22)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissPresetNameEditingIfNeeded(except: preset.id)
            appState.selectLayoutPreset(preset.id)
            if shortcuts.isEmpty {
                addingShortcutPresetID = preset.id
                recordingPresetShortcutID = preset.id
                appState.setShortcutRecordingActive(true)
            } else {
                addingShortcutPresetID = nil
                replacingShortcutIndex = nil
                recordingPresetShortcutID = preset.id
            }
            appState.isEditingLayoutPresets = true
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
                    replacingShortcutIndex = nil
                    recordingPresetShortcutID = nil
                    appState.setShortcutRecordingActive(false)
                    appState.isEditingLayoutPresets = false
                },
                onRecordingChange: { recording in
                    if !recording {
                        replacingShortcutIndex = nil
                        recordingPresetShortcutID = nil
                        appState.setShortcutRecordingActive(false)
                        appState.isEditingLayoutPresets = false
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
        HStack(spacing: 3) {
            if shortcut.isGlobal {
                Image(systemName: "globe")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text(shortcut.displayString)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .lineLimit(1)

            if isEditing && !isReplacing {
                Button {
                    removeShortcut(at: index, from: preset.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.accentColor.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 0.5)
        )
        .onTapGesture {
            guard !isReplacing, !isAdding else { return }
            guard !isEditing else { return }
            dismissPresetNameEditingIfNeeded(except: preset.id)
            appState.selectLayoutPreset(preset.id)
            replacingShortcutIndex = index
            addingShortcutPresetID = nil
            recordingPresetShortcutID = preset.id
            appState.setShortcutRecordingActive(true)
            appState.isEditingLayoutPresets = true
        }
    }

    private func removeShortcut(at index: Int, from presetID: UUID) {
        appState.updateLayoutPreset(presetID) { preset in
            guard index < preset.shortcuts.count else { return }
            preset.shortcuts.remove(at: index)
        }
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
        if !appState.isPersistedLayoutPreset(id), committedName == currentName {
            cancelPresetNameEdit()
            return
        }
        appState.updateLayoutPreset(id) { preset in
            preset.name = committedName
        }
        editingPresetNameID = nil
        editingPresetNameDraft = ""
        syncEditingLayoutPresetsFlag()
    }

    private func cancelPresetNameEdit() {
        editingPresetNameID = nil
        editingPresetNameDraft = ""
        syncEditingLayoutPresetsFlag()
    }

    private func isShowingDeleteButton(for id: UUID) -> Bool {
        editingPresetNameID == id || recordingPresetShortcutID == id
    }

    private func isPresetSelected(_ id: UUID) -> Bool {
        if draggingPresetID == id { return true }
        return (hoveredPresetID ?? appState.selectedLayoutPresetID) == id
    }

    private func updatePresetSelectionPreview(for id: UUID?) {
        guard !appState.isEditingSettings else { return }
        guard draggingPresetID == nil else { return }
        guard activeLayoutSelection == nil else { return }
        guard let id,
              let preset = appState.displayedLayoutPresets.first(where: { $0.id == id }) else {
            appState.updateLayoutPreview(nil)
            return
        }
        appState.updateLayoutPreview(preset.scaledSelection(toRows: appState.rows, columns: appState.columns))
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
        let isEditing = editingPresetNameID != nil || isRecordingGlobalShortcut || recordingPresetShortcutID != nil || draggingPresetID != nil
        if isEditing {
            appState.selectLayoutPreset(preset.id)
            return
        }
        appState.selectLayoutPreset(preset.id)
        appState.applyLayoutPreset(id: preset.id)
    }

    private func startDraggingPreset(_ id: UUID) {
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
        let isEditing = recordingPresetShortcutID != nil || editingPresetNameID != nil
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
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> InlinePresetNameTextField {
        let textField = InlinePresetNameTextField()
        textField.delegate = context.coordinator
        textField.onCommit = context.coordinator.commit
        textField.onCancel = context.coordinator.cancel
        textField.stringValue = text
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
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        private let onCommit: () -> Void
        private let onCancel: () -> Void

        init(text: Binding<String>, onCommit: @escaping () -> Void, onCancel: @escaping () -> Void) {
            _text = text
            self.onCommit = onCommit
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
                onCommit()
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
