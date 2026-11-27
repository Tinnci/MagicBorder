import AppKit
import MagicBorderKit
import SwiftUI

struct ConnectionDoctorView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    @Environment(\.dismiss) private var dismiss

    @State private var host: String
    @State private var report: MBConnectionDoctor.Report?
    @State private var isRunning = false
    @State private var copiedFeedback = false

    init(initialHost: String = "") {
        self._host = State(initialValue: initialHost)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    TextField(localizedString("Target IP or Hostname"), text: self.$host)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    Button(localizedString("Run Check")) {
                        Task { await self.runCheck() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(self.isRunning)
                }

                if self.isRunning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(localizedString("Probing network & firewall ports..."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let report {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(report.stages) { stage in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: self.iconName(for: stage.status))
                                        .foregroundStyle(self.color(for: stage.status))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stage.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(self.detail(for: stage.status))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .padding(4)
                    }

                    Text(report.summary)
                        .font(.caption)
                        .foregroundStyle(report.isHealthy ? .green : .orange)
                }

                Spacer()

                HStack {
                    Button(localizedString("Copy Redacted Diagnostics")) {
                        self.copyDiagnostics()
                    }
                    if self.copiedFeedback {
                        Text(localizedString("Copied"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(20)
            .navigationTitle(localizedString("Connection Doctor"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localizedString("Done")) {
                        self.dismiss()
                    }
                }
            }
            .task {
                if !self.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await self.runCheck()
                }
            }
        }
        .frame(width: 480, height: 380)
    }

    private func runCheck() async {
        self.isRunning = true
        self.report = await self.networkManager.runConnectionDoctor(host: self.host)
        self.isRunning = false
    }

    private func copyDiagnostics() {
        var lines: [String] = []
        lines.append("Protocol: \(self.networkManager.protocolMode.rawValue)")
        lines.append("Local IPs: \(self.networkManager.localIPv4Addresses().joined(separator: ", "))")
        if let report = self.report {
            lines.append("Target: \(report.host)")
            lines.append("Summary: \(report.summary)")
        }
        let redactedLogs = self.networkManager.redactedDiagnosticsText()
        if !redactedLogs.isEmpty {
            lines.append("--- Logs ---")
            lines.append(redactedLogs)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
        self.copiedFeedback = true
    }

    private func iconName(for status: MBConnectionDoctor.StageStatus) -> String {
        switch status {
        case .passed: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private func color(for status: MBConnectionDoctor.StageStatus) -> Color {
        switch status {
        case .passed: .green
        case .warning: .orange
        case .failed: .red
        }
    }

    private func detail(for status: MBConnectionDoctor.StageStatus) -> String {
        switch status {
        case .passed(let text), .warning(let text), .failed(let text):
            text
        }
    }
}
