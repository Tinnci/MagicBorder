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
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                // Standard Header
                HStack(spacing: 16) {
                    Image(systemName: "desktopcomputer")
                        .font(.largeTitle)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(machine.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        HStack(spacing: 6) {
                            StatusDot(active: machine.isOnline)
                            Text(machine.isOnline ? "Online" : "Offline")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

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
                .padding()

                // Quick Links / Configuration
                VStack(alignment: .leading, spacing: 16) {
                    Text("Configuration")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    GroupBox {
                        VStack(spacing: 0) {
                            NavigationLink(destination: Text("Display Settings Content")) {
                                LinkRow(title: "Display Settings", icon: "display")
                            }
                            Divider()
                            NavigationLink(destination: Text("Input Configuration Content")) {
                                LinkRow(title: "Input Configuration", icon: "keyboard")
                            }
                        }
                    }
                }
                .padding()
            }
            Spacer()

            // Bottom Toolbar Divider
            Divider()

            HStack {
                Button(action: {
                    networkManager.reconnect(machineId: machine.id)
                }) {
                    Label("Restart", systemImage: "restart")
                }
                .buttonStyle(.plain)
                .help("Restart connection")

                Button(action: {
                    networkManager.disconnect(machineId: machine.id)
                }) {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                .buttonStyle(.plain)
                .help("Disconnect machine")

                Spacer()

                Button(action: {
                    isRefreshing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        isRefreshing = false
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(
                            isRefreshing
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default, value: isRefreshing)
                }
                .buttonStyle(.plain)
                .help("Refresh Status")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Material.bar)
        }
        .navigationTitle(machine.name)
    }
}

struct ProgramIconButton: View {
    let name: String
    let icon: String
    @State private var isHovering = false

    var body: some View {
        VStack {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.1) : Color.primary.opacity(0.05))
                    .frame(width: 60, height: 60)

                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
            Text(name)
                .font(.caption2)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .onHover { isHovering = $0 }
        .onTapGesture {
            // Mock animation for app launch
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {

            }
        }
    }
}

struct LinkRow: View {
    let title: String
    let icon: String

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}
