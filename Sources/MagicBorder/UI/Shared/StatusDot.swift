import SwiftUI

struct StatusDot: View {
    let active: Bool

    var body: some View {
        Image(systemName: "circle.fill")
            .imageScale(.small)
            .foregroundStyle(active ? .green : .secondary)
            .opacity(active ? 1.0 : 0.4)
            .help(active ? "Online" : "Offline")
            .accessibilityLabel(active ? "Online" : "Offline")
    }
}
