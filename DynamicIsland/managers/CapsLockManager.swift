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
import Combine
import AppKit
import SwiftUI

@MainActor
class CapsLockManager: ObservableObject {
    static let shared = CapsLockManager()
    
    /// Caps Lock is a persistent state, not a transient HUD: ContentView renders the
    /// closed-notch indicator straight from this flag. It must not go through an
    /// infinite sneak peek, which covered the open notch's tab header and could stay
    /// stuck on when the setting was toggled while Caps Lock was active.
    @Published var isCapsLockActive: Bool = false
    
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private let capsLockAnimation = Animation.spring(response: 0.32, dampingFraction: 0.85)
    
    private init() {
        // Get initial state
        isCapsLockActive = NSEvent.modifierFlags.contains(.capsLock)
        
        // Monitor flag changes when app is focused
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        
        // Monitor flag changes globally (even when app is not focused)
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }
        
        print("CapsLockManager: ✅ Initialized with Caps Lock \(isCapsLockActive ? "ON" : "OFF")")
    }
    
    deinit {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        let newState = event.modifierFlags.contains(.capsLock)
        
        guard newState != isCapsLockActive else { return }
        
        withAnimation(capsLockAnimation) {
            isCapsLockActive = newState
        }
        
        print("CapsLockManager: Caps Lock \(newState ? "ACTIVATED" : "DEACTIVATED")")
    }
}
