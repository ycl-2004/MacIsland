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

import Foundation

/// All public state is main-queue owned; sensor work is serialized and coalesced.
final class SystemKeyboardBacklightController {
    static let shared = SystemKeyboardBacklightController()
    var onBacklightChange: ((Float) -> Void)?
    private let workerQueue = DispatchQueue(label: "com.atoll.keyboardBacklight", qos: .userInitiated)
    private var isRunning = false
    private var generation = UUID()
    private var inFlight = false
    private var needsRead = false
    private var pendingLevel: Float?
    private(set) var currentLevel: Float = 0

    private init() {}

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isRunning else { return }
        isRunning = true
        generation = UUID()
        needsRead = true
        drain()
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        isRunning = false
        generation = UUID()
        pendingLevel = nil
        needsRead = false
    }

    func adjust(by delta: Float) { setLevel((pendingLevel ?? currentLevel) + delta) }

    func setLevel(_ value: Float) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isRunning else { return }
        pendingLevel = max(0, min(1, value))
        // Reflect repeated key steps without synchronously querying hardware.
        currentLevel = pendingLevel!
        drain()
    }

    private func drain() {
        guard isRunning, !inFlight, needsRead || pendingLevel != nil else { return }
        inFlight = true
        needsRead = false
        let target = pendingLevel
        pendingLevel = nil
        let expected = generation
        workerQueue.async { [weak self] in
            let result: Result<Float, Error> = Result {
                if let target { try KeyboardBrightnessSensor.setLevel(target) }
                return try KeyboardBrightnessSensor.currentLevel()
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                if self.isRunning, self.generation == expected {
                    switch result {
                    case .success(let level):
                        if self.pendingLevel == nil { self.currentLevel = level }
                        self.onBacklightChange?(level)
                    case .failure:
                        Logger.log("Keyboard backlight is unavailable", category: .warning)
                    }
                }
                self.drain()
            }
        }
    }
}
