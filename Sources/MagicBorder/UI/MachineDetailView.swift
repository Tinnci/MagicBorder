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
            VStack(spacing: 24) {
                // Header
                HStack(spacing: 16) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue)
                        .symbolRenderingMode(.hierarchical)
                        .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(machine.name)
                            .font(.title)
                            .fontWeight(.semibold)
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
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                // Pinned Programs
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pinned Programs")
                        .font(.headline)
                        .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(0..<8) { i in
                            ProgramIconButton(name: "App \(i+1)", icon: "app.dashed")
                        }
                    }
                    .padding(.horizontal)
                }

                // Configuration Groups
                VStack(alignment: .leading, spacing: 12) {
                    Text("Configuration")
                        .font(.headline)
                        .padding(.horizontal)

                    GroupBox {
                        VStack(spacing: 0) {
                            NavigationLink(destination: Text("Display Settings Content")) {
                                LabeledContent {
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                } label: {
                                    Label("Display Settings", systemImage: "display")
                                }
                            }
                            .padding(.vertical, 8)
                            
                            Divider()

                            NavigationLink(destination: Text("Input Configuration Content")) {
                                LabeledContent {
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                } label: {
                                    Label("Input Configuration", systemImage: "keyboard")
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
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

    var body: some View {
        Button(action: {
            // Mock launch
        }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                Text(name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(8)
        }
        .buttonStyle(.plain)
    }
}
