import AppKit
import Carbon
import ServiceManagement
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState: AppState

    lazy var updaterController: SPUStandardUpdaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    override init() {
        // Capture the frontmost app PID before Tiley activates.
        AppState.captureLaunchTimeFrontmostPID()
        appState = AppState()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.updater = updaterController.updater
        moveToApplicationsFolderIfNeeded()
        appState.start(showMainWindowOnLaunch: !wasLaunchedAsLoginItem())
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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

        // Detect whether the app is running from a mounted disk image.
        let isFromDiskImage = bundlePath.hasPrefix("/Volumes/")

        // When launched from a zip without moving first, Gatekeeper App
        // Translocation runs the app from a randomized read-only path.
        // Resolve the original (writable) path so we can move it.
        let sourcePath: String
        if isFromDiskImage {
            sourcePath = bundlePath
        } else {
            sourcePath = Self.originalURLResolvingTranslocation(
                URL(fileURLWithPath: bundlePath)
            )?.path ?? bundlePath
        }

        let alert = NSAlert()
        if isFromDiskImage {
            alert.messageText = NSLocalizedString(
                "Copy to Applications folder?",
                comment: "Alert title asking user to copy app from disk image to /Applications"
            )
            alert.informativeText = NSLocalizedString(
                "Tiley is running from a disk image. Would you like to copy it to the Applications folder?",
                comment: "Alert body explaining app is on a disk image"
            )
            alert.addButton(withTitle: NSLocalizedString(
                "Copy to Applications",
                comment: "Button to copy the app from disk image"
            ))
            alert.addButton(withTitle: NSLocalizedString(
                "Don't Copy",
                comment: "Button to skip copying the app"
            ))
        } else {
            alert.messageText = NSLocalizedString(
                "Move to Applications folder?",
                comment: "Alert title asking user to move app to /Applications"
            )
            alert.informativeText = NSLocalizedString(
                "Tiley is not in the Applications folder. Would you like to move it there?",
                comment: "Alert body explaining app is not in /Applications"
            )
            alert.addButton(withTitle: NSLocalizedString(
                "Move to Applications",
                comment: "Button to move the app"
            ))
            alert.addButton(withTitle: NSLocalizedString(
                "Don't Move",
                comment: "Button to skip moving the app"
            ))
        }
        alert.alertStyle = .informational

        // Temporarily show as regular app so the alert is visible
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        guard response == .alertFirstButtonReturn else { return }

        let appName = (sourcePath as NSString).lastPathComponent
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

            if isFromDiskImage {
                try fileManager.copyItem(atPath: sourcePath, toPath: destinationPath)
            } else {
                try fileManager.moveItem(atPath: sourcePath, toPath: destinationPath)
            }

            // Strip the quarantine extended attribute so macOS does not
            // translocate the app again from its new location.
            removexattr(destinationPath, "com.apple.quarantine", XATTR_NOFOLLOW)

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

    // MARK: - App Translocation resolution (private API via dlsym)

    private typealias IsTranslocatedFn = @convention(c)
        (CFURL, UnsafeMutablePointer<ObjCBool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool
    private typealias OriginalPathFn = @convention(c)
        (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> CFURL?

    /// Resolve the original bundle URL when Gatekeeper App Translocation is
    /// active.  Uses `SecTranslocateCreateOriginalPathForURL` loaded via
    /// `dlsym` (private but stable Security.framework symbol).
    /// Returns `nil` if the app is not translocated or resolution fails.
    private static func originalURLResolvingTranslocation(_ url: URL) -> URL? {
        guard let handle = dlopen(
            "/System/Library/Frameworks/Security.framework/Security",
            RTLD_LAZY
        ) else { return nil }
        defer { dlclose(handle) }

        guard let isSym = dlsym(handle, "SecTranslocateIsTranslocatedURL"),
              let origSym = dlsym(handle, "SecTranslocateCreateOriginalPathForURL")
        else { return nil }

        let isTranslocated = unsafeBitCast(isSym, to: IsTranslocatedFn.self)
        let createOriginal = unsafeBitCast(origSym, to: OriginalPathFn.self)

        var flag = ObjCBool(false)
        guard isTranslocated(url as CFURL, &flag, nil), flag.boolValue else {
            return nil
        }
        guard let originalCFURL = createOriginal(url as CFURL, nil) else {
            return nil
        }
        return originalCFURL as URL
    }

    private func wasLaunchedAsLoginItem() -> Bool {
        // 1. Check the Apple Event flag (works for legacy login items).
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem))?.booleanValue == true {
            return true
        }

        // 2. Heuristic for SMAppService.mainApp login items:
        //    Apple does not set keyAELaunchedAsLogInItem when the app is
        //    launched via SMAppService.mainApp (FB10207829).  As a workaround,
        //    treat the launch as a login-item launch when:
        //      - The app is registered as a login item, AND
        //      - The system has been up for less than 120 seconds (i.e. we are
        //        still in the login phase).
        if SMAppService.mainApp.status == .enabled {
            var bootTime = timeval()
            var size = MemoryLayout<timeval>.size
            var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
            if sysctl(&mib, 2, &bootTime, &size, nil, 0) == 0 {
                let uptime = Date().timeIntervalSince1970 - Double(bootTime.tv_sec)
                if uptime < 120 {
                    return true
                }
            }
        }

        return false
    }
}

extension AppDelegate: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            appState.hideMainWindow()
        }
    }
}
