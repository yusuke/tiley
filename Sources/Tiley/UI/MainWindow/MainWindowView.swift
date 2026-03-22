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
    /// Width of the notch area in the menu bar (0 if no notch).
    /// Derived from auxiliaryTopLeftArea / auxiliaryTopRightArea.
    let notchWidth: CGFloat

    init(visibleFrame: CGRect, screenFrame: CGRect, notchWidth: CGFloat = 0) {
        self.visibleFrame = visibleFrame
        self.screenFrame = screenFrame
        self.notchWidth = notchWidth
    }
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

/// Renders the notch shape (black, bottom corners convex-rounded, top corners concave-rounded)
/// centered in the menu bar.  The concave corners at the top replicate the real MacBook notch
/// where the wallpaper area meets the notch with rounded transitions.
private struct NotchMenuBarCanvas: View {
    let compositeWidth: CGFloat
    let height: CGFloat
    let notchWidth: CGFloat

    private var cornerR: CGFloat { notchWidth * 0.03 }

    var body: some View {
        NotchShape(cornerR: cornerR)
            .fill(Color.black)
            .frame(width: notchWidth + 2 * cornerR, height: height)
    }
}

/// Custom shape that draws the notch outline with concave corners at the top
/// (where the wallpaper meets the notch) and convex corners at the bottom.
private struct NotchShape: Shape {
    let cornerR: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = cornerR
        let h = rect.height
        let bodyLeft = r
        let bodyRight = rect.width - r

        var path = Path()

        // Start at top-left (extended area for concave corner)
        path.move(to: CGPoint(x: 0, y: 0))

        // Top edge across the full width (including concave extensions)
        path.addLine(to: CGPoint(x: rect.width, y: 0))

        // Top-right concave corner: center at inner corner (rect.width, r)
        path.addArc(center: CGPoint(x: rect.width, y: r),
                    radius: r,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(180),
                    clockwise: true)

        // Right side of notch body
        path.addLine(to: CGPoint(x: bodyRight, y: h - r))

        // Bottom-right convex corner
        path.addArc(tangent1End: CGPoint(x: bodyRight, y: h),
                    tangent2End: CGPoint(x: bodyRight - r, y: h),
                    radius: r)

        // Bottom edge
        path.addLine(to: CGPoint(x: bodyLeft + r, y: h))

        // Bottom-left convex corner
        path.addArc(tangent1End: CGPoint(x: bodyLeft, y: h),
                    tangent2End: CGPoint(x: bodyLeft, y: h - r),
                    radius: r)

        // Left side of notch body
        path.addLine(to: CGPoint(x: bodyLeft, y: r))

        // Top-left concave corner: center at inner corner (0, r)
        path.addArc(center: CGPoint(x: 0, y: r),
                    radius: r,
                    startAngle: .degrees(0),
                    endAngle: .degrees(-90),
                    clockwise: true)

        path.closeSubpath()
        return path
    }
}

struct MainWindowView: View {
    private static let windowCornerRadius: CGFloat = 14
    private static let layoutPanelHorizontalPadding: CGFloat = 8
    private static let layoutGridAspectHeightRatio: CGFloat = 0.75
    private static let footerLeadingWidth: CGFloat = 36
    private static let footerTrailingWidth: CGFloat = 88
    private static let footerHeight: CGFloat = 28
    private static let footerBottomPadding: CGFloat = 8
    private static let layoutFooterTopPadding: CGFloat = 8
    private static let layoutFooterBottomPadding: CGFloat = 0
    private static let layoutGridTopPadding: CGFloat = 8
    private static let layoutPresetsTopPadding: CGFloat = 0
    private static let presetRowHeight: CGFloat = 44
    private static let presetRowSpacing: CGFloat = 8
    private static let presetsPanelChromeHeight: CGFloat = 42
    private static let presetGridColumnWidth: CGFloat = 51
    private static let presetShortcutColumnWidth: CGFloat = 160
    private static let presetActionColumnWidth: CGFloat = 60
    private static let defaultGridColumns = 6
    private static let defaultGridRows = 6
    private static let defaultGridGap: CGFloat = 0
    private static let sidebarWidth: CGFloat = 180

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
    @State private var windowSearchText = ""
    @State private var windowSearchFocusTrigger: Int = 0
    @State private var windowSearchBlurTrigger: Int = 0
    @State private var hoveredWindowIndex: Int?
    @State private var hoveredCloseButtonIndex: Int?
    @State private var hoveredKebabButtonIndex: Int?
    @State private var isSearchFieldFocused = false

    init(appState: AppState, screenRole: ScreenRole = .target) {
        self.appState = appState
        self.screenRole = screenRole
        _draftSettings = State(initialValue: appState.settingsSnapshot)
    }

    struct DesktopPictureInfo {
        let url: URL
        // NSImageScaling raw value
        let scaling: Int
        // allowClipping option
        let allowClipping: Bool
        // true when both scaling and allowClipping are absent (macOS tile mode)
        let isTiled: Bool
        // Physical screen size in points
        let screenSize: CGSize
        // Retina scale factor (e.g. 2.0 for Retina); macOS tiles wallpapers at 1 image pixel per physical pixel
        let screenScale: CGFloat
        // Background fill color shown in letterbox areas (fit/center modes)
        let fillColor: Color?
        // Pixel dimensions of the original wallpaper (may differ from url's image size when a thumbnail is used)
        let originalImageSize: CGSize?
    }

    private var desktopPictureInfo: DesktopPictureInfo? {
        _ = appState.desktopImageVersion  // Invalidate when wallpaper changes
        let screen: NSScreen?
        if let ctx = screenContext {
            screen = NSScreen.screens.first(where: { $0.frame == ctx.screenFrame })
        } else {
            screen = NSScreen.main
        }
        guard let screen else { return nil }
        guard let rawURL = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let opts = NSWorkspace.shared.desktopImageOptions(for: screen)

        // On macOS 15+, desktopImageURL always returns DefaultDesktop.heic for system
        // wallpapers. Try to resolve the actual image and display mode via the wallpaper Store.
        let storeInfo = Self.resolvedWallpaperInfo(for: rawURL)

        // Use thumbnail when available (aerial wallpapers with assetID); otherwise fall back to
        // the raw URL (DefaultDesktop.heic for preset wallpapers like "Lake Tahoe").
        // DefaultDesktop.heic is not the actual preset image, but Fill mode covers the grid
        // regardless of aspect ratio, so no gaps will appear.
        let url = storeInfo?.thumbnailURL ?? rawURL

        // When we use a thumbnail, read the actual wallpaper's pixel dimensions from the
        // original .heic so that tile/center size calculations are based on the real image size.
        var originalImageSize: CGSize? = nil
        if storeInfo?.thumbnailURL != nil {
            if let src = CGImageSourceCreateWithURL(rawURL as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
               let pixelWidth = props[kCGImagePropertyPixelWidth] as? CGFloat,
               let pixelHeight = props[kCGImagePropertyPixelHeight] as? CGFloat {
                originalImageSize = CGSize(width: pixelWidth, height: pixelHeight)
            }
        }

        // Whether rawURL points to a custom user image (not DefaultDesktop.heic system symlink).
        // On macOS 15+, custom images still have their actual path in desktopImageURL.
        let isCustomImage = rawURL.lastPathComponent != "DefaultDesktop.heic"

        // Determine display mode.
        // Known placement values from the Store plist:
        //   "Fill"      – proportional fill (clipping allowed)
        //   "SizeToFit" – proportional fit (no clipping)
        //   "Stretch"   – stretch to fill axes independently
        //   "Centered"  – center at 1:1 pixel ratio
        //   "Tiled"     – tile at 1 image pixel per physical pixel
        //
        // NOTE: macOS preset wallpapers (landscapes, cityscapes, etc.) always render as Fill
        // regardless of what the Store plist records. The plist placement field is only
        // meaningful when the user has explicitly set a custom wallpaper image.
        let scalingRaw: Int?
        let allowClipping: Bool
        let isTiled: Bool
        if storeInfo?.thumbnailURL != nil {
            // Aerial wallpaper with thumbnail — always render as fill to cover.
            // The plist placement value is unreliable: macOS records "Centered" even for
            // wallpapers that display as fill/cover. Only "Tile" is preserved because
            // tiling is visually distinct.
            if storeInfo?.placement == "Tile" {
                scalingRaw = nil
                allowClipping = false
                isTiled = true
            } else {
                scalingRaw = Int(NSImageScaling.scaleProportionallyUpOrDown.rawValue)
                allowClipping = true
                isTiled = false
            }
        } else if let scalingRawOpt = opts?[.imageScaling] as? Int {
            // Custom image with explicit desktopImageOptions (older macOS) — use them directly
            scalingRaw = scalingRawOpt
            allowClipping = opts?[.allowClipping] as? Bool ?? false
            isTiled = false
        } else if isCustomImage, let placement = storeInfo?.placement {
            // Custom image on macOS 15+ where desktopImageOptions no longer includes imageScaling.
            // Read the placement from the wallpaper Store plist instead.
            switch placement {
            case "Tile":
                scalingRaw = nil
                allowClipping = false
                isTiled = true
            case "Stretch":
                scalingRaw = Int(NSImageScaling.scaleAxesIndependently.rawValue)
                allowClipping = false
                isTiled = false
            case "Centered":
                scalingRaw = Int(NSImageScaling.scaleNone.rawValue)
                allowClipping = false
                isTiled = false
            case "SizeToFit":
                scalingRaw = Int(NSImageScaling.scaleProportionallyUpOrDown.rawValue)
                allowClipping = false
                isTiled = false
            default: // "Fill" and anything else
                scalingRaw = Int(NSImageScaling.scaleProportionallyUpOrDown.rawValue)
                allowClipping = true
                isTiled = false
            }
        } else {
            // System preset wallpaper (landscapes, cityscapes, etc.) with no useful metadata.
            // macOS always renders these as proportional fill (scale to cover, clip sides).
            scalingRaw = Int(NSImageScaling.scaleProportionallyUpOrDown.rawValue)
            allowClipping = true
            isTiled = false
        }
        let scaling = scalingRaw ?? Int(NSImageScaling.scaleProportionallyUpOrDown.rawValue)

        // Fill color: prefer Store plist value, fall back to desktopImageOptions
        let fillColor: Color?
        if let c = storeInfo?.fillColor {
            fillColor = c
        } else if let nsColor = opts?[.fillColor] as? NSColor,
                  let srgb = nsColor.usingColorSpace(.sRGB) {
            fillColor = Color(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
        } else {
            fillColor = nil
        }
        let info = DesktopPictureInfo(url: url, scaling: scaling, allowClipping: allowClipping, isTiled: isTiled, screenSize: screen.frame.size, screenScale: screen.backingScaleFactor, fillColor: fillColor, originalImageSize: originalImageSize)
        return info
    }

    /// Resolved wallpaper information read from the macOS 15+ wallpaper Store plist.
    private struct WallpaperStoreInfo {
        /// Thumbnail image URL (only available for aerial/system wallpapers with an assetID)
        let thumbnailURL: URL?
        /// Placement string from EncodedOptionValues:
        /// "Fill", "SizeToFit", "Stretch", "Centered", "Tiled"
        let placement: String?
        /// Background fill color from EncodedOptionValues
        let fillColor: Color?
    }

    /// On macOS 15+, desktopImageURL always returns DefaultDesktop.heic for system wallpapers.
    /// This method reads the wallpaper Store plist and returns the placement mode and fill color
    /// (and a thumbnail URL when available for aerial wallpapers with an assetID).
    private static func resolvedWallpaperInfo(for rawURL: URL) -> WallpaperStoreInfo? {
        let storeURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard let data = try? Data(contentsOf: storeURL),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        // Walk: AllSpacesAndDisplays > Desktop > Content
        guard let allSpaces = root["AllSpacesAndDisplays"] as? [String: Any],
              let desktop = allSpaces["Desktop"] as? [String: Any],
              let content = desktop["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              let first = choices.first
        else { return nil }

        // For custom image wallpapers the choice Configuration has type="imageFile" and a URL.
        // Check if it matches rawURL to confirm this is a custom (user-provided) image.
        var isCustomImage = false
        if let configData = first["Configuration"] as? Data,
           let config = try? PropertyListSerialization.propertyList(from: configData, format: nil) as? [String: Any],
           let typeStr = config["type"] as? String,
           typeStr == "imageFile",
           let urlDict = config["url"] as? [String: Any],
           let relativeStr = urlDict["relative"] as? String,
           let configURL = URL(string: relativeStr) {
            isCustomImage = (configURL.path == rawURL.path)
        }

        // Try to get thumbnail from Configuration > assetID (aerials only, not custom images)
        var thumbnailURL: URL? = nil
        if !isCustomImage,
           let configData = first["Configuration"] as? Data,
           let config = try? PropertyListSerialization.propertyList(from: configData, format: nil) as? [String: Any],
           let assetID = config["assetID"] as? String {
            let candidate = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/thumbnails/\(assetID).png")
            if FileManager.default.fileExists(atPath: candidate.path) {
                thumbnailURL = candidate
            }
        }

        // Read placement and fill color from EncodedOptionValues
        var placement: String? = nil
        var fillColor: Color? = nil
        if let encodedData = content["EncodedOptionValues"] as? Data,
           let encoded = try? PropertyListSerialization.propertyList(from: encodedData, format: nil) as? [String: Any],
           let values = encoded["values"] as? [String: Any] {
            // placement: values > placement > picker > _0 > id
            // Known values: "Fill", "SizeToFit", "Stretch", "Centered", "Tiled"
            if let placementDict = values["placement"] as? [String: Any],
               let picker = placementDict["picker"] as? [String: Any],
               let inner = picker["_0"] as? [String: Any],
               let id = inner["id"] as? String {
                placement = id
            }
            // fill color: values > color > color > _0 > color > components [r, g, b, a]
            // Components may be Double (modern plist) or String (older encoding)
            if let colorDict = values["color"] as? [String: Any],
               let colorInner = colorDict["color"] as? [String: Any],
               let color0 = colorInner["_0"] as? [String: Any],
               let colorData = color0["color"] as? [String: Any],
               let components = colorData["components"] as? [Any],
               components.count >= 3 {
                let r = (components[0] as? Double) ?? Double(components[0] as? String ?? "NaN") ?? 0
                let g = (components[1] as? Double) ?? Double(components[1] as? String ?? "NaN") ?? 0
                let b = (components[2] as? Double) ?? Double(components[2] as? String ?? "NaN") ?? 0
                fillColor = Color(red: r, green: g, blue: b)
            }
        }

        return WallpaperStoreInfo(thumbnailURL: thumbnailURL, placement: placement, fillColor: fillColor)
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
            if isShowing {
                windowSearchText = ""
            } else {
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
        .onChange(of: appState.windowTargetMenuRequestVersion) { _, _ in
            if !appState.isSidebarVisible {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.isSidebarVisible = true
                }
            }
            windowSearchFocusTrigger += 1
        }
        .onChange(of: appState.windowSearchFocusRequestVersion) { _, _ in
            if !appState.isSidebarVisible {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.isSidebarVisible = true
                }
            }
            windowSearchFocusTrigger += 1
        }
        .onChange(of: appState.windowSearchHideRequestVersion) { _, _ in
            windowSearchBlurTrigger += 1
            withAnimation(.easeInOut(duration: 0.2)) {
                appState.isSidebarVisible = false
            }
        }
        .onChange(of: windowSearchText) { _, newValue in
            appState.windowSearchQuery = newValue
        }
        .onChange(of: appState.windowSearchQuery) { _, newValue in
            if windowSearchText != newValue {
                windowSearchText = newValue
            }
        }
        .onChange(of: appState.windowTargetListVersion) { _, _ in
            if appState.hasUsedTabCycling {
                showSidebarIfNeeded()
            }
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
        VStack(spacing: 0) {
            // Tahoe-style title bar
            HStack {
                Button {
                    dismissPresetNameEditingIfNeeded()
                    appState.apply(settings: draftSettings)
                    draftSettings = appState.settingsSnapshot
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
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
            .frame(height: 36)
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
        VStack(spacing: 0) {
            // Tahoe-style title bar
            HStack {
                Spacer()

                HStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    Text("Tiley")
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
            .frame(height: 36)
            .padding(.horizontal, 8)

            Divider()
                .opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TahoeSettingsSection(title: NSLocalizedString("Permissions", comment: "Settings section")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(
                                    appState.accessibilityGranted
                                        ? NSLocalizedString("Accessibility enabled", comment: "")
                                        : NSLocalizedString("Accessibility required", comment: ""),
                                    systemImage: appState.accessibilityGranted ? "checkmark.shield" : "exclamationmark.shield"
                                )
                                .foregroundStyle(appState.accessibilityGranted ? .green : .orange)
                                Spacer()
                                Button("Open Prompt") {
                                    appState.requestAccessibilityAccess()
                                }
                                    }
                            Text("Window movement on macOS requires Accessibility permission.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            permissionsScreenshot(named: "dialog")
                            permissionsScreenshot(named: "system")
                        }
                    }
                }
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
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
        let hasSidebar = appState.isSidebarVisible
        let mainContentWidth = hasSidebar ? size.width - Self.sidebarWidth - 1 : size.width
        let fullCompositeWidth = mainContentWidth - (Self.layoutPanelHorizontalPadding * 2)

        // Use the full screen aspect ratio so the composite area (menu bar + grid + Dock)
        // matches the screen's proportions.
        let compositeAspectRatio: CGFloat
        if let ctx = screenContext, ctx.screenFrame.width > 0 {
            compositeAspectRatio = ctx.screenFrame.height / ctx.screenFrame.width
        } else {
            compositeAspectRatio = Self.layoutGridAspectHeightRatio
        }

        // Compute chrome inset ratios from the screen geometry.
        // Only show chrome when the inset is large enough to be a real menu bar / Dock.
        let chromeThreshold: CGFloat = 5.0
        let menuBarHeightRatio: CGFloat
        let dockBottomRatio: CGFloat
        let dockLeftRatio: CGFloat
        let dockRightRatio: CGFloat
        let notchWidthRatio: CGFloat
        if let ctx = screenContext, ctx.screenFrame.height > 0 {
            let sf = ctx.screenFrame
            let vf = ctx.visibleFrame
            let mbH = sf.maxY - vf.maxY
            let dbH = vf.minY - sf.minY
            let dlW = vf.minX - sf.minX
            let drW = sf.maxX - vf.maxX
            menuBarHeightRatio = mbH > chromeThreshold ? mbH / sf.height : 0
            dockBottomRatio    = dbH > chromeThreshold ? dbH / sf.height : 0
            dockLeftRatio      = dlW > chromeThreshold ? dlW / sf.width  : 0
            dockRightRatio     = drW > chromeThreshold ? drW / sf.width  : 0
            notchWidthRatio    = sf.width > 0 ? ctx.notchWidth / sf.width : 0
        } else {
            menuBarHeightRatio = 0; dockBottomRatio = 0; dockLeftRatio = 0; dockRightRatio = 0
            notchWidthRatio = 0
        }

        // Calculate the maximum composite height that still shows at least 4 preset rows.
        let minPresetCount: CGFloat = min(CGFloat(appState.displayedLayoutPresets.count), 4)
        let minPresetsHeight = minPresetCount * Self.presetRowHeight
            + max(0, minPresetCount - 1) * Self.presetRowSpacing
        let nonCompositeHeight = Self.layoutFooterTopPadding
            + Self.footerHeight
            + Self.layoutFooterBottomPadding
            + Self.layoutGridTopPadding
            + Self.layoutPresetsTopPadding
            + Self.presetsPanelChromeHeight
            + minPresetsHeight
            + Self.footerBottomPadding
        let maxCompositeHeight = size.height - nonCompositeHeight
        let fullCompositeHeight = fullCompositeWidth * compositeAspectRatio
        // If the full composite is too tall, shrink width proportionally.
        let compositeHeight: CGFloat
        let compositeWidth: CGFloat
        if fullCompositeHeight > maxCompositeHeight && maxCompositeHeight > 0 {
            compositeHeight = maxCompositeHeight
            compositeWidth = compositeHeight / compositeAspectRatio
        } else {
            compositeHeight = fullCompositeHeight
            compositeWidth = fullCompositeWidth
        }

        // Subdivide composite area into chrome + grid.
        let menuBarDisplayHeight = compositeHeight * menuBarHeightRatio
        let dockBottomDisplayHeight = compositeHeight * dockBottomRatio
        let dockLeftDisplayWidth = compositeWidth * dockLeftRatio
        let dockRightDisplayWidth = compositeWidth * dockRightRatio
        let notchDisplayWidth = compositeWidth * notchWidthRatio
        let gridWidth = compositeWidth - dockLeftDisplayWidth - dockRightDisplayWidth
        let gridHeight = compositeHeight - menuBarDisplayHeight - dockBottomDisplayHeight

        let availablePresetsHeight = max(
            0,
            size.height
                - Self.layoutFooterTopPadding
                - Self.footerHeight
                - Self.layoutFooterBottomPadding
                - Self.layoutGridTopPadding
                - compositeHeight
                - Self.layoutPresetsTopPadding
                - Self.footerBottomPadding
        )

        return HStack(spacing: 0) {
            if hasSidebar {
                windowListSidebar(height: size.height)
            }

            VStack(spacing: 0) {
                layoutGridFooterBar
                    .padding(.horizontal, Self.layoutPanelHorizontalPadding)
                    .padding(.top, Self.layoutFooterTopPadding)
                    .padding(.bottom, Self.layoutFooterBottomPadding)

                screenCompositeView(
                    compositeWidth: compositeWidth,
                    compositeHeight: compositeHeight,
                    menuBarHeight: menuBarDisplayHeight,
                    dockBottomHeight: dockBottomDisplayHeight,
                    dockLeftWidth: dockLeftDisplayWidth,
                    dockRightWidth: dockRightDisplayWidth,
                    notchWidth: notchDisplayWidth,
                    gridWidth: gridWidth,
                    gridHeight: gridHeight
                )
                .padding(.horizontal, Self.layoutPanelHorizontalPadding)
                .padding(.top, 8)

                layoutPresetsPanel(availableHeight: availablePresetsHeight)
                    .padding(.horizontal, Self.layoutPanelHorizontalPadding)
                    .padding(.top, Self.layoutPresetsTopPadding)
                    .padding(.bottom, Self.footerBottomPadding)

                Spacer(minLength: 0)
            }
            .frame(width: mainContentWidth)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            if screenRole.isTarget {
                keyboardHintsBar
            }
        }
    }

    /// Composites the wallpaper, menu bar chrome, Dock chrome, and grid workspace
    /// into a single view that represents the full screen area proportionally.
    @ViewBuilder
    private func screenCompositeView(
        compositeWidth: CGFloat,
        compositeHeight: CGFloat,
        menuBarHeight: CGFloat,
        dockBottomHeight: CGFloat,
        dockLeftWidth: CGFloat,
        dockRightWidth: CGFloat,
        notchWidth: CGFloat,
        gridWidth: CGFloat,
        gridHeight: CGFloat
    ) -> some View {
        let compositeSize = CGSize(width: compositeWidth, height: compositeHeight)
        ZStack(alignment: .topLeading) {
            // Layer 1: Wallpaper spanning the full composite area (menu bar + grid + Dock)
            if let info = desktopPictureInfo,
               let nsImage = NSImage(contentsOf: info.url) {
                DesktopPictureBackgroundView(nsImage: nsImage, info: info, size: compositeSize)
                    .frame(width: compositeWidth, height: compositeHeight)
                    .opacity(0.5)
            }

            // Layer 2: Menu bar + Dock chrome overlays + grid workspace
            VStack(spacing: 0) {
                // Menu bar — no background bar, just menu items rendered on top of wallpaper
                if menuBarHeight > 0 {
                    let menuItemOpacity: CGFloat = screenRole.isTarget ? 1.0 : 0.5
                    let fontSize = max(5, menuBarHeight * 0.35)
                    // When a notch is present, constrain menu items to the left auxiliary area
                    // so they don't overlap the notch. Left area ends at (compositeWidth - notchWidth) / 2.
                    let leftAreaWidth = notchWidth > 0
                        ? (compositeWidth - notchWidth) / 2
                        : compositeWidth
                    ZStack {
                        // Notch: full-width canvas drawing only the notch region in black
                        if notchWidth > 0 {
                            NotchMenuBarCanvas(
                                compositeWidth: compositeWidth,
                                height: menuBarHeight,
                                notchWidth: notchWidth
                            )
                        }
                        // Left-aligned menu items clipped to left auxiliary area
                        HStack(spacing: 0) {
                            HStack(spacing: fontSize * 0.6) {
                                Image(systemName: "apple.logo")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: fontSize)
                                Text(appState.currentLayoutTargetPrimaryText)
                                    .font(.system(size: fontSize, weight: .bold))
                                ForEach(appState.targetMenuBarTitles, id: \.self) { title in
                                    Text(title)
                                        .font(.system(size: fontSize))
                                }
                                Spacer()
                            }
                            .padding(.leading, menuBarHeight * 0.4 + fontSize * 0.5)
                            .frame(width: leftAreaWidth, height: menuBarHeight)
                            .clipped()
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .opacity(menuItemOpacity)
                        .frame(width: compositeWidth, height: menuBarHeight)
                    }
                    .frame(width: compositeWidth, height: menuBarHeight)
                }

                // Middle row: optional left Dock, grid, optional right Dock
                HStack(spacing: 0) {
                    if dockLeftWidth > 0 {
                        // Left Dock: rounded rect sized to fit Dock app icons, centered vertically
                        let leftDockApps = DockReader.readApps()
                        let leftDockIconSize = dockLeftWidth * 0.7
                        let leftDockIconSpacing = leftDockIconSize * 0.1
                        let leftDockRectHeight = min(
                            leftDockIconSize * CGFloat(leftDockApps.count)
                                + leftDockIconSpacing * CGFloat(max(0, leftDockApps.count - 1))
                                + leftDockIconSize * 0.3,
                            gridHeight * 0.9
                        )
                        VStack {
                            Spacer()
                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: dockLeftWidth * 0.25, style: .continuous)
                                    .fill(Color.white.opacity(0.50))
                                    .frame(width: dockLeftWidth * 0.85, height: leftDockRectHeight)
                                VStack(spacing: leftDockIconSpacing) {
                                    ForEach(leftDockApps.indices, id: \.self) { i in
                                        Image(nsImage: leftDockApps[i].icon)
                                            .resizable()
                                            .frame(width: leftDockIconSize, height: leftDockIconSize)
                                    }
                                }
                                .offset(y: leftDockIconSize * 0.15)
                            }
                            .clipped()
                            Spacer()
                        }
                        .frame(width: dockLeftWidth, height: gridHeight)
                    }

                    LayoutGridWorkspaceView(
                        rows: appState.rows,
                        columns: appState.columns,
                        gap: appState.gap,
                        highlightSelection: editingPresetHighlightSelection,
                        desktopPictureInfo: desktopPictureInfo,
                        showDesktopPicture: false,
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

                    if dockRightWidth > 0 {
                        // Right Dock: rounded rect sized to fit Dock app icons, centered vertically
                        let rightDockApps = DockReader.readApps()
                        let rightDockIconSize = dockRightWidth * 0.7
                        let rightDockIconSpacing = rightDockIconSize * 0.1
                        let rightDockRectHeight = min(
                            rightDockIconSize * CGFloat(rightDockApps.count)
                                + rightDockIconSpacing * CGFloat(max(0, rightDockApps.count - 1))
                                + rightDockIconSize * 0.3,
                            gridHeight * 0.9
                        )
                        VStack {
                            Spacer()
                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: dockRightWidth * 0.25, style: .continuous)
                                    .fill(Color.white.opacity(0.50))
                                    .frame(width: dockRightWidth * 0.85, height: rightDockRectHeight)
                                VStack(spacing: rightDockIconSpacing) {
                                    ForEach(rightDockApps.indices, id: \.self) { i in
                                        Image(nsImage: rightDockApps[i].icon)
                                            .resizable()
                                            .frame(width: rightDockIconSize, height: rightDockIconSize)
                                    }
                                }
                                .offset(y: rightDockIconSize * 0.15)
                            }
                            .clipped()
                            Spacer()
                        }
                        .frame(width: dockRightWidth, height: gridHeight)
                    }
                }

                // Bottom Dock: rounded rect sized to fit Dock app icons, centered horizontally
                if dockBottomHeight > 0 {
                    let bottomDockApps = DockReader.readApps()
                    let bottomDockIconSize = dockBottomHeight * 0.75
                    let bottomDockIconSpacing = bottomDockIconSize * 0.1
                    let bottomDockRectWidth = min(
                        bottomDockIconSize * CGFloat(bottomDockApps.count)
                            + bottomDockIconSpacing * CGFloat(max(0, bottomDockApps.count - 1))
                            + bottomDockIconSize * 0.3,
                        compositeWidth * 0.9
                    )
                    HStack {
                        Spacer()
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: dockBottomHeight * 0.4, style: .continuous)
                                .fill(Color.white.opacity(0.50))
                                .frame(width: bottomDockRectWidth, height: dockBottomHeight * 0.85)
                            HStack(spacing: bottomDockIconSpacing) {
                                ForEach(bottomDockApps.indices, id: \.self) { i in
                                    Image(nsImage: bottomDockApps[i].icon)
                                        .resizable()
                                        .frame(width: bottomDockIconSize, height: bottomDockIconSize)
                                }
                            }
                            .offset(x: bottomDockIconSize * 0.15)
                        }
                        .clipped()
                        Spacer()
                    }
                    .frame(width: compositeWidth, height: dockBottomHeight)
                }
            }
        }
        .frame(width: compositeWidth, height: compositeHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var keyboardHintsBar: some View {
        HStack(spacing: 12) {
            hintLabel("↓ Tab", NSLocalizedString("Next window", comment: "Status bar hint for next window"))
            hintLabel("↑ ⇧Tab", NSLocalizedString("Previous window", comment: "Status bar hint for previous window"))
            if isSearchFieldFocused {
                hintLabel("↩", NSLocalizedString("Confirm search criteria", comment: "Status bar hint for confirming search criteria"))
                hintLabel("Esc", NSLocalizedString("Clear search criteria", comment: "Status bar hint for clearing search criteria"))
            } else {
                hintLabel("↩", NSLocalizedString("Bring to front", comment: "Status bar hint for Enter key"))
                hintLabel("/", NSLocalizedString("Close window", comment: "Status bar hint for slash key to close window"))
                hintLabel("Esc", NSLocalizedString("Close Tiley", comment: "Status bar hint for Escape to close"))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .background(.ultraThinMaterial)
    }

    private func hintLabel(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.quaternary)
                )
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var layoutGridFooterBar: some View {
        HStack(spacing: 8) {
            // Leading: sidebar toggle button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.isSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(TahoeToolbarButtonStyle())
            .instantTooltip(appState.isSidebarVisible
                ? NSLocalizedString("Hide sidebar", comment: "Sidebar toggle tooltip when visible")
                : NSLocalizedString("Show sidebar", comment: "Sidebar toggle tooltip when hidden"))

            targetInfoContent

            Spacer(minLength: 0)

            if screenRole.isTarget {
                // Trailing: gear button
                Button {
                    dismissPresetNameEditingIfNeeded()
                    draftSettings = appState.settingsSnapshot
                    appState.beginSettingsEditing()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(TahoeToolbarButtonStyle())
                .instantTooltip(NSLocalizedString("Settings (⌘,)", comment: "Settings button tooltip"))
                .overlay(alignment: .trailing) {
                    if appState.hasUpdateBadge {
                        UpdateAvailableBadge()
                            .fixedSize()
                            .offset(x: -28)
                    }
                }
            }
        }
        .frame(height: Self.footerHeight)
    }

    private func layoutPresetsPanel(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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
            .frame(height: 24)
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
            .scrollIndicators(.automatic)
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

    // MARK: - Window List Sidebar

    private struct WindowListItem: Identifiable {
        let id: Int
        let appName: String
        let windowTitle: String
        let pid: pid_t
        let isLastWindowOfApp: Bool
        let sameAppWindowCount: Int
        let isHidden: Bool
    }

    private var filteredWindowTargets: [WindowListItem] {
        let targets = appState.windowTargetList
        let query = windowSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Count windows per PID to determine if a window is the last one for its app.
        var windowCountByPID: [pid_t: Int] = [:]
        for target in targets {
            windowCountByPID[target.processIdentifier, default: 0] += 1
        }

        var items: [WindowListItem] = []
        for (index, target) in targets.enumerated() {
            let title = target.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !query.isEmpty {
                let matchesApp = target.appName.lowercased().contains(query)
                let matchesTitle = title.lowercased().contains(query)
                if !matchesApp && !matchesTitle { continue }
            }
            items.append(WindowListItem(
                id: index,
                appName: target.appName,
                windowTitle: title,
                pid: target.processIdentifier,
                isLastWindowOfApp: windowCountByPID[target.processIdentifier] == 1,
                sameAppWindowCount: windowCountByPID[target.processIdentifier] ?? 1,
                isHidden: target.isHidden
            ))
        }
        return items
    }

    private func windowListSidebar(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            WindowSearchField(
                text: $windowSearchText,
                focusTrigger: windowSearchFocusTrigger,
                blurTrigger: windowSearchBlurTrigger,
                onTab: { forward in
                    appState.cycleTargetWindow(forward: forward)
                    windowSearchBlurTrigger += 1
                },
                onEscape: {
                    windowSearchText = ""
                    windowSearchBlurTrigger += 1
                },
                onFocusChange: { focused in
                    isSearchFieldFocused = focused
                }
            )
            .instantTooltip(NSLocalizedString("Type to filter (⌘F)", comment: "Window filter search field tooltip"))
            .frame(height: 22)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(filteredWindowTargets) { item in
                            windowListRow(item: item)
                                .id(item.id)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                }
                .scrollIndicators(.automatic)
                .onChange(of: appState.currentWindowTargetIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(width: Self.sidebarWidth - 8, height: height - 16)
        .modifier(SidebarGlassBackground(cornerRadius: 10))
        .padding(.leading, 8)
        .padding(.vertical, 8)
        .frame(width: Self.sidebarWidth, height: height)
        .onAppear {
            if screenRole.isTarget {
                appState.refreshAvailableWindows()
            }
        }
    }

    private func windowListRow(item: WindowListItem) -> some View {
        let isSelected = item.id == appState.currentWindowTargetIndex
        let isHovered = hoveredWindowIndex == item.id

        return Button {
            appState.selectWindowTarget(at: item.id)
        } label: {
            HStack(spacing: 6) {
                if let icon = NSRunningApplication(processIdentifier: item.pid)?.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.appName)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    if !item.windowTitle.isEmpty {
                        Text(item.windowTitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ThemeColors.presetRowBackground(selected: isSelected || isHovered, for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(ThemeColors.presetRowBorder(selected: isSelected, for: colorScheme), lineWidth: isSelected ? 1 : 0)
            )
            .overlay(alignment: .trailing) {
                if isHovered {
                    HStack(spacing: 2) {
                        // Close button
                        let isCloseHovered = hoveredCloseButtonIndex == item.id
                        Button {
                            appState.closeWindowTarget(at: item.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(isCloseHovered ? .primary : .tertiary)
                                .frame(width: 16, height: 16)
                                .background(
                                    Circle()
                                        .fill(isCloseHovered
                                              ? Color(white: colorScheme == .dark ? 0.45 : 0.55)
                                              : Color(white: colorScheme == .dark ? 0.3 : 0.7))
                                )
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            hoveredCloseButtonIndex = hovering ? item.id : nil
                        }
                        .instantTooltip({
                            if item.isLastWindowOfApp && appState.quitAppOnLastWindowClose {
                                return String(
                                    format: NSLocalizedString("Quit %@", comment: "Tooltip for closing the last window of an app (quits the app)"),
                                    item.appName
                                )
                            } else {
                                return String(
                                    format: NSLocalizedString("Close %@", comment: "Tooltip for close window button with window name"),
                                    item.windowTitle.isEmpty ? item.appName : item.windowTitle
                                )
                            }
                        }())

                        // More menu button
                        let isKebabHovered = hoveredKebabButtonIndex == item.id
                        WindowListMoreButton(
                            isHovered: isKebabHovered,
                            colorScheme: colorScheme,
                            sameAppWindowCount: item.sameAppWindowCount,
                            appName: item.appName,
                            windowTitle: item.windowTitle,
                            onCloseOthers: { appState.closeOtherWindowTargets(except: item.id) },
                            onQuit: { appState.quitApp(at: item.id) },
                            onHideOthers: { appState.hideOtherApps(except: item.id) }
                        )
                        .onHover { hovering in
                            hoveredKebabButtonIndex = hovering ? item.id : nil
                        }
                    }
                    .padding(.trailing, 4)
                    .transition(.identity)
                }
            }
            .animation(nil, value: isHovered)
        }
        .buttonStyle(.plain)
        .opacity(item.isHidden ? 0.5 : 1.0)
        .onHover { hovering in hoveredWindowIndex = hovering ? item.id : nil }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                appState.focusWindowAndDismiss(at: item.id)
            }
        )
    }

    // MARK: - Target Info (secondary screens)

    private var targetInfoContent: some View {
        HStack(spacing: 6) {
            if let icon = appState.currentLayoutTargetIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            if let secondary = appState.currentLayoutTargetSecondaryText {
                Text("\(appState.currentLayoutTargetPrimaryText) — \(secondary)")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(appState.currentLayoutTargetPrimaryText)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
        }
    }

    private var settingsEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            TahoeSettingsSection(title: NSLocalizedString("Startup", comment: "Settings section")) {
                VStack(spacing: 0) {
                    TahoeSettingsRow(label: NSLocalizedString("Launch at login", comment: "")) {
                        Toggle("", isOn: Binding(
                            get: { draftSettings.launchAtLoginEnabled },
                            set: { newValue in
                                _ = appState.setLaunchAtLoginEnabled(newValue)
                                draftSettings.launchAtLoginEnabled = appState.launchAtLoginEnabled
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)

                    Divider().opacity(0.4)

                    TahoeSettingsRow(label: NSLocalizedString("Show menu icon", comment: "")) {
                        Toggle("", isOn: Binding(
                            get: { draftSettings.menuIconVisible },
                            set: { newValue in
                                appState.setMenuIconVisible(newValue)
                                draftSettings.menuIconVisible = appState.menuIconVisible
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)

                    Divider().opacity(0.4)

                    TahoeSettingsRow(label: NSLocalizedString("Show Dock icon", comment: "")) {
                        Toggle("", isOn: Binding(
                            get: { draftSettings.dockIconVisible },
                            set: { newValue in
                                appState.setDockIconVisible(newValue)
                                draftSettings.dockIconVisible = appState.dockIconVisible
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                }
            }

            TahoeSettingsSection(title: NSLocalizedString("Shortcut", comment: "Settings section")) {
                VStack(spacing: 8) {
                    TahoeSettingsRow(label: NSLocalizedString("Global shortcut", comment: "")) {
                        ShortcutRecorderField(
                            shortcut: $draftSettings.hotKeyShortcut,
                            onRecordingChange: { isRecording in
                                isRecordingGlobalShortcut = isRecording
                                appState.setShortcutRecordingActive(isRecording)
                            }
                        )
                        .frame(width: 140, height: 22)
                    }
                    .padding(.vertical, 2)

                    HStack {
                        Text("Click the field, then press the new shortcut.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button("Reset to Default") {
                            dismissPresetNameEditingIfNeeded()
                            draftSettings.hotKeyShortcut = .default
                        }
                    }
                }
            }

            TahoeSettingsSection(title: NSLocalizedString("Windows", comment: "Settings section")) {
                VStack(spacing: 0) {
                    TahoeSettingsRow(label: NSLocalizedString("Quit app when closing last window", comment: "")) {
                        Toggle("", isOn: Binding(
                            get: { draftSettings.quitAppOnLastWindowClose },
                            set: { newValue in
                                draftSettings.quitAppOnLastWindowClose = newValue
                                appState.quitAppOnLastWindowClose = newValue
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)

                }
            }

            TahoeSettingsSection(title: NSLocalizedString("Grid", comment: "Settings section")) {
                VStack(spacing: 0) {
                    TahoeSettingsRow(label: NSLocalizedString("Columns", comment: "")) {
                        Stepper("\(draftSettings.columns)", value: $draftSettings.columns, in: 2...12)
                            .labelsHidden()
                        Text("\(draftSettings.columns)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)
                    }
                    .padding(.vertical, 4)

                    Divider().opacity(0.4)

                    TahoeSettingsRow(label: NSLocalizedString("Rows", comment: "")) {
                        Stepper("\(draftSettings.rows)", value: $draftSettings.rows, in: 2...12)
                            .labelsHidden()
                        Text("\(draftSettings.rows)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)
                    }
                    .padding(.vertical, 4)

                    Divider().opacity(0.4)

                    VStack(spacing: 4) {
                        TahoeSettingsRow(label: NSLocalizedString("Gap", comment: "")) {
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
                        dismissPresetNameEditingIfNeeded()
                        appState.resetLayoutPresetsToDefault()
                    }
                }
            }

            if let updater = appState.updater {
                TahoeSettingsSection(title: NSLocalizedString("Updates", comment: "Settings section")) {
                    VStack(spacing: 0) {
                        TahoeSettingsRow(label: NSLocalizedString("Automatically check for updates", comment: "")) {
                            Toggle("", isOn: Binding(
                                get: { updater.automaticallyChecksForUpdates },
                                set: { updater.automaticallyChecksForUpdates = $0 }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }
                        .padding(.vertical, 4)

                        Divider().opacity(0.4)

                        HStack {
                            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if appState.hasUpdateBadge {
                                UpdateAvailableBadge()
                            }
                            CheckForUpdatesView(updater: updater)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            TahoeSettingsSection(title: NSLocalizedString("Debug", comment: "Settings section")) {
                VStack(spacing: 0) {
                    TahoeSettingsRow(label: NSLocalizedString("Write resize debug log to ~/tiley.log", comment: "")) {
                        Toggle("", isOn: Binding(
                            get: { draftSettings.useAppleScriptResize },
                            set: { newValue in
                                draftSettings.useAppleScriptResize = newValue
                                appState.useAppleScriptResize = newValue
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .font(.system(size: 13))
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
                .instantTooltip(NSLocalizedString("Edit Layout", comment: "Tooltip for edit layout button"))

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

    private func showSidebarIfNeeded() {
        if !appState.isSidebarVisible {
            withAnimation(.easeInOut(duration: 0.2)) {
                appState.isSidebarVisible = true
            }
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

// MARK: - Window Search Field (NSViewRepresentable)

/// A search field that intercepts Tab, Shift+Tab, and Escape before the system
/// focus navigation handles them.  Focus is driven by integer triggers rather
/// than `@FocusState` because the latter does not work with NSViewRepresentable.
private struct WindowSearchField: NSViewRepresentable {
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

// MARK: - Tahoe Settings Section

private struct TahoeSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)

            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(SettingsSectionBackground(cornerRadius: 10))
        }
    }
}

private struct SettingsSectionBackground: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(settingsCardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(settingsCardBorder, lineWidth: 0.5)
                )
        }
    }

    private var settingsCardFill: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.06)
        default:
            return Color.white.opacity(0.65)
        }
    }

    private var settingsCardBorder: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.10)
        default:
            return Color.black.opacity(0.08)
        }
    }
}

// MARK: - Tahoe Settings Row

private struct TahoeSettingsRow<Trailing: View>: View {
    let label: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            trailing()
        }
    }
}

// MARK: - SidebarGlassBackground

/// Applies Liquid Glass (macOS 26+) or falls back to NSVisualEffectView.
private struct SidebarGlassBackground: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    VisualEffectFallbackBackground(cornerRadius: cornerRadius)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

/// Fallback for macOS < 26.
private struct VisualEffectFallbackBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .withinWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.layer?.cornerRadius = cornerRadius
    }
}

// MARK: - Tahoe-style Toolbar Button

private struct TahoeQuitButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovered || configuration.isPressed ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color.black.opacity(0.08)
                            : isHovered
                                ? Color.white.opacity(0.9)
                                : Color.clear
                    )
                    .shadow(
                        color: isHovered || configuration.isPressed
                            ? .black.opacity(0.08) : .clear,
                        radius: 2, x: 0, y: 0.5
                    )
            )
            .contentShape(Capsule())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct TahoeToolbarButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovered || configuration.isPressed ? .primary : .secondary)
            .frame(width: 30, height: 30)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color.black.opacity(0.08)
                            : isHovered
                                ? Color.white.opacity(0.9)
                                : Color.clear
                    )
                    .shadow(
                        color: isHovered || configuration.isPressed
                            ? .black.opacity(0.08) : .clear,
                        radius: 2, x: 0, y: 0.5
                    )
            )
            .contentShape(Capsule())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct UpdateAvailableBadge: View {
    var body: some View {
        Text(NSLocalizedString("Update available", comment: "Badge shown when an update is available"))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.red, in: Capsule())
            .fixedSize()
    }
}

// MARK: - Window List More Button (NSViewRepresentable)

/// A circular "…" button that shows a context menu via NSMenu.
/// Using NSViewRepresentable avoids SwiftUI Menu rendering issues
/// where the Circle background gets stripped by borderlessButton style.
private struct WindowListMoreButton: NSViewRepresentable {
    let isHovered: Bool
    let colorScheme: ColorScheme
    let sameAppWindowCount: Int
    let appName: String
    let windowTitle: String
    let onCloseOthers: () -> Void
    let onQuit: () -> Void
    let onHideOthers: () -> Void

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true

        let button = NSButton(frame: .zero)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 8, weight: .bold))
        button.imagePosition = .imageOnly
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.tag = 1

        container.addSubview(button)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 16),
            container.heightAnchor.constraint(equalToConstant: 16),
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 16),
            button.heightAnchor.constraint(equalToConstant: 16),
        ])

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let coord = context.coordinator
        coord.sameAppWindowCount = sameAppWindowCount
        coord.appName = appName
        coord.windowTitle = windowTitle
        coord.onCloseOthers = onCloseOthers
        coord.onQuit = onQuit
        coord.onHideOthers = onHideOthers

        let bgColor: NSColor
        if isHovered {
            bgColor = NSColor(white: colorScheme == .dark ? 0.45 : 0.55, alpha: 1)
        } else {
            bgColor = NSColor(white: colorScheme == .dark ? 0.3 : 0.7, alpha: 1)
        }
        container.layer?.backgroundColor = bgColor.cgColor

        if let button = container.viewWithTag(1) as? NSButton {
            button.contentTintColor = isHovered ? .labelColor : .tertiaryLabelColor
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            sameAppWindowCount: sameAppWindowCount,
            appName: appName,
            windowTitle: windowTitle,
            onCloseOthers: onCloseOthers,
            onQuit: onQuit,
            onHideOthers: onHideOthers
        )
    }

    class Coordinator: NSObject {
        var sameAppWindowCount: Int
        var appName: String
        var windowTitle: String
        var onCloseOthers: () -> Void
        var onQuit: () -> Void
        var onHideOthers: () -> Void

        init(sameAppWindowCount: Int, appName: String, windowTitle: String,
             onCloseOthers: @escaping () -> Void, onQuit: @escaping () -> Void,
             onHideOthers: @escaping () -> Void) {
            self.sameAppWindowCount = sameAppWindowCount
            self.appName = appName
            self.windowTitle = windowTitle
            self.onCloseOthers = onCloseOthers
            self.onQuit = onQuit
            self.onHideOthers = onHideOthers
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()

            if sameAppWindowCount > 1 {
                let closeOthersItem = NSMenuItem(
                    title: String(
                        format: NSLocalizedString("Close other windows of %@", comment: "Menu item to close other windows of the same app"),
                        appName
                    ),
                    action: #selector(closeOthersAction),
                    keyEquivalent: ""
                )
                closeOthersItem.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
                closeOthersItem.target = self
                menu.addItem(closeOthersItem)
            }

            let quitItem = NSMenuItem(
                title: String(
                    format: NSLocalizedString("Quit %@", comment: "Menu item to quit the application"),
                    appName
                ),
                action: #selector(quitAction),
                keyEquivalent: ""
            )
            quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
            quitItem.target = self
            menu.addItem(quitItem)

            let hideItem = NSMenuItem(
                title: String(
                    format: NSLocalizedString("Hide windows besides %@", comment: "Menu item to hide all windows except the selected app"),
                    appName
                ),
                action: #selector(hideOthersAction),
                keyEquivalent: ""
            )
            hideItem.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
            hideItem.target = self
            menu.addItem(hideItem)

            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
        }

        @objc private func closeOthersAction() { onCloseOthers() }
        @objc private func quitAction() { onQuit() }
        @objc private func hideOthersAction() { onHideOthers() }
    }
}

#Preview("NotchShape") {
    NotchMenuBarCanvas(compositeWidth: 300, height: 30, notchWidth: 120)
        .background(Color.blue)
        .frame(width: 300, height: 30)
}
