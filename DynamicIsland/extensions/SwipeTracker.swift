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

/// Folds one gesture direction's scroll events into swipes.
///
/// A swipe is the touch phase plus the momentum that follows it, so a quick
/// flick counts in full. It ends only when the momentum does (or a new touch
/// starts): ending it between touch and momentum re-armed the gesture, so one
/// flick skipped two tracks, and dropping momentum instead left flicks too short
/// to open or close the notch.
struct SwipeTracker {
    enum Step: Equatable {
        case report(CGFloat, NSEvent.Phase)
        /// End the swipe after this delay unless another step cancels it.
        case endAfter(TimeInterval)
        case cancelEnd
    }

    /// Momentum follows lifted fingers within a frame or two; wait this long for
    /// it before treating the swipe as over.
    static let momentumGrace: TimeInterval = 0.1
    /// A mouse wheel sends no phases, so its swipe ends after this much quiet.
    static let wheelIdle: TimeInterval = 0.25
    static let noiseThreshold: CGFloat = 0.2

    /// Distance before the swipe starts reporting.
    let threshold: CGFloat
    private(set) var translation: CGFloat = 0
    private(set) var isActive = false
    /// Set once a swipe starts over the notch, so scrolling elsewhere on screen
    /// never reaches the gesture handlers.
    private(set) var isTracking = false

    init(threshold: CGFloat) {
        self.threshold = threshold
    }

    /// One scroll event; `signedDelta` is its movement along this direction.
    mutating func handle(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, signedDelta: CGFloat, isOverNotch: Bool) -> [Step] {
        // A swipe under way still gets its ending, wherever the pointer is.
        if isTracking, momentumPhase.contains(.ended) || momentumPhase.contains(.cancelled) {
            return end().map { [$0] } ?? []
        }
        if isTracking, phase.contains(.ended) || phase.contains(.cancelled) {
            return [.endAfter(Self.momentumGrace)]
        }
        guard isOverNotch else { return [] }

        var steps: [Step] = []
        if phase.contains(.began) || phase.contains(.mayBegin) {
            if let ended = end() { steps.append(ended) }
            steps.append(.cancelEnd)
        } else if !momentumPhase.isEmpty {
            steps.append(.cancelEnd)
        } else if phase.isEmpty {
            steps.append(.endAfter(Self.wheelIdle))
        }
        isTracking = true

        guard signedDelta.magnitude > Self.noiseThreshold else { return steps }
        // Moving back the other way starts the count again.
        translation = signedDelta > 0 ? translation + signedDelta : 0
        if !isActive && translation >= threshold {
            isActive = true
            steps.append(.report(translation, .began))
        } else if isActive {
            steps.append(.report(translation, .changed))
        }
        return steps
    }

    /// Ends the swipe, if one is being tracked, reporting how far it got.
    mutating func end() -> Step? {
        guard isTracking else { return nil }
        defer {
            translation = 0
            isActive = false
            isTracking = false
        }
        return .report(isActive ? translation : 0, .ended)
    }
}
