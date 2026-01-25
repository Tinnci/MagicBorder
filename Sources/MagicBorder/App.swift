@preconcurrency import ApplicationServices
import MagicBorderKit
import SwiftUI

@main
struct MagicBorderApp: App {
    @StateObject var accessibilityService = AccessibilityService()
    @StateObject var inputManager = InputManager.shared
    @StateObject var networkManager = NetworkManager.shared

    @State private var showSettings = false

    var body: some Scene {
        WindowGroup {
            DashboardView(showSettings: $showSettings)
                .environmentObject(accessibilityService)
                .environmentObject(inputManager)
                .environmentObject(networkManager)
                .onAppear {
                    accessibilityService.startPolling()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
