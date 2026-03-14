import AppKit
import Carbon
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appState.updater = updaterController.updater
        moveToApplicationsFolderIfNeeded()
        appState.start(showMainWindowOnLaunch: !wasLaunchedAsLoginItem())
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        appState.reopenMainWindowFromDock()
        return true
    }

    private func moveToApplicationsFolderIfNeeded() {
        let bundlePath = Bundle.main.bundlePath
        let applicationsDir = "/Applications"

        // Already in /Applications — nothing to do
        if bundlePath.hasPrefix(applicationsDir + "/") { return }

        // Skip development builds (Xcode DerivedData, Swift PM .build, etc.)
        if bundlePath.contains("/DerivedData/") || bundlePath.contains("/Build/Products/") || bundlePath.contains("/.build/") { return }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString(
            "Move to Applications folder?",
            comment: "Alert title asking user to move app to /Applications"
        )
        alert.informativeText = NSLocalizedString(
            "Tiley is not in the Applications folder. Would you like to move it there?",
            comment: "Alert body explaining app is not in /Applications"
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString(
            "Move to Applications",
            comment: "Button to move the app"
        ))
        alert.addButton(withTitle: NSLocalizedString(
            "Don't Move",
            comment: "Button to skip moving the app"
        ))

        // Temporarily show as regular app so the alert is visible
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        NSApp.setActivationPolicy(.accessory)

        guard response == .alertFirstButtonReturn else { return }

        let appName = (bundlePath as NSString).lastPathComponent
        let destinationPath = (applicationsDir as NSString).appendingPathComponent(appName)
        let fileManager = FileManager.default

        do {
            // Terminate any running instance at the destination before replacing
            if fileManager.fileExists(atPath: destinationPath) {
                let destinationURL = URL(fileURLWithPath: destinationPath)
                let runningInstances = NSWorkspace.shared.runningApplications.filter {
                    $0.bundleURL?.standardizedFileURL == destinationURL.standardizedFileURL
                }
                for app in runningInstances {
                    app.terminate()
                }
                // Wait briefly for the process to exit
                for app in runningInstances {
                    let deadline = Date().addingTimeInterval(5)
                    while app.isTerminated == false, Date() < deadline {
                        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                    }
                    if !app.isTerminated {
                        app.forceTerminate()
                        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                    }
                }
                try fileManager.removeItem(atPath: destinationPath)
            }
            try fileManager.moveItem(atPath: bundlePath, toPath: destinationPath)

            // Relaunch from the new location
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-n", destinationPath]
            try task.run()
            NSApp.terminate(nil)
        } catch {
            let errorAlert = NSAlert(error: error)
            errorAlert.runModal()
        }
    }

    private func wasLaunchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return false
        }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem))?.booleanValue ?? false
    }
}
