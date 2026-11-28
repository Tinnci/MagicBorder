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
    @State private var controller = MBAppController()

    private var currentLocale: Locale {
        if let languageCode = Locale.preferredLanguages.first {
            return Locale(identifier: languageCode)
        }
        return .current
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            DashboardView()
                .environment(self.controller)
                .environment(self.controller.accessibilityService)
                .environment(self.controller.inputManager)
                .environment(self.controller.networkManager)
                .environment(self.controller.overlayPreferences)
                .environment(\.locale, self.currentLocale)
        }
        .defaultSize(width: 780, height: 580)

        Settings {
            SettingsView()
                .environment(self.controller)
                .environment(self.controller.accessibilityService)
                .environment(self.controller.networkManager)
                .environment(self.controller.overlayPreferences)
                .environment(\.locale, self.currentLocale)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("MagicBorder", systemImage: self.controller.menuBarIconName) {
            MenuBarView()
                .environment(self.controller)
                .environment(self.controller.accessibilityService)
                .environment(self.controller.networkManager)
                .environment(self.controller.overlayPreferences)
                .environment(\.locale, self.currentLocale)
        }
    }
}
