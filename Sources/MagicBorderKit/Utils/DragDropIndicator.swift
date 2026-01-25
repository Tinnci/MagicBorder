import AppKit
import SwiftUI

public enum MBDragDropState: Sendable {
    case dragging
    case dropping
}

@MainActor
public final class MBDragDropIndicator {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<MBDragDropIndicatorView>?

    public init() {}

    public func show(state: MBDragDropState, sourceName: String?) {
        let view = MBDragDropIndicatorView(state: state, sourceName: sourceName)

        if let hostingView {
            hostingView.rootView = view
        } else {
            let hostingView = NSHostingView(rootView: view)
            self.hostingView = hostingView

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 64),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
            panel.contentView = hostingView
            self.panel = panel
        }

        positionPanel()
        panel?.orderFrontRegardless()
    }

    public func hide() {
        panel?.orderOut(nil)
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let size = panel.frame.size
        let x = screenFrame.midX - (size.width / 2)
        let y = screenFrame.maxY - size.height - 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct MBDragDropIndicatorView: View {
    let state: MBDragDropState
    let sourceName: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state == .dropping ? "tray.and.arrow.down" : "hand.draw")
                .font(.title2)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(state == .dropping ? "Release to drop" : "Dragging file")
                    .font(.headline)
                if let sourceName, !sourceName.isEmpty {
                    Text(sourceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}
