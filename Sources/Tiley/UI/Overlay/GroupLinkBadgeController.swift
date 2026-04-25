import AppKit
import SwiftUI

// MARK: - Style constants

/// Visual-style constants for the group-link badge. All magic numbers live here.
private enum BadgeStyle {
    // MARK: Size / shape
    /// Outer NSPanel size when the badge is shown alone (no hover menu).
    static let windowSize: CGFloat = 40
    /// Diameter of the visible circle.
    static let visibleDiameter: CGFloat = 22
    /// Inset for the click area (the visible-diameter circle is centered inside windowSize).
    static let hitAreaInset: CGFloat = (windowSize - visibleDiameter) / 2
    /// Stroke width of the circle outline.
    static let strokeWidth: CGFloat = 1
    /// Font size for the SF Symbol (`link`, `link.badge.plus`).
    static let symbolFontSize: CGFloat = 11
    /// Shadow blur radius.
    static let shadowRadius: CGFloat = 3
    /// Shadow y-offset (downward).
    static let shadowYOffset: CGFloat = 1

    // MARK: Hover menu (linked badges only)
    enum Menu {
        /// Vertical gap between badge and menu pill.
        static let gap: CGFloat = 6
        /// Diameter of each circular action button.
        static let buttonDiameter: CGFloat = 32
        /// Horizontal spacing between buttons inside the pill.
        static let buttonSpacing: CGFloat = 6
        /// Padding around the buttons inside the pill capsule.
        static let pillPadding: CGFloat = 6
        /// Pill width = 2 buttons + spacing + 2× padding.
        static let pillWidth: CGFloat = buttonDiameter * 2 + buttonSpacing + pillPadding * 2
        /// Pill height = 1 button + 2× padding.
        static let pillHeight: CGFloat = buttonDiameter + pillPadding * 2
        /// Total panel width when menu is shown.
        static let panelWidth: CGFloat = max(windowSize, pillWidth)
        /// Total panel height when menu is shown.
        static let panelHeight: CGFloat = windowSize + gap + pillHeight
        /// Font size for the SF Symbol on action buttons.
        static let symbolFontSize: CGFloat = 18
    }

    // MARK: Color / opacity
    enum Opacity {
        // Unlinked state (`link.badge.plus`)
        /// Background (accent color) when unlinked and idle.
        static let unlinkedBgIdle: Double = 0.85
        /// Background (accent color) when unlinked and hovered.
        static let unlinkedBgHover: Double = 0.95

        // Linked state (`link`)
        /// Background (black, subtle) when linked and idle.
        static let linkedBgIdle: Double = 0.25
        /// Background (black) when linked and hovered (slightly darker so the
        /// hover affordance is visible without changing icon/color).
        static let linkedBgHover: Double = 0.55
        /// Icon (white) when linked and idle.
        static let linkedForegroundIdle: Double = 0.6
        /// Stroke (white) when linked and idle.
        static let linkedStrokeIdle: Double = 0.35
        /// Shadow (black) when linked and idle.
        static let linkedShadowIdle: Double = 0.15

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

/// Action emitted by a badge or its hover menu.
enum BadgeAction {
    /// The badge itself was clicked (unlinked → user wants to link).
    case toggleLink
    /// "Ungroup" button in the hover menu.
    case ungroup
    /// "Swap" button in the hover menu.
    case swap
}

/// Where the hover menu is placed relative to the badge.
enum BadgeMenuPlacement {
    case below
    case above
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
    /// Invoked when a badge action is triggered.
    var onBadgeAction: ((GroupLinkBadge, BadgeAction) -> Void)?

    /// One NSWindow per badge, keyed by adjacency key.
    private var windowsByBadge: [AdjacencyKey: NSWindow] = [:]
    /// The most recent `GroupLinkBadge` per id, so hover callbacks can re-render
    /// with the correct content.
    private var badgesByID: [AdjacencyKey: GroupLinkBadge] = [:]
    /// Whether the hover menu is currently shown for a given badge.
    private var hoverShownByID: Set<AdjacencyKey> = []

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
            badgesByID.removeValue(forKey: id)
            hoverShownByID.remove(id)
            fadeOutAndClose(window, duration: duration)
        }

        // New or updated badges.
        for badge in badges {
            badgesByID[badge.id] = badge
            // Drop any stale hover flag for badges that are no longer linked.
            if badge.state != .linked {
                hoverShownByID.remove(badge.id)
            }
            renderBadge(badge, isNewlyCreated: nil)
        }
    }

    func hide() {
        let snapshot = windowsByBadge
        windowsByBadge.removeAll()
        badgesByID.removeAll()
        hoverShownByID.removeAll()
        for window in snapshot.values {
            fadeOutAndClose(window, duration: BadgeStyle.Animation.defaultFadeOut)
        }
    }

    /// Re-render the panel for `badge`. If `isNewlyCreated` is nil, infer based
    /// on whether a panel already exists.
    private func renderBadge(_ badge: GroupLinkBadge, isNewlyCreated explicitNew: Bool?) {
        let showMenu = (badge.state == .linked) && hoverShownByID.contains(badge.id)
        let placement = preferredPlacement(for: badge, showingMenu: showMenu)
        let frame = panelFrame(for: badge, showingMenu: showMenu, placement: placement)

        let isNew: Bool
        let window: NSWindow
        if let existing = windowsByBadge[badge.id] {
            window = existing
            window.setFrame(frame, display: false)
            isNew = explicitNew ?? false
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
            isNew = explicitNew ?? true
        }

        let id = badge.id
        let rootView = BadgeDot(
            badge: badge,
            showMenu: showMenu,
            menuPlacement: placement,
            onTap: { [weak self] in
                self?.onBadgeAction?(badge, .toggleLink)
            },
            onHoverChange: { [weak self] hovering in
                self?.handleHoverChange(id: id, hovering: hovering)
            },
            onUngroup: { [weak self] in
                self?.handleMenuAction(id: id, action: .ungroup)
            },
            onSwap: { [weak self] in
                self?.handleMenuAction(id: id, action: .swap)
            }
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

    private func handleHoverChange(id: AdjacencyKey, hovering: Bool) {
        guard let badge = badgesByID[id], badge.state == .linked else { return }
        let wasShown = hoverShownByID.contains(id)
        if hovering {
            if wasShown { return }
            hoverShownByID.insert(id)
        } else {
            if !wasShown { return }
            hoverShownByID.remove(id)
        }
        renderBadge(badge, isNewlyCreated: false)
    }

    private func handleMenuAction(id: AdjacencyKey, action: BadgeAction) {
        guard let badge = badgesByID[id] else { return }
        // Hide the menu before notifying — the action may rebuild groups and
        // call `update()` with a different badge set; clearing here keeps the
        // hover state consistent.
        hoverShownByID.remove(id)
        onBadgeAction?(badge, action)
    }

    /// Picks `.below` unless the panel would be clipped at the bottom of the
    /// screen containing the badge — in which case it falls back to `.above`.
    private func preferredPlacement(for badge: GroupLinkBadge, showingMenu: Bool) -> BadgeMenuPlacement {
        guard showingMenu else { return .below }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(badge.center) })
            ?? NSScreen.main
        guard let screen else { return .below }
        let frameBelow = panelFrame(for: badge, showingMenu: true, placement: .below)
        if frameBelow.minY < screen.frame.minY {
            return .above
        }
        return .below
    }

    /// Computes the panel frame for the given badge in screen coordinates
    /// (AppKit, bottom-left origin). The badge's circle stays centered on
    /// `badge.center` regardless of menu visibility.
    private func panelFrame(for badge: GroupLinkBadge, showingMenu: Bool, placement: BadgeMenuPlacement) -> CGRect {
        if !showingMenu {
            let origin = CGPoint(
                x: badge.center.x - BadgeStyle.windowSize / 2,
                y: badge.center.y - BadgeStyle.windowSize / 2
            )
            return CGRect(origin: origin, size: CGSize(width: BadgeStyle.windowSize, height: BadgeStyle.windowSize))
        }
        let width = BadgeStyle.Menu.panelWidth
        let height = BadgeStyle.Menu.panelHeight
        let originX = badge.center.x - width / 2
        let originY: CGFloat
        switch placement {
        case .below:
            // Badge sits at the top of the panel; menu hangs below it.
            // badge center y = panel.origin.y + height - windowSize/2.
            originY = badge.center.y - (height - BadgeStyle.windowSize / 2)
        case .above:
            // Badge sits at the bottom of the panel; menu floats above it.
            // badge center y = panel.origin.y + windowSize/2.
            originY = badge.center.y - BadgeStyle.windowSize / 2
        }
        return CGRect(origin: CGPoint(x: originX, y: originY), size: CGSize(width: width, height: height))
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

/// Conditionally attaches the `instantTooltip` to a view. Used so the linked
/// badge can opt out — its tooltip would render below the badge and obscure
/// the hover menu pill that we want the user to interact with.
private struct BadgeTooltipModifier: ViewModifier {
    let text: String
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.instantTooltip(text)
        } else {
            content
        }
    }
}

private struct BadgeDot: View {
    let badge: GroupLinkBadge
    /// When true, the hover menu pill is rendered alongside the badge.
    let showMenu: Bool
    let menuPlacement: BadgeMenuPlacement
    let onTap: () -> Void
    let onHoverChange: (Bool) -> Void
    let onUngroup: () -> Void
    let onSwap: () -> Void

    @State private var isHovering = false

    /// Whether hover effects should actually be shown.
    private var effectiveHover: Bool { isHovering }

    private var symbolName: String {
        switch badge.state {
        case .unlinked:
            return "link.badge.plus"
        case .linked:
            // The badge no longer transitions to an "unlink" icon; the hover
            // menu provides the explicit ungroup affordance instead.
            return "link"
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
                return Color.black.opacity(BadgeStyle.Opacity.linkedBgHover)
            }
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

    private var swapSymbolName: String {
        badge.adjacency.edgeOfA.isHorizontal
            ? "arrow.left.arrow.right.circle"
            : "arrow.up.arrow.down.circle"
    }

    var body: some View {
        Group {
            if showMenu {
                // VStack arranges children top-to-bottom in SwiftUI. In AppKit
                // screen coordinates that means the first child has the higher
                // y. So `{badge, menu}` puts the menu *below* the badge, and
                // `{menu, badge}` puts it above.
                VStack(spacing: BadgeStyle.Menu.gap) {
                    if menuPlacement == .above { menuPill }
                    badgeView
                    if menuPlacement == .below { menuPill }
                }
            } else {
                badgeView
            }
        }
        .frame(
            width: showMenu ? BadgeStyle.Menu.panelWidth : BadgeStyle.windowSize,
            height: showMenu ? BadgeStyle.Menu.panelHeight : BadgeStyle.windowSize
        )
        // Make the entire panel rectangle the hover region so the cursor can
        // travel from the badge into the menu pill without the gap or any
        // transparent padding around the pill killing the hover state.
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            onHoverChange(hovering)
        }
    }

    private var badgeView: some View {
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
        .onTapGesture {
            // Only the unlinked badge is directly clickable. The linked badge
            // exposes its actions through the hover menu instead.
            if case .unlinked = badge.state { onTap() }
        }
        .accessibilityLabel(accessibilityLabelText)
        // Only the unlinked badge shows a tooltip. For linked badges the
        // hover menu is the primary affordance, and a tooltip rendered below
        // the badge would obscure the menu pill itself.
        .modifier(BadgeTooltipModifier(text: badgeTooltipText, enabled: badge.state == .unlinked))
    }

    private var menuPill: some View {
        HStack(spacing: BadgeStyle.Menu.buttonSpacing) {
            menuButton(
                symbol: "xmark.circle.fill",
                tooltip: NSLocalizedString("Ungroup", comment: "Tooltip for the ungroup action button"),
                accessibility: NSLocalizedString("Ungroup", comment: "Accessibility label for the ungroup action button"),
                action: onUngroup
            )
            menuButton(
                symbol: swapSymbolName,
                tooltip: swapTooltipText,
                accessibility: swapTooltipText,
                action: onSwap
            )
        }
        .padding(BadgeStyle.Menu.pillPadding)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.75))
                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 1)
        )
    }

    private func menuButton(symbol: String, tooltip: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: BadgeStyle.Menu.symbolFontSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: BadgeStyle.Menu.buttonDiameter, height: BadgeStyle.Menu.buttonDiameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .instantTooltip(tooltip)
    }

    private var accessibilityLabelText: String {
        switch badge.state {
        case .unlinked:
            return NSLocalizedString("Link windows", comment: "Accessibility label for the link-windows badge")
        case .linked:
            return NSLocalizedString("Window group", comment: "Accessibility label for a linked window-group badge")
        }
    }

    private var badgeTooltipText: String {
        // Only used when state == .unlinked (see BadgeTooltipModifier).
        String(
            format: NSLocalizedString("Group %@ with %@", comment: "Tooltip for the link-windows badge; %@ are window names"),
            badge.titleA,
            badge.titleB
        )
    }

    private var swapTooltipText: String {
        if badge.adjacency.edgeOfA.isHorizontal {
            return NSLocalizedString("Swap left/right windows", comment: "Tooltip for the swap action button on a horizontal window pair")
        } else {
            return NSLocalizedString("Swap top/bottom windows", comment: "Tooltip for the swap action button on a vertical window pair")
        }
    }
}
