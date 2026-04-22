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
    /// Display name for `adjacency.windowA` (used in tooltip).
    let titleA: String
    /// Display name for `adjacency.windowB` (used in tooltip).
    let titleB: String
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

            // Preserve the existing NSHostingView when we're updating an
            // already-visible badge — updating `rootView` keeps BadgeDot's
            // `@State` alive across updates. Creating a fresh host each time
            // would reset `hoverActivated`, so refreshBadgeOverlays() calls
            // that happen during a user's leave→return gesture would wipe it,
            // and the `x` icon would fail to appear on hover.
            let rootView = BadgeDot(
                badge: badge,
                onClick: { [weak self] in self?.onBadgeClick?(badge) }
            )
            if let existingHost = window.contentView as? NSHostingView<BadgeDot> {
                existingHost.rootView = rootView
                existingHost.frame = CGRect(origin: .zero, size: frame.size)
            } else {
                let hosting = NSHostingView(rootView: rootView)
                hosting.frame = CGRect(origin: .zero, size: frame.size)
                window.contentView = hosting
            }
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
    /// Gate for the linked-state hover presentation.
    /// Defaults to `true` so the very first hover on a linked badge shows the
    /// `x` icon — this matters when a badge appears as linked without the user
    /// being over it (e.g. a newly merged group, or a group becoming visible
    /// when its app comes to the front).
    /// Briefly flipped to `false` only at the moment a badge transitions from
    /// unlinked to linked **while the cursor is still on it** (i.e. right
    /// after the user clicked to group). That suppresses the jarring `x` flash
    /// immediately after a link action. Re-enabled as soon as the cursor
    /// leaves the badge.
    @State private var hoverActivated = true

    /// Whether hover effects should actually be shown.
    /// Unlinked: use `isHovering` directly (active from the first hover).
    /// Linked:   `isHovering && hoverActivated` (gated briefly right after linking).
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
        .onChange(of: badge.state) { _, newState in
            // When a badge transitions unlinked → linked while the cursor is
            // still over it (user just clicked to group), briefly suppress
            // the `x` affordance until the cursor leaves. Prevents the jarring
            // flash from "link" to "x" right after a link click.
            // If the state changed to linked without the user hovering (e.g.
            // via a merge or via the owning app coming to the front), leave
            // `hoverActivated` alone so the first hover still shows `x`.
            if newState == .linked && isHovering {
                hoverActivated = false
            }
        }
        .onHover { hovering in
            if !hovering {
                // Any time the cursor leaves, re-arm hover effects.
                hoverActivated = true
            }
            isHovering = hovering
        }
        .onTapGesture { onClick() }
        .accessibilityLabel(accessibilityLabelText)
        .instantTooltip(tooltipText)
    }

    private var accessibilityLabelText: String {
        switch badge.state {
        case .unlinked:
            return NSLocalizedString("Link windows", comment: "Accessibility label for the link-windows badge")
        case .linked:
            return NSLocalizedString("Unlink window group", comment: "Accessibility label for the unlink-window-group badge")
        }
    }

    private var tooltipText: String {
        switch badge.state {
        case .unlinked:
            return String(
                format: NSLocalizedString("Group %@ with %@", comment: "Tooltip for the link-windows badge; %@ are window names"),
                badge.titleA,
                badge.titleB
            )
        case .linked:
            return NSLocalizedString("Ungroup", comment: "Tooltip for the unlink-window-group badge")
        }
    }
}
