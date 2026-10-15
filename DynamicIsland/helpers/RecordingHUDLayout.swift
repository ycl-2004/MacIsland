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

import CoreGraphics

/// Recording is a side indicator; it never owns the main HUD or grows on hover.
struct RecordingHUDLayout {
    static let dotDiameter: CGFloat = 6
    static let indicatorInset: CGFloat = 12
    static let maximumExtraWidth = indicatorInset * 2

    let isVisible: Bool

    var sideInset: CGFloat { isVisible ? Self.indicatorInset : 0 }

    func addingIndicator(to size: CGSize) -> CGSize {
        CGSize(width: size.width + sideInset * 2, height: size.height)
    }
}

func makeRecordingHUDLayout(
    notchState: NotchState,
    screenRecordingDetectionEnabled: Bool,
    showRecordingIndicator: Bool,
    hideOnClosed: Bool,
    isRecording: Bool
) -> RecordingHUDLayout {
    RecordingHUDLayout(isVisible: notchState == .closed
        && screenRecordingDetectionEnabled
        && showRecordingIndicator
        && !hideOnClosed
        && isRecording)
}
