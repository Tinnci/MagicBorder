import SwiftUI

struct ToastOverlayView: View {
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: self.systemImage)
                .font(.system(size: 28, weight: .semibold))
            Text(self.message)
                .font(.system(size: 18, weight: .medium))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
        .padding(24) // Ensure window is large enough for shadow
        .accessibilityLabel(self.message)
    }
}
