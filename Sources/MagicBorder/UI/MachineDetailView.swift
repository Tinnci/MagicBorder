import MagicBorderKit
import SwiftUI

struct MachineDetailView: View {
    @Environment(MagicBorderKit.MBNetworkManager.self) private var networkManager
    let machine: Machine

    private let columns = [
        GridItem(.adaptive(minimum: 70))
    ]

    @State private var isRefreshing = false

    var body: some View {

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Compact Header
                HStack(spacing: 16) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                        .symbolRenderingMode(.hierarchical)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(machine.name)
                            .font(.title2)
                            .fontWeight(.medium)
                        HStack(spacing: 6) {
                            StatusDot(active: machine.isOnline)
                            Text(machine.isOnline ? "Online" : "Offline")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding()

                Divider()

                // Pinned Programs Grid
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pinned Programs")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(0..<8) { i in
                            ProgramIconButton(name: "App \(i+1)", icon: "app.dashed")
                        }
                    }
                }
                .padding(.horizontal)

                // Quick Links / Configuration
                VStack(alignment: .leading, spacing: 12) {
                    Text("Configuration")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Form {
                        Section {
                            NavigationLink(destination: Text("Display Settings Content")) {
                                Label("Display Settings", systemImage: "display")
                            }
                            NavigationLink(destination: Text("Input Configuration Content")) {
                                Label("Input Configuration", systemImage: "keyboard")
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .frame(height: 160)  // Limit height for embedded form feeling
                    .scrollDisabled(true)
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 20)
        }
        .navigationTitle(machine.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    isRefreshing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        isRefreshing = false
                    }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(
                            isRefreshing
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default, value: isRefreshing)
                }
                .help("Refresh Status")
            }

            ToolbarItem(placement: .status) {
                Button(action: {
                    networkManager.reconnect(machineId: machine.id)
                }) {
                    Label("Restart Connection", systemImage: "restart")
                }
                .help("Restart Connection")
            }

            ToolbarItem(placement: .destructiveAction) {
                Button(action: {
                    networkManager.disconnect(machineId: machine.id)
                }) {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                .help("Disconnect Machine")
            }
        }
    }

}

struct ProgramIconButton: View {
    let name: String
    let icon: String

    @State private var isHovering = false

    var body: some View {
        Button(action: {
            // Mock launch
        }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                    .frame(width: 48, height: 48)
                    .background {
                        if isHovering {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.1))
                        }
                    }

                Text(name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
