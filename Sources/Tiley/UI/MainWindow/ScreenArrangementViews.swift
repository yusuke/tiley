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
    @Environment(\.tahoeActionBarHovered) private var isHovered
    @Environment(\.isEnabled) private var isEnabled

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
            ZStack {
                ScreenArrangementIcon(highlightDisplayID: targetScreen.displayID, size: 12, color: .secondary)
                    .opacity(isHovered && isEnabled ? 0 : 1)
                ScreenArrangementIcon(highlightDisplayID: targetScreen.displayID, size: 12, color: .primary)
                    .opacity(isHovered && isEnabled ? 1 : 0)
            }
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

    private let iconSize: CGFloat = 96
    private let arrowFontSize: CGFloat = 40
    private let arrowSpacing: CGFloat = 8

    /// Direction components derived from the arrow symbol name.
    private var direction: (horizontal: Int, vertical: Int) {
        // horizontal: -1 = left, 0 = centre, 1 = right
        // vertical:   -1 = up,   0 = centre, 1 = down
        let name = directionArrowSymbol(from: thisScreen)
        var h = 0, v = 0
        if name.contains(".left")  { h = -1 }
        if name.contains(".right") { h =  1 }
        if name.contains(".up")    { v = -1 }
        if name.contains(".down")  { v =  1 }
        // Pure "arrow.left" / "arrow.right" etc.
        if h == 0 && v == 0 {
            if name == "arrow.left"  { h = -1 }
            if name == "arrow.right" { h =  1 }
            if name == "arrow.up"    { v = -1 }
            if name == "arrow.down"  { v =  1 }
        }
        return (h, v)
    }

    var body: some View {
        let arrowName = directionArrowSymbol(from: thisScreen)
        let dir = direction

        let arrowImage = Image(systemName: arrowName)
            .font(.system(size: arrowFontSize, weight: .bold))

        let iconView = ScreenArrangementIcon(highlightDisplayID: windowDisplayID, size: iconSize, color: .primary)
            .frame(width: iconSize, height: iconSize)

        // Place the arrow relative to the icon based on direction.
        // Cardinal directions: HStack/VStack centred on that edge.
        // Diagonal directions: ZStack with offset so the arrow sits at the corner.
        Group {
            switch (dir.horizontal, dir.vertical) {
            case (-1, 0):  // left
                HStack(spacing: arrowSpacing) { arrowImage; iconView }
            case (1, 0):   // right
                HStack(spacing: arrowSpacing) { iconView; arrowImage }
            case (0, -1):  // up
                VStack(spacing: arrowSpacing) { arrowImage; iconView }
            case (0, 1):   // down
                VStack(spacing: arrowSpacing) { iconView; arrowImage }
            default:       // diagonal
                let offsetX = CGFloat(dir.horizontal) * (iconSize / 2 + arrowFontSize / 2 + arrowSpacing)
                let offsetY = CGFloat(dir.vertical)   * (iconSize / 2 + arrowFontSize / 2 + arrowSpacing)
                ZStack {
                    iconView
                    arrowImage
                        .offset(x: offsetX, y: offsetY)
                }
            }
        }
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
