import AppKit
import SwiftUI

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

struct ScreenContextKey: EnvironmentKey {
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
struct NotchMenuBarCanvas: View {
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
struct NotchShape: Shape {
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

final class AppInfoCache {
    private var icons: [pid_t: NSImage] = [:]
    private var bundleIDs: [pid_t: String] = [:]
    private var originalNames: [pid_t: String?] = [:]

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

    /// Returns the non-localized (original) app name for the given PID, if different from the localized name.
    func originalAppName(for pid: pid_t) -> String? {
        if let cached = originalNames[pid] { return cached }  // returns String? from the dict
        guard !originalNames.keys.contains(pid) else { return nil }  // already looked up, no result
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleURL = app.bundleURL else { return nil }
        let bundle = Bundle(url: bundleURL)
        // Read CFBundleName from the root Info.plist (not the localized version).
        let name = bundle?.infoDictionary?["CFBundleName"] as? String
        // Only store if it differs from the localized name.
        if let name, name.lowercased() != app.localizedName?.lowercased() {
            originalNames[pid] = name
            return name
        }
        originalNames[pid] = nil
        return nil
    }

    func invalidate() {
        icons.removeAll(keepingCapacity: true)
        bundleIDs.removeAll(keepingCapacity: true)
        originalNames.removeAll(keepingCapacity: true)
    }
}
