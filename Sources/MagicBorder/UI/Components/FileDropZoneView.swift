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

import SwiftUI

struct FileDropZoneView: View {
    var body: some View {
        VStack(spacing: AppTheme.Layout.mediumSpacing) {
            Image(systemName: "tray.and.arrow.up")
                .font(.system(size: AppTheme.Layout.dropZoneIconSize, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(MBLocalized("Drag files here to send"))
                .font(.headline)
            Text(MBLocalized("Supports files and folders"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(AppTheme.Layout.largePadding)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Layout.dropZoneCornerRadius)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Layout.dropZoneCornerRadius)
                        .strokeBorder(
                            Color.accentColor.opacity(0.35), lineWidth: AppTheme.Layout.dropZoneBorderWidth)))
        .shadow(radius: AppTheme.Layout.dropZoneShadowRadius)
        .padding(AppTheme.Layout.extraLargePadding)
    }
}
