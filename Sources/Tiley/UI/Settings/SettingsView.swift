import AppKit
import Carbon
import Sparkle
import SwiftUI

struct SettingsView: View {
    private static let windowCornerRadius: CGFloat = 20
    private static let defaultGridColumns = 6
    private static let defaultGridRows = 6
    private static let defaultGridGap: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme
    var appState: AppState
    @State private var draftSettings: AppState.SettingsSnapshot
    @State private var isHoveringGridSection = false
    @State private var recordingDisplayShortcutKey: String?
    @State private var recordingDisplayShortcutIsGlobal = false

    init(appState: AppState) {
        self.appState = appState
        _draftSettings = State(initialValue: appState.settingsSnapshot)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                VStack(spacing: 0) {
                // Tahoe-style title bar
                HStack {
                    Button {
                        appState.apply(settings: draftSettings)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(TahoeToolbarButtonStyle())
                    .help("Back")

                    Spacer()

                    HStack(spacing: 6) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                        Text(NSLocalizedString("Settings", comment: "Settings window title"))
                            .font(.system(size: 13, weight: .semibold))
                    }

                    Spacer()

                    Button {
                        appState.quitApp()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "power")
                                .font(.system(size: 10, weight: .semibold))
                            Text(NSLocalizedString("Quit Tiley", comment: "Quit button"))
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(TahoeQuitButtonStyle())
                    .help(NSLocalizedString("Quit Tiley", comment: "Quit button tooltip"))
                }
                .padding(.top, 10)
                .padding(.bottom, 4)
                .padding(.horizontal, 8)

                Divider()
                    .opacity(0.5)

                ScrollView {
                    settingsEditor
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                }
            }
            } // ZStack
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: Self.windowCornerRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            if isHoveringGridSection {
                appState.updateSettingsPreview(draftSettings)
            }
        }
        .onChange(of: draftSettings) {
            // Mirror the draft so any exit path (status item, app switch,
            // window close, Quit) can persist it — see
            // `AppState.pendingSettingsDraft`.
            appState.pendingSettingsDraft = draftSettings
            if isHoveringGridSection {
                appState.updateSettingsPreview(draftSettings)
            }
        }
    }

    // MARK: - Settings Editor

    private var settingsEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let updater = appState.updater {
                TahoeSettingsSection(title: NSLocalizedString("Updates", comment: "Settings section")) {
                    VStack(spacing: 0) {
                        TahoeSettingsRow(label: NSLocalizedString("Automatically check for updates", comment: ""), systemImage: "exclamationmark.circle", iconAlignment: .center) {
                            Toggle("", isOn: Binding(
                                get: { updater.automaticallyChecksForUpdates },
                                set: { updater.automaticallyChecksForUpdates = $0 }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                        }
                        .padding(.vertical, 4)

                        Divider().opacity(0.4)

                        HStack {
                            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            CheckForUpdatesView(updater: updater)
                                .popover(isPresented: Binding(
                                    get: { appState.showsUpdateIndicator },
                                    set: { _ in }
                                ), arrowEdge: .bottom) {
                                    Text(NSLocalizedString("Update available", comment: "Badge shown when an update is available"))
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            TahoeSettingsSection(title: NSLocalizedString("Grid", comment: "Settings section")) {
                VStack(spacing: 0) {
                    TahoeSettingsRow(label: NSLocalizedString("Rows", comment: ""), systemImage: "square.split.1x2", iconAlignment: .center) {
                        Stepper("\(draftSettings.rows)", value: $draftSettings.rows, in: 2...12)
                            .labelsHidden()
                        Text("\(draftSettings.rows)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)
                    }
                    .padding(.vertical, 4)

                    Divider().opacity(0.4)

                    TahoeSettingsRow(label: NSLocalizedString("Columns", comment: ""), systemImage: "square.split.2x1", iconAlignment: .center) {
                        Stepper("\(draftSettings.columns)", value: $draftSettings.columns, in: 2...12)
                            .labelsHidden()
                        Text("\(draftSettings.columns)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)
                    }
                    .padding(.vertical, 4)

                    Divider().opacity(0.4)

                    VStack(spacing: 4) {
                        TahoeSettingsRow(label: NSLocalizedString("Gap", comment: ""), systemImage: "square.split.2x2", iconAlignment: .center) {
                            Text("\(Int(draftSettings.gap)) pt")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $draftSettings.gap, in: 0...24, step: 1)
                    }
                    .padding(.vertical, 4)

                    Divider().opacity(0.4)

                    HStack {
                        Spacer()
                        Button("Reset Grid to Default") {
                            draftSettings.columns = Self.defaultGridColumns
                            draftSettings.rows = Self.defaultGridRows
                            draftSettings.gap = Self.defaultGridGap
                        }
                        .disabled(isGridAtDefault)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onHover { hovering in
                isHoveringGridSection = hovering
                if hovering {
                    appState.updateSettingsPreview(draftSettings)
                } else {
                    appState.hidePreviewOverlay()
                }
            }

            TahoeSettingsSection(title: NSLocalizedString("Layouts", comment: "Settings section")) {
                HStack {
                    Text("Reset the layout preset list to the defaults.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Restore Defaults") {
                        appState.resetLayoutPresetsToDefault()
                    }
                    .disabled(isLayoutPresetsAtDefault)
                }
            }

            displayShortcutsSection

            TahoeSettingsSection(title: NSLocalizedString("Startup", comment: "Settings section")) {
                VStack(spacing: 0) {
                    TahoeSettingsRow(label: NSLocalizedString("Launch at login", comment: ""), systemImage: "power", iconAlignment: .center) {
                        Toggle("", isOn: Binding(
                            get: { draftSettings.launchAtLoginEnabled },
                            set: { newValue in
                                _ = appState.setLaunchAtLoginEnabled(newValue)
                                draftSettings.launchAtLoginEnabled = appState.launchAtLoginEnabled
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)

                    Divider().opacity(0.4)

                    TahoeSettingsRow(label: NSLocalizedString("Show menu icon", comment: ""), systemImage: "menubar.rectangle", iconAlignment: .center) {
                        Toggle("", isOn: Binding(
                            get: { draftSettings.menuIconVisible },
                            set: { newValue in
                                appState.setMenuIconVisible(newValue)
                                draftSettings.menuIconVisible = appState.menuIconVisible
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)

                    Divider().opacity(0.4)

                    TahoeSettingsRow(label: NSLocalizedString("Show Dock icon", comment: ""), systemImage: "dock.rectangle", iconAlignment: .center) {
                        Toggle("", isOn: Binding(
                            get: { draftSettings.dockIconVisible },
                            set: { newValue in
                                appState.setDockIconVisible(newValue)
                                draftSettings.dockIconVisible = appState.dockIconVisible
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)

                    Divider().opacity(0.4)

                    TahoeSettingsRow(label: NSLocalizedString("Show near icon when clicked", comment: "Show Tiley window near the menu bar or Dock icon"), systemImage: "cursorarrow.rays", iconAlignment: .center) {
                        Toggle("", isOn: $draftSettings.showNearIcon)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                    }
                    .padding(.vertical, 4)
                }
            }

            TahoeSettingsSection(title: NSLocalizedString("Debug", comment: "Settings section")) {
                VStack(spacing: 0) {
                    TahoeSettingsRow(label: NSLocalizedString("Write debug log to ~/tiley.log", comment: ""), systemImage: "ladybug", iconAlignment: .center) {
                        Toggle("", isOn: Binding(
                            get: { draftSettings.enableDebugLog },
                            set: { newValue in
                                draftSettings.enableDebugLog = newValue
                                appState.enableDebugLog = newValue
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)

                    #if DEBUG
                    Divider().opacity(0.4)

                    TahoeSettingsRow(label: NSLocalizedString("Simulate update available appearance", comment: "Debug toggle to preview the update-available UI")) {
                        Toggle("", isOn: Binding(
                            get: { draftSettings.debugSimulateUpdate },
                            set: { newValue in
                                draftSettings.debugSimulateUpdate = newValue
                                appState.debugSimulateUpdate = newValue
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                    #endif
                }
            }

            AcknowledgementsSection()
        }
        .font(.system(size: 13))
    }

    // MARK: - Shortcuts

    @ViewBuilder
    private var showTileyShortcutRow: some View {
        let keyPath = "showTiley.global"
        let isRecording = recordingDisplayShortcutKey == keyPath && recordingDisplayShortcutIsGlobal == true
        let hasShortcut = !draftSettings.hotKeyShortcut.isEmpty

        TahoeSettingsRow(label: NSLocalizedString("Show Tiley", comment: "Shortcut action to show Tiley overlay"), systemImage: "macwindow") {
            if isRecording {
                CompactShortcutRecorderField(
                    onShortcutRecorded: { newShortcut in
                        var s = newShortcut
                        s.isGlobal = true
                        draftSettings.hotKeyShortcut = s
                        recordingDisplayShortcutKey = nil
                        appState.setShortcutRecordingActive(false)
                    },
                    onRecordingChange: { recording in
                        if !recording {
                            recordingDisplayShortcutKey = nil
                            appState.setShortcutRecordingActive(false)
                        }
                    },
                    validateShortcut: { candidate in
                        validateDisplayShortcut(candidate, excludeKeyPath: keyPath)
                    }
                )
                .frame(width: 120, height: 22)
            } else if hasShortcut {
                DisplayShortcutBadgeLabelView(
                    shortcut: draftSettings.hotKeyShortcut,
                    isGlobal: true,
                    onTap: {
                        recordingDisplayShortcutKey = keyPath
                        recordingDisplayShortcutIsGlobal = true
                        appState.setShortcutRecordingActive(true)
                    },
                    onDelete: {
                        draftSettings.hotKeyShortcut = .empty
                    }
                )
            } else {
                AddShortcutButton(colorScheme: colorScheme, tooltip: NSLocalizedString("Add Global Shortcut", comment: "Tooltip for add global shortcut button")) {
                    HStack(spacing: 2) {
                        Image(systemName: "globe")
                            .font(.system(size: 8, weight: .semibold))
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                } action: {
                    recordingDisplayShortcutKey = keyPath
                    recordingDisplayShortcutIsGlobal = true
                    appState.setShortcutRecordingActive(true)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var isGridAtDefault: Bool {
        draftSettings.columns == Self.defaultGridColumns &&
        draftSettings.rows == Self.defaultGridRows &&
        draftSettings.gap == Self.defaultGridGap
    }

    /// Memoized display resolver — building one enumerates every screen and
    /// queries each display's vendor/model/serial fingerprint, and the
    /// settings body re-evaluates per slider tick. Rebuilt only when the
    /// screen configuration actually changes.
    @MainActor
    private enum DisplayResolverCache {
        static var signature: String = ""
        static var resolver: DisplayFingerprintResolver?
    }

    @MainActor
    private static func cachedDisplayResolver() -> DisplayFingerprintResolver {
        let sig = NSScreen.screens.map { "\($0.displayID):\($0.frame)" }.joined(separator: "|")
        if let cached = DisplayResolverCache.resolver, DisplayResolverCache.signature == sig {
            return cached
        }
        let fresh = DisplayFingerprintResolver()
        DisplayResolverCache.signature = sig
        DisplayResolverCache.resolver = fresh
        return fresh
    }

    /// Cache for `LayoutPreset.defaultPresets` keyed by grid size — the
    /// default set is rebuilt per body pass otherwise (settings body
    /// re-evaluates per slider tick).
    @MainActor
    private enum DefaultPresetsCache {
        static var key: String = ""
        static var presets: [LayoutPreset] = []
        static func presets(rows: Int, columns: Int) -> [LayoutPreset] {
            let k = "\(rows)x\(columns)"
            if k == key { return presets }
            let fresh = LayoutPreset.defaultPresets(rows: rows, columns: columns)
            key = k
            presets = fresh
            return fresh
        }
    }

    private var isLayoutPresetsAtDefault: Bool {
        let defaults = DefaultPresetsCache.presets(rows: appState.rows, columns: appState.columns)
        guard appState.layoutPresets.count == defaults.count else { return false }
        return zip(appState.layoutPresets, defaults).allSatisfy { current, def in
            current.name == def.name &&
            current.selection == def.selection &&
            current.secondarySelections == def.secondarySelections &&
            current.baseRows == def.baseRows &&
            current.baseColumns == def.baseColumns &&
            current.shortcuts == def.shortcuts
        }
    }

    private var isShortcutsAtDefault: Bool {
        draftSettings.hotKeyShortcut == .default &&
        draftSettings.displayShortcutSettings.selectNextWindow == DisplayShortcutSettings.defaultSelectNextWindow &&
        draftSettings.displayShortcutSettings.selectPreviousWindow == DisplayShortcutSettings.defaultSelectPreviousWindow &&
        draftSettings.displayShortcutSettings.bringToFront == DisplayShortcutSettings.defaultBringToFront &&
        draftSettings.displayShortcutSettings.closeOrQuit == DisplayShortcutSettings.defaultCloseOrQuit
    }

    private var displayShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
        TahoeSettingsSection(title: NSLocalizedString("Shortcuts", comment: "Settings section for shortcuts")) {
            VStack(spacing: 0) {
                    showTileyShortcutRow

                    Divider().opacity(0.4)

                    localOnlyShortcutRow(
                        label: NSLocalizedString("Select Next Window", comment: "Shortcut action to select next window"),
                        binding: $draftSettings.displayShortcutSettings.selectNextWindow.local,
                        enabledBinding: $draftSettings.displayShortcutSettings.selectNextWindow.localEnabled,
                        keyPath: "selectNextWindow.local",
                        iconContent: AnyView(
                            HStack(spacing: 1) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 9, weight: .semibold))
                                Image(systemName: "sidebar.left")
                                    .font(.system(size: 12, weight: .regular))
                            }
                            .foregroundStyle(.secondary)
                        )
                    )

                    Divider().opacity(0.4)

                    localOnlyShortcutRow(
                        label: NSLocalizedString("Select Previous Window", comment: "Shortcut action to select previous window"),
                        binding: $draftSettings.displayShortcutSettings.selectPreviousWindow.local,
                        enabledBinding: $draftSettings.displayShortcutSettings.selectPreviousWindow.localEnabled,
                        keyPath: "selectPreviousWindow.local",
                        iconContent: AnyView(
                            HStack(spacing: 1) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 9, weight: .semibold))
                                Image(systemName: "sidebar.left")
                                    .font(.system(size: 12, weight: .regular))
                            }
                            .foregroundStyle(.secondary)
                        )
                    )

                    Divider().opacity(0.4)

                    localOnlyShortcutRow(
                        label: NSLocalizedString("Bring to Front", comment: "Shortcut action to bring selected window to front"),
                        binding: $draftSettings.displayShortcutSettings.bringToFront.local,
                        enabledBinding: $draftSettings.displayShortcutSettings.bringToFront.localEnabled,
                        keyPath: "bringToFront.local",
                        systemImage: "macwindow.stack"
                    )

                    Divider().opacity(0.4)

                    localOnlyShortcutRow(
                        label: NSLocalizedString("Close / Quit", comment: "Shortcut action to close window or quit app"),
                        binding: $draftSettings.displayShortcutSettings.closeOrQuit.local,
                        enabledBinding: $draftSettings.displayShortcutSettings.closeOrQuit.localEnabled,
                        keyPath: "closeOrQuit.local",
                        iconContent: AnyView(
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 1)
                        )
                    )

                    Divider().opacity(0.4)

                    HStack {
                        Spacer()
                        Button(NSLocalizedString("Reset to Default", comment: "Reset shortcut to default")) {
                            draftSettings.hotKeyShortcut = .default
                            draftSettings.displayShortcutSettings.selectNextWindow = DisplayShortcutSettings.defaultSelectNextWindow
                            draftSettings.displayShortcutSettings.selectPreviousWindow = DisplayShortcutSettings.defaultSelectPreviousWindow
                            draftSettings.displayShortcutSettings.bringToFront = DisplayShortcutSettings.defaultBringToFront
                            draftSettings.displayShortcutSettings.closeOrQuit = DisplayShortcutSettings.defaultCloseOrQuit
                        }
                        .disabled(isShortcutsAtDefault)
                    }
                    .padding(.vertical, 4)
            }
        }

        TahoeSettingsSection(title: NSLocalizedString("Display Move Shortcuts", comment: "Settings section for display move shortcuts")) {
            VStack(spacing: 0) {
                    displayShortcutRow(
                    label: NSLocalizedString("Move to Primary Display", comment: "Display shortcut action"),
                    localBinding: $draftSettings.displayShortcutSettings.moveToPrimary.local,
                    localEnabledBinding: $draftSettings.displayShortcutSettings.moveToPrimary.localEnabled,
                    globalBinding: $draftSettings.displayShortcutSettings.moveToPrimary.global,
                    globalEnabledBinding: $draftSettings.displayShortcutSettings.moveToPrimary.globalEnabled,
                    localKeyPath: "moveToPrimary.local",
                    globalKeyPath: "moveToPrimary.global",
                    systemImage: "dot.scope.display"
                )

                Divider().opacity(0.4)

                displayShortcutRow(
                    label: NSLocalizedString("Move to Next Display", comment: "Display shortcut action"),
                    localBinding: $draftSettings.displayShortcutSettings.moveToNext.local,
                    localEnabledBinding: $draftSettings.displayShortcutSettings.moveToNext.localEnabled,
                    globalBinding: $draftSettings.displayShortcutSettings.moveToNext.global,
                    globalEnabledBinding: $draftSettings.displayShortcutSettings.moveToNext.globalEnabled,
                    localKeyPath: "moveToNext.local",
                    globalKeyPath: "moveToNext.global",
                    iconContent: AnyView(
                        HStack(spacing: 1) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .semibold))
                            Image(systemName: "display")
                                .font(.system(size: 12, weight: .regular))
                        }
                        .foregroundStyle(.secondary)
                    )
                )

                Divider().opacity(0.4)

                displayShortcutRow(
                    label: NSLocalizedString("Move to Previous Display", comment: "Display shortcut action"),
                    localBinding: $draftSettings.displayShortcutSettings.moveToPrevious.local,
                    localEnabledBinding: $draftSettings.displayShortcutSettings.moveToPrevious.localEnabled,
                    globalBinding: $draftSettings.displayShortcutSettings.moveToPrevious.global,
                    globalEnabledBinding: $draftSettings.displayShortcutSettings.moveToPrevious.globalEnabled,
                    localKeyPath: "moveToPrevious.local",
                    globalKeyPath: "moveToPrevious.global",
                    iconContent: AnyView(
                        HStack(spacing: 1) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 9, weight: .semibold))
                            Image(systemName: "display")
                                .font(.system(size: 12, weight: .regular))
                        }
                        .foregroundStyle(.secondary)
                    )
                )

                Divider().opacity(0.4)

                displayShortcutRow(
                    label: NSLocalizedString("Move to Other Display", comment: "Display shortcut action - shows popup menu"),
                    localBinding: $draftSettings.displayShortcutSettings.moveToOther.local,
                    localEnabledBinding: $draftSettings.displayShortcutSettings.moveToOther.localEnabled,
                    globalBinding: $draftSettings.displayShortcutSettings.moveToOther.global,
                    globalEnabledBinding: $draftSettings.displayShortcutSettings.moveToOther.globalEnabled,
                    localKeyPath: "moveToOther.local",
                    globalKeyPath: "moveToOther.global",
                    systemImage: "filemenu.and.selection"
                )

                Divider().opacity(0.4)

                displayShortcutRow(
                    label: NSLocalizedString("Move to Space", comment: "Shortcut action - shows a picker of Mission Control spaces"),
                    localBinding: $draftSettings.displayShortcutSettings.moveToSpace.local,
                    localEnabledBinding: $draftSettings.displayShortcutSettings.moveToSpace.localEnabled,
                    globalBinding: $draftSettings.displayShortcutSettings.moveToSpace.global,
                    globalEnabledBinding: $draftSettings.displayShortcutSettings.moveToSpace.globalEnabled,
                    localKeyPath: "moveToSpace.local",
                    globalKeyPath: "moveToSpace.global",
                    systemImage: "square.grid.3x1.below.line.grid.1x2"
                )

                DesktopShortcutStatusView()
                    .padding(.leading, shortcutIconColumnWidth + 8)
                    .padding(.bottom, 6)

                let resolver = Self.cachedDisplayResolver()
                ForEach(resolver.displays, id: \.displayID) { resolved in
                    Divider().opacity(0.4)

                    let fp = resolved.fingerprint
                    let occ = resolved.occurrenceIndex
                    let did = resolved.displayID
                    let name = resolver.displayName(for: resolved)
                    let keyBase = "moveToDisplay.\(fp.vendorNumber).\(fp.modelNumber).\(fp.serialNumber).\(occ)"
                    displayShortcutRow(
                        label: String(format: NSLocalizedString("Move to %@", comment: "Display shortcut action for specific display"), name),
                        localBinding: Binding(
                            get: { draftSettings.displayShortcutSettings.entry(for: fp, occurrenceIndex: occ)?.shortcuts.local },
                            set: {
                                let idx = draftSettings.displayShortcutSettings.ensureEntry(for: fp, occurrenceIndex: occ)
                                draftSettings.displayShortcutSettings.moveToDisplay[idx].shortcuts.local = $0
                            }
                        ),
                        localEnabledBinding: Binding(
                            get: { draftSettings.displayShortcutSettings.entry(for: fp, occurrenceIndex: occ)?.shortcuts.localEnabled ?? false },
                            set: {
                                let idx = draftSettings.displayShortcutSettings.ensureEntry(for: fp, occurrenceIndex: occ)
                                draftSettings.displayShortcutSettings.moveToDisplay[idx].shortcuts.localEnabled = $0
                            }
                        ),
                        globalBinding: Binding(
                            get: { draftSettings.displayShortcutSettings.entry(for: fp, occurrenceIndex: occ)?.shortcuts.global },
                            set: {
                                let idx = draftSettings.displayShortcutSettings.ensureEntry(for: fp, occurrenceIndex: occ)
                                draftSettings.displayShortcutSettings.moveToDisplay[idx].shortcuts.global = $0
                            }
                        ),
                        globalEnabledBinding: Binding(
                            get: { draftSettings.displayShortcutSettings.entry(for: fp, occurrenceIndex: occ)?.shortcuts.globalEnabled ?? false },
                            set: {
                                let idx = draftSettings.displayShortcutSettings.ensureEntry(for: fp, occurrenceIndex: occ)
                                draftSettings.displayShortcutSettings.moveToDisplay[idx].shortcuts.globalEnabled = $0
                            }
                        ),
                        localKeyPath: "\(keyBase).local",
                        globalKeyPath: "\(keyBase).global",
                        systemImage: "display.and.arrow.down"
                    )
                    .onHover { hovering in
                        if hovering {
                            appState.showDisplayHighlight(displayID: did)
                        } else {
                            appState.hideDisplayHighlight()
                        }
                    }
                }
            }
        }
        } // end VStack
    }

    @ViewBuilder
    private func localOnlyShortcutRow(
        label: String,
        binding: Binding<HotKeyShortcut?>,
        enabledBinding: Binding<Bool>,
        keyPath: String,
        systemImage: String? = nil,
        systemImageWeight: Font.Weight = .regular,
        iconContent: AnyView? = nil
    ) -> some View {
        TahoeSettingsRow(label: label, systemImage: systemImage, systemImageWeight: systemImageWeight, iconContent: iconContent) {
            displayShortcutBadgeOrRecorder(
                binding: binding,
                enabledBinding: enabledBinding,
                keyPath: keyPath,
                isGlobal: false
            )
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func displayShortcutRow(
        label: String,
        localBinding: Binding<HotKeyShortcut?>,
        localEnabledBinding: Binding<Bool>,
        globalBinding: Binding<HotKeyShortcut?>,
        globalEnabledBinding: Binding<Bool>,
        localKeyPath: String,
        globalKeyPath: String,
        systemImage: String? = nil,
        iconContent: AnyView? = nil
    ) -> some View {
        TahoeSettingsRow(label: label, systemImage: systemImage, iconContent: iconContent) {
            displayShortcutBadgeOrRecorder(
                binding: globalBinding,
                enabledBinding: globalEnabledBinding,
                keyPath: globalKeyPath,
                isGlobal: true
            )
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func displayShortcutBadgeOrRecorder(
        binding: Binding<HotKeyShortcut?>,
        enabledBinding: Binding<Bool>,
        keyPath: String,
        isGlobal: Bool
    ) -> some View {
        let isRecording = recordingDisplayShortcutKey == keyPath && recordingDisplayShortcutIsGlobal == isGlobal
        let hasShortcut = binding.wrappedValue != nil && binding.wrappedValue?.isEmpty == false

        if isRecording {
            CompactShortcutRecorderField(
                onShortcutRecorded: { newShortcut in
                    var s = newShortcut
                    s.isGlobal = isGlobal
                    binding.wrappedValue = s
                    enabledBinding.wrappedValue = true
                    recordingDisplayShortcutKey = nil
                    appState.setShortcutRecordingActive(false)
                },
                onRecordingChange: { recording in
                    if !recording {
                        recordingDisplayShortcutKey = nil
                        appState.setShortcutRecordingActive(false)
                    }
                },
                validateShortcut: { candidate in
                    validateDisplayShortcut(candidate, excludeKeyPath: keyPath)
                }
            )
            .frame(width: 120, height: 22)
        } else if hasShortcut {
            DisplayShortcutBadgeLabelView(
                shortcut: binding.wrappedValue!,
                isGlobal: isGlobal,
                onTap: {
                    recordingDisplayShortcutKey = keyPath
                    recordingDisplayShortcutIsGlobal = isGlobal
                    appState.setShortcutRecordingActive(true)
                },
                onDelete: {
                    binding.wrappedValue = nil
                    enabledBinding.wrappedValue = false
                }
            )
        } else {
            AddShortcutButton(colorScheme: colorScheme, tooltip: isGlobal
                ? NSLocalizedString("Add Global Shortcut", comment: "Tooltip for add global shortcut button")
                : NSLocalizedString("Add Shortcut", comment: "Tooltip for add shortcut button")
            ) {
                if isGlobal {
                    HStack(spacing: 2) {
                        Image(systemName: "globe")
                            .font(.system(size: 8, weight: .semibold))
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            } action: {
                recordingDisplayShortcutKey = keyPath
                recordingDisplayShortcutIsGlobal = isGlobal
                appState.setShortcutRecordingActive(true)
            }
        }
    }

    // MARK: - Validation

    private func validateDisplayShortcut(_ candidate: HotKeyShortcut, excludeKeyPath: String) -> String? {
        // Reserved keys
        if !candidate.isGlobal {
            if !excludeKeyPath.hasPrefix("selectNextWindow") && !excludeKeyPath.hasPrefix("selectPreviousWindow") && !excludeKeyPath.hasPrefix("bringToFront") && !excludeKeyPath.hasPrefix("closeOrQuit") && !excludeKeyPath.hasPrefix("moveToSpace") {
                if draftWindowActionConflicts(with: candidate) {
                    return NSLocalizedString("This shortcut is already used for a window action.", comment: "Shortcut conflict with window action")
                }
            }
            if candidate.keyCode == UInt32(kVK_ANSI_F), candidate.modifiers == UInt32(cmdKey) {
                return NSLocalizedString("\u{2318}F is reserved for searching the window list.", comment: "Cmd+F shortcut reserved for window search")
            }
        }

        // Check against draft hotKeyShortcut (Show Tiley)
        if excludeKeyPath != "showTiley.global" {
            let bareCandidate = HotKeyShortcut(keyCode: candidate.keyCode, modifiers: candidate.modifiers)
            let bareHotKey = HotKeyShortcut(keyCode: draftSettings.hotKeyShortcut.keyCode, modifiers: draftSettings.hotKeyShortcut.modifiers)
            if !draftSettings.hotKeyShortcut.isEmpty && bareCandidate == bareHotKey {
                return NSLocalizedString("This shortcut is already used by the global shortcut.", comment: "Layout shortcut conflict with app global shortcut")
            }
        }

        // Check layout presets
        if appState.layoutPresets.contains(where: { $0.shortcuts.contains(where: {
            $0.keyCode == candidate.keyCode && $0.modifiers == candidate.modifiers && $0.isGlobal == candidate.isGlobal
        }) }) {
            return NSLocalizedString("This shortcut is already used by a layout.", comment: "Display shortcut conflict with layout preset")
        }

        // Check other draft display shortcuts (excluding the current slot)
        let ds = draftSettings.displayShortcutSettings
        var allSlots: [(String, HotKeyShortcut)] = []
        let suffix = candidate.isGlobal ? ".global" : ".local"
        if let s = candidate.isGlobal ? ds.moveToPrimary.global : ds.moveToPrimary.local {
            allSlots.append(("moveToPrimary\(suffix)", s))
        }
        if let s = candidate.isGlobal ? ds.moveToNext.global : ds.moveToNext.local {
            allSlots.append(("moveToNext\(suffix)", s))
        }
        if let s = candidate.isGlobal ? ds.moveToPrevious.global : ds.moveToPrevious.local {
            allSlots.append(("moveToPrevious\(suffix)", s))
        }
        if let s = candidate.isGlobal ? ds.moveToOther.global : ds.moveToOther.local {
            allSlots.append(("moveToOther\(suffix)", s))
        }
        for entry in ds.moveToDisplay {
            let fp = entry.fingerprint
            let keyBase = "moveToDisplay.\(fp.vendorNumber).\(fp.modelNumber).\(fp.serialNumber).\(entry.occurrenceIndex)"
            if let s = candidate.isGlobal ? entry.shortcuts.global : entry.shortcuts.local {
                allSlots.append(("\(keyBase)\(suffix)", s))
            }
        }
        if let s = candidate.isGlobal ? ds.selectNextWindow.global : ds.selectNextWindow.local {
            allSlots.append(("selectNextWindow\(suffix)", s))
        }
        if let s = candidate.isGlobal ? ds.selectPreviousWindow.global : ds.selectPreviousWindow.local {
            allSlots.append(("selectPreviousWindow\(suffix)", s))
        }
        if let s = candidate.isGlobal ? ds.bringToFront.global : ds.bringToFront.local {
            allSlots.append(("bringToFront\(suffix)", s))
        }
        if let s = candidate.isGlobal ? ds.closeOrQuit.global : ds.closeOrQuit.local {
            allSlots.append(("closeOrQuit\(suffix)", s))
        }
        if let s = candidate.isGlobal ? ds.moveToSpace.global : ds.moveToSpace.local {
            allSlots.append(("moveToSpace\(suffix)", s))
        }
        for (kp, s) in allSlots where kp != excludeKeyPath {
            if s.keyCode == candidate.keyCode && s.modifiers == candidate.modifiers {
                return NSLocalizedString("This shortcut is already used by another display shortcut.", comment: "Display shortcut conflict with another display shortcut")
            }
        }

        return nil
    }

    private func draftWindowActionConflicts(with shortcut: HotKeyShortcut) -> Bool {
        let ds = draftSettings.displayShortcutSettings
        if ds.selectNextWindow.localEnabled,
           let s = ds.selectNextWindow.local, s == shortcut { return true }
        if ds.selectPreviousWindow.localEnabled,
           let s = ds.selectPreviousWindow.local, s == shortcut { return true }
        if ds.bringToFront.localEnabled,
           let s = ds.bringToFront.local, s == shortcut { return true }
        if ds.closeOrQuit.localEnabled,
           let s = ds.closeOrQuit.local, s == shortcut { return true }
        if ds.moveToSpace.localEnabled,
           let s = ds.moveToSpace.local, s == shortcut { return true }
        return false
    }
}

// MARK: - Desktop shortcut status

/// Shows which desktops can't be reached with a single "Switch to Desktop N"
/// press, with a button to the system Keyboard Shortcuts settings. Refreshes
/// whenever Tiley becomes active again, e.g. after returning from System Settings.
private struct DesktopShortcutStatusView: View {
    @State private var coverage: [SpaceMover.DesktopShortcutCoverage] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(coverage, id: \.displayName) { display in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: display.missing.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(display.missing.isEmpty ? Color.green : Color.orange)
                    Text(summary(for: display))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if coverage.contains(where: { !$0.missing.isEmpty }) {
                Text(NSLocalizedString(
                    "Desktops without a shortcut are reached one step at a time with ⌃← / ⌃→. Turn on “Switch to Desktop” shortcuts under Mission Control.",
                    comment: "Settings hint about missing Switch to Desktop shortcuts"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if !fixableDesktops.isEmpty {
                    Button(NSLocalizedString("Turn On Missing Shortcuts…", comment: "Button that turns on missing Switch to Desktop shortcuts")) {
                        confirmAndEnableMissingShortcuts()
                    }
                }
                Button(NSLocalizedString("Open Keyboard Shortcuts…", comment: "Button that opens the system Keyboard Shortcuts settings")) {
                    SpaceMover.openMissionControlShortcutSettings()
                }
            }
            .controlSize(.small)
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        coverage = SpaceMover.desktopShortcutCoverage()
    }

    /// Missing desktops that macOS has a shortcut slot for (1–16).
    private var fixableDesktops: [Int] {
        coverage.flatMap(\.missing).filter { $0 <= SpaceMover.maxDesktopShortcutNumber }
    }

    private func confirmAndEnableMissingShortcuts() {
        let (plans, skipped) = SpaceMover.planDesktopShortcuts(for: fixableDesktops)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Turn on Switch to Desktop shortcuts?", comment: "Confirm alert title")

        var lines: [String] = []
        if plans.isEmpty {
            lines.append(NSLocalizedString("None of the missing shortcuts can be turned on.", comment: "Confirm alert: nothing to do"))
        } else {
            lines.append(NSLocalizedString("Tiley will turn on these system shortcuts:", comment: "Confirm alert intro"))
            for plan in plans {
                lines.append(String(format: NSLocalizedString("Desktop %d: %@", comment: "Confirm alert line: desktop number, key"),
                                    plan.desktopNumber, plan.keyLabel))
            }
            lines.append("")
            lines.append(NSLocalizedString("These keys will switch desktops in every app. You can change them later in System Settings › Keyboard › Keyboard Shortcuts › Mission Control.", comment: "Confirm alert note"))
        }
        if !skipped.isEmpty {
            lines.append("")
            lines.append(String(format: NSLocalizedString("Skipped Desktop %@: its key is already used by another system shortcut.", comment: "Confirm alert: desktops skipped for key conflicts"),
                                SpaceMover.formatRanges(skipped)))
        }
        alert.informativeText = lines.joined(separator: "\n")

        if plans.isEmpty {
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
            alert.runModal()
            return
        }
        alert.addButton(withTitle: NSLocalizedString("Turn On", comment: "Confirm button that turns shortcuts on"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        SpaceMover.enableDesktopShortcuts(plans)
        refresh()
    }

    private func summary(for display: SpaceMover.DesktopShortcutCoverage) -> String {
        let all = SpaceMover.formatRanges(display.desktopNumbers)
        if display.missing.isEmpty {
            return String(format: NSLocalizedString(
                "%@: Desktop %@ — all set up for direct jumps.",
                comment: "Settings: display name, its System Settings desktop numbers"), display.displayName, all)
        }
        var text = String(format: NSLocalizedString(
            "%@: Desktop %@ — no shortcut for Desktop %@.",
            comment: "Settings: display name, its System Settings desktop numbers, numbers without a shortcut"),
            display.displayName, all, SpaceMover.formatRanges(display.missing))
        if display.missing.contains(where: { $0 > SpaceMover.maxDesktopShortcutNumber }) {
            text += " " + String(format: NSLocalizedString(
                "macOS only has shortcuts up to Desktop %d.",
                comment: "Settings: macOS limit on Switch to Desktop shortcuts"), SpaceMover.maxDesktopShortcutNumber)
        }
        return text
    }
}
