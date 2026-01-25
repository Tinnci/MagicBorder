import MagicBorderKit
import SwiftUI

struct PairingCardView: View {
    @Binding var securityKey: String
    @State private var isVisible = false
    @State private var justCopied = false

    var maskedKey: String {
        String(repeating: "•", count: securityKey.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Security Key", systemImage: "key.fill")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                // Key Display
                HStack {
                    ZStack(alignment: .leading) {
                        if isVisible {
                            TextField("Security Key", text: $securityKey)
                                .textFieldStyle(.plain)
                                .font(.system(.title3, design: .monospaced))
                                .foregroundStyle(.primary)
                                .transition(.opacity)
                        } else {
                            Text(maskedKey)
                                .font(.system(.title3, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                        }
                    }
                    Spacer()

                    // Visibility Toggle
                    Button(action: {
                        withAnimation(.snappy) { isVisible.toggle() }
                    }) {
                        Image(systemName: isVisible ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Material.thick)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .purple.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )

                // Actions
                HStack(spacing: 8) {
                    Button(action: {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(securityKey, forType: .string)

                        withAnimation { justCopied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { justCopied = false }
                        }
                    }) {
                        ZStack {
                            Image(systemName: "doc.on.doc")
                                .opacity(justCopied ? 0 : 1)
                                .scaleEffect(justCopied ? 0.5 : 1)
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                                .opacity(justCopied ? 1 : 0)
                                .scaleEffect(justCopied ? 1 : 0.5)
                        }
                        .font(.title3)
                        .frame(width: 36, height: 36)
                        .background(Material.ultraThin.opacity(0.5))
                        .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy to Clipboard")

                    Button(action: {
                        withAnimation(.bouncy) {
                            securityKey = String(UUID().uuidString.prefix(16))
                        }
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            .background(Material.ultraThin.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Generate New Key")
                }
            }
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Material.regular)

                // Subtle glowing gradient background "bleed"
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
}

#Preview {
    @Previewable @State var key = "1234567890ABCDEF"
    PairingCardView(securityKey: $key)
        .padding()
}
