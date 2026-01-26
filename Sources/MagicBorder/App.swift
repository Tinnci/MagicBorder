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

import MagicBorderKit
import SwiftUI

@main
struct MagicBorderApp: App {
    @State private var accessibilityService = MBAccessibilityService()
    @State private var inputManager = MBInputManager.shared
    @State private var networkManager = MBNetworkManager.shared
    @State private var overlayPreferences = MBOverlayPreferencesStore()
    @State private var toastPresenter = MBToastPresenter()
    @AppStorage("captureInput") private var captureInput = true

    var body: some Scene {
        WindowGroup(id: "main") {
            DashboardView()
                .environment(self.accessibilityService)
                .environment(self.inputManager)
                .environment(self.networkManager)
                .environment(self.overlayPreferences)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    self.accessibilityService.startPolling()
                    self.syncInputCapture()
                }
                .onChange(of: self.accessibilityService.isTrusted) { _, _ in
                    self.syncInputCapture()
                }
                .onChange(of: self.captureInput) { _, _ in
                    self.syncInputCapture()
                }
                .onChange(of: self.networkManager.toast) { _, toast in
                    if let toast {
                        self.toastPresenter.show(
                            message: toast.message,
                            systemImage: toast.systemImage)
                    } else {
                        self.toastPresenter.hide()
                    }
                }
        }
        .commands {
            // Add any custom commands if needed, but Settings is standard
        }

        Settings {
            SettingsView()
                .environment(self.accessibilityService)
                .environment(self.networkManager)
                .environment(self.overlayPreferences)
        }

        MenuBarExtra("MagicBorder", systemImage: "rectangle.and.cursor.arrow") {
            MenuBarView()
                .environment(self.accessibilityService)
                .environment(self.networkManager)
                .environment(self.overlayPreferences)
        }
    }

    private func syncInputCapture() {
        let shouldCapture = self.captureInput && self.accessibilityService.isTrusted
        self.inputManager.toggleInterception(shouldCapture)
    }
}
