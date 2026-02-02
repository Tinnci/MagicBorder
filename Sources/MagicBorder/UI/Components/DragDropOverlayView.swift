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

struct DragDropOverlayView: View {
    let state: MBDragDropState
    let sourceName: String?
    let fileSummary: String?
    let progress: Double?
    let showDevice: Bool
    let showProgress: Bool

    var body: some View {
        VStack(spacing: AppTheme.Layout.smallSpacing) {
            HStack(spacing: AppTheme.Layout.mediumSpacing) {
                Image(systemName: self.state == .dropping ? "tray.and.arrow.down" : "hand.draw")
                    .font(.title3)
                VStack(alignment: .leading, spacing: AppTheme.Layout.tinySpacing) {
                    Text(
                        self.state == .dropping
                            ? MBLocalized("Release to drop") : MBLocalized("Dragging files"))
                        .font(.headline)
                    if self.showDevice, let sourceName, !sourceName.isEmpty {
                        Text(sourceName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if let summary = fileSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if self.showProgress {
                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }
        }
        .padding(AppTheme.Layout.mediumPadding)
        .frame(maxWidth: AppTheme.Layout.dragDropOverlayMaxWidth)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Layout.cornerRadius))
    }
}
