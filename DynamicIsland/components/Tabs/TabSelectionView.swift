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
    @StateObject private var quickShareService = QuickShareService.shared
    @Default(.quickShareProvider) private var quickShareProvider
    @State private var showQuickSharePopover = false
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.enableAgentsFeature) private var enableAgentsFeature
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
        var tabsArray: [TabModel] = []

        if homeTabVisible {
            tabsArray.append(TabModel(label: "Home", icon: "house.fill", view: .home))
        }

        if Defaults[.dynamicShelf] {
            tabsArray.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        
        if enableTimerFeature && timerDisplayMode == .tab {
            tabsArray.append(TabModel(label: "Timer", icon: "timer", view: .timer))
        }

        // Stats tab only shown when stats feature is enabled
        if Defaults[.enableStatsFeature] {
            tabsArray.append(TabModel(label: "Stats", icon: "chart.xyaxis.line", view: .stats))
        }

        if enableAgentsFeature {
            tabsArray.append(TabModel(label: "Agents", icon: "sparkles", view: .agents))
        }
        return SavedRowOrder.apply(tabOrder, to: tabsArray, key: \.orderKey)
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
            ensureValidSelection(with: tabs)
        }
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

    private var homeTabVisible: Bool {
        showStandardMediaControls || showCalendar || showMirror
    }

    private func isSelected(_ tab: TabModel) -> Bool {
        coordinator.currentView == tab.view
    }

    private func ensureValidSelection(with tabs: [TabModel]) {
        guard !tabs.isEmpty else { return }
        if tabs.contains(where: { isSelected($0) }) {
            return
        }
        guard let first = tabs.first else { return }
        coordinator.currentView = first.view
    }
}

#Preview {
    DynamicIslandHeader().environmentObject(DynamicIslandViewModel())
}
