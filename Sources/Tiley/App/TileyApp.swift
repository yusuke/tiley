import Sparkle
import SwiftUI

@main
struct TileyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A hidden utility window prevents SwiftUI from forcing the
        // activation policy to .accessory (which it does for
        // Settings-only apps). The window is never shown; activation
        // policy is managed manually via AppState.
        Window("Tiley", id: "tiley-anchor") {
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    // Close the anchor window immediately; it only exists
                    // to prevent SwiftUI from forcing .accessory policy.
                    DispatchQueue.main.async {
                        for window in NSApp.windows {
                            if window.identifier?.rawValue.contains("tiley-anchor") == true {
                                window.orderOut(nil)
                                window.setFrame(.zero, display: false)
                            }
                        }
                    }
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.appState.openSettingsFromAppMenu()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: appDelegate.updaterController.updater)
            }
        }
    }
}
