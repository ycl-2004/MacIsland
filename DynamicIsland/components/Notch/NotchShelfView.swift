/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Defaults
import SwiftUI

struct NotchShelfView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Default(.shelfFileDropEnabled) private var fileDropEnabled
    @Default(.shelfAirDropEnabled) private var airDropEnabled
    @Default(.enableFileConvertFeature) private var convertEnabled

    var body: some View {
        GeometryReader { geometry in
            let filePanelCount = (fileDropEnabled ? 1 : 0) + (convertEnabled ? 1 : 0)
            let workspaceWidth = max(0, geometry.size.width - (airDropEnabled ? geometry.size.height + 12 : 0))
            let panelWidth = filePanelCount == 2 ? max(0, (workspaceWidth - 12) / 2) : workspaceWidth

            HStack(spacing: 12) {
                if airDropEnabled {
                    FileShareView()
                        .frame(width: geometry.size.height)
                }
                if fileDropEnabled {
                    ShelfView()
                        .frame(width: panelWidth)
                }
                if convertEnabled {
                    NotchFileConvertView()
                        .frame(width: panelWidth)
                }
                if !airDropEnabled && filePanelCount == 0 {
                    VStack(spacing: 10) {
                        Text("Choose your Shelf tools")
                            .font(.notch(.body, weight: .medium))
                            .foregroundStyle(.inkSecondary)
                        Button("Configure Shelf") {
                            SettingsWindowController.shared.showWindow(tab: "shelf")
                        }
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onChange(of: fileDropEnabled) { _, enabled in
            if !enabled { vm.dragDetectorTargeting = false }
        }
        .onChange(of: airDropEnabled) { _, enabled in
            if !enabled { vm.dropZoneTargeting = false }
        }
        .onChange(of: convertEnabled) { _, enabled in
            if !enabled { vm.convertDropTargeting = false }
        }
    }
}

