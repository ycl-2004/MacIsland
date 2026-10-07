/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import SwiftUI
import Combine
import Defaults
import AppKit

struct TabModel: Identifiable, Hashable {
    let label: String
    let icon: String
    let view: NotchViews

    var id: String { "system-\(view)-\(label)" }
    var orderKey: String { String(describing: view) }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.dynamicShelf) private var dynamicShelf
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.enableAgentsFeature) private var enableAgentsFeature
    @Default(.enableExtraSpaceFeature) private var enableExtraSpaceFeature
    @Default(.enableColorPickerFeature) var enableColorPickerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.notchTabOrder) private var tabOrder
    @Namespace var animation
    @State private var agentsNeedYou = false
    @State private var shelfHasItems = false
    
    private var tabs: [TabModel] {
        let labels: [NotchViews: (String, String)] = [
            .home: ("Home", "house.fill"), .shelf: ("Shelf", "tray.fill"),
            .timer: ("Timer", "timer"), .stats: ("Stats", "chart.xyaxis.line"),
            .agents: ("Agents", "sparkles"), .extraSpace: ("Extra Space", "text.alignleft")]
        return NotchTabAvailability.current.tabs.compactMap { view in
            labels[view].map { TabModel(label: $0.0, icon: $0.1, view: view) }
        }
    }
    var body: some View {
        ReorderableRow(items: tabs, spacing: 24 - 2 * TabButton.horizontalPadding, onReorder: { reordered in
            tabOrder = SavedRowOrder.merging(reordered.map(\.orderKey), into: tabOrder)
        }) { tab in
            let isSelected = isSelected(tab)

            TabButton(label: tab.label, icon: tab.icon, selected: isSelected, badge: badge(for: tab.view)) {
                coordinator.currentView = tab.view
            }
            .background {
                if isSelected {
                    Capsule()
                        .fill(.fillControl)
                        .matchedGeometryEffect(id: "capsule", in: animation)
                } else {
                    Capsule()
                        .fill(Color.clear)
                        .matchedGeometryEffect(id: "capsule", in: animation)
                        .hidden()
                }
            }
        }
        .clipShape(Capsule())
        .onAppear {
            coordinator.ensureValidSelection()
        }
        .onChange(of: tabs) { _, _ in coordinator.ensureValidSelection() }
        // Reduced to one Bool each before reaching state, so the row redraws
        // when a dot comes or goes rather than on every session update.
        .onReceive(
            AgentSessionStore.shared.$sessions
                .map { $0.contains { $0.isTerminalSession && $0.isWaitingOnUser } }
                .removeDuplicates()
        ) { agentsNeedYou = $0 }
        .onReceive(
            ShelfStateViewModel.shared.$items
                .map { !$0.isEmpty }
                .removeDuplicates()
        ) { shelfHasItems = $0 }
    }

    /// Agents waiting on you get the attention colour; files resting on the
    /// shelf only get a quiet dot, since they can sit there for days.
    private func badge(for view: NotchViews) -> Color? {
        switch view {
        case .agents: return agentsNeedYou ? .statusAttention : nil
        case .shelf: return shelfHasItems && coordinator.currentView != .shelf ? .inkTertiary : nil
        default: return nil
        }
    }

    private func isSelected(_ tab: TabModel) -> Bool {
        coordinator.currentView == tab.view
    }

}

#Preview {
    DynamicIslandHeader().environmentObject(DynamicIslandViewModel())
}
