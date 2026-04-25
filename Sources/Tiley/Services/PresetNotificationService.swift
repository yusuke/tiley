import AppKit
@preconcurrency import UserNotifications

/// macOS system-notification wrapper for preset-application feedback.
///
/// Used when a preset has an assigned application whose window cannot be
/// resolved — either the app is running but has zero standard windows, or the
/// app was launched on behalf of the user but no window appeared within the
/// launch timeout.
@MainActor
final class PresetNotificationService {
    static let shared = PresetNotificationService()

    private var authorizationRequested = false
    private var isAuthorized = false

    private init() {}

    private func ensureAuthorizationAndPost(_ content: UNMutableNotificationContent) {
        let center = UNUserNotificationCenter.current()

        let postIfAllowed: () -> Void = {
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(request) { error in
                if let error {
                    debugLog("PresetNotificationService: add request failed: \(error.localizedDescription)")
                }
            }
        }

        if isAuthorized {
            postIfAllowed()
            return
        }

        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    self.isAuthorized = true
                    postIfAllowed()
                case .notDetermined:
                    guard !self.authorizationRequested else { return }
                    self.authorizationRequested = true
                    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        DispatchQueue.main.async {
                            self.isAuthorized = granted
                            if granted { postIfAllowed() }
                        }
                    }
                case .denied:
                    // Silently skip — user has muted Tiley notifications.
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    func postNoWindow(appName: String) {
        let content = UNMutableNotificationContent()
        content.title = appName
        content.body = String(
            format: NSLocalizedString("%@ has no windows to place.", comment: "Banner body when an assigned app is running but has no windows"),
            appName
        )
        ensureAuthorizationAndPost(content)
    }

    func postWindowNeverAppeared(appName: String) {
        let content = UNMutableNotificationContent()
        content.title = appName
        content.body = String(
            format: NSLocalizedString("Couldn't find a window for %@ after launching.", comment: "Banner body when an app was launched but no window appeared within the timeout"),
            appName
        )
        ensureAuthorizationAndPost(content)
    }
}
