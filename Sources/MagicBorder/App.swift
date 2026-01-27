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

    // Computed locale based on preferred languages for swift run compatibility
    private var currentLocale: Locale {
        if let languageCode = Locale.preferredLanguages.first {
            return Locale(identifier: languageCode)
        }
        return .current
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            DashboardView()
                .environment(self.accessibilityService)
                .environment(self.inputManager)
                .environment(self.networkManager)
                .environment(self.overlayPreferences)
                .environment(\.locale, self.currentLocale)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    self.accessibilityService.startPolling()
                    self.syncInputCapture()
                    // Run localization diagnostics when explicitly requested via env var
                    self.logLocalizationDiagnosticsIfNeeded()
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
                .environment(\.locale, self.currentLocale)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("MagicBorder", systemImage: "rectangle.and.cursor.arrow") {
            MenuBarView()
                .environment(self.accessibilityService)
                .environment(self.networkManager)
                .environment(self.overlayPreferences)
                .environment(\.locale, self.currentLocale)
        }
    }

    private func syncInputCapture() {
        let shouldCapture = self.captureInput && self.accessibilityService.isTrusted
        self.inputManager.toggleInterception(shouldCapture)
    }

    private func logLocalizationDiagnosticsIfNeeded() {
        guard ProcessInfo.processInfo.environment["MB_I18N_DEBUG"] == "1" else { return }
        MBLogger.ui.debug("[locale] Preferred Languages: \(Locale.preferredLanguages)")
        print("[locale] Preferred Languages: \(Locale.preferredLanguages)")

        // Log Bundle.main info
        MBLogger.ui.debug("--- Bundle.main ---")
        print("--- Bundle.main ---")
        let mainBundle = Bundle.main
        MBLogger.ui.debug("Preferred Localizations: \(mainBundle.preferredLocalizations)")
        print("Preferred Localizations: \(mainBundle.preferredLocalizations)")
        MBLogger.ui.debug("Localizations in Bundle: \(mainBundle.localizations)")
        print("Localizations in Bundle: \(mainBundle.localizations)")

        let mainLocalizedStrings = mainBundle.paths(forResourcesOfType: "strings", inDirectory: nil)
            .filter { $0.contains("Localizable") }
        if mainLocalizedStrings.isEmpty {
            MBLogger.ui.warning("No Localizable.strings found in main bundle.")
            print("No Localizable.strings found in main bundle.")
        } else {
            MBLogger.ui.debug("Localizable.strings paths: \(mainLocalizedStrings)")
            print("Localizable.strings paths: \(mainLocalizedStrings)")
        }

        // Log Bundle.module info
        MBLogger.ui.debug("--- Bundle.module ---")
        print("--- Bundle.module ---")
        let moduleBundle = Bundle.module
        MBLogger.ui.debug("Preferred Localizations: \(moduleBundle.preferredLocalizations)")
        print("Preferred Localizations: \(moduleBundle.preferredLocalizations)")
        MBLogger.ui.debug("Localizations in Bundle: \(moduleBundle.localizations)")
        print("Localizations in Bundle: \(moduleBundle.localizations)")
        let moduleStrings = moduleBundle.paths(forResourcesOfType: "strings", inDirectory: nil)
            .filter { $0.contains("Localizable") }
        if moduleStrings.isEmpty {
            MBLogger.ui.warning("No Localizable.strings found in module bundle.")
            print("No Localizable.strings found in module bundle.")
        } else {
            MBLogger.ui.debug("Localizable.strings paths: \(moduleStrings)")
            print("Localizable.strings paths: \(moduleStrings)")
        }

        let sampleKey = "Settings"
        let sampleValue = MBLocalized(sampleKey)
        MBLogger.ui.debug("[module] Sample \"\(sampleKey)\": \(sampleValue)")
        print("[module] Sample \"\(sampleKey)\": \(sampleValue)")
    }
}
