import AppKit

/// Looks up app icons / localized names by bundle identifier, with a small
/// in-memory cache. Intended for UI code that renders preset rectangle
/// assignments and preview miniatures.
@MainActor
enum AppIconLookup {
    private static var iconCache: [String: NSImage] = [:]
    private static var nameCache: [String: String] = [:]
    private static var averageColorCache: [String: NSColor] = [:]

    static func icon(forBundleID bid: String) -> NSImage? {
        if let cached = iconCache[bid] { return cached }

        if let runningIcon = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            .first(where: { $0.activationPolicy == .regular })?.icon {
            iconCache[bid] = runningIcon
            return runningIcon
        }

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            iconCache[bid] = icon
            return icon
        }

        return nil
    }

    static func localizedName(forBundleID bid: String) -> String? {
        if let cached = nameCache[bid] { return cached }

        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            .first(where: { $0.activationPolicy == .regular })?.localizedName {
            nameCache[bid] = running
            return running
        }

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid),
           let bundle = Bundle(url: url) {
            if let name = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String {
                nameCache[bid] = name
                return name
            }
            if let name = bundle.localizedInfoDictionary?["CFBundleName"] as? String {
                nameCache[bid] = name
                return name
            }
            if let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String {
                nameCache[bid] = name
                return name
            }
            if let name = bundle.infoDictionary?["CFBundleName"] as? String {
                nameCache[bid] = name
                return name
            }
            let stem = url.deletingPathExtension().lastPathComponent
            nameCache[bid] = stem
            return stem
        }

        return nil
    }

    /// Returns the alpha-weighted average sRGB color of the app's icon
    /// (opaque pixels only), used to tint preset-thumbnail rectangles where
    /// the app is assigned. The result is **desaturated** so the icon
    /// itself stays visually distinct from the tinted background. Cached
    /// per bundle ID.
    static func averageColor(forBundleID bid: String) -> NSColor? {
        if let cached = averageColorCache[bid] { return cached }
        guard let icon = icon(forBundleID: bid) else { return nil }
        guard let raw = computeAverageColor(of: icon) else { return nil }
        let desaturated = desaturate(raw, saturationFactor: 0.45, brightnessFactor: 1.05)
        averageColorCache[bid] = desaturated
        return desaturated
    }

    /// Returns a tinted variant of `color` with reduced saturation and
    /// optionally adjusted brightness so it works as a background fill
    /// without drowning out the icon overlaid on top.
    private static func desaturate(_ color: NSColor, saturationFactor: CGFloat, brightnessFactor: CGFloat) -> NSColor {
        let working = color.usingColorSpace(.sRGB) ?? color
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        working.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let newS = max(0, min(1, s * saturationFactor))
        let newB = max(0, min(1, b * brightnessFactor))
        return NSColor(hue: h, saturation: newS, brightness: newB, alpha: a)
    }

    private static func computeAverageColor(of image: NSImage) -> NSColor? {
        let pixelDim = 16
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelDim,
            pixelsHigh: pixelDim,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pixelDim * 4,
            bitsPerPixel: 32
        ) else { return nil }
        bitmap.size = NSSize(width: pixelDim, height: pixelDim)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: pixelDim, height: pixelDim).fill()
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixelDim, height: pixelDim),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.bitmapData else { return nil }
        var rSum: Double = 0, gSum: Double = 0, bSum: Double = 0
        var weightSum: Double = 0
        let totalPixels = pixelDim * pixelDim
        for i in 0..<totalPixels {
            let r = Double(data[i * 4])
            let g = Double(data[i * 4 + 1])
            let b = Double(data[i * 4 + 2])
            let a = Double(data[i * 4 + 3])
            // Skip mostly-transparent pixels — typical for icon corners
            // and rounded mask edges that would wash the result toward
            // black/grey.
            if a < 32 { continue }
            let weight = a / 255.0
            rSum += r * weight
            gSum += g * weight
            bSum += b * weight
            weightSum += weight
        }
        guard weightSum > 0 else { return nil }
        return NSColor(
            srgbRed: rSum / weightSum / 255.0,
            green: gSum / weightSum / 255.0,
            blue: bSum / weightSum / 255.0,
            alpha: 1.0
        )
    }

    static func invalidate() {
        iconCache.removeAll()
        nameCache.removeAll()
        averageColorCache.removeAll()
    }
}
