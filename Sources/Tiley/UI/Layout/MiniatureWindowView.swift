import SwiftUI

struct MiniatureWindowView: View {
    let titleBarHeight: CGFloat
    var appIcon: NSImage?
    var appName: String?
    var windowTitle: String?
    var cornerRadiusOverride: CGFloat?
    @Environment(\.colorScheme) private var colorScheme

    private var titleBarText: String? {
        let app = (appName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (windowTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !app.isEmpty && !title.isEmpty && app != title {
            return "\(app) — \(title)"
        } else if !app.isEmpty {
            return app
        } else if !title.isEmpty {
            return title
        }
        return nil
    }

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let cornerRadius = cornerRadiusOverride ?? max(2, min(w, h) * 0.02)
            let buttonDiameter = max(2, titleBarHeight * 0.38)
            let buttonSpacing = buttonDiameter * 0.55
            let buttonLeftPadding = buttonDiameter * 0.8
            let showButtons = w > 30 && titleBarHeight > 6
            let hasTitle = titleBarText != nil
            // Space occupied by the three traffic-light buttons + padding
            let buttonsTrailingEdge = buttonLeftPadding + buttonDiameter * 3 + buttonSpacing * 2 + buttonDiameter * 0.5
            let titleBarFontSize = max(4, titleBarHeight * 0.6)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(bodyFill)
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        // Title bar fill
                        ZStack {
                            Rectangle()
                                .fill(titleBarFill)
                            // Window title centered in title bar with app icon
                            if showButtons {
                                HStack(spacing: titleBarFontSize * 0.4) {
                                    if let icon = appIcon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .interpolation(.high)
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: titleBarHeight * 0.6, height: titleBarHeight * 0.6)
                                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                                    }
                                    if let text = titleBarText {
                                        Text(text)
                                            .font(.system(size: titleBarFontSize))
                                            .foregroundStyle(titleTextColor)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                }
                                .padding(.horizontal, buttonsTrailingEdge)
                            }
                        }
                        .frame(height: titleBarHeight)
                        // Divider
                        Rectangle()
                            .fill(dividerColor)
                            .frame(height: 0.5)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    // Traffic light buttons
                    if showButtons {
                        HStack(spacing: buttonSpacing) {
                            Circle()
                                .fill(Color(red: 1.0, green: 0.373, blue: 0.341))
                            Circle()
                                .fill(Color(red: 0.996, green: 0.737, blue: 0.180))
                            Circle()
                                .fill(Color(red: 0.157, green: 0.784, blue: 0.251))
                        }
                        .frame(height: buttonDiameter)
                        .fixedSize()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, buttonLeftPadding)
                        .padding(.top, (titleBarHeight - buttonDiameter) / 2)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                }
        }
    }

    private var bodyFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.white.opacity(0.45)
    }

    private var titleBarFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.white.opacity(0.65)
    }

    private var dividerColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.10)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.20)
            : Color.black.opacity(0.18)
    }

    private var titleTextColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.70)
            : Color.black.opacity(0.55)
    }

}
