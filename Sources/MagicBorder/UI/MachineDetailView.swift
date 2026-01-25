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
        Form {
            Section {
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
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section("Pinned Programs") {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(0..<8) { i in
                        ProgramIconButton(name: "App \(i+1)", icon: "app.dashed")
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Configuration") {
                NavigationLink(destination: Text("Display Settings Content")) {
                    Label("Display Settings", systemImage: "display")
                }
                NavigationLink(destination: Text("Input Configuration Content")) {
                    Label("Input Configuration", systemImage: "keyboard")
                }
            }
        }
        .formStyle(.grouped)
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

    var body: some View {
        Button(action: {
            // Mock launch
        }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                    .frame(width: 48, height: 48)

                Text(name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(ProgramIconButtonStyle())
    }
}

struct ProgramIconButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if isHovering || configuration.isPressed {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                }
            }
            .onHover { isHovering = $0 }
    }
}
