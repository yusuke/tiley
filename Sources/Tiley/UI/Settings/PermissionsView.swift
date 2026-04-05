import AppKit
import SwiftUI

struct PermissionsView: View {
    private static let windowCornerRadius: CGFloat = 20

    @Environment(\.colorScheme) private var colorScheme
    var appState: AppState

    private static let permissionsImageLocale: String = {
        let lang = Locale.preferredLanguages.first ?? "en"
        return lang.hasPrefix("ja") ? "ja" : "en"
    }()

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .windowBackgroundColor)

            VStack(spacing: 0) {
                // Tahoe-style title bar
                HStack {
                    Spacer()

                    HStack(spacing: 6) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                        Text("Tiley")
                            .font(.system(size: 13, weight: .semibold))
                    }

                    Spacer()

                    Button {
                        appState.quitApp()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "power")
                                .font(.system(size: 10, weight: .semibold))
                            Text(NSLocalizedString("Quit Tiley", comment: "Quit button"))
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(TahoeQuitButtonStyle())
                    .help(NSLocalizedString("Quit Tiley", comment: "Quit button tooltip"))
                }
                .padding(.top, 10)
                .padding(.bottom, 4)
                .padding(.horizontal, 8)

                Divider()
                    .opacity(0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TahoeSettingsSection(title: NSLocalizedString("Permissions", comment: "Settings section")) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label(
                                        appState.accessibilityGranted
                                            ? NSLocalizedString("Accessibility enabled", comment: "")
                                            : NSLocalizedString("Accessibility required", comment: ""),
                                        systemImage: appState.accessibilityGranted ? "checkmark.shield" : "exclamationmark.shield"
                                    )
                                    .foregroundStyle(appState.accessibilityGranted ? .green : .orange)
                                    Spacer()
                                    Button(NSLocalizedString("Open Prompt", comment: "Accessibility prompt button")) {
                                        appState.requestAccessibilityAccess()
                                    }
                                        }
                                Text(NSLocalizedString("Window movement on macOS requires Accessibility permission.", comment: "Accessibility permission description"))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)

                                permissionsScreenshot(named: "dialog")
                                permissionsScreenshot(named: "system")
                            }
                        }
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
            }
            } // ZStack
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: Self.windowCornerRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func permissionsScreenshot(named name: String) -> some View {
        if let nsImage = Self.permissionsImage(named: name) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(ThemeColors.screenshotBorder(for: colorScheme), lineWidth: 1)
                )
        }
    }

    private static func permissionsImage(named name: String) -> NSImage? {
        let fileName = "\(name)-\(permissionsImageLocale)"
        let url = resourceBundle.url(forResource: fileName, withExtension: "png", subdirectory: "Images")
            ?? resourceBundle.url(forResource: fileName, withExtension: "png")
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }
}
