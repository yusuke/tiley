import AppKit
import SwiftUI

/// Action bar button for 2-display setups: arrow + screen arrangement icon.
/// Tracks hover internally so the Canvas-based ScreenArrangementIcon can
/// respond to hover/press state changes.
struct MoveToDisplayButton: View {
    let targetScreen: NSScreen
    let disabled: Bool
    let onSelect: (NSScreen) -> Void
    var triggerVersion: Int = 0

    var body: some View {
        Button {
            onSelect(targetScreen)
        } label: {
            MoveToDisplayButtonLabel(
                targetScreen: targetScreen
            )
        }
        .buttonStyle(TahoeActionBarButtonStyle())
        .frame(width: 32, height: 24)
        .disabled(disabled)
        .onChange(of: triggerVersion) { _, newValue in
            if newValue > 0 && !disabled {
                onSelect(targetScreen)
            }
        }
    }
}

struct MoveToDisplayButtonLabel: View {
    let targetScreen: NSScreen

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: {
                // Arrow points from the current display toward the target display.
                guard let currentScreen = NSScreen.screens.first(where: { $0.displayID != targetScreen.displayID }) else {
                    return "arrow.right"
                }
                return directionArrowSymbol(from: currentScreen, to: targetScreen)
            }())
                .font(.system(size: 8, weight: .bold))
                .frame(width: 10, height: 10)
            ScreenArrangementIcon(highlightDisplayID: targetScreen.displayID, size: 12, color: .primary)
                .frame(width: 12, height: 12)
        }
        .frame(width: 32, height: 24)
    }
}

/// Overlay shown in the centre of the grid on a display that has no windows,
/// indicating which display the windows are on with an arrow + arrangement icon.
/// The arrow is placed on the side of the icon that corresponds to the direction.
struct EmptyDisplayOverlay: View {
    let thisScreen: NSScreen
    let windowDisplayID: CGDirectDisplayID

    private let arrowFontSize: CGFloat = 160

    var body: some View {
        Image(systemName: directionArrowSymbol(from: thisScreen))
            .font(.system(size: arrowFontSize, weight: .bold))
            .foregroundStyle(.primary)
            .allowsHitTesting(false)
    }
}

/// Returns the SF Symbol name for an arrow pointing from `screen` toward the
/// other display in a 2-display setup.  Covers all 8 cardinal/diagonal directions.
func directionArrowSymbol(from screen: NSScreen) -> String {
    guard let otherScreen = NSScreen.screens.first(where: { $0.displayID != screen.displayID }) else {
        return "arrow.right"
    }
    return directionArrowSymbol(from: screen, to: otherScreen)
}

/// Returns the SF Symbol name for an arrow pointing from `fromScreen` toward `toScreen`.
func directionArrowSymbol(from fromScreen: NSScreen, to toScreen: NSScreen) -> String {
    let dx = toScreen.frame.midX - fromScreen.frame.midX
    // NSScreen Y increases upward (Cocoa coords), matching the physical "up" direction.
    let dy = toScreen.frame.midY - fromScreen.frame.midY

    let angle = atan2(dy, dx) * 180 / .pi  // degrees: 0 = right, 90 = up

    // 8 sectors of 45° each, centred on the cardinal/diagonal directions.
    switch angle {
    case -22.5 ..< 22.5:    return "arrow.right"
    case 22.5  ..< 67.5:    return "arrow.up.right"
    case 67.5  ..< 112.5:   return "arrow.up"
    case 112.5 ..< 157.5:   return "arrow.up.left"
    case -67.5 ..< -22.5:   return "arrow.down.right"
    case -112.5 ..< -67.5:  return "arrow.down"
    case -157.5 ..< -112.5: return "arrow.down.left"
    default:                 return "arrow.left"
    }
}

/// Draws a miniature representation of the screen arrangement, highlighting the
/// specified display. Each screen is drawn as a rounded rectangle whose position
/// and size reflect the actual display layout, scaled to fit within the given
/// frame.
struct ScreenArrangementIcon: View {
    let highlightDisplayID: CGDirectDisplayID
    let size: CGFloat
    var color: Color = .secondary

    var body: some View {
        Canvas { context, canvasSize in
            let screens = NSScreen.screens
            guard !screens.isEmpty else { return }

            // Compute the bounding rect of all screens.
            var union = CGRect.null
            for screen in screens {
                union = union.union(screen.frame)
            }
            guard union.width > 0, union.height > 0 else { return }

            // Inset slightly so strokes don't clip.
            let inset: CGFloat = 0.5
            let available = CGSize(width: canvasSize.width - inset * 2,
                                   height: canvasSize.height - inset * 2)
            let scale = min(available.width / union.width,
                            available.height / union.height)

            // Center the arrangement within the canvas.
            let scaledWidth = union.width * scale
            let scaledHeight = union.height * scale
            let offsetX = (canvasSize.width - scaledWidth) / 2
            let offsetY = (canvasSize.height - scaledHeight) / 2

            let gap: CGFloat = 0.5  // visual gap between screens

            for screen in screens {
                let f = screen.frame
                // NSScreen uses bottom-left origin; flip Y for Canvas (top-left).
                let x = (f.minX - union.minX) * scale + offsetX + gap
                let y = (union.maxY - f.maxY) * scale + offsetY + gap
                let w = f.width * scale - gap * 2
                let h = f.height * scale - gap * 2

                let rect = CGRect(x: x, y: y, width: max(w, 1), height: max(h, 1))
                let cornerRadius: CGFloat = 1.5
                let path = Path(roundedRect: rect, cornerRadius: cornerRadius)

                let isHighlight = screen.displayID == highlightDisplayID
                if isHighlight {
                    context.fill(path, with: .color(color))
                } else {
                    context.stroke(path, with: .color(color), lineWidth: 0.75)
                }
            }
        }
        .frame(width: size, height: size)
    }
}
