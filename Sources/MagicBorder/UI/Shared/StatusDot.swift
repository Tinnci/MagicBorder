import SwiftUI

struct StatusDot: View {
    let active: Bool

    var body: some View {
        Circle()
            .fill(active ? Color.green : Color.secondary)
            .frame(width: 8, height: 8)
            .opacity(active ? 1.0 : 0.4)
            .help(active ? "Online" : "Offline")
            .accessibilityLabel(active ? "Online" : "Offline")
    }
}
