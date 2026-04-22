import AppKit
import SwiftUI

// MARK: - Style constants

/// Visual-style constants for the group-link badge. All magic numbers live here.
private enum BadgeStyle {
    // MARK: Size / shape
    /// Outer NSPanel size. Includes padding around the circular badge for the shadow.
    static let windowSize: CGFloat = 40
    /// Diameter of the visible circle.
    static let visibleDiameter: CGFloat = 22
    /// Inset for the click area (the visible-diameter circle is centered inside windowSize).
    static let hitAreaInset: CGFloat = (windowSize - visibleDiameter) / 2
    /// Stroke width of the circle outline.
    static let strokeWidth: CGFloat = 1
    /// Font size for the SF Symbol (`link`, `link.badge.plus`, `xmark`).
    static let symbolFontSize: CGFloat = 11
    /// Shadow blur radius.
    static let shadowRadius: CGFloat = 3
    /// Shadow y-offset (downward).
    static let shadowYOffset: CGFloat = 1

    // MARK: Color / opacity
    enum Opacity {
        // Unlinked state (`link.badge.plus`)
        /// Background (accent color) when unlinked and idle.
        static let unlinkedBgIdle: Double = 0.85
        /// Background (accent color) when unlinked and hovered.
        static let unlinkedBgHover: Double = 0.95

        // Linked state (`link` / `xmark`)
        /// Background (black, subtle) when linked and idle.
        static let linkedBgIdle: Double = 0.25
        /// Icon (white) when linked and idle.
        static let linkedForegroundIdle: Double = 0.6
        /// Stroke (white) when linked and idle.
        static let linkedStrokeIdle: Double = 0.35
        /// Shadow (black) when linked and idle.
        static let linkedShadowIdle: Double = 0.15
        /// Background (red — unlink warning color) when linked and hovered.
        static let linkedBgHover: Double = 0.85

        // Shared "active" opacities (unlinked idle / hover, linked hover)
        /// Stroke opacity (white) when active.
        static let activeStroke: Double = 0.8
        /// Shadow opacity (black) when active.
        static let activeShadow: Double = 0.4
    }

    // MARK: Animation
    enum Animation {
        /// Scale factor applied on hover.
        static let hoverScale: CGFloat = 1.12
        /// Duration of the hover scale animation.
        static let hoverDuration: TimeInterval = 0.12
        /// Fade-in duration when a badge first appears (short, so it pops quickly).
        static let fadeIn: TimeInterval = 0.08
        /// Fade-out duration on the 5-second timeout or when adjacency is lost.
        static let defaultFadeOut: TimeInterval = 0.25
        /// Fade-out duration at the start of a drag / resize.
        static let fastFadeOut: TimeInterval = 0.15
    }
}

/// Visual state of a badge.
enum GroupLinkBadgeState {
    case unlinked      // Not yet grouped: `link.badge.plus`.
    case linked        // Grouped: `link`.
}

/// Represents a single badge.
struct GroupLinkBadge: Identifiable {
    let id: AdjacencyKey
    let state: GroupLinkBadgeState
    /// Badge center in AppKit screen coordinates (bottom-left origin).
    let center: CGPoint
    let adjacency: WindowAdjacency
}

/// Floating overlay that shows a `link.badge.plus` / `link` badge at the midpoint
/// of each touching pair of windows.
///
/// **Design**: one small independent NSWindow per badge. A full-screen transparent
/// overlay window would swallow clicks even on its transparent pixels and block
/// interaction with the windows beneath, so we use small per-badge panels instead.
@MainActor
final class GroupLinkBadgeController {
    /// Invoked when a badge is clicked.
    var onBadgeClick: ((GroupLinkBadge) -> Void)?

    /// One NSWindow per badge, keyed by adjacency key.
    private var windowsByBadge: [AdjacencyKey: NSWindow] = [:]

    init() {}

    /// Update the badge list. Existing badges whose position or state changed are
    /// updated in place; badges that disappeared are faded out before being closed.
    /// Pass a non-nil `fadeOutDuration` to override the fade duration.
    func update(badges: [GroupLinkBadge], fadeOutDuration: TimeInterval? = nil) {
        let newIDs = Set(badges.map { $0.id })
        let duration = fadeOutDuration ?? BadgeStyle.Animation.defaultFadeOut

        // Fade out and close badges that no longer exist.
        for (id, window) in windowsByBadge where !newIDs.contains(id) {
            windowsByBadge.removeValue(forKey: id)
            fadeOutAndClose(window, duration: duration)
        }

        // New or updated badges.
        for badge in badges {
            let origin = CGPoint(
                x: badge.center.x - BadgeStyle.windowSize / 2,
                y: badge.center.y - BadgeStyle.windowSize / 2
            )
            let frame = CGRect(
                origin: origin,
                size: CGSize(width: BadgeStyle.windowSize, height: BadgeStyle.windowSize)
            )

            let isNew: Bool
            let window: NSWindow
            if let existing = windowsByBadge[badge.id] {
                window = existing
                window.setFrame(frame, display: false)
                isNew = false
            } else {
                // An NSPanel with `.nonactivatingPanel` keeps Tiley from becoming the
                // frontmost app when the user clicks the badge. This avoids the
                // "clicking the badge activates Tiley → focus leaves the grouped
                // apps → badges disappear" failure mode.
                let panel = NSPanel(
                    contentRect: frame,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                panel.level = .floating
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.hasShadow = false
                panel.ignoresMouseEvents = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                panel.becomesKeyOnlyIfNeeded = true
                panel.hidesOnDeactivate = false
                panel.isFloatingPanel = true
                panel.worksWhenModal = true
                // Disable the system's default fade-in/fade-out on show/hide:
                // we drive fades ourselves.
                panel.animationBehavior = .none
                // Start at alpha=0 so the fade-in can ramp it up.
                panel.alphaValue = 0
                window = panel
                windowsByBadge[badge.id] = panel
                isNew = true
            }

            let hosting = NSHostingView(rootView: BadgeDot(
                badge: badge,
                onClick: { [weak self] in self?.onBadgeClick?(badge) }
            ))
            hosting.frame = CGRect(origin: .zero, size: frame.size)
            window.contentView = hosting
            window.orderFront(nil)

            if isNew {
                // Fade in.
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = BadgeStyle.Animation.fadeIn
                    window.animator().alphaValue = 1
                }
            } else {
                // Existing badge (state transition only): snap back to fully opaque.
                window.alphaValue = 1
            }
        }
    }

    func hide() {
        let snapshot = windowsByBadge
        windowsByBadge.removeAll()
        for window in snapshot.values {
            fadeOutAndClose(window, duration: BadgeStyle.Animation.defaultFadeOut)
        }
    }

    private func fadeOutAndClose(_ window: NSWindow, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            window.contentView = nil
            window.alphaValue = 1
        })
    }
}

private struct BadgeDot: View {
    let badge: GroupLinkBadge
    let onClick: () -> Void

    @State private var isHovering = false
    /// Tracks whether the mouse has left the badge at least once.
    /// Suppresses the hover presentation immediately after a linked badge appears
    /// (while the cursor is still on top of it) so the `x` icon does not flash
    /// right after linking. **Unlinked badges are not gated** — they should react
    /// on the very first hover.
    @State private var hoverActivated = false

    /// Whether hover effects should actually be shown.
    /// Unlinked: use `isHovering` directly (active from the first hover).
    /// Linked:   `isHovering && hoverActivated` (disabled until the cursor leaves once).
    private var effectiveHover: Bool {
        switch badge.state {
        case .unlinked:
            return isHovering
        case .linked:
            return isHovering && hoverActivated
        }
    }

    private var symbolName: String {
        switch badge.state {
        case .unlinked:
            return "link.badge.plus"
        case .linked:
            return effectiveHover ? "xmark" : "link"
        }
    }

    private var backgroundColor: Color {
        switch badge.state {
        case .unlinked:
            return effectiveHover
                ? Color.accentColor.opacity(BadgeStyle.Opacity.unlinkedBgHover)
                : Color.accentColor.opacity(BadgeStyle.Opacity.unlinkedBgIdle)
        case .linked:
            if effectiveHover {
                return Color.red.opacity(BadgeStyle.Opacity.linkedBgHover)
            }
            // Idle linked badge is intentionally subdued so it doesn't distract.
            return Color.black.opacity(BadgeStyle.Opacity.linkedBgIdle)
        }
    }

    private var foregroundColor: Color {
        // Idle linked icon is also slightly toned down.
        if case .linked = badge.state, !effectiveHover {
            return Color.white.opacity(BadgeStyle.Opacity.linkedForegroundIdle)
        }
        return .white
    }

    /// Stroke color. Subdued when linked and idle.
    private var strokeColor: Color {
        if case .linked = badge.state, !effectiveHover {
            return Color.white.opacity(BadgeStyle.Opacity.linkedStrokeIdle)
        }
        return Color.white.opacity(BadgeStyle.Opacity.activeStroke)
    }

    /// Shadow darkness. Subdued when linked and idle.
    private var shadowOpacity: Double {
        if case .linked = badge.state, !effectiveHover {
            return BadgeStyle.Opacity.linkedShadowIdle
        }
        return BadgeStyle.Opacity.activeShadow
    }

    var body: some View {
        // Compose the Circle + Image inside a ZStack so the shadow has room to
        // render without being clipped by the NSHostingView bounds.
        ZStack {
            Circle()
                .fill(backgroundColor)
                .overlay(Circle().stroke(strokeColor, lineWidth: BadgeStyle.strokeWidth))
                .frame(width: BadgeStyle.visibleDiameter, height: BadgeStyle.visibleDiameter)
                .shadow(
                    color: .black.opacity(shadowOpacity),
                    radius: BadgeStyle.shadowRadius,
                    x: 0,
                    y: BadgeStyle.shadowYOffset
                )
            Image(systemName: symbolName)
                .font(.system(size: BadgeStyle.symbolFontSize, weight: .semibold))
                .foregroundStyle(foregroundColor)
        }
        .frame(width: BadgeStyle.windowSize, height: BadgeStyle.windowSize)
        .contentShape(Circle().inset(by: BadgeStyle.hitAreaInset))
        .scaleEffect(effectiveHover ? BadgeStyle.Animation.hoverScale : 1.0)
        .animation(.easeOut(duration: BadgeStyle.Animation.hoverDuration), value: effectiveHover)
        .onAppear {
            // Suppress hover effects right after appearance (prevents the `x` from
            // flashing immediately after the link is established).
            hoverActivated = false
        }
        .onHover { hovering in
            if !hovering {
                // Allow hover effects once the cursor has left the badge.
                hoverActivated = true
            }
            isHovering = hovering
        }
        .onTapGesture { onClick() }
        .accessibilityLabel(accessibilityLabelText)
    }

    private var accessibilityLabelText: String {
        switch badge.state {
        case .unlinked:
            return NSLocalizedString("Link windows", comment: "Accessibility label for the link-windows badge")
        case .linked:
            return NSLocalizedString("Unlink window group", comment: "Accessibility label for the unlink-window-group badge")
        }
    }
}
