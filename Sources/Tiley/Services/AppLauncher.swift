import AppKit

/// Launches an application by bundle identifier and waits for a usable
/// standard window to appear.
///
/// Used by the preset apply pipeline when an assigned app is not yet running:
/// the launch must complete before we can place the app's window into the
/// preset rectangle. The poll interval is short and bounded by `timeout`.
@MainActor
enum AppLauncher {
    /// Launches `bundleID` (no-op if already running) and polls until a
    /// `WindowTarget` can be resolved for its PID or `timeout` seconds elapse.
    ///
    /// Returns `nil` on timeout. The caller is responsible for user feedback
    /// (posting a notification etc.).
    static func launchAndWaitForWindow(
        bundleID: String,
        using accessibilityService: AccessibilityService,
        timeout: TimeInterval = 30
    ) async -> WindowTarget? {
        let pid: pid_t
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.activationPolicy == .regular }) {
            pid = running.processIdentifier
        } else if let launched = await launch(bundleID: bundleID) {
            pid = launched.processIdentifier
        } else {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let target = try? accessibilityService.windowTarget(for: pid) {
                return target
            }
            try? await Task.sleep(nanoseconds: 250_000_000) // 250 ms
        }
        return nil
    }

    /// Launches the app behind `bundleID` and returns the resulting
    /// `NSRunningApplication`, or `nil` if the bundle couldn't be resolved or
    /// the system rejected the launch.
    private static func launch(bundleID: String) async -> NSRunningApplication? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                if let error {
                    debugLog("AppLauncher: openApplication failed: \(error.localizedDescription)")
                }
                continuation.resume(returning: app)
            }
        }
    }
}
