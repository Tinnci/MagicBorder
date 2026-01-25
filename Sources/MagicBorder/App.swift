@preconcurrency import ApplicationServices
import MagicBorderKit
import Observation
import SwiftUI

@main
struct MagicBorderApp: App {
    @State var accessibilityService = MBAccessibilityService()
    @State var inputManager = MBInputManager.shared
    @State var networkManager = MBNetworkManager.shared

    @State private var showSettings = false

    var body: some Scene {
        WindowGroup {
            DashboardView(showSettings: $showSettings)
                .environment(accessibilityService)
                .environment(inputManager)
                .environment(networkManager)
                .onAppear {
                    accessibilityService.startPolling()
                }
        }
    }
}
