import SwiftUI

struct StatusDot: View {
    var active: Bool

    var body: some View {
        Circle()
            .fill(active ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color.secondary.opacity(0.5)))
            .frame(width: 8, height: 8)
    }
}
