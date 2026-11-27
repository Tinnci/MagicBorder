import AppKit
import MagicBorderKit
import SwiftUI

struct PairingCardView: View {
    @Binding var securityKey: String
    @State private var isVisible = false
    @State private var copyMessage: String?
    @State private var copyMessageTask: Task<Void, Never>?

    var maskedKey: String {
        String(repeating: "•", count: self.securityKey.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(localizedString("Security Key"), systemImage: "key.fill")
                    .font(.headline)
                Spacer()
                Button(action: { self.isVisible.toggle() }) {
                    Image(systemName: self.isVisible ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(self.isVisible ? localizedString("Hide") : localizedString("Show"))
            }

            Group {
                if self.isVisible {
                    TextField(localizedString("Security Key"), text: self.$securityKey)
                } else {
                    SecureField(localizedString("Security Key"), text: self.$securityKey)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))

            HStack(spacing: 8) {
                Button(localizedString("Copy")) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(self.securityKey, forType: .string)
                    self.showCopyMessage(localizedString("Copied"))
                }
                .buttonStyle(.bordered)

                Button(localizedString("Regenerate")) {
                    self.securityKey = Self.generatedSecurityKey()
                    self.showCopyMessage(localizedString("New key generated"))
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

    private static func generatedSecurityKey() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(32))
    }

    private func showCopyMessage(_ text: String) {
        self.copyMessage = text
        self.copyMessageTask?.cancel()
        self.copyMessageTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
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
