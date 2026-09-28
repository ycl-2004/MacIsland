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

import SwiftUI

/// A horizontal row whose items can be dragged sideways to change their order.
///
/// Clicks still reach the items: only a drag past a few points starts a reorder.
/// While dragging, the order lives here so the row never waits on storage; the
/// final order is handed to `onReorder` when the drag ends.
struct ReorderableRow<Item: Hashable, Content: View>: View {
    let items: [Item]
    let spacing: CGFloat
    let onReorder: ([Item]) -> Void
    @ViewBuilder let content: (Item) -> Content

    @State private var liveOrder: [Item]?
    @State private var dragged: Item?
    @State private var offset: CGFloat = 0
    /// How far the dragged item's slot has moved since the drag began, so the
    /// item stays under the pointer as its neighbours swap past it.
    @State private var slotShift: CGFloat = 0
    @State private var widths: [Item: CGFloat] = [:]

    /// Past the ends of the row the item only gives a little, then stops.
    private let edgeGive: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(liveOrder ?? items, id: \.self) { item in
                let isDragged = dragged == item
                content(item)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: ItemWidthsKey<Item>.self, value: [item: proxy.size.width])
                        }
                    }
                    .offset(x: isDragged ? offset : 0)
                    .scaleEffect(isDragged ? 1.12 : 1)
                    .zIndex(isDragged ? 1 : 0)
                    .transaction { if isDragged { $0.animation = nil } }
                    .highPriorityGesture(dragGesture(for: item))
            }
        }
        .animation(.smooth(duration: 0.2), value: liveOrder)
        .onPreferenceChange(ItemWidthsKey<Item>.self) { widths = $0 }
    }

    private func dragGesture(for item: Item) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragged == nil {
                    dragged = item
                    liveOrder = items
                    slotShift = 0
                }
                guard dragged == item, var order = liveOrder, let index = order.firstIndex(of: item) else { return }

                var proposed = value.translation.width - slotShift
                if proposed > 0, index + 1 < order.count {
                    let step = (widths[order[index + 1]] ?? 0) + spacing
                    if proposed > step / 2 {
                        order.swapAt(index, index + 1)
                        slotShift += step
                        proposed -= step
                    }
                } else if proposed < 0, index > 0 {
                    let step = (widths[order[index - 1]] ?? 0) + spacing
                    if -proposed > step / 2 {
                        order.swapAt(index, index - 1)
                        slotShift -= step
                        proposed += step
                    }
                }

                let newIndex = order.firstIndex(of: item) ?? index
                if newIndex == 0 { proposed = max(proposed, -edgeGive) }
                if newIndex == order.count - 1 { proposed = min(proposed, edgeGive) }

                liveOrder = order
                offset = proposed
            }
            .onEnded { _ in
                if let liveOrder, liveOrder != items {
                    onReorder(liveOrder)
                }
                withAnimation(.smooth(duration: 0.2)) {
                    offset = 0
                    dragged = nil
                }
                liveOrder = nil
                slotShift = 0
            }
    }
}

/// Saved drag order for a row whose items come and go with settings. The saved
/// list keeps every item ever placed, so one that is hidden and shown again
/// returns to where it was put.
enum SavedRowOrder {
    /// `items` in their default order, rearranged by `saved`; items `saved` has
    /// never seen follow in their default order.
    static func apply<Item>(_ saved: [String], to items: [Item], key: (Item) -> String) -> [Item] {
        items.enumerated()
            .sorted { lhs, rhs in
                rank(of: key(lhs.element), defaultIndex: lhs.offset, in: saved)
                    < rank(of: key(rhs.element), defaultIndex: rhs.offset, in: saved)
            }
            .map(\.element)
    }

    /// The saved order after the visible items were rearranged into `visible`:
    /// they take over the slots the visible items held, hidden ones keep theirs.
    static func merging(_ visible: [String], into saved: [String]) -> [String] {
        var merged = saved + visible.filter { !saved.contains($0) }
        let visibleSet = Set(visible)
        var next = visible.makeIterator()
        for index in merged.indices where visibleSet.contains(merged[index]) {
            if let key = next.next() {
                merged[index] = key
            }
        }
        return merged
    }

    private static func rank(of key: String, defaultIndex: Int, in saved: [String]) -> Int {
        saved.firstIndex(of: key) ?? saved.count + defaultIndex
    }
}

private struct ItemWidthsKey<Item: Hashable>: PreferenceKey {
    static var defaultValue: [Item: CGFloat] { [:] }

    static func reduce(value: inout [Item: CGFloat], nextValue: () -> [Item: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}
