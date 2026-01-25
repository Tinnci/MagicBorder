/*
 * MagicBorder - A native macOS application for mouse and keyboard sharing.
 * Copyright (C) 2026 MagicBorder Contributors
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

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
