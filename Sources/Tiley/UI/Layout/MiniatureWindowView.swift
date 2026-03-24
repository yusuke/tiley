import SwiftUI

struct MiniatureWindowView: View {
    let titleBarHeight: CGFloat
    var appIcon: NSImage?
    var windowTitle: String?
    var appName: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let cornerRadius = max(2, min(w, h) * 0.02)
            let buttonDiameter = max(2, titleBarHeight * 0.38)
            let buttonSpacing = buttonDiameter * 0.55
            let buttonLeftPadding = buttonDiameter * 0.8
            let showButtons = w > 30 && titleBarHeight > 6
            let contentHeight = h - titleBarHeight - 0.5
            let desiredIconSize = titleBarHeight * 2.6
            let iconSize = min(desiredIconSize, contentHeight * 0.7, w * 0.35)
            let displayTitle = windowTitle ?? appName ?? ""
            let showTitleArea = !displayTitle.isEmpty || appIcon != nil
            let desiredFontSize = titleBarHeight * 1.8
            let titleFontSize = max(4, min(desiredFontSize, contentHeight * 0.25))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(bodyFill)
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        // Title bar fill
                        Rectangle()
                            .fill(titleBarFill)
                            .frame(height: titleBarHeight)
                        // Divider
                        Rectangle()
                            .fill(dividerColor)
                            .frame(height: 0.5)
                        // App icon + window title area
                        if showTitleArea {
                            HStack(spacing: iconSize * 0.2) {
                                if let icon = appIcon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: iconSize, height: iconSize)
                                }
                                if !displayTitle.isEmpty {
                                    Text(displayTitle)
                                        .font(.system(size: titleFontSize, weight: .medium))
                                        .foregroundStyle(titleTextColor)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                            .padding(.horizontal, iconSize * 0.2)
                            .padding(.top, iconSize * 0.15)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
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
