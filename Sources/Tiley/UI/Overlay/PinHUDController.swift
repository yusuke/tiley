import AppKit
import SwiftUI

/// A brief, click-through confirmation shown when a window is pinned to or
/// unpinned from all Spaces. Fades out on its own.
@MainActor
final class PinHUDController {
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    private static let visibleDuration: TimeInterval = 1.4
    private static let fadeDuration: TimeInterval = 0.25

    init(title: String, subtitle: String, systemImage: String, icon: NSImage?) {
        let hosting = NSHostingView(rootView: PinHUDView(
            title: title, subtitle: subtitle, systemImage: systemImage, icon: icon
        ))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = hosting
        self.panel = panel
    }

    func show(on screen: NSScreen) {
        guard let panel else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        // Lower third, like the system volume HUD.
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + visible.height * 0.22))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleDuration, execute: work)
    }

    func dismiss() {
        dismissWork?.cancel()
        dismissWork = nil
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}

private struct PinHUDView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let icon: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 36, height: 36)
                }
                Image(systemName: systemImage)
                    .font(.system(size: icon == nil ? 22 : 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(icon == nil ? 0 : 4)
                    .background {
                        if icon != nil { Circle().fill(Color.accentColor) }
                    }
                    .offset(x: icon == nil ? 0 : 4, y: icon == nil ? 0 : 4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: 320, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .fixedSize()
    }
}
