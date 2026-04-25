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
        /// Pill width for the given number of action buttons:
        ///   N buttons + (N-1)× spacing + 2× padding.
        static func pillWidth(buttonCount: Int) -> CGFloat {
            let n = max(1, buttonCount)
            return buttonDiameter * CGFloat(n)
                + buttonSpacing * CGFloat(n - 1)
                + pillPadding * 2
        }
        /// Pill height = 1 button + 2× padding.
        static let pillHeight: CGFloat = buttonDiameter + pillPadding * 2
        /// Total panel width when the menu is shown for `buttonCount` buttons.
        static func panelWidth(buttonCount: Int) -> CGFloat {
            max(windowSize, pillWidth(buttonCount: buttonCount))
        }
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
        /// Fade-in duration of the hover-menu pill when it appears.
        static let menuFadeIn: TimeInterval = 0.16
        /// Fade-out duration of the hover-menu pill when it disappears.
        /// The NSPanel is kept at its expanded size for this same duration so
        /// the pill isn't visually clipped mid-fade.
        static let menuFadeOut: TimeInterval = 0.16
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
    /// "Match window extents" button in the hover menu — grows the smaller
    /// window's perpendicular extent (height for L/R pairs, width for T/B
    /// pairs) so both windows span the same outer envelope along that axis.
    case matchExtents
    /// "Fill screen width" button in the hover menu — proportionally scales
    /// every window in the group along the X axis so the group's bounding
    /// box spans the screen's visible width (Dock / menu bar excluded).
    case fillScreenWidth
    /// "Fill screen height" button in the hover menu — proportionally scales
    /// every window in the group along the Y axis so the group's bounding
    /// box spans the screen's visible height (Dock / menu bar excluded).
    case fillScreenHeight
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
    /// True when the two windows differ in their perpendicular-axis extent
    /// (vertical span for left/right pairs, horizontal span for top/bottom
    /// pairs), so the "match window heights/widths" hover-menu button has
    /// something to do. When false, that third button is hidden because the
    /// extents already line up.
    let canMatchExtents: Bool
    /// True when the group's bounding box doesn't yet span the screen's
    /// visible width — surfaces the "fill screen width" button.
    let canFillScreenWidth: Bool
    /// True when the group's bounding box doesn't yet span the screen's
    /// visible height — surfaces the "fill screen height" button.
    let canFillScreenHeight: Bool
}

extension GroupLinkBadge {
    /// Number of buttons rendered inside the linked-state hover pill.
    /// Ungroup + Swap are always present; the three remaining buttons
    /// (match-extents, fill-width, fill-height) are conditional.
    var menuButtonCount: Int {
        var count = 2
        if canMatchExtents { count += 1 }
        if canFillScreenWidth { count += 1 }
        if canFillScreenHeight { count += 1 }
        return count
    }
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
    /// Whether the hover-menu pill is currently *visible* for a given badge.
    /// Drives the SwiftUI opacity animation. Cleared on hover-exit immediately
    /// so the pill begins fading out.
    private var hoverShownByID: Set<AdjacencyKey> = []
    /// Whether the NSPanel is currently sized to fit the menu pill. Kept set
    /// for `Animation.menuFadeOut` after the pill starts fading so the panel
    /// doesn't shrink and clip the still-fading pill mid-animation.
    private var panelExpandedByID: Set<AdjacencyKey> = []
    /// Pending "shrink the panel after fade-out" tasks, keyed by badge id, so
    /// a re-hover during fade-out can cancel the shrink.
    private var pendingPanelShrinkByID: [AdjacencyKey: DispatchWorkItem] = [:]

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
            panelExpandedByID.remove(id)
            pendingPanelShrinkByID.removeValue(forKey: id)?.cancel()
            fadeOutAndClose(window, duration: duration)
        }

        // New or updated badges.
        for badge in badges {
            badgesByID[badge.id] = badge
            // Drop any stale hover flag for badges that are no longer linked.
            if badge.state != .linked {
                hoverShownByID.remove(badge.id)
                panelExpandedByID.remove(badge.id)
                pendingPanelShrinkByID.removeValue(forKey: badge.id)?.cancel()
            } else if hoverShownByID.contains(badge.id) {
                // Hover (or click-to-link) requested the menu — make sure the
                // panel size flag tracks it so the pill has room to render.
                panelExpandedByID.insert(badge.id)
                pendingPanelShrinkByID.removeValue(forKey: badge.id)?.cancel()
            }
            renderBadge(badge, isNewlyCreated: nil)
        }
    }

    func hide() {
        let snapshot = windowsByBadge
        windowsByBadge.removeAll()
        badgesByID.removeAll()
        hoverShownByID.removeAll()
        panelExpandedByID.removeAll()
        for (_, work) in pendingPanelShrinkByID { work.cancel() }
        pendingPanelShrinkByID.removeAll()
        for window in snapshot.values {
            fadeOutAndClose(window, duration: BadgeStyle.Animation.defaultFadeOut)
        }
    }

    /// Re-render the panel for `badge`. If `isNewlyCreated` is nil, infer based
    /// on whether a panel already exists.
    private func renderBadge(_ badge: GroupLinkBadge, isNewlyCreated explicitNew: Bool?) {
        // `panelExpanded` drives panel sizing (kept set during fade-out so the
        // pill has room to fade gracefully). `pillVisible` drives the SwiftUI
        // opacity animation of the pill itself.
        let panelExpanded = (badge.state == .linked) && panelExpandedByID.contains(badge.id)
        let pillVisible = (badge.state == .linked) && hoverShownByID.contains(badge.id)
        let placement = preferredPlacement(for: badge, showingMenu: panelExpanded)
        let frame = panelFrame(for: badge, showingMenu: panelExpanded, placement: placement)

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
            showMenu: panelExpanded,
            pillVisible: pillVisible,
            menuPlacement: placement,
            onTap: { [weak self] in
                // Pre-mark the badge as panel-expanded so the rebuilt
                // `.linked` badge enters the view tree with the menu pill
                // already in place — but at opacity 0. We then flip
                // `hoverShownByID` on the next runloop so the pill fades in
                // (same two-phase trick as `handleHoverChange`). Without the
                // gap, the pill would render at opacity 1 from the start
                // and no transition would play.
                guard let self else { return }
                self.panelExpandedByID.insert(id)
                self.pendingPanelShrinkByID.removeValue(forKey: id)?.cancel()
                self.onBadgeAction?(badge, .toggleLink)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard let current = self.badgesByID[id], current.state == .linked else { return }
                    guard self.panelExpandedByID.contains(id) else { return }
                    if !self.hoverShownByID.contains(id) {
                        self.hoverShownByID.insert(id)
                        self.renderBadge(current, isNewlyCreated: false)
                    }
                }
            },
            onHoverChange: { [weak self] hovering in
                self?.handleHoverChange(id: id, hovering: hovering)
            },
            onUngroup: { [weak self] in
                self?.handleMenuAction(id: id, action: .ungroup)
            },
            onSwap: { [weak self] in
                self?.handleMenuAction(id: id, action: .swap)
            },
            onMatchExtents: { [weak self] in
                self?.handleMenuAction(id: id, action: .matchExtents)
            },
            onFillScreenWidth: { [weak self] in
                self?.handleMenuAction(id: id, action: .fillScreenWidth)
            },
            onFillScreenHeight: { [weak self] in
                self?.handleMenuAction(id: id, action: .fillScreenHeight)
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
            // Cancel any in-flight shrink — the user came back before the
            // fade-out finished.
            pendingPanelShrinkByID.removeValue(forKey: id)?.cancel()
            if wasShown && panelExpandedByID.contains(id) { return }
            // Two-phase render so the fade-in actually plays:
            //   1. Render the panel at expanded size with the pill in the
            //      view tree but at opacity 0 (pillVisible=false).
            //   2. Next runloop turn, flip pillVisible to true so SwiftUI's
            //      `.animation(value: pillVisible)` sees the change and
            //      animates opacity 0 → 1. (Without phase 1 the pill would
            //      enter the tree already at opacity 1 and no transition
            //      would play.)
            panelExpandedByID.insert(id)
            renderBadge(badge, isNewlyCreated: false)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Cursor may have left during the gap, or the badge may have
                // gone away entirely.
                guard let current = self.badgesByID[id], current.state == .linked else { return }
                guard self.panelExpandedByID.contains(id) else { return }
                if !self.hoverShownByID.contains(id) {
                    self.hoverShownByID.insert(id)
                    self.renderBadge(current, isNewlyCreated: false)
                }
            }
        } else {
            if !wasShown { return }
            // Hide the pill immediately (SwiftUI fades opacity to 0); keep the
            // panel at its expanded size for `menuFadeOut` so the pill isn't
            // clipped, then collapse the panel.
            hoverShownByID.remove(id)
            renderBadge(badge, isNewlyCreated: false)
            pendingPanelShrinkByID.removeValue(forKey: id)?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingPanelShrinkByID.removeValue(forKey: id)
                // Don't shrink if the user re-hovered (or clicked → linked) in
                // the meantime.
                guard !self.hoverShownByID.contains(id) else { return }
                guard let current = self.badgesByID[id] else { return }
                self.panelExpandedByID.remove(id)
                self.renderBadge(current, isNewlyCreated: false)
            }
            pendingPanelShrinkByID[id] = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + BadgeStyle.Animation.menuFadeOut,
                execute: work
            )
        }
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
        let width = BadgeStyle.Menu.panelWidth(buttonCount: badge.menuButtonCount)
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
    /// When true, the panel is sized to fit the menu pill and the pill is
    /// laid out alongside the badge. The pill's *visual opacity* is driven
    /// independently by `pillVisible` so it can fade out before the panel
    /// collapses back to the badge-only size.
    let showMenu: Bool
    /// When true, the pill renders fully opaque; when false it animates to
    /// transparent. Independent from `showMenu` so the panel can keep its
    /// expanded size for the duration of the fade-out.
    let pillVisible: Bool
    let menuPlacement: BadgeMenuPlacement
    let onTap: () -> Void
    let onHoverChange: (Bool) -> Void
    let onUngroup: () -> Void
    let onSwap: () -> Void
    let onMatchExtents: () -> Void
    let onFillScreenWidth: () -> Void
    let onFillScreenHeight: () -> Void

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

    /// SF Symbol for the "match extents" button. Points perpendicular to the
    /// adjacency axis: a horizontal-edge pair (windows side-by-side) is
    /// equalised along the *vertical* axis, so the icon shows up/down arrows;
    /// a vertical-edge pair is equalised along the *horizontal* axis.
    private var matchExtentsSymbolName: String {
        badge.adjacency.edgeOfA.isHorizontal
            ? "arrow.up.and.down.circle"
            : "arrow.left.and.right.circle"
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
            width: showMenu ? BadgeStyle.Menu.panelWidth(buttonCount: badge.menuButtonCount) : BadgeStyle.windowSize,
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
        menuPillContent
            .opacity(pillVisible ? 1 : 0)
            .animation(
                .easeOut(duration: pillVisible
                         ? BadgeStyle.Animation.menuFadeIn
                         : BadgeStyle.Animation.menuFadeOut),
                value: pillVisible
            )
            // Suppress hit-testing when invisible so a fading-out pill doesn't
            // catch button presses or block clicks on whatever is underneath.
            .allowsHitTesting(pillVisible)
    }

    private var menuPillContent: some View {
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
            if badge.canMatchExtents {
                menuButton(
                    symbol: matchExtentsSymbolName,
                    tooltip: matchExtentsTooltipText,
                    accessibility: matchExtentsTooltipText,
                    action: onMatchExtents
                )
            }
            if badge.canFillScreenWidth {
                menuButton(
                    symbol: "rectangle.portrait.arrowtriangle.2.outward",
                    tooltip: fillScreenWidthTooltipText,
                    accessibility: fillScreenWidthTooltipText,
                    action: onFillScreenWidth
                )
            }
            if badge.canFillScreenHeight {
                menuButton(
                    symbol: "rectangle.arrowtriangle.2.outward",
                    tooltip: fillScreenHeightTooltipText,
                    accessibility: fillScreenHeightTooltipText,
                    action: onFillScreenHeight
                )
            }
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

    private var matchExtentsTooltipText: String {
        if badge.adjacency.edgeOfA.isHorizontal {
            return NSLocalizedString("Match window heights", comment: "Tooltip for the match-extents action button on a horizontal (left/right) window pair — both windows grow vertically to span the outer envelope")
        } else {
            return NSLocalizedString("Match window widths", comment: "Tooltip for the match-extents action button on a vertical (top/bottom) window pair — both windows grow horizontally to span the outer envelope")
        }
    }

    private var fillScreenWidthTooltipText: String {
        NSLocalizedString("Fill screen width", comment: "Tooltip for the hover-menu button that scales the window group horizontally to span the screen's visible width (Dock and menu bar excluded)")
    }

    private var fillScreenHeightTooltipText: String {
        NSLocalizedString("Fill screen height", comment: "Tooltip for the hover-menu button that scales the window group vertically to span the screen's visible height (Dock and menu bar excluded)")
    }
}
