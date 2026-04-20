import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A rounded rectangle with an optional triangular speech-bubble pointer on one edge.
/// When used as a clip shape the arrow protrudes into the padding area of the window.
private struct BubbleShape: Shape {
    let cornerRadius: CGFloat
    let arrowEdge: BubbleArrowEdge
    /// 0–1 fraction along the arrow edge where the tip is located.
    let arrowFraction: CGFloat
    let arrowWidth: CGFloat
    let arrowHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        // The body rect is inset on the arrow edge so the arrow extends into that margin.
        var body = rect
        switch arrowEdge {
        case .top:    body.origin.y += arrowHeight; body.size.height -= arrowHeight
        case .bottom: body.size.height -= arrowHeight
        case .leading:  body.origin.x += arrowHeight; body.size.width -= arrowHeight
        case .trailing: body.size.width -= arrowHeight
        }

        let cr = min(cornerRadius, min(body.width, body.height) / 2)
        let halfArrow = arrowWidth / 2

        var path = Path()

        // --- Top edge ---
        path.move(to: CGPoint(x: body.minX + cr, y: body.minY))
        if arrowEdge == .top {
            let tipX = body.minX + body.width * arrowFraction
            let leftX = max(tipX - halfArrow, body.minX + cr)
            let rightX = min(tipX + halfArrow, body.maxX - cr)
            path.addLine(to: CGPoint(x: leftX, y: body.minY))
            path.addLine(to: CGPoint(x: tipX, y: rect.minY))
            path.addLine(to: CGPoint(x: rightX, y: body.minY))
        }
        path.addLine(to: CGPoint(x: body.maxX - cr, y: body.minY))
        // Top-right corner
        path.addArc(center: CGPoint(x: body.maxX - cr, y: body.minY + cr),
                     radius: cr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)

        // --- Right (trailing) edge ---
        if arrowEdge == .trailing {
            let tipY = body.minY + body.height * arrowFraction
            let topY = max(tipY - halfArrow, body.minY + cr)
            let bottomY = min(tipY + halfArrow, body.maxY - cr)
            path.addLine(to: CGPoint(x: body.maxX, y: topY))
            path.addLine(to: CGPoint(x: rect.maxX, y: tipY))
            path.addLine(to: CGPoint(x: body.maxX, y: bottomY))
        }
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - cr))
        // Bottom-right corner
        path.addArc(center: CGPoint(x: body.maxX - cr, y: body.maxY - cr),
                     radius: cr, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)

        // --- Bottom edge ---
        if arrowEdge == .bottom {
            let tipX = body.minX + body.width * arrowFraction
            let rightX = min(tipX + halfArrow, body.maxX - cr)
            let leftX = max(tipX - halfArrow, body.minX + cr)
            path.addLine(to: CGPoint(x: rightX, y: body.maxY))
            path.addLine(to: CGPoint(x: tipX, y: rect.maxY))
            path.addLine(to: CGPoint(x: leftX, y: body.maxY))
        }
        path.addLine(to: CGPoint(x: body.minX + cr, y: body.maxY))
        // Bottom-left corner
        path.addArc(center: CGPoint(x: body.minX + cr, y: body.maxY - cr),
                     radius: cr, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)

        // --- Left (leading) edge ---
        if arrowEdge == .leading {
            let tipY = body.minY + body.height * arrowFraction
            let bottomY = min(tipY + halfArrow, body.maxY - cr)
            let topY = max(tipY - halfArrow, body.minY + cr)
            path.addLine(to: CGPoint(x: body.minX, y: bottomY))
            path.addLine(to: CGPoint(x: rect.minX, y: tipY))
            path.addLine(to: CGPoint(x: body.minX, y: topY))
        }
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + cr))
        // Top-left corner
        path.addArc(center: CGPoint(x: body.minX + cr, y: body.minY + cr),
                     radius: cr, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

        path.closeSubpath()
        return path
    }
}

struct MainWindowView: View {
    private static let windowCornerRadius: CGFloat = 20
    private static let bubbleArrowHeight: CGFloat = 12
    private static let bubbleArrowWidth: CGFloat = 24
    private static let layoutPanelHorizontalPadding: CGFloat = 8
    private static let layoutGridAspectHeightRatio: CGFloat = 0.75
    private static let footerBottomPadding: CGFloat = 8
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
    private static let sidebarWidth: CGFloat = MainWindowController.sidebarWidth

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenContext) private var screenContext
    var appState: AppState
    var screenRole: ScreenRole
    @State private var activeLayoutSelection: GridSelection?
    @State private var editingPresetID: UUID?
    @State private var editingPresetNameID: UUID?
    @State private var editingPresetNameDraft = ""
    /// Snapshot of the preset's selections before editing, for rollback when all selections are deleted.
    @State private var editingPresetSelectionSnapshot: (selection: GridSelection, secondarySelections: [GridSelection])?
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
    @State private var windowSearchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var appInfoCache = AppInfoCache()
    @State private var windowSearchFocusTrigger: Int = 0
    @State private var windowSearchBlurTrigger: Int = 0
    @State private var hoveredWindowIndex: Int?
    @State private var hoveredAppHeaderPID: pid_t?
    @State private var hoveredScreenHeaderID: CGDirectDisplayID?
    @State private var hoveredEmptyScreenID: CGDirectDisplayID?
    @State private var isSearchFieldFocused = false
    @State private var isSearchFieldVisible = false
    @State private var sidebarSelection: SidebarSelection?

    init(appState: AppState, screenRole: ScreenRole = .target) {
        self.appState = appState
        self.screenRole = screenRole
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

        // Always read the actual pixel dimensions of the wallpaper image.
        // nsImage.size is DPI-dependent (e.g. a 144 DPI Retina screenshot reports
        // half its pixel dimensions), but tile/center/fit calculations need real pixels.
        // For thumbnails, read from the original wallpaper (rawURL), not the thumbnail.
        var originalImageSize: CGSize? = nil
        let pixelSizeSourceURL = storeInfo?.thumbnailURL != nil ? rawURL : url
        if let src = CGImageSourceCreateWithURL(pixelSizeSourceURL as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let pixelWidth = props[kCGImagePropertyPixelWidth] as? CGFloat,
           let pixelHeight = props[kCGImagePropertyPixelHeight] as? CGFloat {
            originalImageSize = CGSize(width: pixelWidth, height: pixelHeight)
        }

        // Whether rawURL points to a custom user image (not DefaultDesktop.heic system symlink).
        // On macOS 15+, custom images still have their actual path in desktopImageURL.
        let isCustomImage = rawURL.lastPathComponent != "DefaultDesktop.heic"

        // Whether the wallpaper is user-provided content whose display mode (placement)
        // should be respected. This includes custom image files AND user-content providers
        // like Photos. System presets (Tahoe, Sequoia, etc.) always render as Fill
        // regardless of what the Store plist records, so placement is ignored for those.
        let respectsPlacement: Bool
        if isCustomImage {
            respectsPlacement = true
        } else if let provider = storeInfo?.provider,
                  provider != "default",
                  !provider.hasPrefix("com.apple.wallpaper.choice.") {
            // Non-system providers (e.g. com.apple.wallpaper.extension.photos)
            // are user-selected content that respects placement settings.
            respectsPlacement = true
        } else {
            respectsPlacement = false
        }

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
        } else if respectsPlacement, let placement = storeInfo?.placement {
            // User-provided image with Store plist placement (macOS 15+ and some macOS 14 installs).
            // The Store plist is the most reliable source for display mode on modern macOS.
            switch placement {
            case "Tiled", "Tile":
                scalingRaw = nil
                allowClipping = false
                isTiled = true
            case "Stretch", "FillScreen":
                // "Stretch" on older macOS, "FillScreen" on macOS Tahoe
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
        } else if let scalingRawOpt = opts?[.imageScaling] as? Int {
            // Custom image with explicit desktopImageOptions (older macOS without Store plist) —
            // use them directly. imageScaling is absent for tile mode, so this branch
            // only fires for non-tiled modes.
            scalingRaw = scalingRawOpt
            allowClipping = opts?[.allowClipping] as? Bool ?? false
            isTiled = false
        } else if respectsPlacement, opts != nil, opts?[.imageScaling] == nil {
            // Older macOS tile mode: desktopImageOptions exists but does NOT contain
            // imageScaling or allowClipping — this is the classic tile mode indicator.
            scalingRaw = nil
            allowClipping = false
            isTiled = true
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
        // Try the wallpaper agent's rendered BMP cache as a last resort (covers
        // Photos wallpapers and other providers without dedicated thumbnails).
        // If no cache hit either, skip showing the wallpaper entirely.
        if storeInfo?.thumbnailURL == nil && !isCustomImage {
            if let cachedURL = Self.wallpaperCacheBMP(forScreenWidth: Int(screen.frame.width * screen.backingScaleFactor),
                                                      height: Int(screen.frame.height * screen.backingScaleFactor)) {
                // Read pixel dimensions from the BMP (its DPI may differ from 72)
                var bmpPixelSize: CGSize? = nil
                if let src = CGImageSourceCreateWithURL(cachedURL as CFURL, nil),
                   let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                   let pw = props[kCGImagePropertyPixelWidth] as? CGFloat,
                   let ph = props[kCGImagePropertyPixelHeight] as? CGFloat {
                    bmpPixelSize = CGSize(width: pw, height: ph)
                }
                return DesktopPictureInfo(url: cachedURL, scaling: scaling, allowClipping: allowClipping, isTiled: isTiled, screenSize: screen.frame.size, screenScale: screen.backingScaleFactor, fillColor: fillColor, originalImageSize: bmpPixelSize)
            }
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
        /// Provider string from the plist Choices entry (e.g. "com.apple.wallpaper.extension.photos")
        let provider: String?
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
        // Try multiple plist paths to find the active Desktop content.
        // macOS versions vary in where they store the wallpaper info:
        //   - AllSpacesAndDisplays > Desktop > Content  (older macOS)
        //   - AllSpacesAndDisplays > Linked > Content   (macOS Tahoe)
        //   - SystemDefault > Desktop > Content          (macOS 15+)
        //   - SystemDefault > Linked > Content           (macOS Tahoe)
        //   - Displays > {UUID} > Desktop/Linked > Content (per-display override)
        // Helper to extract Content dict from a section that may use "Desktop" or "Linked" key.
        func extractContent(from section: [String: Any]) -> [String: Any]? {
            for key in ["Desktop", "Linked"] {
                if let sub = section[key] as? [String: Any],
                   let c = sub["Content"] as? [String: Any] {
                    return c
                }
            }
            return nil
        }
        let content: [String: Any]
        let first: [String: Any]
        if let allSpaces = root["AllSpacesAndDisplays"] as? [String: Any],
           let c = extractContent(from: allSpaces),
           let choices = c["Choices"] as? [[String: Any]],
           let f = choices.first {
            content = c
            first = f
        } else if let sysDefault = root["SystemDefault"] as? [String: Any],
                  let c = extractContent(from: sysDefault),
                  let choices = c["Choices"] as? [[String: Any]],
                  let f = choices.first {
            content = c
            first = f
        } else if let displays = root["Displays"] as? [String: Any],
                  let firstDisplay = displays.values.first(where: {
                      guard let d = $0 as? [String: Any] else { return false }
                      return d["Desktop"] != nil || d["Linked"] != nil
                  }) as? [String: Any],
                  let c = extractContent(from: firstDisplay),
                  let choices = c["Choices"] as? [[String: Any]],
                  let f = choices.first {
            content = c
            first = f
        } else {
            return nil
        }

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

        let provider = first["Provider"] as? String
        return WallpaperStoreInfo(thumbnailURL: thumbnailURL, placement: placement, fillColor: fillColor, provider: provider)
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

        case "default":
            // macOS Tahoe default wallpaper (Lake Tahoe). The extension bundle is
            // NeptuneOneWallpaper.appex and contains TahoeLight/TahoeDark thumbnails.
            let suffix = isDark ? "TahoeDark" : "TahoeLight"
            let base = "/System/Library/ExtensionKit/Extensions/NeptuneOneWallpaper.appex/Contents/Resources"
            return firstExisting([
                "\(base)/\(suffix).heic",
            ])

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

    /// Searches the wallpaper agent's rendered BMP cache for an image matching
    /// the given physical screen dimensions. This covers wallpaper types that
    /// have no dedicated thumbnail (e.g. Photos wallpapers).
    /// The cache lives in the wallpaper agent's container and stores rendered
    /// BMP files with filenames like `{hash}-{width}-{height}-{flags}.bmp`.
    /// Providers whose caches should be skipped during BMP fallback lookup,
    /// because they already have dedicated thumbnail resolution in `thumbnailForProvider`.
    private static let handledCacheProviders: Set<String> = [
        "aerials", "sequoia", "sonoma", "ventura", "monterey", "macintosh",
    ]

    private static func wallpaperCacheBMP(forScreenWidth width: Int, height: Int) -> URL? {
        let cacheBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches")
        guard let extensionDirs = try? FileManager.default.contentsOfDirectory(atPath: cacheBase.path) else { return nil }
        let suffix = "-\(width)-\(height)-"
        var bestURL: URL? = nil
        var bestDate: Date = .distantPast
        for dir in extensionDirs {
            // Skip cache directories for providers that have dedicated thumbnail handlers.
            // Their BMPs may be stale leftovers that would incorrectly win the recency check.
            if handledCacheProviders.contains(where: { dir.contains($0) }) { continue }
            let dirURL = cacheBase.appendingPathComponent(dir)
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dirURL.path) else { continue }
            for file in files where file.hasSuffix(".bmp") && file.contains(suffix) {
                let fileURL = dirURL.appendingPathComponent(file)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let modified = attrs[.modificationDate] as? Date,
                   modified > bestDate {
                    bestDate = modified
                    bestURL = fileURL
                }
            }
        }
        return bestURL
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

    /// Edge insets for the bubble arrow, applied as content padding so the arrow
    /// area doesn't overlap interactive content.
    private var bubbleArrowInsets: EdgeInsets {
        guard let edge = appState.bubbleArrowEdge, isBubbleArrowScreen else { return EdgeInsets() }
        let h = Self.bubbleArrowHeight
        switch edge {
        case .top:      return EdgeInsets(top: h, leading: 0, bottom: 0, trailing: 0)
        case .bottom:   return EdgeInsets(top: 0, leading: 0, bottom: h, trailing: 0)
        case .leading:  return EdgeInsets(top: 0, leading: h, bottom: 0, trailing: 0)
        case .trailing: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: h)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let insets = bubbleArrowInsets
            let contentSize = CGSize(
                width: geometry.size.width - insets.leading - insets.trailing,
                height: geometry.size.height - insets.top - insets.bottom
            )
            ZStack(alignment: .topLeading) {
                // Window background — also acts as a drag handle for any area
                // not covered by interactive controls (buttons, grid, list rows).
                WindowDragArea()
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.86))

                layoutGridPanel(size: contentSize)
                    .padding(insets)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipShape(windowClipShape(size: geometry.size))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
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
        .onChange(of: appState.windowTargetMenuRequestVersion) { _, _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                isSearchFieldVisible = true
            }
            windowSearchFocusTrigger += 1
        }
        .onChange(of: appState.windowSearchFocusRequestVersion) { _, _ in
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

    private func layoutGridPanel(size: CGSize) -> some View {
        let mainContentWidth = size.width - Self.sidebarWidth - 1
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
        let nonCompositeHeight = Self.layoutGridTopPadding
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
                - Self.layoutGridTopPadding
                - compositeHeight
                - Self.layoutPresetsTopPadding
                - Self.footerBottomPadding
        )

        return HStack(spacing: 0) {
            windowListSidebar(height: size.height)

            VStack(spacing: 0) {
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
                .padding(.top, Self.layoutGridTopPadding)

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
                            .padding(.leading, menuBarHeight * 0.4 + fontSize * 0.5 + 2)
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
                    .allowsHitTesting(false)
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
                        highlightSelections: editingPresetHighlightSelections,
                        highlightWindowInfo: appState.presetHoverWindowInfo,
                        desktopPictureInfo: desktopPictureInfo,
                        showDesktopPicture: false,
                        windowFrameRelative: appState.currentLayoutTargetRelativeFrame,
                        showStaticWindowPreview: screenRole.isTarget,
                        resizePreviewRelativeFrame: appState.resizePreviewRelativeFrame,
                        screenEdgeInsets: gridScreenEdgeInsets,
                        committedSelections: editingPresetCommittedSelections,
                        // Only provide the delete callback while actively editing a preset —
                        // the view uses this closure's presence as the edit-mode signal that
                        // switches rendering between preset-editing (committed-style
                        // rectangles, index numbers) and layout-application
                        // (miniature windows with app icon/name/title).
                        onDeleteSelection: editingPresetID == nil ? nil : { index in
                            guard let editingID = editingPresetID else { return }
                            appState.updateLayoutPreset(editingID) { preset in
                                if index == 0 {
                                    if !preset.secondarySelections.isEmpty {
                                        preset.selection = preset.secondarySelections.removeFirst()
                                    } else {
                                        // Last selection removed — mark as empty.
                                        // Will be rolled back on finishEditingPreset.
                                        preset.selection = LayoutPreset.emptySelection
                                    }
                                } else {
                                    let secondaryIndex = index - 1
                                    if secondaryIndex < preset.secondarySelections.count {
                                        preset.secondarySelections.remove(at: secondaryIndex)
                                    }
                                }
                            }
                            appState.updateLayoutPreview(nil)
                        },
                        isDragDisabled: appState.activeLayoutTarget == nil,
                        onSelectionChange: { selection in
                            if editingPresetID == nil {
                                dismissPresetNameEditingIfNeeded()
                                dismissShortcutEditingIfNeeded()
                                hoveredPresetID = nil
                                appState.selectedLayoutPresetID = nil
                            }
                            activeLayoutSelection = selection
                            let nextColorIndex = editingPresetID != nil ? editingPresetCommittedSelections.count : 0
                            if let ctx = screenContext {
                                appState.updateLayoutPreview(selection, screenContext: ctx, colorIndex: nextColorIndex)
                            } else {
                                appState.updateLayoutPreview(selection, colorIndex: nextColorIndex)
                            }
                        },
                        onHoverChange: { selection in
                            guard activeLayoutSelection == nil else { return }
                            let nextColorIndex = editingPresetID != nil ? editingPresetCommittedSelections.count : 0
                            if let ctx = screenContext {
                                appState.updateLayoutPreview(selection, screenContext: ctx, colorIndex: nextColorIndex)
                            } else {
                                appState.updateLayoutPreview(selection, colorIndex: nextColorIndex)
                            }
                        },
                        onSelectionCommit: { selection in
                            activeLayoutSelection = nil
                            if let editingID = editingPresetID {
                                appState.updateLayoutPreset(editingID) { preset in
                                    if preset.selection == LayoutPreset.emptySelection {
                                        // Refill primary when all selections were deleted.
                                        preset.selection = selection
                                    } else {
                                        preset.secondarySelections.append(selection)
                                    }
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

    /// Whether this view's screen is the one that should display the bubble arrow.
    private var isBubbleArrowScreen: Bool {
        guard let arrowDisplayID = appState.bubbleArrowDisplayID else { return false }
        switch screenRole {
        case .secondary(let screen):
            return screen.displayID == arrowDisplayID
        case .target:
            guard let screenContext else { return false }
            return NSScreen.screen(containing: screenContext.screenFrame)?.displayID == arrowDisplayID
        }
    }

    /// Returns the clip shape for the main window, optionally with a speech-bubble arrow.
    private func windowClipShape(size: CGSize) -> AnyShape {
        if let edge = appState.bubbleArrowEdge, isBubbleArrowScreen {
            return AnyShape(BubbleShape(
                cornerRadius: Self.windowCornerRadius,
                arrowEdge: edge,
                arrowFraction: appState.bubbleArrowFraction,
                arrowWidth: Self.bubbleArrowWidth,
                arrowHeight: Self.bubbleArrowHeight
            ))
        } else {
            return AnyShape(RoundedRectangle(cornerRadius: Self.windowCornerRadius, style: .continuous))
        }
    }

    /// Returns the clip shape for the screen composite view.
    private var compositeClipShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
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
        WindowDragArea()
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(.ultraThinMaterial)
            .overlay {
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
                .allowsHitTesting(false)
            }
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
                var appPart = target.appName
                if let orig = appInfoCache.originalAppName(for: target.processIdentifier) {
                    appPart += " " + orig
                }
                let combined = (appPart + " " + title).lowercased()
                if !combined.isSubsequence(of: query) { continue }
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
                // Settings button at the leading edge
                Button {
                    dismissPresetNameEditingIfNeeded()
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
                        .font(.system(size: 11))
                        .frame(width: 28, height: 24)
                    #else
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 24)
                    #endif
                }
                .buttonStyle(TahoeActionBarButtonStyle())
                .frame(width: 28, height: 24)
                .overlay(alignment: .topTrailing) {
                    if appState.showsUpdateIndicator {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .offset(x: -2, y: 3)
                    }
                }
                .instantTooltip(appState.showsUpdateIndicator
                    ? NSLocalizedString("Update available", comment: "Badge shown when an update is available")
                    : NSLocalizedString("Settings (⌘,)", comment: "Settings button tooltip"))

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
                    .onChange(of: appState.windowTargetListVersion, initial: true) { _, _ in
                        // When the window list is populated (e.g. after Phase 2
                        // of toggleOverlay), sync sidebarSelection if it hasn't
                        // been set yet so toolbar buttons are enabled.
                        if sidebarSelection == nil {
                            let idx = appState.currentWindowTargetIndex
                            if idx >= 0, idx < appState.windowTargetList.count {
                                sidebarSelection = .window(index: idx)
                            }
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
            // Note: we intentionally do NOT call `appState.refreshAvailableWindows()`
            // here.  `toggleOverlay` / `reopenMainWindowFromDock` already kicks
            // off the post-open refresh with `snapToFreshTop: true`; a second
            // refresh from this view would race with that one, and its result
            // (without snapToFreshTop) can land last and reshuffle the list a
            // few hundred ms after the correct order is already on screen.

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
        if appState.isMultiSelection {
            multiWindowActionButtons
        } else {
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

        // Resize to predefined size
        resizeButton(index: idx, disabled: !hasSelection)

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
        .instantTooltip({
            if isFinder || sameAppCount > 1 {
                let title = selectedTarget?.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let name = title.isEmpty ? (selectedTarget?.appName ?? "") : title
                return String(format: NSLocalizedString("Close \"%@\"", comment: "Action bar tooltip for close window button with window name"), name)
            } else {
                return NSLocalizedString("Quit App", comment: "Action bar tooltip for quit app button")
            }
        }())

        // Quit App (shown alongside Close Window for non-Finder apps with multiple windows)
        if !isFinder && sameAppCount > 1 {
            Button {
                if hasSelection { appState.quitApp(at: idx) }
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 24)
            }
            .buttonStyle(TahoeActionBarButtonStyle())
            .frame(width: 28, height: 24)
            .disabled(!hasSelection)
            .instantTooltip(NSLocalizedString("Quit App", comment: "Action bar tooltip for quit app button"))
        }

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

    /// Action buttons for multi-window selection.
    @ViewBuilder
    private var multiWindowActionButtons: some View {
        let selectedIndices = appState.currentSelectedWindowIndices
        let targets = appState.windowTargetList
        let count = selectedIndices.count

        // Move to other display: use the primary target's screen as reference.
        let primaryIdx = appState.currentWindowTargetIndex
        let otherScreens = otherScreensForWindow(at: primaryIdx)
        let primaryScreen: NSScreen? = (primaryIdx >= 0 && primaryIdx < targets.count)
            ? NSScreen.screen(containing: targets[primaryIdx].screenFrame) : nil
        moveToDisplayButton(
            otherScreens: otherScreens,
            disabled: otherScreens.isEmpty,
            currentScreen: primaryScreen,
            onSelect: { screen in appState.moveSelectedWindowsToScreen(screen); appState.hideMainWindow() }
        )

        // Close / Quit
        Button {
            appState.closeSelectedWindows()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(TahoeActionBarButtonStyle())
        .frame(width: 28, height: 24)
        .instantTooltip(
            String(format: NSLocalizedString("Close %d windows", comment: "Action bar tooltip for closing multiple windows"), count)
        )

        // Selection count badge
        Text("\(count)")
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
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

    /// Resize button: dropdown menu with predefined sizes filtered by current screen.
    @ViewBuilder
    private func resizeButton(index idx: Int, disabled: Bool) -> some View {
        let targets = appState.windowTargetList
        let screen: NSScreen? = (!disabled && idx < targets.count)
            ? NSScreen.screen(containing: targets[idx].screenFrame) ?? NSScreen.screens.first
            : NSScreen.screens.first
        let groupedPresets = screen.map { WindowResizePreset.presetsAvailable(on: $0) } ?? []
        let noPresets = groupedPresets.isEmpty

        // Read current window AX position and info for hover preview
        let selectedTarget = (!disabled && idx < targets.count) ? targets[idx] : nil
        let windowAXPos: CGPoint = {
            guard let window = selectedTarget?.windowElement else { return .zero }
            let (pos, _) = appState.accessibilityService.readPositionAndSize(of: window)
            return pos
        }()
        let targetAppIcon: NSImage? = selectedTarget.flatMap {
            NSRunningApplication(processIdentifier: $0.processIdentifier)?.icon
        }
        let targetWindowTitle = selectedTarget?.windowTitle
        let targetAppName = selectedTarget?.appName

        TahoeResizeMenuButton(
            symbolName: "arrow.up.left.and.arrow.down.right",
            disabled: disabled || noPresets,
            colorScheme: colorScheme,
            groupedPresets: groupedPresets,
            onSelect: { size in
                appState.resizeWindow(at: idx, to: size)
            },
            windowAXPosition: windowAXPos,
            windowScreen: screen,
            onPreview: { frame, screen in
                appState.showResizePreview(frame: frame, on: screen, windowTitle: targetWindowTitle, appName: targetAppName, appIcon: targetAppIcon)
            },
            onPreviewHide: {
                appState.hideResizePreview()
            }
        )
        .frame(width: 38, height: 24)
        .instantTooltip(NSLocalizedString("Resize", comment: "Action bar tooltip for resize button"))
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
            appState.selectAllWindowsOnScreen(displayID: displayID)
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
        let isExplicitlySelected = sidebarSelection == .appHeader(pid: pid, appName: appName)
        // Only highlight when ALL child windows of this app are selected.
        let allChildrenSelected: Bool = {
            let targets = appState.windowTargetList
            let selectedIndices = appState.currentSelectedWindowIndices
            let appIndices = targets.indices.filter { targets[$0].processIdentifier == pid }
            return !appIndices.isEmpty && appIndices.allSatisfy { selectedIndices.contains($0) }
        }()
        let isSelected = isExplicitlySelected || allChildrenSelected
        let isHovered = hoveredAppHeaderPID == pid

        return Button {
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            let shift = flags.contains(.shift)
            let cmd = flags.contains(.command)
            sidebarSelection = .appHeader(pid: pid, appName: appName)
            appState.selectAllWindowsOfApp(pid: pid, shift: shift, cmd: cmd)
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
                    .fill(ThemeColors.presetRowBackground(selected: isSelected || isHovered, for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(ThemeColors.presetRowBorder(selected: isExplicitlySelected, for: colorScheme), lineWidth: isExplicitlySelected ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in hoveredAppHeaderPID = hovering ? pid : nil }
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
        let isPrimary = item.id == appState.currentWindowTargetIndex
        let isInSelection = appState.currentSelectedWindowIndices.contains(item.id)
        let isSelected = isPrimary || isInSelection
        let isHovered = hoveredWindowIndex == item.id || (item.isUnderAppHeader && hoveredAppHeaderPID == item.pid)
        let showBorderOnHeader = item.isUnderAppHeader && sidebarSelection == .appHeader(pid: item.pid, appName: item.appName)
        let presetColorIndex = appState.presetHoverHighlights[item.id]

        return Button {
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            let shift = flags.contains(.shift)
            let cmd = flags.contains(.command)
            appState.selectWindowTarget(at: item.id, shift: shift, cmd: cmd)
            if item.isUnderAppHeader {
                sidebarSelection = .appHeader(pid: item.pid, appName: item.appName)
            } else {
                sidebarSelection = .window(index: item.id)
            }
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
                    .fill(
                        presetColorIndex != nil
                            ? ThemeColors.indexedSidebarHighlight(index: presetColorIndex!, for: colorScheme)
                            : ThemeColors.presetRowBackground(selected: isSelected || isHovered, for: colorScheme)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        presetColorIndex != nil
                            ? ThemeColors.indexedSidebarHighlightBorder(index: presetColorIndex!, for: colorScheme)
                            : ThemeColors.presetRowBorder(selected: isPrimary && !showBorderOnHeader, for: colorScheme),
                        lineWidth: presetColorIndex != nil ? 1 : ((isSelected && !showBorderOnHeader) ? 1 : 0)
                    )
            )
            .overlay(alignment: .trailing) {
                if let ci = presetColorIndex {
                    Text("\(ci + 1)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(
                            Circle()
                                .fill(ThemeColors.indexedSelectionFill(index: ci, for: colorScheme))
                        )
                        .padding(.trailing, 4)
                } else if appState.isMultiSelection,
                          let selIdx = appState.currentSelectionOrder.firstIndex(of: item.id) {
                    Text("\(selIdx + 1)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(
                            Circle()
                                .fill(ThemeColors.indexedSelectionFill(index: 0, for: colorScheme))
                        )
                        .padding(.trailing, 4)
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

            // Resize submenu
            let resizeScreen: NSScreen? = {
                let targets = appState.windowTargetList
                guard item.id >= 0, item.id < targets.count else { return NSScreen.screens.first }
                return NSScreen.screen(containing: targets[item.id].screenFrame) ?? NSScreen.screens.first
            }()
            let resizeGroups = resizeScreen.map { WindowResizePreset.presetsAvailable(on: $0) } ?? []
            if !resizeGroups.isEmpty {
                Menu {
                    ForEach(Array(resizeGroups.enumerated()), id: \.offset) { _, group in
                        Section(group.ratio) {
                            ForEach(Array(group.presets.enumerated()), id: \.offset) { _, preset in
                                Button(preset.label) {
                                    appState.resizeWindow(at: item.id, to: preset.size)
                                }
                            }
                        }
                    }
                } label: {
                    Label(
                        NSLocalizedString("Resize", comment: "Context menu item for resize submenu"),
                        systemImage: "arrow.up.left.and.arrow.down.right"
                    )
                }
                Divider()
            }

            if appState.isMultiSelection, appState.currentSelectedWindowIndices.contains(item.id) {
                let count = appState.currentSelectedWindowIndices.count
                Button {
                    appState.closeSelectedWindows()
                } label: {
                    Label(
                        String(format: NSLocalizedString("Close %d windows", comment: "Action bar tooltip for closing multiple windows"), count),
                        systemImage: "xmark.rectangle.portrait"
                    )
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

    @ViewBuilder
    private func layoutPresetRow(_ preset: LayoutPreset) -> some View {
        let isInEditMode = editingPresetID == preset.id
        let presetGridSize = Self.presetGridThumbnailSize(for: screenContext)
        HStack(spacing: 12) {
            PresetGridPreviewView(
                rows: appState.rows,
                columns: appState.columns,
                selection: preset.scaledSelection(toRows: appState.rows, columns: appState.columns),
                secondarySelections: preset.scaledSecondarySelections(toRows: appState.rows, columns: appState.columns)
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
        // Rollback to snapshot if all selections were deleted.
        if let snapshot = editingPresetSelectionSnapshot,
           let preset = appState.displayedLayoutPresets.first(where: { $0.id == id }),
           preset.allSelections.isEmpty {
            appState.updateLayoutPreset(id) { preset in
                preset.selection = snapshot.selection
                preset.secondarySelections = snapshot.secondarySelections
            }
        }
        editingPresetSelectionSnapshot = nil

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
        editingPresetSelectionSnapshot = (selection: preset.selection, secondarySelections: preset.secondarySelections)
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

    /// 1pt inset on grid edges that correspond to physical screen edges (not menu bar / Dock).
    private var gridScreenEdgeInsets: EdgeInsets {
        guard let ctx = screenContext else {
            return EdgeInsets(top: 0, leading: 1, bottom: 1, trailing: 1)
        }
        let vf = ctx.visibleFrame
        let sf = ctx.screenFrame
        let tolerance: CGFloat = 1
        return EdgeInsets(
            top: abs(vf.maxY - sf.maxY) < tolerance ? 1 : 0,
            leading: abs(vf.minX - sf.minX) < tolerance ? 1 : 0,
            bottom: abs(vf.minY - sf.minY) < tolerance ? 1 : 0,
            trailing: abs(vf.maxX - sf.maxX) < tolerance ? 1 : 0
        )
    }

    /// Committed selections for the grid workspace when editing a preset.
    private var editingPresetCommittedSelections: [GridSelection] {
        guard let editingID = editingPresetID,
              let preset = appState.displayedLayoutPresets.first(where: { $0.id == editingID }) else {
            return []
        }
        return preset.allScaledSelections(toRows: appState.rows, columns: appState.columns)
    }

    /// Returns the preset to highlight (hovered or keyboard-selected), if any.
    private var highlightPreset: LayoutPreset? {
        // When editing a preset, committed selections handle the display.
        if let editingID = editingPresetID,
           appState.displayedLayoutPresets.contains(where: { $0.id == editingID }) {
            return nil
        }
        if let hoveredID = hoveredPresetID,
           let preset = appState.displayedLayoutPresets.first(where: { $0.id == hoveredID }) {
            return preset
        }
        if let selectedID = appState.selectedLayoutPresetID, isMouseOnThisScreen,
           let preset = appState.displayedLayoutPresets.first(where: { $0.id == selectedID }) {
            return preset
        }
        return nil
    }

    private var editingPresetHighlightSelection: GridSelection? {
        guard let preset = highlightPreset else { return nil }
        // Use single highlight only for presets without secondary selections.
        guard preset.secondarySelections.isEmpty else { return nil }
        return preset.scaledSelection(toRows: appState.rows, columns: appState.columns)
    }

    /// All scaled selections for a hovered/selected multi-selection preset.
    private var editingPresetHighlightSelections: [GridSelection] {
        guard let preset = highlightPreset else { return [] }
        guard !preset.secondarySelections.isEmpty else { return [] }
        return preset.allScaledSelections(toRows: appState.rows, columns: appState.columns)
    }

    private func updatePresetSelectionPreview(for id: UUID?) {
        guard !appState.isEditingSettings else { return }
        guard editingPresetID == nil else { return }
        guard draggingPresetID == nil else { return }
        guard activeLayoutSelection == nil else { return }
        guard let id,
              let preset = appState.displayedLayoutPresets.first(where: { $0.id == id }) else {
            appState.updateLayoutPreview(nil)
            appState.presetHoverHighlights = [:]
            appState.presetHoverWindowInfo = []
            return
        }

        // Update sidebar highlights and window info for affected windows.
        let hoverInfo = appState.computePresetHoverInfo(for: preset)
        appState.presetHoverHighlights = hoverInfo.highlights
        appState.presetHoverWindowInfo = hoverInfo.windowInfo

        // Use multi-selection preview when the preset has secondary selections
        // and multiple windows are selected.
        if !preset.secondarySelections.isEmpty, appState.isMultiSelection {
            appState.updateLayoutPreviewForPreset(preset, screenContext: screenContext, showIndexLabels: true)
        } else if !preset.secondarySelections.isEmpty {
            // Single selection but preset has multiple layouts → show multi-preview with z-order windows
            appState.updateLayoutPreviewForPreset(preset, screenContext: screenContext, showIndexLabels: true)
        } else {
            let selection = preset.scaledSelection(toRows: appState.rows, columns: appState.columns)
            if let ctx = screenContext {
                appState.updateLayoutPreview(selection, screenContext: ctx)
            } else {
                appState.updateLayoutPreview(selection)
            }
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

// InlinePresetNameField, InlinePresetNameTextField moved to PresetEditingViews.swift

// ShortcutBadgeLabelView, DisplayShortcutBadgeLabelView, AddShortcutButton moved to PresetEditingViews.swift

// EditingTooltipModifier moved to TooltipViews.swift

// DeleteLayoutButton, FlowLayout, PresetGridPreviewView moved to PresetEditingViews.swift

// InstantBubbleTooltip, TooltipTriggerView, TooltipHoverView moved to TooltipViews.swift

// MoveToDisplayButton, MoveToDisplayButtonLabel, EmptyDisplayOverlay,
// directionArrowSymbol, ScreenArrangementIcon moved to ScreenArrangementViews.swift

// View extension (instantTooltip, instantTooltipView), InstantBubbleTooltipView,
// RichTooltipTriggerView, RichTooltipHoverView moved to TooltipViews.swift

// WindowSearchField moved to WindowSearchField.swift

// Tahoe UI styles moved to TahoeStyles.swift

