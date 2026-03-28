import AppKit
import Carbon
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

    private var cornerR: CGFloat { notchWidth * 0.05 }

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

private final class AppInfoCache {
    private var icons: [pid_t: NSImage] = [:]
    private var bundleIDs: [pid_t: String] = [:]

    func icon(for pid: pid_t) -> NSImage? {
        if let cached = icons[pid] { return cached }
        guard let icon = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        icons[pid] = icon
        return icon
    }

    func bundleID(for pid: pid_t) -> String? {
        if let cached = bundleIDs[pid] { return cached }
        guard let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return nil }
        bundleIDs[pid] = id
        return id
    }

    func invalidate() {
        icons.removeAll(keepingCapacity: true)
        bundleIDs.removeAll(keepingCapacity: true)
    }
}

struct MainWindowView: View {
    private static let windowCornerRadius: CGFloat = 20
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
    private static let presetGridMaxHeight: CGFloat = 28
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
    @State private var recordingPresetShortcutID: UUID?
    @State private var addingShortcutPresetID: UUID?
    @State private var addingShortcutIsGlobal = false
    @State private var replacingShortcutIndex: Int?
    @State private var recordingDisplayShortcutKey: String?
    @State private var recordingDisplayShortcutIsGlobal = false
    @State private var nameFieldFocusTrigger: Int = 0
    @State private var hoveredPresetID: UUID?
    @State private var draggingPresetID: UUID?
    @State private var didReorderDuringDrag = false
    @State private var isPerformingDrop = false
    @State private var dragEndTask: Task<Void, Never>?
    @State private var isHoveringGridSection = false
    @State private var windowSearchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var appInfoCache = AppInfoCache()
    @State private var windowSearchFocusTrigger: Int = 0
    @State private var windowSearchBlurTrigger: Int = 0
    @State private var hoveredWindowIndex: Int?
    @State private var hoveredScreenHeaderID: CGDirectDisplayID?
    @State private var hoveredEmptyScreenID: CGDirectDisplayID?
    @State private var isSearchFieldFocused = false
    @State private var isSearchFieldVisible = false
    @State private var sidebarSelection: SidebarSelection?

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
            // The plist placement value is unreliable for system wallpapers: macOS
            // always renders presets as Fill regardless of what the Store records.
            scalingRaw = Int(NSImageScaling.scaleProportionallyUpOrDown.rawValue)
            allowClipping = true
            isTiled = false
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
        // For system wallpapers without a resolvable thumbnail (e.g. programmatic
        // wallpapers like "Macintosh"), DefaultDesktop.heic is NOT the correct image.
        // Skip showing the wallpaper entirely rather than displaying the wrong image.
        if storeInfo?.thumbnailURL == nil && !isCustomImage {
            return nil
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

        // If no assetID thumbnail, try provider-based lookup for dynamic wallpapers
        // (Sequoia, Sonoma, Ventura, Monterey).
        if thumbnailURL == nil, !isCustomImage,
           let provider = first["Provider"] as? String {
            thumbnailURL = Self.thumbnailForProvider(provider)
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

    /// Resolves a thumbnail URL for provider-based dynamic wallpapers.
    /// Maps known provider strings to system thumbnail files, choosing
    /// a light or dark variant based on the current system appearance.
    private static func thumbnailForProvider(_ provider: String) -> URL? {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        switch provider {
        case "com.apple.wallpaper.choice.sequoia":
            // Sequoia thumbnails live inside the extension bundle.
            let suffix = isDark ? "thumbnail dark" : "thumbnail light"
            let base = "/System/Library/ExtensionKit/Extensions/WallpaperSequoiaExtension.appex/Contents/Resources"
            return firstExisting([
                "\(base)/\(suffix).heic",
                "\(base)/thumbnail.heic",
            ])

        case "com.apple.wallpaper.choice.sonoma":
            return thumbnailInSystemDir(name: "Sonoma", isDark: isDark)

        case "com.apple.wallpaper.choice.ventura":
            return thumbnailInSystemDir(name: "Ventura Graphic", isDark: isDark)

        case "com.apple.wallpaper.choice.monterey":
            return thumbnailInSystemDir(name: "Monterey Graphic", isDark: isDark)

        case "com.apple.wallpaper.choice.macintosh":
            // The Macintosh wallpaper is fully programmatic (Metal-rendered), but the
            // extension bundle contains IconGarden.png — the iconic scattered classic
            // Mac icons that form the wallpaper's main visual.
            let path = "/System/Library/ExtensionKit/Extensions/WallpaperMacintoshExtension.appex/Contents/Resources/IconGarden.png"
            return firstExisting([path])

        default:
            return nil
        }
    }

    /// Looks up a wallpaper thumbnail in `/System/Library/Desktop Pictures/.thumbnails/`
    /// with light/dark variant support.
    private static func thumbnailInSystemDir(name: String, isDark: Bool) -> URL? {
        let dir = "/System/Library/Desktop Pictures/.thumbnails"
        let suffix = isDark ? " Dark" : " Light"
        return firstExisting([
            "\(dir)/\(name)\(suffix).heic",
            "\(dir)/\(name).heic",
        ])
    }

    /// Returns the first path that exists on disk as a file URL, or nil.
    private static func firstExisting(_ paths: [String]) -> URL? {
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Determines the menu bar text color for the current preview screen.
    ///
    /// For the screen where the status item lives, we read the actual macOS menu bar
    /// appearance (VibrantLight → black, VibrantDark → white).  For other screens we
    /// fall back to sampling the wallpaper image brightness.
    private func menuBarForegroundColor(wallpaperImage: NSImage?) -> Color {
        _ = appState.desktopImageVersion  // re-evaluate when wallpaper changes

        // Determine which screen we are previewing.
        let previewScreen: NSScreen?
        if let ctx = screenContext {
            previewScreen = NSScreen.screens.first(where: { $0.frame == ctx.screenFrame })
        } else {
            previewScreen = NSScreen.main
        }

        // If the status item is on the same screen, use the OS-reported appearance.
        let statusItemScreen = appState.statusItemScreen
        if let ps = previewScreen, let ss = statusItemScreen, ps.frame == ss.frame {
            return appState.menuBarIsDark ? .white : .black
        }

        // Fall back to image-based luminance for other screens.
        guard let image = wallpaperImage,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return .white }
        return Self.menuBarForegroundColorFromImage(cgImage, info: desktopPictureInfo)
    }

    /// Returns the menu bar text color by sampling the top ~4 % of the image.
    /// CGContext.draw maps CGImage row 0 (visual top) to the bottom of the
    /// destination rect, so we draw at y = 0 to capture the visual top.
    /// Menu bar height in points (macOS standard).
    private static let menuBarPoints: CGFloat = 25

    private static func menuBarForegroundColorFromImage(
        _ cgImage: CGImage,
        info: DesktopPictureInfo?
    ) -> Color {
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)

        // Compute the image rows that actually appear behind the menu bar.
        var sampleStart = 0        // first row of the image behind the menu bar
        var sampleRows  = max(1, Int(imgH) / 25)  // fallback: top 4 %

        if let info {
            let scrW = info.screenSize.width  * info.screenScale
            let scrH = info.screenSize.height * info.screenScale
            let isFill = info.allowClipping   // Fill clips the overflow

            let scale: CGFloat
            if isFill {
                scale = max(scrW / imgW, scrH / imgH)
            } else {
                scale = min(scrW / imgW, scrH / imgH)
            }

            // In Fill mode the image is centred and the excess is cropped.
            let cropTop: CGFloat = isFill
                ? max(0, (imgH * scale - scrH) / 2.0 / scale)
                : 0

            let menuBarImageRows = Int(ceil(menuBarPoints * info.screenScale / scale))
            sampleStart = Int(cropTop)
            sampleRows  = max(1, min(menuBarImageRows, Int(imgH) - sampleStart))
        }

        // Crop the image to the menu bar region.
        // CGImage coordinate system has (0,0) at the top-left, so this
        // directly selects the visual rows behind the menu bar.
        guard let cropped = cgImage.cropping(to: CGRect(
            x: 0, y: sampleStart, width: Int(imgW), height: sampleRows
        )) else { return .white }

        let width = cropped.width
        let space = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        guard let context = CGContext(
            data: nil, width: width, height: cropped.height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .white }

        context.draw(cropped, in: CGRect(x: 0, y: 0,
                                          width: CGFloat(width),
                                          height: CGFloat(cropped.height)))

        guard let data = context.data else { return .white }
        let buffer = data.assumingMemoryBound(to: UInt8.self)

        // Build a luminance histogram and find the median.
        // The median is robust against small dark elements (icons, silhouettes)
        // — similar to the Gaussian blur macOS applies behind the menu bar.
        var histogram = [Int](repeating: 0, count: 256)
        let pixelCount = width * cropped.height
        for i in 0..<pixelCount {
            let offset = i * 4
            let r = Double(buffer[offset])     / 255.0
            let g = Double(buffer[offset + 1]) / 255.0
            let b = Double(buffer[offset + 2]) / 255.0
            let lum = 0.299 * r + 0.587 * g + 0.114 * b
            histogram[min(255, Int(lum * 255.0))] += 1
        }
        var cumulative = 0
        let medianTarget = pixelCount / 2
        var medianBin = 0
        for bin in 0..<256 {
            cumulative += histogram[bin]
            if cumulative >= medianTarget {
                medianBin = bin
                break
            }
        }
        let medianLuminance = Double(medianBin) / 255.0

        // Threshold measured to match macOS Sequoia menu bar behaviour.
        return medianLuminance > 0.7125 ? .black : .white
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color(nsColor: .windowBackgroundColor)
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
                isSearchFieldVisible = false
                windowSearchText = ""
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
            withAnimation(.easeInOut(duration: 0.15)) {
                isSearchFieldVisible = true
            }
            windowSearchFocusTrigger += 1
        }
        .onChange(of: appState.windowSearchFocusRequestVersion) { _, _ in
            if !appState.isSidebarVisible {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.isSidebarVisible = true
                }
            }
            withAnimation(.easeInOut(duration: 0.15)) {
                isSearchFieldVisible = true
            }
            windowSearchFocusTrigger += 1
        }
        .onChange(of: appState.windowSearchHideRequestVersion) { _, _ in
            windowSearchText = ""
            windowSearchBlurTrigger += 1
            withAnimation(.easeInOut(duration: 0.2)) {
                isSearchFieldVisible = false
                appState.isSidebarVisible = false
            }
        }
        .onChange(of: windowSearchText) { _, newValue in
            // Guard against redundant writes: in multi-display setups each
            // MainWindowView listens to appState.windowSearchQuery and syncs
            // it back to windowSearchText.  Without this check the two onChange
            // handlers can cycle (view A writes → appState → view B writes →
            // appState → view A …), leading to runaway CPU usage.
            guard appState.windowSearchQuery != newValue else { return }
            appState.windowSearchQuery = newValue
            searchDebounceTask?.cancel()
            if newValue.isEmpty {
                debouncedSearchText = newValue
            } else {
                searchDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    debouncedSearchText = newValue
                }
            }
        }
        .onChange(of: appState.windowSearchQuery) { _, newValue in
            if windowSearchText != newValue {
                windowSearchText = newValue
            }
        }
        .onChange(of: appState.windowTargetListVersion) { _, _ in
            appInfoCache.invalidate()
            if appState.hasUsedTabCycling {
                showSidebarIfNeeded()
            }
        }
        .onChange(of: appState.selectedLayoutPresetID) { _, selectedID in
            if let hoveredPresetID, selectedID != hoveredPresetID {
                // Guard: only the view instance that owns the hover should
                // override the selection.  Without this check, multiple
                // MainWindowView instances (one per display) can ping-pong
                // the selectedLayoutPresetID back and forth, causing 100% CPU.
                guard isMouseOnThisScreen else { return }
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

    /// Returns the thumbnail size for the preset grid preview, matching the
    /// visible screen area's aspect ratio (excluding menu bar and Dock).
    private static func presetGridThumbnailSize(for screenContext: ScreenContext?) -> CGSize {
        let maxW = presetGridColumnWidth
        let maxH = presetGridMaxHeight
        guard let ctx = screenContext,
              ctx.visibleFrame.width > 0,
              ctx.visibleFrame.height > 0 else {
            return CGSize(width: maxW, height: maxH)
        }
        let aspect = ctx.visibleFrame.width / ctx.visibleFrame.height
        let fitW = min(maxW, maxH * aspect)
        let fitH = fitW / aspect
        return CGSize(width: fitW, height: fitH)
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
                .padding(.top, 4)

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
            keyboardHintsBar
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
        // Load wallpaper image once for both the background layer and menu bar color.
        let wallpaperImage: NSImage? = {
            guard let info = desktopPictureInfo else { return nil }
            return NSImage(contentsOf: info.url)
        }()
        // Determine menu bar text color: OS detection for the active screen,
        // image luminance fallback for other screens.
        let menuBarTextColor = menuBarForegroundColor(wallpaperImage: wallpaperImage)
        ZStack(alignment: .topLeading) {
            // Layer 1: Wallpaper spanning the full composite area (menu bar + grid + Dock)
            if let info = desktopPictureInfo,
               let nsImage = wallpaperImage {
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
                            HStack(alignment: .center, spacing: fontSize * 0.6) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: fontSize))
                                Text(appState.currentLayoutTargetPrimaryText)
                                    .font(.system(size: fontSize, weight: .bold))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                ForEach(appState.targetMenuBarTitles, id: \.self) { title in
                                    Text(title)
                                        .font(.system(size: fontSize))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                Spacer()
                            }
                            .padding(.leading, menuBarHeight * 0.4 + fontSize * 0.5)
                            .fixedSize(horizontal: true, vertical: false)
                            .minimumScaleFactor(0.5)
                            .frame(width: leftAreaWidth, height: menuBarHeight, alignment: .leading)
                            .clipped()
                            Spacer()
                        }
                        .foregroundColor(menuBarTextColor)
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
                        windowFrameRelative: screenRole.isTarget ? appState.currentLayoutTargetRelativeFrame : nil,
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
                    .overlay {
                        // Show arrow + display arrangement icon when the currently
                        // selected window is on a different display.
                        let thisScreen: NSScreen? = {
                            switch screenRole {
                            case .secondary(let screen): return screen
                            case .target:
                                guard let ctx = screenContext else { return nil }
                                return NSScreen.screen(containing: ctx.screenFrame)
                            }
                        }()
                        if let thisScreen, NSScreen.screens.count > 1 {
                            let thisDisplayID = thisScreen.displayID
                            let targets = appState.windowTargetList
                            let idx = appState.currentWindowTargetIndex
                            let selectedOnOtherDisplay: Bool = {
                                guard idx >= 0, idx < targets.count else { return false }
                                let selectedDisplayID = NSScreen.screen(containing: targets[idx].screenFrame)?.displayID
                                return selectedDisplayID != nil && selectedDisplayID != thisDisplayID
                            }()
                            if selectedOnOtherDisplay {
                                let selectedDisplayID = NSScreen.screen(containing: targets[idx].screenFrame)!.displayID
                                EmptyDisplayOverlay(thisScreen: thisScreen, windowDisplayID: selectedDisplayID)
                            }
                        }
                    }

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
        .clipShape(compositeClipShape)
    }

    /// Returns the clip shape for the screen composite view.
    /// Built-in (laptop) display: rounded top-left and top-right corners only.
    /// External displays: no corner radius.
    private var compositeClipShape: UnevenRoundedRectangle {
        if isBuiltInDisplay {
            return UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 8,
                style: .continuous
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        }
    }

    /// Whether the current screen is the built-in laptop display.
    private var isBuiltInDisplay: Bool {
        let screen: NSScreen?
        if let ctx = screenContext {
            screen = NSScreen.screens.first(where: { $0.frame == ctx.screenFrame })
        } else {
            screen = NSScreen.main
        }
        guard let screen else { return false }
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        return CGDisplayIsBuiltin(screenNumber) != 0
    }

    /// Returns "Close" if the selected window belongs to a multi-window app or Finder, "Quit" if single-window non-Finder app.
    private var slashKeyHintLabel: String {
        let targets = appState.windowTargetList
        let idx = appState.currentWindowTargetIndex
        guard idx >= 0, idx < targets.count else {
            return NSLocalizedString("Close", comment: "Status bar hint for slash key to close window")
        }
        let pid = targets[idx].processIdentifier
        let isFinder = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder"
        if isFinder {
            return NSLocalizedString("Close", comment: "Status bar hint for slash key to close window")
        }
        let count = targets.filter { $0.processIdentifier == pid }.count
        if count > 1 {
            return NSLocalizedString("Close", comment: "Status bar hint for slash key to close window")
        } else {
            return NSLocalizedString("Quit", comment: "Status bar hint for slash key to quit app")
        }
    }

    private var keyboardHintsBar: some View {
        HStack(spacing: 12) {
            if let nextShortcut = appState.displayShortcutSettings.selectNextWindow.local,
               appState.displayShortcutSettings.selectNextWindow.localEnabled {
                hintLabel(nextShortcut.compactDisplayString, NSLocalizedString("Next window", comment: "Status bar hint for next window"))
            }
            if let prevShortcut = appState.displayShortcutSettings.selectPreviousWindow.local,
               appState.displayShortcutSettings.selectPreviousWindow.localEnabled {
                hintLabel(prevShortcut.compactDisplayString, NSLocalizedString("Previous window", comment: "Status bar hint for previous window"))
            }
            if isSearchFieldFocused {
                hintLabel("↩", NSLocalizedString("Confirm search criteria", comment: "Status bar hint for confirming search criteria"))
                hintLabel("Esc", NSLocalizedString("Clear search criteria", comment: "Status bar hint for clearing search criteria"))
            } else {
                if let bringShortcut = appState.displayShortcutSettings.bringToFront.local,
                   appState.displayShortcutSettings.bringToFront.localEnabled {
                    hintLabel(bringShortcut.compactDisplayString, NSLocalizedString("Bring to front", comment: "Status bar hint for Enter key"))
                }
                if let closeShortcut = appState.displayShortcutSettings.closeOrQuit.local,
                   appState.displayShortcutSettings.closeOrQuit.localEnabled {
                    hintLabel(closeShortcut.compactDisplayString, slashKeyHintLabel)
                }
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

            // Trailing: update badge + gear button (shown on all screens)
            if appState.showsUpdateIndicator {
                UpdateAvailableBadge()
                    .fixedSize()
            }
            Button {
                dismissPresetNameEditingIfNeeded()
                draftSettings = appState.settingsSnapshot
                if case .secondary(let screen) = screenRole {
                    appState.beginSettingsEditing(on: screen)
                } else if let frame = screenContext?.screenFrame,
                          let screen = NSScreen.screens.first(where: { $0.frame == frame }) {
                    appState.beginSettingsEditing(on: screen)
                } else {
                    appState.beginSettingsEditing()
                }
            } label: {
                #if DEBUG
                Text("🐛")
                    .font(.system(size: 13))
                #else
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .medium))
                #endif
            }
            .buttonStyle(TahoeToolbarButtonStyle())
            .instantTooltip(NSLocalizedString("Settings (⌘,)", comment: "Settings button tooltip"))
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
        let isFinder: Bool
        /// True when this window is on a non-current Mission Control space.
        let isOnOtherSpace: Bool
        /// True when this item appears under an app header (multi-window app group).
        var isUnderAppHeader: Bool = false
    }

    /// Tracks which sidebar item is selected for action bar operations.
    private enum SidebarSelection: Equatable {
        case window(index: Int)
        case appHeader(pid: pid_t, appName: String)
        case screenHeader(displayID: CGDirectDisplayID, name: String)
    }

    private enum SidebarRow: Identifiable {
        case spaceHeader(spaceID: UInt64, index: Int, isCurrent: Bool)
        case screenHeader(displayID: CGDirectDisplayID, name: String, hasWindowsOnOtherScreens: Bool, hasWindowsOnThisScreen: Bool)
        case emptyScreen(displayID: CGDirectDisplayID, name: String)
        case appHeader(pid: pid_t, appName: String)
        case window(WindowListItem)

        var id: String {
            switch self {
            case .spaceHeader(let spaceID, _, _): return "space-\(spaceID)"
            case .screenHeader(let displayID, _, _, _): return "screen-\(displayID)"
            case .emptyScreen(let displayID, _): return "empty-screen-\(displayID)"
            case .appHeader(let pid, _): return "app-\(pid)"
            case .window(let item): return "window-\(item.id)"
            }
        }
    }

    private var filteredSidebarRows: [SidebarRow] {
        // While the deferred refresh is pending and there is no cached data
        // from a previous cycle, return empty so the sidebar shows a spinner.
        // If previous data exists, keep showing it until the refresh completes.
        let targets = appState.windowTargetList
        let query = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Count windows per PID to determine if a window is the last one for its app.
        var windowCountByPID: [pid_t: Int] = [:]
        for target in targets {
            windowCountByPID[target.processIdentifier, default: 0] += 1
        }

        // Build WindowListItems with search filtering.
        var items: [WindowListItem] = []
        for (index, target) in targets.enumerated() {
            let title = target.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !query.isEmpty {
                let matchesApp = target.appName.lowercased().contains(query)
                let matchesTitle = title.lowercased().contains(query)
                if !matchesApp && !matchesTitle { continue }
            }
            let isFinder = appInfoCache.bundleID(for: target.processIdentifier) == "com.apple.finder"
            items.append(WindowListItem(
                id: index,
                appName: target.appName,
                windowTitle: title,
                pid: target.processIdentifier,
                isLastWindowOfApp: windowCountByPID[target.processIdentifier] == 1,
                sameAppWindowCount: windowCountByPID[target.processIdentifier] ?? 1,
                isHidden: target.isHidden,
                isFinder: isFinder,
                isOnOtherSpace: target.isOnOtherSpace
            ))
        }

        // Helper: group items by app (PID), emitting app headers for multi-window apps.
        func appGroupedRows(from groupItems: [WindowListItem]) -> [SidebarRow] {
            // Preserve original order: group consecutive items with same PID,
            // but also merge non-consecutive items of the same app.
            var appOrder: [pid_t] = []
            var appItems: [pid_t: [WindowListItem]] = [:]
            for item in groupItems {
                if appItems[item.pid] == nil {
                    appOrder.append(item.pid)
                }
                appItems[item.pid, default: []].append(item)
            }

            var rows: [SidebarRow] = []
            for pid in appOrder {
                guard let windows = appItems[pid] else { continue }
                if windows.count == 1 {
                    // Single window: show as a normal row (icon + app name + title).
                    rows.append(.window(windows[0]))
                } else {
                    // Multiple windows: app header + window-only rows.
                    rows.append(.appHeader(pid: pid, appName: windows[0].appName))
                    for var item in windows {
                        item.isUnderAppHeader = true
                        rows.append(.window(item))
                    }
                }
            }
            return rows
        }

        // Helper: group items by screen, emitting screen headers for multi-screen setups.
        func screenGroupedRows(from screenItems: [WindowListItem]) -> [SidebarRow] {
            let screens = NSScreen.screens
            let isMultiScreen = screens.count > 1
            guard isMultiScreen else { return appGroupedRows(from: screenItems) }

            var screenGroups: [(displayID: CGDirectDisplayID, name: String, items: [WindowListItem])] = []
            var groupMap: [CGDirectDisplayID: Int] = [:]

            for screen in screens {
                let displayID = screen.displayID
                if groupMap[displayID] == nil {
                    let idx = screenGroups.count
                    groupMap[displayID] = idx
                    screenGroups.append((displayID: displayID, name: screen.localizedName, items: []))
                }
            }

            for item in screenItems {
                let target = targets[item.id]
                let screen = NSScreen.screen(containing: target.screenFrame)
                let displayID = screen?.displayID ?? 0

                if let groupIdx = groupMap[displayID] {
                    screenGroups[groupIdx].items.append(item)
                } else {
                    let screenName = screen?.localizedName ?? NSLocalizedString("Unknown Display", comment: "Fallback screen name")
                    let idx = screenGroups.count
                    groupMap[displayID] = idx
                    screenGroups.append((displayID: displayID, name: screenName, items: [item]))
                }
            }

            let thisDisplayID: CGDirectDisplayID? = {
                switch screenRole {
                case .secondary(let screen):
                    return screen.displayID
                case .target:
                    guard let screenContext else { return nil }
                    return NSScreen.screen(containing: screenContext.screenFrame)?.displayID
                }
            }()
            screenGroups.sort { a, b in
                let aIsThis = a.displayID == thisDisplayID
                let bIsThis = b.displayID == thisDisplayID
                if aIsThis != bIsThis { return aIsThis }
                return a.displayID < b.displayID
            }

            let screensWithWindows = Set(screenGroups.compactMap { $0.items.isEmpty ? nil : $0.displayID })

            var rows: [SidebarRow] = []
            for group in screenGroups {
                if group.items.isEmpty {
                    rows.append(.emptyScreen(displayID: group.displayID, name: group.name))
                } else {
                    let hasWindowsOnOther = screensWithWindows.contains { $0 != group.displayID }
                    rows.append(.screenHeader(
                        displayID: group.displayID,
                        name: group.name,
                        hasWindowsOnOtherScreens: hasWindowsOnOther,
                        hasWindowsOnThisScreen: true
                    ))
                    rows.append(contentsOf: appGroupedRows(from: group.items))
                }
            }
            return rows
        }

        // Check if we need space-level grouping.
        // Count how many distinct spaces have windows.
        let spaceIDsWithWindows: Set<UInt64> = {
            var ids = Set<UInt64>()
            for item in items {
                if let sid = targets[item.id].spaceID {
                    ids.insert(sid)
                }
            }
            return ids
        }()
        let hasMultipleSpacesWithWindows = spaceIDsWithWindows.count > 1

        // If only one space has windows (or space detection unavailable), use existing screen/app grouping.
        guard hasMultipleSpacesWithWindows else {
            return screenGroupedRows(from: items)
        }

        // Show only windows belonging to any of the current (active) spaces (one per display).
        let filteredItems: [WindowListItem]
        let activeIDs = appState.currentActiveSpaceIDs
        if !activeIDs.isEmpty {
            filteredItems = items.filter { item in
                guard let sid = targets[item.id].spaceID else { return true }
                return activeIDs.contains(sid)
            }
        } else {
            filteredItems = items
        }

        return screenGroupedRows(from: filteredItems)
    }

    /// Extracts window-target indices from sidebar rows and syncs them to AppState
    /// so that Tab cycling follows the same visual order as the sidebar.
    @discardableResult
    private func updateSidebarWindowOrder(_ rows: [SidebarRow]) -> Bool {
        let order = rows.compactMap { row -> Int? in
            if case .window(let item) = row { return item.id }
            return nil
        }
        if order != appState.sidebarWindowOrder {
            appState.sidebarWindowOrder = order
        }
        return true
    }

    private func windowListSidebar(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Action bar (always visible)
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                sidebarActionButtons
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, isSearchFieldVisible ? 0 : 6)

            // Search field (shown on ⌘F, hidden when blurred and empty)
            if isSearchFieldVisible {
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
                        if !focused && windowSearchText.isEmpty {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isSearchFieldVisible = false
                            }
                        }
                    }
                )
                .frame(height: 22)
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if appState.isLoadingWindowList && appState.windowTargetList.isEmpty {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    let rows = filteredSidebarRows
                    let _ = updateSidebarWindowOrder(rows)
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(rows) { row in
                                switch row {
                                case .spaceHeader:
                                    EmptyView()
                                case .screenHeader(let displayID, let name, let hasOther, let hasThis):
                                    screenHeaderRow(displayID: displayID, name: name, hasWindowsOnOtherScreens: hasOther, hasWindowsOnThisScreen: hasThis)
                                case .emptyScreen(let displayID, let name):
                                    emptyScreenRow(displayID: displayID, name: name)
                                case .appHeader(let pid, let appName):
                                    appHeaderRow(pid: pid, appName: appName)
                                case .window(let item):
                                    windowListRow(item: item)
                                }
                            }
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 40)
                        .padding(.horizontal, 6)
                    }
                    .scrollIndicators(.automatic)
                    .onChange(of: appState.currentWindowTargetIndex) { _, newIndex in
                        sidebarSelection = .window(index: newIndex)
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo("window-\(newIndex)", anchor: .center)
                        }
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
            // Sync sidebar selection with the initially active window so
            // action buttons are enabled from the start.
            if sidebarSelection == nil {
                let idx = appState.currentWindowTargetIndex
                if idx >= 0, idx < appState.windowTargetList.count {
                    sidebarSelection = .window(index: idx)
                }
            }
        }
    }


    private func otherScreensForDisplay(_ displayID: CGDirectDisplayID) -> [NSScreen] {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return [] }
        return screens.filter { $0.displayID != displayID }
    }

    private func screenForDisplay(_ displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }

    /// Action buttons shown next to the search field, adapting to the current sidebar selection.
    @ViewBuilder
    private var sidebarActionButtons: some View {
        switch sidebarSelection {
        case .window(let idx):
            windowActionButtons(index: idx)
        case .appHeader(let pid, let appName):
            appHeaderActionButtons(pid: pid, appName: appName)
        case .screenHeader(let displayID, let name):
            screenHeaderActionButtons(displayID: displayID, name: name)
        case nil:
            windowActionButtons(index: -1) // show disabled buttons
        }
    }

    @ViewBuilder
    private func windowActionButtons(index idx: Int) -> some View {
        let targets = appState.windowTargetList
        let hasSelection = idx >= 0 && idx < targets.count
        let selectedTarget = hasSelection ? targets[idx] : nil
        let pid = selectedTarget?.processIdentifier ?? 0
        let isFinder = hasSelection && NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder"
        let sameAppCount = hasSelection ? targets.filter { $0.processIdentifier == pid }.count : 0
        let otherScreens = hasSelection ? otherScreensForWindow(at: idx) : []

        // Move to other display
        let windowScreen: NSScreen? = hasSelection ? NSScreen.screen(containing: targets[idx].screenFrame) : nil
        let thisDisplayID = screenContext.flatMap { ctx in
            NSScreen.screens.first(where: { $0.frame == ctx.screenFrame })?.displayID
        }
        let displayTrigger = (thisDisplayID != nil && thisDisplayID == appState.moveToOtherDisplayTargetID)
            ? appState.moveToOtherDisplayRequestVersion : 0
        moveToDisplayButton(
            otherScreens: otherScreens,
            disabled: !hasSelection || otherScreens.isEmpty,
            currentScreen: windowScreen,
            onSelect: { screen in appState.moveWindowToScreen(at: idx, screen: screen); appState.hideMainWindow() },
            triggerVersion: displayTrigger
        )

        // Close or Quit
        Button {
            if hasSelection {
                if isFinder || sameAppCount > 1 {
                    appState.closeWindowTarget(at: idx)
                } else {
                    appState.quitApp(at: idx)
                }
            }
        } label: {
            Image(systemName: isFinder || sameAppCount > 1 ? "xmark" : "power")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(TahoeActionBarButtonStyle())
        .frame(width: 28, height: 24)
        .disabled(!hasSelection)
        .instantTooltip(
            isFinder || sameAppCount > 1
            ? NSLocalizedString("Close Window", comment: "Action bar tooltip for close window button")
            : NSLocalizedString("Quit App", comment: "Action bar tooltip for quit app button")
        )

        // Hide others
        Button {
            if hasSelection { appState.hideOtherApps(except: idx) }
        } label: {
            Image(systemName: "eye.slash")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(TahoeActionBarButtonStyle())
        .frame(width: 28, height: 24)
        .disabled(!hasSelection)
        .instantTooltip(NSLocalizedString("Hide Other Apps", comment: "Action bar tooltip for hide other apps button"))
    }

    @ViewBuilder
    private func appHeaderActionButtons(pid: pid_t, appName: String) -> some View {
        let otherScreens = otherScreensForApp(pid: pid)
        let isFinder = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder"

        // Move all windows to other display
        let appScreen: NSScreen? = appState.windowTargetList
            .first(where: { $0.processIdentifier == pid })
            .flatMap { NSScreen.screen(containing: $0.screenFrame) }
        moveToDisplayButton(
            otherScreens: otherScreens,
            disabled: otherScreens.isEmpty,
            currentScreen: appScreen,
            onSelect: { screen in appState.moveAllAppWindowsToScreen(pid: pid, screen: screen); appState.hideMainWindow() }
        )

        // Quit or Close all windows (Finder)
        if isFinder {
            Button {
                appState.closeAllWindows(pid: pid)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(TahoeActionBarButtonStyle())
            .frame(width: 28, height: 24)
            .instantTooltip(
                String(format: NSLocalizedString("Close all %@ windows", comment: "Action bar tooltip to close all windows of an app"), appName)
            )
        } else {
            Button {
                appState.quitApp(pid: pid)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(TahoeActionBarButtonStyle())
            .frame(width: 28, height: 24)
            .instantTooltip(
                String(format: NSLocalizedString("Quit %@", comment: "Menu item to quit the application"), appName)
            )
        }

        // Hide others
        Button {
            appState.hideOtherApps(exceptPID: pid)
        } label: {
            Image(systemName: "eye.slash")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(TahoeActionBarButtonStyle())
        .frame(width: 28, height: 24)
        .instantTooltip(
            String(format: NSLocalizedString("Hide windows besides %@", comment: "Menu item to hide all windows except the selected app"), appName)
        )
    }

    @ViewBuilder
    private func screenHeaderActionButtons(displayID: CGDirectDisplayID, name: String) -> some View {
        let otherScreens = otherScreensForDisplay(displayID)
        let hasWindowsOnOtherScreens = appState.windowTargetList.contains {
            guard let screenID = NSScreen.screen(containing: $0.screenFrame)?.displayID else { return false }
            return screenID != displayID
        }
        let hasWindowsOnThisScreen = appState.windowTargetList.contains {
            NSScreen.screen(containing: $0.screenFrame)?.displayID == displayID
        }

        // Gather windows to this screen (hidden on single display)
        if !otherScreens.isEmpty {
            Button {
                if let screen = screenForDisplay(displayID) {
                    appState.gatherWindowsToScreen(screen)
                    appState.hideMainWindow()
                }
            } label: {
                Image(systemName: "rectangle.compress.vertical")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(TahoeActionBarButtonStyle())
            .frame(width: 28, height: 24)
            .disabled(!hasWindowsOnOtherScreens)
            .instantTooltip(
                String(format: NSLocalizedString("Gather windows to %@", comment: "Menu item to gather all windows from other screens to this screen"), name)
            )
        }

        // Move this screen's windows to other display
        moveToDisplayButton(
            otherScreens: otherScreens,
            disabled: !hasWindowsOnThisScreen || otherScreens.isEmpty,
            currentScreen: screenForDisplay(displayID),
            onSelect: { screen in
                appState.moveScreenWindowsToScreen(from: displayID, to: screen)
                appState.hideMainWindow()
            }
        )
    }

    /// Shared move-to-display button: single-click for 2 displays, dropdown for 3+.
    @ViewBuilder
    private func moveToDisplayButton(otherScreens: [NSScreen], disabled: Bool, currentScreen: NSScreen? = nil, onSelect: @escaping (NSScreen) -> Void, triggerVersion: Int = 0) -> some View {
        if otherScreens.count >= 2 {
            TahoeActionBarMenuButton(
                symbolName: "rectangle.portrait.and.arrow.right",
                disabled: disabled,
                colorScheme: colorScheme,
                showChevron: true,
                currentScreen: currentScreen,
                menuItems: otherScreens.map { screen in
                    let title = String(
                        format: NSLocalizedString("Move to %@", comment: "Action bar menu item to move window to another display"),
                        screen.localizedName
                    )
                    return (title: title, screen: screen)
                },
                onSelect: onSelect,
                triggerVersion: triggerVersion
            )
            .frame(width: 38, height: 24)
            .modifier(InteractiveGlassBackground(cornerRadius: 8))
            .instantTooltip(NSLocalizedString("Move to Other Display", comment: "Action bar tooltip for move-to-screen button"))
        } else if let targetScreen = otherScreens.first {
            MoveToDisplayButton(
                targetScreen: targetScreen,
                disabled: disabled,
                onSelect: onSelect,
                triggerVersion: triggerVersion
            )
            .instantTooltipView {
                HStack(spacing: 4) {
                    ScreenArrangementIcon(highlightDisplayID: targetScreen.displayID, size: 14)
                    Text(String(format: NSLocalizedString("Move to %@", comment: "Action bar menu item to move window to another display"), targetScreen.localizedName))
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .fixedSize()
            }
        }
    }


    private func screenHeaderRow(displayID: CGDirectDisplayID, name: String, hasWindowsOnOtherScreens: Bool, hasWindowsOnThisScreen: Bool) -> some View {
        let isHovered = hoveredScreenHeaderID == displayID
        let isSelected = sidebarSelection == .screenHeader(displayID: displayID, name: name)
        let otherScreens = otherScreensForDisplay(displayID)

        return Button {
            sidebarSelection = .screenHeader(displayID: displayID, name: name)
        } label: {
            HStack(spacing: 6) {
                ScreenArrangementIcon(highlightDisplayID: displayID, size: 16)
                Text(name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
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
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in hoveredScreenHeaderID = hovering ? displayID : nil }
        .contextMenu {
            if hasWindowsOnOtherScreens {
                Button {
                    if let screen = screenForDisplay(displayID) {
                        appState.gatherWindowsToScreen(screen)
                        appState.hideMainWindow()
                    }
                } label: {
                    Label(
                        String(format: NSLocalizedString("Gather windows to %@", comment: "Menu item to gather all windows from other screens to this screen"), name),
                        systemImage: "rectangle.compress.vertical"
                    )
                }
            }

            if !otherScreens.isEmpty {
                if hasWindowsOnOtherScreens {
                    Divider()
                }
                ForEach(otherScreens, id: \.displayID) { screen in
                    Button {
                        appState.moveScreenWindowsToScreen(from: displayID, to: screen)
                        appState.hideMainWindow()
                    } label: {
                        Label(
                            String(format: NSLocalizedString("Move %1$@ windows to %2$@", comment: "Menu item to move all windows from one screen to another. First arg is source screen, second is destination screen"), name, screen.localizedName),
                            systemImage: "rectangle.portrait.and.arrow.right"
                        )
                    }
                    .disabled(!hasWindowsOnThisScreen)
                }
            }
        }
    }

    private func emptyScreenRow(displayID: CGDirectDisplayID, name: String) -> some View {
        let isHovered = hoveredEmptyScreenID == displayID
        return Button {
            if let screen = screenForDisplay(displayID) {
                appState.gatherWindowsToScreen(screen)
                appState.hideMainWindow()
            }
        } label: {
            HStack(spacing: 6) {
                ScreenArrangementIcon(highlightDisplayID: displayID, size: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(isHovered
                         ? NSLocalizedString("Gather windows", comment: "Label shown on hover to gather windows to an empty screen")
                         : NSLocalizedString("No windows", comment: "Placeholder shown when a screen has no windows"))
                        .font(.system(size: 10))
                        .foregroundStyle(isHovered ? .secondary : .tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered
                          ? ThemeColors.presetRowBackground(selected: true, for: colorScheme)
                          : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in hoveredEmptyScreenID = hovering ? displayID : nil }
    }

    private func appHeaderRow(pid: pid_t, appName: String) -> some View {
        let isSelected = sidebarSelection == .appHeader(pid: pid, appName: appName)

        return Button {
            sidebarSelection = .appHeader(pid: pid, appName: appName)
        } label: {
            HStack(spacing: 6) {
                if let icon = appInfoCache.icon(for: pid) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                Text(appName)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 1)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ThemeColors.presetRowBackground(selected: isSelected, for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(ThemeColors.presetRowBorder(selected: isSelected, for: colorScheme), lineWidth: isSelected ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .contextMenu {
            let otherScreens = otherScreensForApp(pid: pid)
            if !otherScreens.isEmpty {
                ForEach(otherScreens, id: \.displayID) { screen in
                    Button {
                        appState.moveAllAppWindowsToScreen(pid: pid, screen: screen)
                        appState.hideMainWindow()
                    } label: {
                        Label(
                            String(format: NSLocalizedString("Move %1$@ to %2$@", comment: "Menu item to move a window/app to another screen. First arg is window/app name, second is screen name"), appName, screen.localizedName),
                            systemImage: "rectangle.portrait.and.arrow.right"
                        )
                    }
                }
                Divider()
            }

            Button {
                appState.hideOtherApps(exceptPID: pid)
            } label: {
                Label(
                    String(format: NSLocalizedString("Hide windows besides %@", comment: "Menu item to hide all windows except the selected app"), appName),
                    systemImage: "eye.slash"
                )
            }

            Divider()

            if NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder" {
                Button {
                    appState.closeAllWindows(pid: pid)
                } label: {
                    Label(
                        String(format: NSLocalizedString("Close all %@ windows", comment: "Action bar tooltip to close all windows of an app"), appName),
                        systemImage: "xmark"
                    )
                }
            } else {
                Button {
                    appState.quitApp(pid: pid)
                } label: {
                    Label(
                        String(format: NSLocalizedString("Quit %@", comment: "Menu item to quit the application"), appName),
                        systemImage: "power"
                    )
                }
            }
        }
    }

    /// Returns all other screens (for moving all app windows to a different screen).
    private func otherScreensForApp(pid: pid_t) -> [NSScreen] {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return [] }
        // Use the screen of the first window of this app as "current".
        let targets = appState.windowTargetList
        let firstTarget = targets.first { $0.processIdentifier == pid }
        let currentDisplayID = firstTarget.flatMap { NSScreen.screen(containing: $0.screenFrame)?.displayID }
        return screens.filter { $0.displayID != currentDisplayID }
    }

    /// Returns screens that are different from where a specific window is.
    private func otherScreensForWindow(at index: Int) -> [NSScreen] {
        guard NSScreen.screens.count > 1 else { return [] }
        let targets = appState.windowTargetList
        guard index >= 0, index < targets.count else { return [] }
        let target = targets[index]
        let currentDisplayID = NSScreen.screen(containing: target.screenFrame)?.displayID
        return NSScreen.screens.filter { $0.displayID != currentDisplayID }
    }

    private func windowListRow(item: WindowListItem) -> some View {
        let isSelected = item.id == appState.currentWindowTargetIndex
        let isHovered = hoveredWindowIndex == item.id

        return Button {
            appState.selectWindowTarget(at: item.id)
            sidebarSelection = .window(index: item.id)
        } label: {
            HStack(spacing: 6) {
                if item.isUnderAppHeader {
                    // Under an app header: show only window title, indented.
                    Text(item.windowTitle.isEmpty ? item.appName : item.windowTitle)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .padding(.leading, 20)
                } else {
                    if let icon = appInfoCache.icon(for: item.pid) {
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
        .contextMenu {
            let otherScreens = otherScreensForWindow(at: item.id)
            if !otherScreens.isEmpty {
                let windowName = item.windowTitle.isEmpty ? item.appName : item.windowTitle
                ForEach(otherScreens, id: \.displayID) { screen in
                    Button {
                        appState.moveWindowToScreen(at: item.id, screen: screen)
                        appState.hideMainWindow()
                    } label: {
                        Label(
                            String(format: NSLocalizedString("Move %1$@ to %2$@", comment: "Menu item to move a window/app to another screen. First arg is window/app name, second is screen name"), windowName, screen.localizedName),
                            systemImage: "rectangle.portrait.and.arrow.right"
                        )
                    }
                }
                Divider()
            }

            if item.isUnderAppHeader || item.isFinder {
                Button {
                    appState.closeWindowTarget(at: item.id)
                } label: {
                    Label(
                        String(format: NSLocalizedString("Close %@", comment: "Menu item to close a window"), item.windowTitle.isEmpty ? item.appName : item.windowTitle),
                        systemImage: "xmark"
                    )
                }
            }

            if item.sameAppWindowCount > 1 {
                Button {
                    appState.closeOtherWindowTargets(except: item.id)
                } label: {
                    Label(
                        String(format: NSLocalizedString("Close other windows of %@", comment: "Menu item to close other windows of the same app"), item.appName),
                        systemImage: "xmark.rectangle"
                    )
                }
            }

            Button {
                appState.hideOtherApps(except: item.id)
            } label: {
                Label(
                    String(format: NSLocalizedString("Hide windows besides %@", comment: "Menu item to hide all windows except the selected app"), item.appName),
                    systemImage: "eye.slash"
                )
            }

            Divider()
            if item.isFinder {
                Button {
                    appState.closeAllWindows(pid: item.pid)
                } label: {
                    Label(
                        String(format: NSLocalizedString("Close all %@ windows", comment: "Action bar tooltip to close all windows of an app"), item.appName),
                        systemImage: "xmark"
                    )
                }
            } else {
                Button {
                    appState.quitApp(at: item.id)
                } label: {
                    Label(
                        String(format: NSLocalizedString("Quit %@", comment: "Menu item to quit the application"), item.appName),
                        systemImage: "power"
                    )
                }
            }
        }
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
                            if appState.showsUpdateIndicator {
                                UpdateAvailableBadge()
                            }
                            CheckForUpdatesView(updater: updater)
                        }
                        .padding(.vertical, 4)
                    }
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

            displayShortcutsSection

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

            TahoeSettingsSection(title: NSLocalizedString("Debug", comment: "Settings section")) {
                VStack(spacing: 0) {
                    TahoeSettingsRow(label: NSLocalizedString("Write debug log to ~/tiley.log", comment: "")) {
                        Toggle("", isOn: Binding(
                            get: { draftSettings.enableDebugLog },
                            set: { newValue in
                                draftSettings.enableDebugLog = newValue
                                appState.enableDebugLog = newValue
                            }
                        ))
                        .toggleStyle(.switch)
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
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                    #endif
                }
            }
        }
        .font(.system(size: 13))
    }

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

    private var displayShortcutsSection: some View {
        TahoeSettingsSection(title: NSLocalizedString("Shortcuts", comment: "Settings section for shortcuts")) {
            VStack(spacing: 8) {
                // Window action shortcuts group
                VStack(spacing: 0) {
                    // Show Tiley (global-only shortcut, formerly separate "Shortcut" section)
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
                            dismissPresetNameEditingIfNeeded()
                            draftSettings.hotKeyShortcut = .default
                            draftSettings.displayShortcutSettings.selectNextWindow = DisplayShortcutSettings.defaultSelectNextWindow
                            draftSettings.displayShortcutSettings.selectPreviousWindow = DisplayShortcutSettings.defaultSelectPreviousWindow
                            draftSettings.displayShortcutSettings.bringToFront = DisplayShortcutSettings.defaultBringToFront
                            draftSettings.displayShortcutSettings.closeOrQuit = DisplayShortcutSettings.defaultCloseOrQuit
                        }
                    }
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(SettingsSectionBackground(cornerRadius: 10))

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

                let resolver = DisplayFingerprintResolver()
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
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(SettingsSectionBackground(cornerRadius: 10))
            }
        }
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

    @ViewBuilder
    private func layoutPresetRow(_ preset: LayoutPreset) -> some View {
        let isInEditMode = editingPresetID == preset.id
        let presetGridSize = Self.presetGridThumbnailSize(for: screenContext)
        HStack(spacing: 12) {
            PresetGridPreviewView(
                rows: appState.rows,
                columns: appState.columns,
                selection: preset.scaledSelection(toRows: appState.rows, columns: appState.columns)
            )
            .frame(width: presetGridSize.width, height: presetGridSize.height)
            .frame(width: Self.presetGridColumnWidth, alignment: .center)

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
        let isEditing = editingPresetID != nil || editingPresetNameID != nil || recordingDisplayShortcutKey != nil || recordingPresetShortcutID != nil || draggingPresetID != nil
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

    /// Validates a shortcut candidate against **draft** settings instead of the committed appState,
    /// so that a shortcut deleted in the draft can be immediately re-assigned.
    private func validateDisplayShortcut(_ candidate: HotKeyShortcut, excludeKeyPath: String) -> String? {
        // Reserved keys
        if !candidate.isGlobal {
            // Check against configured window action shortcuts (excluding self).
            if !excludeKeyPath.hasPrefix("selectNextWindow") && !excludeKeyPath.hasPrefix("selectPreviousWindow") && !excludeKeyPath.hasPrefix("bringToFront") && !excludeKeyPath.hasPrefix("closeOrQuit") {
                if draftWindowActionConflicts(with: candidate) {
                    return NSLocalizedString("This shortcut is already used for a window action.", comment: "Shortcut conflict with window action")
                }
            }
            if candidate.keyCode == UInt32(kVK_ANSI_F), candidate.modifiers == UInt32(cmdKey) {
                return NSLocalizedString("⌘F is reserved for searching the window list.", comment: "Cmd+F shortcut reserved for window search")
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
        for (kp, s) in allSlots where kp != excludeKeyPath {
            if s.keyCode == candidate.keyCode && s.modifiers == candidate.modifiers {
                return NSLocalizedString("This shortcut is already used by another display shortcut.", comment: "Display shortcut conflict with another display shortcut")
            }
        }

        return nil
    }

    /// Checks if a shortcut conflicts with the draft window action shortcuts.
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
        return false
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

private struct DisplayShortcutBadgeLabelView: View {
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

// MARK: - Screen Arrangement Icon

/// Action bar button for 2-display setups: arrow + screen arrangement icon.
/// Tracks hover internally so the Canvas-based ScreenArrangementIcon can
/// respond to hover/press state changes.
private struct MoveToDisplayButton: View {
    let targetScreen: NSScreen
    let disabled: Bool
    let onSelect: (NSScreen) -> Void
    var triggerVersion: Int = 0

    var body: some View {
        Button {
            onSelect(targetScreen)
        } label: {
            MoveToDisplayButtonLabel(
                targetScreen: targetScreen
            )
        }
        .buttonStyle(TahoeActionBarButtonStyle())
        .frame(width: 32, height: 24)
        .disabled(disabled)
        .onChange(of: triggerVersion) { _, newValue in
            if newValue > 0 && !disabled {
                onSelect(targetScreen)
            }
        }
    }
}

private struct MoveToDisplayButtonLabel: View {
    let targetScreen: NSScreen
    @Environment(\.tahoeActionBarHovered) private var isHovered
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: {
                // Arrow points from the current display toward the target display.
                guard let currentScreen = NSScreen.screens.first(where: { $0.displayID != targetScreen.displayID }) else {
                    return "arrow.right"
                }
                return directionArrowSymbol(from: currentScreen, to: targetScreen)
            }())
                .font(.system(size: 8, weight: .bold))
                .frame(width: 10, height: 10)
            ZStack {
                ScreenArrangementIcon(highlightDisplayID: targetScreen.displayID, size: 12, color: .secondary)
                    .opacity(isHovered && isEnabled ? 0 : 1)
                ScreenArrangementIcon(highlightDisplayID: targetScreen.displayID, size: 12, color: .primary)
                    .opacity(isHovered && isEnabled ? 1 : 0)
            }
            .frame(width: 12, height: 12)
        }
        .frame(width: 32, height: 24)
    }
}

/// Overlay shown in the centre of the grid on a display that has no windows,
/// indicating which display the windows are on with an arrow + arrangement icon.
/// The arrow is placed on the side of the icon that corresponds to the direction.
private struct EmptyDisplayOverlay: View {
    let thisScreen: NSScreen
    let windowDisplayID: CGDirectDisplayID

    private let iconSize: CGFloat = 96
    private let arrowFontSize: CGFloat = 40
    private let arrowSpacing: CGFloat = 8

    /// Direction components derived from the arrow symbol name.
    private var direction: (horizontal: Int, vertical: Int) {
        // horizontal: -1 = left, 0 = centre, 1 = right
        // vertical:   -1 = up,   0 = centre, 1 = down
        let name = directionArrowSymbol(from: thisScreen)
        var h = 0, v = 0
        if name.contains(".left")  { h = -1 }
        if name.contains(".right") { h =  1 }
        if name.contains(".up")    { v = -1 }
        if name.contains(".down")  { v =  1 }
        // Pure "arrow.left" / "arrow.right" etc.
        if h == 0 && v == 0 {
            if name == "arrow.left"  { h = -1 }
            if name == "arrow.right" { h =  1 }
            if name == "arrow.up"    { v = -1 }
            if name == "arrow.down"  { v =  1 }
        }
        return (h, v)
    }

    var body: some View {
        let arrowName = directionArrowSymbol(from: thisScreen)
        let dir = direction

        let arrowImage = Image(systemName: arrowName)
            .font(.system(size: arrowFontSize, weight: .bold))

        let iconView = ScreenArrangementIcon(highlightDisplayID: windowDisplayID, size: iconSize, color: .primary)
            .frame(width: iconSize, height: iconSize)

        // Place the arrow relative to the icon based on direction.
        // Cardinal directions: HStack/VStack centred on that edge.
        // Diagonal directions: ZStack with offset so the arrow sits at the corner.
        Group {
            switch (dir.horizontal, dir.vertical) {
            case (-1, 0):  // left
                HStack(spacing: arrowSpacing) { arrowImage; iconView }
            case (1, 0):   // right
                HStack(spacing: arrowSpacing) { iconView; arrowImage }
            case (0, -1):  // up
                VStack(spacing: arrowSpacing) { arrowImage; iconView }
            case (0, 1):   // down
                VStack(spacing: arrowSpacing) { iconView; arrowImage }
            default:       // diagonal
                let offsetX = CGFloat(dir.horizontal) * (iconSize / 2 + arrowFontSize / 2 + arrowSpacing)
                let offsetY = CGFloat(dir.vertical)   * (iconSize / 2 + arrowFontSize / 2 + arrowSpacing)
                ZStack {
                    iconView
                    arrowImage
                        .offset(x: offsetX, y: offsetY)
                }
            }
        }
        .foregroundStyle(.primary)
        .allowsHitTesting(false)
    }
}

/// Returns the SF Symbol name for an arrow pointing from `screen` toward the
/// other display in a 2-display setup.  Covers all 8 cardinal/diagonal directions.
private func directionArrowSymbol(from screen: NSScreen) -> String {
    guard let otherScreen = NSScreen.screens.first(where: { $0.displayID != screen.displayID }) else {
        return "arrow.right"
    }
    return directionArrowSymbol(from: screen, to: otherScreen)
}

/// Returns the SF Symbol name for an arrow pointing from `fromScreen` toward `toScreen`.
private func directionArrowSymbol(from fromScreen: NSScreen, to toScreen: NSScreen) -> String {
    let dx = toScreen.frame.midX - fromScreen.frame.midX
    // NSScreen Y increases upward (Cocoa coords), matching the physical "up" direction.
    let dy = toScreen.frame.midY - fromScreen.frame.midY

    let angle = atan2(dy, dx) * 180 / .pi  // degrees: 0 = right, 90 = up

    // 8 sectors of 45° each, centred on the cardinal/diagonal directions.
    switch angle {
    case -22.5 ..< 22.5:    return "arrow.right"
    case 22.5  ..< 67.5:    return "arrow.up.right"
    case 67.5  ..< 112.5:   return "arrow.up"
    case 112.5 ..< 157.5:   return "arrow.up.left"
    case -67.5 ..< -22.5:   return "arrow.down.right"
    case -112.5 ..< -67.5:  return "arrow.down"
    case -157.5 ..< -112.5: return "arrow.down.left"
    default:                 return "arrow.left"
    }
}

/// Draws a miniature representation of the screen arrangement, highlighting the
/// specified display. Each screen is drawn as a rounded rectangle whose position
/// and size reflect the actual display layout, scaled to fit within the given
/// frame.
private struct ScreenArrangementIcon: View {
    let highlightDisplayID: CGDirectDisplayID
    let size: CGFloat
    var color: Color = .secondary

    var body: some View {
        Canvas { context, canvasSize in
            let screens = NSScreen.screens
            guard !screens.isEmpty else { return }

            // Compute the bounding rect of all screens.
            var union = CGRect.null
            for screen in screens {
                union = union.union(screen.frame)
            }
            guard union.width > 0, union.height > 0 else { return }

            // Inset slightly so strokes don't clip.
            let inset: CGFloat = 0.5
            let available = CGSize(width: canvasSize.width - inset * 2,
                                   height: canvasSize.height - inset * 2)
            let scale = min(available.width / union.width,
                            available.height / union.height)

            // Center the arrangement within the canvas.
            let scaledWidth = union.width * scale
            let scaledHeight = union.height * scale
            let offsetX = (canvasSize.width - scaledWidth) / 2
            let offsetY = (canvasSize.height - scaledHeight) / 2

            let gap: CGFloat = 0.5  // visual gap between screens

            for screen in screens {
                let f = screen.frame
                // NSScreen uses bottom-left origin; flip Y for Canvas (top-left).
                let x = (f.minX - union.minX) * scale + offsetX + gap
                let y = (union.maxY - f.maxY) * scale + offsetY + gap
                let w = f.width * scale - gap * 2
                let h = f.height * scale - gap * 2

                let rect = CGRect(x: x, y: y, width: max(w, 1), height: max(h, 1))
                let cornerRadius: CGFloat = 1.5
                let path = Path(roundedRect: rect, cornerRadius: cornerRadius)

                let isHighlight = screen.displayID == highlightDisplayID
                if isHighlight {
                    context.fill(path, with: .color(color))
                } else {
                    context.stroke(path, with: .color(color), lineWidth: 0.75)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

extension View {
    fileprivate func instantTooltip(_ text: String) -> some View {
        modifier(InstantBubbleTooltip(text: text))
    }

    fileprivate func instantTooltipView<V: View>(@ViewBuilder _ content: @escaping () -> V) -> some View {
        modifier(InstantBubbleTooltipView(tooltipContent: AnyView(content())))
    }
}

private struct InstantBubbleTooltipView: ViewModifier {
    let tooltipContent: AnyView

    func body(content: Content) -> some View {
        content
            .background(RichTooltipTriggerView(tooltipContent: tooltipContent))
    }
}

private struct RichTooltipTriggerView: NSViewRepresentable {
    let tooltipContent: AnyView

    func makeNSView(context: Context) -> RichTooltipHoverView {
        let view = RichTooltipHoverView()
        view.tooltipContent = tooltipContent
        return view
    }

    func updateNSView(_ nsView: RichTooltipHoverView, context: Context) {
        nsView.tooltipContent = tooltipContent
    }
}

private final class RichTooltipHoverView: NSView {
    var tooltipContent: AnyView = AnyView(EmptyView())
    private var popover: NSPopover?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { showTooltip() }
    override func mouseExited(with event: NSEvent) { dismissTooltip() }
    override func removeFromSuperview() { dismissTooltip(); super.removeFromSuperview() }

    private func showTooltip() {
        guard popover == nil else { return }
        let p = NSPopover()
        p.behavior = .semitransient
        p.animates = false
        let hostingController = NSHostingController(rootView: tooltipContent)
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

private let shortcutIconColumnWidth: CGFloat = 24

private struct TahoeSettingsRow<Trailing: View>: View {
    let label: String
    var systemImage: String? = nil
    var systemImageWeight: Font.Weight = .regular
    var iconContent: AnyView? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Group {
                if let iconContent {
                    iconContent
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: systemImageWeight))
                        .foregroundStyle(.secondary)
                } else {
                    Color.clear
                }
            }
            .frame(width: shortcutIconColumnWidth, alignment: .trailing)
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

// MARK: - Interactive Glass Background (for NSViewRepresentable buttons)

/// Applies .interactive() glass on macOS 26+; no-op on earlier versions.
private struct InteractiveGlassBackground: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
        }
    }
}

// MARK: - Tahoe-style Toolbar Button

private struct TahoeQuitButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if #available(macOS 26.0, *) {
                configuration.label
                    .foregroundStyle(isHovered || configuration.isPressed ? .primary : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .contentShape(Capsule())
            } else {
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
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Finder-style dropdown menu button: rounded background, hover highlight,
/// stays highlighted while the popup menu is open.
private struct TahoeActionBarMenuButton: NSViewRepresentable {
    let symbolName: String
    let disabled: Bool
    let colorScheme: ColorScheme
    var showChevron: Bool = true
    /// The screen where the window/app currently resides (used for arrow direction in menu items).
    var currentScreen: NSScreen? = nil
    let menuItems: [(title: String, screen: NSScreen)]
    let onSelect: (NSScreen) -> Void
    /// When changed, programmatically opens the popup menu.
    var triggerVersion: Int = 0

    func makeNSView(context: Context) -> TahoeMenuButtonView {
        let view = TahoeMenuButtonView()
        view.coordinator = context.coordinator
        view.showChevron = showChevron
        view.translatesAutoresizingMaskIntoConstraints = false
        let width: CGFloat = showChevron ? 38 : 28
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: width),
            view.heightAnchor.constraint(equalToConstant: 24),
        ])
        return view
    }

    func updateNSView(_ nsView: TahoeMenuButtonView, context: Context) {
        let coord = context.coordinator
        coord.symbolName = symbolName
        coord.disabled = disabled
        coord.colorScheme = colorScheme
        coord.currentScreen = currentScreen
        coord.menuItems = menuItems
        coord.onSelect = onSelect
        nsView.showChevron = showChevron
        nsView.isEnabled = !disabled
        nsView.needsDisplay = true
        if triggerVersion != coord.lastTriggerVersion {
            coord.lastTriggerVersion = triggerVersion
            if triggerVersion > 0 && !disabled {
                DispatchQueue.main.async {
                    nsView.showMenuProgrammatically()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(symbolName: symbolName, disabled: disabled, colorScheme: colorScheme,
                    currentScreen: currentScreen, menuItems: menuItems, onSelect: onSelect)
    }

    final class TahoeMenuButtonView: NSView {
        weak var coordinator: Coordinator?
        private var isHovered = false
        private var isMenuOpen = false
        private var trackingArea: NSTrackingArea?

        override var isFlipped: Bool { true }
        var isEnabled: Bool = true
        var showChevron: Bool = true

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let ta = trackingArea { removeTrackingArea(ta) }
            let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
            addTrackingArea(ta)
            trackingArea = ta
        }

        override func mouseEntered(with event: NSEvent) {
            guard isEnabled else { return }
            isHovered = true
            needsDisplay = true
        }

        override func mouseExited(with event: NSEvent) {
            isHovered = false
            needsDisplay = true
        }

        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            showMenuProgrammatically()
        }

        func showMenuProgrammatically() {
            guard isEnabled, let coord = coordinator else { return }
            isMenuOpen = true
            needsDisplay = true

            let menu = NSMenu()
            for item in coord.menuItems {
                let mi = NSMenuItem(title: item.title, action: #selector(Coordinator.menuAction(_:)), keyEquivalent: "")
                mi.target = coord
                mi.representedObject = item.screen
                if let fromScreen = coord.currentScreen {
                    mi.image = Self.arrowWithScreenArrangementImage(
                        from: fromScreen, to: item.screen, size: 16
                    )
                } else {
                    mi.image = Self.screenArrangementImage(highlightDisplayID: item.screen.displayID, size: 16)
                }
                menu.addItem(mi)
            }

            // Show below the button, aligned to leading edge
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 2), in: self)

            // Menu closed
            isMenuOpen = false
            isHovered = false
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            let isDark = coordinator?.colorScheme == .dark
            let cornerRadius: CGFloat = 8
            let path = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

            if #available(macOS 26.0, *) {
                // Background and border are handled by .glassEffect() applied from SwiftUI.
            } else {
                // Background fill
                let fillAlpha: CGFloat
                if isMenuOpen {
                    fillAlpha = isDark ? 0.18 : 0.12
                } else if isHovered {
                    fillAlpha = isDark ? 0.12 : 0.08
                } else {
                    fillAlpha = isDark ? 0.06 : 0.04
                }
                let fillColor = isDark ? CGColor(gray: 1, alpha: fillAlpha) : CGColor(gray: 0, alpha: fillAlpha)
                ctx.addPath(path)
                ctx.setFillColor(fillColor)
                ctx.fillPath()

                // Border
                let borderAlpha: CGFloat = isDark ? 0.10 : 0.08
                let borderColor = isDark ? CGColor(gray: 1, alpha: borderAlpha) : CGColor(gray: 0, alpha: borderAlpha)
                ctx.addPath(path)
                ctx.setStrokeColor(borderColor)
                ctx.setLineWidth(0.5)
                ctx.strokePath()
            }

            // Tint color
            let tintColor: NSColor
            if !isEnabled {
                tintColor = .tertiaryLabelColor
            } else if isHovered || isMenuOpen {
                tintColor = .labelColor
            } else {
                tintColor = .secondaryLabelColor
            }

            // Main icon
            let symbolName = coordinator?.symbolName ?? "rectangle.portrait.and.arrow.right"
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let tinted = image.tinted(with: tintColor)
                let imageSize = tinted.size
                if showChevron {
                    // Shift icon left to make room for chevron
                    let chevronSpace: CGFloat = 10
                    let x = (bounds.width - chevronSpace - imageSize.width) / 2
                    let y = (bounds.height - imageSize.height) / 2
                    tinted.draw(in: NSRect(x: x, y: y, width: imageSize.width, height: imageSize.height))
                } else {
                    let x = (bounds.width - imageSize.width) / 2
                    let y = (bounds.height - imageSize.height) / 2
                    tinted.draw(in: NSRect(x: x, y: y, width: imageSize.width, height: imageSize.height))
                }
            }

            // Chevron down (right side, only for dropdown mode)
            if showChevron {
                let chevronConfig = NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)
                if let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                    .withSymbolConfiguration(chevronConfig) {
                    let tintedChevron = chevron.tinted(with: tintColor)
                    let chevronSize = tintedChevron.size
                    let cx = bounds.width - chevronSize.width - 5
                    let cy = (bounds.height - chevronSize.height) / 2
                    tintedChevron.draw(in: NSRect(x: cx, y: cy, width: chevronSize.width, height: chevronSize.height))
                }
            }
        }

        /// Renders an arrow + screen arrangement icon as a combined NSImage for NSMenu items.
        static func arrowWithScreenArrangementImage(from fromScreen: NSScreen, to toScreen: NSScreen, size: CGFloat) -> NSImage {
            let arrowName = directionArrowSymbol(from: fromScreen, to: toScreen)
            let arrowConfig = NSImage.SymbolConfiguration(pointSize: size * 0.55, weight: .bold)
            let arrowImage = NSImage(systemSymbolName: arrowName, accessibilityDescription: nil)?
                .withSymbolConfiguration(arrowConfig)
            let displayImage = screenArrangementImage(highlightDisplayID: toScreen.displayID, size: size)

            let arrowSize = arrowImage?.size ?? .zero
            let spacing: CGFloat = 2
            let totalWidth = arrowSize.width + spacing + size
            let totalHeight = max(arrowSize.height, size)

            let combined = NSImage(size: NSSize(width: totalWidth, height: totalHeight), flipped: false) { rect in
                // Draw arrow on the left, vertically centred
                let arrowY = (totalHeight - arrowSize.height) / 2
                arrowImage?.draw(in: NSRect(x: 0, y: arrowY, width: arrowSize.width, height: arrowSize.height))
                // Draw display icon on the right, vertically centred
                let iconY = (totalHeight - size) / 2
                displayImage.draw(in: NSRect(x: arrowSize.width + spacing, y: iconY, width: size, height: size))
                return true
            }
            combined.isTemplate = true
            return combined
        }

        /// Renders a ScreenArrangementIcon-equivalent as an NSImage for use in NSMenu items.
        static func screenArrangementImage(highlightDisplayID: CGDirectDisplayID, size: CGFloat) -> NSImage {
            let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
                let screens = NSScreen.screens
                guard !screens.isEmpty else { return true }

                var union = CGRect.null
                for screen in screens {
                    union = union.union(screen.frame)
                }
                guard union.width > 0, union.height > 0 else { return true }

                let inset: CGFloat = 0.5
                let available = CGSize(width: rect.width - inset * 2, height: rect.height - inset * 2)
                let scale = min(available.width / union.width, available.height / union.height)
                let scaledWidth = union.width * scale
                let scaledHeight = union.height * scale
                let offsetX = (rect.width - scaledWidth) / 2
                let offsetY = (rect.height - scaledHeight) / 2
                let gap: CGFloat = 0.5

                for screen in screens {
                    let f = screen.frame
                    let x = (f.minX - union.minX) * scale + offsetX + gap
                    // Flip Y: NSScreen is bottom-left, drawing context is top-left (flipped)
                    let y = (union.maxY - f.maxY) * scale + offsetY + gap
                    let w = f.width * scale - gap * 2
                    let h = f.height * scale - gap * 2
                    let screenRect = NSRect(x: x, y: y, width: max(w, 1), height: max(h, 1))
                    let cornerRadius: CGFloat = 1.5
                    let path = NSBezierPath(roundedRect: screenRect, xRadius: cornerRadius, yRadius: cornerRadius)

                    let isHighlight = screen.displayID == highlightDisplayID
                    if isHighlight {
                        NSColor.secondaryLabelColor.setFill()
                        path.fill()
                    } else {
                        NSColor.secondaryLabelColor.setStroke()
                        path.lineWidth = 0.75
                        path.stroke()
                    }
                }
                return true
            }
            img.isTemplate = true
            return img
        }
    }

    class Coordinator: NSObject {
        var symbolName: String
        var disabled: Bool
        var colorScheme: ColorScheme
        var currentScreen: NSScreen?
        var menuItems: [(title: String, screen: NSScreen)]
        var onSelect: (NSScreen) -> Void
        var lastTriggerVersion: Int = 0

        init(symbolName: String, disabled: Bool, colorScheme: ColorScheme,
             currentScreen: NSScreen?, menuItems: [(title: String, screen: NSScreen)], onSelect: @escaping (NSScreen) -> Void) {
            self.symbolName = symbolName
            self.disabled = disabled
            self.colorScheme = colorScheme
            self.currentScreen = currentScreen
            self.menuItems = menuItems
            self.onSelect = onSelect
        }

        @objc func menuAction(_ sender: NSMenuItem) {
            guard let screen = sender.representedObject as? NSScreen else { return }
            onSelect(screen)
        }
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let img = self.copy() as! NSImage
        img.lockFocus()
        color.set()
        NSRect(origin: .zero, size: img.size).fill(using: .sourceAtop)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}

private struct TahoeActionBarHoveredKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var tahoeActionBarHovered: Bool {
        get { self[TahoeActionBarHoveredKey.self] }
        set { self[TahoeActionBarHoveredKey.self] = newValue }
    }
}

/// Tahoe-style action bar button: large corner radius, subtle fill, hover highlight.
private struct TahoeActionBarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private func fillColor(isPressed: Bool) -> Color {
        let isDark = colorScheme == .dark
        if isPressed {
            return isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.10)
        } else if isHovered {
            return isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
        } else {
            return isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
        }
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    func makeBody(configuration: Configuration) -> some View {
        let fgStyle: HierarchicalShapeStyle = !isEnabled ? .tertiary : (isHovered || configuration.isPressed ? .primary : .secondary)

        Group {
            if #available(macOS 26.0, *) {
                configuration.label
                    .environment(\.tahoeActionBarHovered, isHovered || configuration.isPressed)
                    .foregroundStyle(fgStyle)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                configuration.label
                    .environment(\.tahoeActionBarHovered, isHovered || configuration.isPressed)
                    .foregroundStyle(fgStyle)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(fillColor(isPressed: configuration.isPressed))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(borderColor, lineWidth: 0.5)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct TahoeToolbarButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if #available(macOS 26.0, *) {
                configuration.label
                    .foregroundStyle(isHovered || configuration.isPressed ? .primary : .secondary)
                    .frame(width: 30, height: 30)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .contentShape(Capsule())
            } else {
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
            }
        }
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

#Preview("NotchShape") {
    NotchMenuBarCanvas(compositeWidth: 300, height: 30, notchWidth: 120)
        .background(Color.blue)
        .frame(width: 300, height: 30)
}
