import AppKit

/// Reads the user's Dock configuration from the Dock plist and provides
/// app icons in order.
struct DockReader {
    struct DockApp {
        let icon: NSImage
    }

    /// Returns the ordered list of apps in the Dock's persistent-apps section.
    /// Finder is always prepended (macOS shows it first and it's not in the plist).
    static func readApps() -> [DockApp] {
        var apps: [DockApp] = []

        // Finder is always the first item in the Dock but not in persistent-apps
        let finderIcon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
        apps.append(DockApp(icon: finderIcon))

        guard let plistURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Preferences/com.apple.dock.plist"),
              let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let persistentApps = plist["persistent-apps"] as? [[String: Any]] else {
            return apps
        }

        for entry in persistentApps {
            guard let tileData = entry["tile-data"] as? [String: Any],
                  let fileData = tileData["file-data"] as? [String: Any],
                  let urlString = fileData["_CFURLString"] as? String,
                  let url = URL(string: urlString) else { continue }

            let path = url.path
            // Skip non-.app entries (folders, spacers, etc.)
            guard path.hasSuffix(".app") || path.hasSuffix(".app/") else { continue }

            let cleanPath = path.hasSuffix("/") ? String(path.dropLast()) : path
            let icon = NSWorkspace.shared.icon(forFile: cleanPath)
            apps.append(DockApp(icon: icon))
        }

        return apps
    }
}
