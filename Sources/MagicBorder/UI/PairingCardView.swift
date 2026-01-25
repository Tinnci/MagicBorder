import MagicBorderKit
import SwiftUI

struct PairingCardView: View {
    @Binding var securityKey: String
    @State private var isVisible = false
    @State private var copyMessage: String?

    var maskedKey: String {
        String(repeating: "•", count: self.securityKey.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Security Key", systemImage: "key.fill")
                    .font(.headline)
                Spacer()
                Button(action: { self.isVisible.toggle() }) {
                    Image(systemName: self.isVisible ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(self.isVisible ? "Hide" : "Show")
            }

            Group {
                if self.isVisible {
                    TextField("Security Key", text: self.$securityKey)
                } else {
                    SecureField("Security Key", text: self.$securityKey)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))

            HStack(spacing: 8) {
                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(self.securityKey, forType: .string)
                    self.showCopyMessage("Copied")
                }
                .buttonStyle(.bordered)

                Button("Regenerate") {
                    self.securityKey = String(UUID().uuidString.prefix(16))
                    self.showCopyMessage("New key generated")
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
        self.copyMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.copyMessage == text {
                self.copyMessage = nil
            }
        }
    }
}

#Preview {
    @Previewable @State var key = "1234567890ABCDEF"
    PairingCardView(securityKey: $key)
        .padding()
}
