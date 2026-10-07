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

struct TabButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: String
    let icon: String
    let selected: Bool
    /// A dot in the tab's corner when something inside wants a look.
    var badge: Color? = nil
    let onClick: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onClick) {
            Image(systemName: icon)
                // Room either side so the selection capsule reads as a pill
                // around the glyph rather than a sliver behind it. The row's
                // spacing gives the same amount back, so glyphs stay as far
                // apart and the row grows only by the padding at its two ends.
                .padding(.horizontal, Self.horizontalPadding)
                .frame(height: 26)
                .contentShape(Capsule())
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Circle()
                            .fill(badge)
                            .frame(width: 5, height: 5)
                            .offset(x: -3, y: 4)
                            .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
                    }
                }
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundStyle(selected ? Color.inkPrimary : isHovering ? .inkSecondary : .inkTertiary)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .notchQuick, value: isHovering)
        .animation(reduceMotion ? nil : .notchStandard, value: badge)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static let horizontalPadding: CGFloat = 5
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        debugLog("Tapped")
    }
}
