import SwiftUI

struct StatusDot: View {
    let active: Bool

    var body: some View {
        Circle()
            .fill(self.active ? Color.green : Color.secondary)
            .frame(width: 8, height: 8)
            .opacity(self.active ? 1.0 : 0.4)
            .help(self.active ? localizedString("Online") : localizedString("Offline"))
            .accessibilityLabel(self.active ? localizedString("Online") : localizedString("Offline"))
    }
}
