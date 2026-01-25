import MagicBorderKit
import SwiftUI

struct PairingCardView: View {
    @Binding var securityKey: String
    @State private var isVisible = false
    @State private var copyMessage: String?

    var maskedKey: String {
        String(repeating: "•", count: securityKey.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Security Key", systemImage: "key.fill")
                    .font(.headline)
                Spacer()
                Button(action: { isVisible.toggle() }) {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(isVisible ? "Hide" : "Show")
            }

            Group {
                if isVisible {
                    TextField("Security Key", text: $securityKey)
                } else {
                    SecureField("Security Key", text: $securityKey)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))

            HStack(spacing: 8) {
                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(securityKey, forType: .string)
                    showCopyMessage("Copied")
                }
                .buttonStyle(.bordered)

                Button("Regenerate") {
                    securityKey = String(UUID().uuidString.prefix(16))
                    showCopyMessage("New key generated")
                }
                .buttonStyle(.bordered)

                if let message = copyMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    private func showCopyMessage(_ text: String) {
        copyMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if copyMessage == text {
                copyMessage = nil
            }
        }
    }
}

#Preview {
    @Previewable @State var key = "1234567890ABCDEF"
    PairingCardView(securityKey: $key)
        .padding()
}
