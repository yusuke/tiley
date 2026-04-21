import AppKit
import SwiftUI

/// バッジの視覚状態。
enum GroupLinkBadgeState {
    case unlinked      // 未グループ化：`link.badge.plus`
    case linked        // グループ化済：`link`
}

/// 1つのバッジを表す。
struct GroupLinkBadge: Identifiable {
    let id: AdjacencyKey
    let state: GroupLinkBadgeState
    /// AppKit 画面座標（bottom-left 原点）でのバッジ中心。
    let center: CGPoint
    let adjacency: WindowAdjacency
}

/// 接するウインドウペアの中央に `link.badge.plus` / `link` バッジを表示する
/// フローティングオーバーレイ。
///
/// **設計**: バッジごとに独立した小さな NSWindow を使う。
/// フルスクリーンの透過ウインドウ方式では、透過部分もマウスクリックを吸収してしまい、
/// 下のウインドウ操作ができなくなる問題があったため、個別の小ウインドウ方式とした。
@MainActor
final class GroupLinkBadgeController {
    /// バッジがクリックされたときに呼ばれる。
    var onBadgeClick: ((GroupLinkBadge) -> Void)?

    /// 各バッジの NSWindow。adjacency key でキー付け。
    private var windowsByBadge: [AdjacencyKey: NSWindow] = [:]

    private let badgeSize: CGFloat = 40

    init() {}

    /// デフォルトのフェードアウト時間（5 秒タイムアウト・隣接喪失時）。
    private let defaultFadeOutDuration: TimeInterval = 0.25
    /// ドラッグ/リサイズ開始時のフェードアウト時間。
    private let fastFadeOutDuration: TimeInterval = 0.15
    /// 新規バッジ出現時のフェードイン時間。
    private let fadeInDuration: TimeInterval = 0.15

    /// バッジ一覧を更新する。既存のバッジは位置・状態が変わっていれば更新、
    /// 消えたバッジはフェードアウトしてから閉じる。
    /// `fadeOutDuration` を nil 以外にするとフェード時間を上書きできる。
    func update(badges: [GroupLinkBadge], fadeOutDuration: TimeInterval? = nil) {
        let newIDs = Set(badges.map { $0.id })
        let duration = fadeOutDuration ?? defaultFadeOutDuration

        // 消えたバッジを**フェードアウト**して閉じる。
        for (id, window) in windowsByBadge where !newIDs.contains(id) {
            windowsByBadge.removeValue(forKey: id)
            fadeOutAndClose(window, duration: duration)
        }

        // 新規・更新。
        for badge in badges {
            let origin = CGPoint(
                x: badge.center.x - badgeSize / 2,
                y: badge.center.y - badgeSize / 2
            )
            let frame = CGRect(origin: origin, size: CGSize(width: badgeSize, height: badgeSize))

            let isNew: Bool
            let window: NSWindow
            if let existing = windowsByBadge[badge.id] {
                window = existing
                window.setFrame(frame, display: false)
                isNew = false
            } else {
                // NSPanel with `.nonactivatingPanel` は、ユーザーがクリックしても
                // Tiley 自身が frontmost にならない。これにより「バッジをクリック
                // した瞬間、Tiley がアクティブ化してグループメンバーのアプリから
                // フォーカスが離れ、badges が非表示になる」問題を回避する。
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
                // 表示/非表示時のシステムデフォルトのフェードアニメーションを無効化。
                // （フェードイン・フェードアウトは自前で制御。）
                panel.animationBehavior = .none
                // 新規作成時は alpha=0 から開始してフェードインさせる。
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
                // フェードイン。
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = fadeInDuration
                    window.animator().alphaValue = 1
                }
            } else {
                // 既存バッジ（状態遷移のみ）は即座に不透明に戻す。
                window.alphaValue = 1
            }
        }
    }

    func hide() {
        let snapshot = windowsByBadge
        windowsByBadge.removeAll()
        for window in snapshot.values {
            fadeOutAndClose(window, duration: defaultFadeOutDuration)
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
    /// 「少なくとも一度マウスがバッジの外に出た」ことを示す。
    /// バッジ出現直後の（ユーザーのマウスがまだバッジ上にある状態での）ホバー表示を抑制し、
    /// リンク直後に `x` アイコンが即座に現れてしまう問題を防ぐ。
    @State private var hoverActivated = false

    /// 実際にホバー効果を表示すべきか。
    private var effectiveHover: Bool { isHovering && hoverActivated }

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
            return effectiveHover ? Color.accentColor.opacity(0.95) : Color.accentColor.opacity(0.85)
        case .linked:
            if effectiveHover {
                return Color.red.opacity(0.85)
            }
            return Color.black.opacity(0.55)
        }
    }

    private var foregroundColor: Color { .white }

    var body: some View {
        // ZStack で Circle + Image を組み合わせ、外側の 40×40 フレーム内でシャドウが
        // 見切れないようにする（NSHostingView の clip 境界に当たらないよう余裕を持たせる）。
        ZStack {
            Circle()
                .fill(backgroundColor)
                .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(foregroundColor)
        }
        .frame(width: 40, height: 40)
        .contentShape(Circle().inset(by: 9))  // 円形の中央 22pt のみをクリック領域に
        .scaleEffect(effectiveHover ? 1.12 : 1.0)
        .animation(.easeOut(duration: 0.12), value: effectiveHover)
        .onAppear {
            // 出現直後はホバー効果を抑制する（リンク直後の即 x 表示を防ぐ）。
            hoverActivated = false
        }
        .onHover { hovering in
            if !hovering {
                // マウスが一度外に出たらホバー効果を解禁する。
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
