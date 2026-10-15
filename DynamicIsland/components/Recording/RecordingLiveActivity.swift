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

/// Reserves a narrow, symmetric gutter so the main content stays centered on
/// the physical notch. The red dot cannot consume the main surface's hover.
struct RecordingLiveActivity<Content: View>: View {
    let layout: RecordingHUDLayout
    let closedNotchSize: CGSize
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(minWidth: layout.isVisible ? closedNotchSize.width : nil)
            .padding(.horizontal, layout.sideInset)
            // Overlay preserves the primary content's height and alignment.
            // https://developer.apple.com/documentation/swiftui/view/overlay(alignment:content:)
            .overlay(alignment: .topTrailing) {
                if layout.isVisible {
                    RecordingIndicator(showsControls: false)
                        .frame(width: layout.sideInset, height: closedNotchSize.height)
                        .allowsHitTesting(false)
                }
            }
    }
}
