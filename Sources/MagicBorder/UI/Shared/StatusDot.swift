import SwiftUI

struct StatusDot: View {
    var active: Bool
    
    @State private var pulse = false
    
    var body: some View {
        Circle()
            .fill(active ? Color.green : Color.red)
            .frame(width: 8, height: 8)
            .shadow(
                color: (active ? Color.green : Color.red).opacity(active ? 0.8 : 0.4),
                radius: active ? 4 : 2
            )
            .overlay {
                if active {
                    Circle()
                        .stroke(Color.green.opacity(0.5))
                        .scaleEffect(pulse ? 2 : 1)
                        .opacity(pulse ? 0 : 1)
                        .onAppear {
                            withAnimation(
                                .easeOut(duration: 1.5).repeatForever(autoreverses: false)
                            ) {
                                pulse = true
                            }
                        }
                }
            }
    }
}
