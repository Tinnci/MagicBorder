import MagicBorderKit
import SwiftUI

struct PairingCardView: View {
    @Binding var securityKey: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Security Key", systemImage: "key.fill")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                SecureField("Security Key", text: $securityKey)
                    .textFieldStyle(.plain)
                    .font(.system(.title2, design: .monospaced))
                    .padding(12)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(8)
                // Make it visible on toggle? SecureField is usually hidden dots.
                // MWB usually shows it or hides it.
                // Let's use TextField for visibility if user wants to copy, or SecureField toggle.
                // For "Pairs Card" design, usually it's visible or has an eyeicon.
                // Let's simplify: Use TextField but monospaced.

                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(securityKey, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.title2)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .help("Copy to Clipboard")

                Button(action: {
                    // Regenerate Key
                    // In real app, call MWBCrypto.createRandomKey() if we moved it to Logic.
                    // For now, random alphanumeric string.
                    securityKey = String(UUID().uuidString.prefix(16))
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title2)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .help("Generate New Key")
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(radius: 2)
    }
}

#Preview {
    @Previewable @State var key = "1234567890ABCDEF"
    PairingCardView(securityKey: $key)
        .padding()
}
