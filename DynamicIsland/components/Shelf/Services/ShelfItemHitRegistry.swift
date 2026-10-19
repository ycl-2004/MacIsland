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

import AppKit

/// Maps shelf item IDs to the live `NSView` backing each cell.
///
/// Used to verify that native card frames agree with the fixed row geometry.
/// Marquee selection uses ShelfRowLayout for both visible and offscreen cards;
/// this registry intentionally contains only live views and holds them weakly.
@MainActor
final class ShelfItemHitRegistry {
    static let shared = ShelfItemHitRegistry()
    private init() {}

    private final class Box {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }

    private var boxes: [UUID: Box] = [:]

    /// Prunes here too: only tests call `frames(in:)`, and a cell released with
    /// its window never sees `viewDidMoveToWindow(nil)` to unregister.
    func register(_ view: NSView, for id: UUID) {
        boxes = boxes.filter { $0.value.view != nil }
        boxes[id] = Box(view)
    }

    /// Drops the registration only if it still points at `view`. A recycled cell
    /// registers its new ID before the old one unregisters, and without this
    /// check that teardown would evict the fresh entry.
    func unregister(_ id: UUID, view: NSView) {
        guard let existing = boxes[id]?.view else {
            boxes.removeValue(forKey: id)
            return
        }
        if existing === view { boxes.removeValue(forKey: id) }
    }

    /// Frames of the currently-live cells, in `space`'s coordinate system.
    /// Prunes entries whose view has been deallocated.
    func frames(in space: NSView) -> [(id: UUID, frame: NSRect)] {
        var dead: [UUID] = []
        var result: [(id: UUID, frame: NSRect)] = []

        for (id, box) in boxes {
            guard let view = box.view else {
                dead.append(id)
                continue
            }
            guard view.window != nil, view.window === space.window else { continue }
            result.append((id, space.convert(view.bounds, from: view)))
        }

        for id in dead { boxes.removeValue(forKey: id) }
        return result
    }
}
