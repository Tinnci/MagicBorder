import AppKit
import MagicBorderKit
import SwiftUI

@MainActor
final class MBDragDropOverlayPresenter {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?

    func show(
        state: MBDragDropState,
        sourceName: String?,
        fileSummary: String?,
        progress: Double?,
        preferences: MBOverlayPreferences
    ) {
        let overlay = AnyView(
            DragDropOverlayView(
                state: state,
                sourceName: sourceName,
                fileSummary: fileSummary,
                progress: progress,
                showDevice: preferences.showDevice,
                showProgress: preferences.showProgress
            )
            .scaleEffect(preferences.scale)
            .padding(20))

        if self.panel == nil {
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true)
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.hasShadow = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

            let hosting = NSHostingView(rootView: overlay)
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentView = hosting

            self.panel = panel
            self.hostingView = hosting
        } else {
            self.hostingView?.rootView = overlay
        }

        guard let panel = self.panel, let hosting = self.hostingView else { return }
        let targetSize = hosting.fittingSize
        let size = CGSize(width: max(240, targetSize.width), height: max(84, targetSize.height))
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let origin = Self.origin(for: preferences.position, in: screenFrame, size: size)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFront(nil)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel = self.panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
            }
        }
    }

    private static func origin(for position: MBOverlayPosition, in frame: CGRect, size: CGSize) -> CGPoint {
        let inset: CGFloat = 20
        let x: CGFloat =
            switch position {
            case .topLeading, .bottomLeading:
                frame.minX + inset
            case .topTrailing, .bottomTrailing:
                frame.maxX - size.width - inset
            case .top, .bottom:
                frame.midX - size.width / 2
            }
        let y: CGFloat =
            switch position {
            case .top, .topLeading, .topTrailing:
                frame.maxY - size.height - inset
            case .bottom, .bottomLeading, .bottomTrailing:
                frame.minY + inset
            }
        return CGPoint(x: x, y: y)
    }
}
