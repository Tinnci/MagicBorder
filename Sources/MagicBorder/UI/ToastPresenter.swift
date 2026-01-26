import AppKit
import SwiftUI

@MainActor
final class MBToastPresenter {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<ToastOverlayView>?

    func show(message: String, systemImage: String) {
        let view = ToastOverlayView(message: message, systemImage: systemImage)

        if panel == nil {
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true)
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.hasShadow = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

            let hostingView = NSHostingView(rootView: view)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            panel.contentView = hostingView

            self.panel = panel
            self.hostingView = hostingView
        } else {
            self.hostingView?.rootView = view
        }

        guard let panel, let hostingView else { return }

        let targetSize = hostingView.fittingSize
        let size = CGSize(width: max(220, targetSize.width), height: max(44, targetSize.height))
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let origin = CGPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2)

        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFront(nil)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }
}
