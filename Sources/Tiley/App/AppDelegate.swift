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
        performDeferredDMGCleanupIfNeeded()
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

        // Already in /Applications — but a Tiley DMG may still be mounted
        // (e.g. the user copied the app manually via Finder).
        if bundlePath.hasPrefix(applicationsDir + "/") {
            cleanupMountedDiskImageIfNeeded()
            return
        }

        // Skip development builds (Xcode DerivedData, Swift PM .build, etc.)
        if bundlePath.contains("/DerivedData/") || bundlePath.contains("/Build/Products/") || bundlePath.contains("/.build/") { return }

        // Detect whether the app is running from a mounted disk image.
        var isFromDiskImage = bundlePath.hasPrefix("/Volumes/")

        // When launched from a zip (or DMG) without moving first, Gatekeeper
        // App Translocation runs the app from a randomized read-only path
        // (e.g. /private/var/folders/.../AppTranslocation/...).
        // Resolve the original (writable) path so we can move/copy it.
        let sourcePath: String
        if isFromDiskImage {
            sourcePath = bundlePath
        } else {
            sourcePath = Self.originalURLResolvingTranslocation(
                URL(fileURLWithPath: bundlePath)
            )?.path ?? bundlePath

            // The resolved original path may reside on a mounted disk image
            // (e.g. the user opened the app directly from a DMG, triggering
            // translocation).  Re-check so we copy instead of move.
            if sourcePath.hasPrefix("/Volumes/") {
                isFromDiskImage = true
            }
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

            // For disk image launches, ask whether to eject & trash the DMG.
            // The actual cleanup is deferred to the relaunched process because
            // the current process is still running from the DMG volume.
            var cleanupDMGPath: String?
            var cleanupMountPoint: String?
            if isFromDiskImage {
                let volComponents = sourcePath.split(separator: "/", maxSplits: 3)
                if volComponents.count >= 2, volComponents[0] == "Volumes" {
                    let mp = "/" + volComponents[0 ..< 2].joined(separator: "/")
                    let dmg = dmgPathForVolume(mp)
                    if askCleanupDiskImage(mountPoint: mp, dmgPath: dmg, copiedByApp: true) {
                        cleanupMountPoint = mp
                        cleanupDMGPath = dmg
                    }
                }
            }

            // Relaunch from the new location
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            var args = ["-n", destinationPath, "--args"]
            if let mp = cleanupMountPoint {
                args += ["--cleanup-dmg-mount", mp]
            }
            if let dmg = cleanupDMGPath {
                args += ["--cleanup-dmg-path", dmg]
            }
            task.arguments = args
            try task.run()
            NSApp.terminate(nil)
        } catch {
            let errorAlert = NSAlert(error: error)
            errorAlert.runModal()
        }
    }

    // MARK: - Disk image cleanup

    /// Show a dialog asking the user whether to eject the DMG volume and trash
    /// the DMG file.  Returns `true` if the user accepted.
    @discardableResult
    private func askCleanupDiskImage(mountPoint: String, dmgPath: String?, copiedByApp: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString(
            "Eject disk image?",
            comment: "Alert title asking whether to eject the DMG after copying"
        )
        if let dmg = dmgPath {
            let key = copiedByApp
                ? "The app has been copied. Would you like to eject the disk image and move \"%@\" to the Trash?"
                : "A Tiley disk image is still mounted. Would you like to eject it and move \"%@\" to the Trash?"
            alert.informativeText = String(
                format: NSLocalizedString(
                    key,
                    comment: "Alert body when DMG path is known; %@ is the DMG filename"
                ),
                (dmg as NSString).lastPathComponent
            )
        } else {
            let key = copiedByApp
                ? "The app has been copied. Would you like to eject the disk image?"
                : "A Tiley disk image is still mounted. Would you like to eject it?"
            alert.informativeText = NSLocalizedString(
                key,
                comment: "Alert body when DMG path is unknown"
            )
        }
        alert.addButton(withTitle: NSLocalizedString(
            "Eject and Move to Trash",
            comment: "Button to eject volume and trash DMG"
        ))
        alert.addButton(withTitle: NSLocalizedString(
            "Don't Eject",
            comment: "Button to skip ejecting"
        ))
        alert.alertStyle = .informational

        // Temporarily show as regular app so the alert is visible
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Eject the DMG volume and move the DMG file to Trash.
    private func performDMGCleanup(mountPoint: String, dmgPath: String?) {
        // Eject the volume via hdiutil detach.
        let detach = Process()
        detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        detach.arguments = ["detach", mountPoint, "-force"]
        detach.standardOutput = FileHandle.nullDevice
        detach.standardError = FileHandle.nullDevice
        try? detach.run()
        detach.waitUntilExit()

        // Move the DMG to Trash.
        if let dmg = dmgPath, FileManager.default.fileExists(atPath: dmg) {
            try? FileManager.default.trashItem(
                at: URL(fileURLWithPath: dmg),
                resultingItemURL: nil
            )
        }
    }

    /// Called on launch to handle --cleanup-dmg-mount / --cleanup-dmg-path
    /// arguments passed by the previous (DMG-based) process.
    private func performDeferredDMGCleanupIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard let mountIdx = args.firstIndex(of: "--cleanup-dmg-mount"),
              mountIdx + 1 < args.count
        else { return }
        let mountPoint = args[mountIdx + 1]

        var dmgPath: String?
        if let pathIdx = args.firstIndex(of: "--cleanup-dmg-path"),
           pathIdx + 1 < args.count {
            dmgPath = args[pathIdx + 1]
        }

        performDMGCleanup(mountPoint: mountPoint, dmgPath: dmgPath)
    }

    /// Check whether a Tiley disk image volume is currently mounted and, if so,
    /// offer to eject it and trash the DMG.  Called when the app is already
    /// running from /Applications (i.e. the user copied it manually).
    private func cleanupMountedDiskImageIfNeeded() {
        guard let (mountPoint, _) = findMountedTileyDiskImage() else { return }
        let dmgPath = dmgPathForVolume(mountPoint)
        if askCleanupDiskImage(mountPoint: mountPoint, dmgPath: dmgPath, copiedByApp: false) {
            performDMGCleanup(mountPoint: mountPoint, dmgPath: dmgPath)
        }
    }

    /// Use `hdiutil info -plist` to find a mounted volume whose DMG filename
    /// contains "Tiley" (case-insensitive).  Returns the mount point and DMG
    /// path, or `nil` if none is found.
    private func findMountedTileyDiskImage() -> (mountPoint: String, dmgPath: String)? {
        guard let images = hdiutilImageList() else { return nil }
        let appName = (Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Tiley").lowercased()
        for image in images {
            guard let imagePath = image["image-path"] as? String else { continue }
            let filename = (imagePath as NSString).lastPathComponent.lowercased()
            guard filename.contains(appName) else { continue }
            guard let entities = image["system-entities"] as? [[String: Any]] else { continue }
            for entity in entities {
                if let mp = entity["mount-point"] as? String {
                    return (mp, imagePath)
                }
            }
        }
        return nil
    }

    /// Use `hdiutil info -plist` to find the disk image file backing a volume.
    private func dmgPathForVolume(_ mountPoint: String) -> String? {
        guard let images = hdiutilImageList() else { return nil }
        for image in images {
            guard let entities = image["system-entities"] as? [[String: Any]] else { continue }
            for entity in entities {
                if let mp = entity["mount-point"] as? String, mp == mountPoint {
                    return image["image-path"] as? String
                }
            }
        }
        return nil
    }

    /// Run `hdiutil info -plist` and return the images array.
    private func hdiutilImageList() -> [[String: Any]]? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        proc.arguments = ["info", "-plist"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        guard let data = try? pipe.fileHandleForReading.readDataToEndOfFile(),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any],
              let images = plist["images"] as? [[String: Any]]
        else { return nil }
        return images
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
    nonisolated func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        Task { @MainActor in
            appState.hideMainWindow()
        }
    }
}
