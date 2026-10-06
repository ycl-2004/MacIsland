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
import Defaults
import Combine

class SystemHUDManager {
    static let shared = SystemHUDManager()
    
    private var changesObserver: SystemChangesObserver?
    private weak var coordinator: DynamicIslandViewCoordinator?
    private var isSetupComplete = false
    private var isSystemOperationInProgress = false
    /// The lock state the native HUD has actually been handed over for, so a
    /// handover that restarts OSDUIHelper only happens when it changes.
    private var lastNativeHUDLockState: Bool?
    
    private init() {
        // Set up observer for settings changes
        setupSettingsObserver()
    }
    
    private func setupSettingsObserver() {
        Defaults.publisher(.enableSystemHUD, options: []).sink { [weak self] change in
            guard let self = self, self.isSetupComplete else {
                return
            }
            Task { @MainActor in
                if change.newValue {
                    await self.startSystemObserver()
                } else {
                    await self.stopSystemObserver()
                }
            }
        }.store(in: &cancellables)

        Publishers.Merge3(
            Defaults.publisher(.enableVolumeHUD, options: []).map { _ in () },
            Defaults.publisher(.enableBrightnessHUD, options: []).map { _ in () },
            Defaults.publisher(.enableKeyboardBacklightHUD, options: []).map { _ in () }
        ).sink { [weak self] in
            guard let self = self, self.isSetupComplete, Defaults[.enableSystemHUD] else {
                return
            }
            let flags = self.resolvedControlFlags()
            self.changesObserver?.update(
                volumeEnabled: flags.volume,
                brightnessEnabled: flags.brightness,
                keyboardBacklightEnabled: flags.backlight
            )
        }.store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()

    /// Public property to check if system operations are in progress
    var isOperationInProgress: Bool {
        return isSystemOperationInProgress
    }
    
    func setup(coordinator: DynamicIslandViewCoordinator) {
        self.coordinator = coordinator

        if Defaults[.enableSystemHUD] {
            Task { @MainActor in
                await startSystemObserver()
                self.isSetupComplete = true
            }
        } else {
            isSetupComplete = true
        }
    }
    
    /// Which system controls Atoll handles.
    private func resolvedControlFlags() -> (volume: Bool, brightness: Bool, backlight: Bool) {
        (Defaults[.enableVolumeHUD], Defaults[.enableBrightnessHUD], Defaults[.enableKeyboardBacklightHUD])
    }

    @MainActor
    private func startSystemObserver() async {
        guard let coordinator = coordinator, !isSystemOperationInProgress else { return }
        
        isSystemOperationInProgress = true

        // Stop any existing observer directly (cannot call stopSystemObserver()
        // because isSystemOperationInProgress is already true).
        changesObserver?.stopObserving()
        changesObserver = nil
        
        changesObserver = SystemChangesObserver(coordinator: coordinator)

        let flags = resolvedControlFlags()
        changesObserver?.startObserving(
            volumeEnabled: flags.volume,
            brightnessEnabled: flags.brightness,
            keyboardBacklightEnabled: flags.backlight
        )
        
        // A fresh observer has none of the old one's suppression applied to it,
        // so what was handed over before this restart says nothing about what
        // is in force now.
        lastNativeHUDLockState = nil

        // Force disable system HUD to ensure no duplicates
        SystemOSDManager.disableSystemHUD()
        
        debugLog("System observer started")
        isSystemOperationInProgress = false
    }
    
    /// Hands the HUD to macOS while the Mac is locked, and takes it back on
    /// unlock.
    ///
    /// This app's HUD lives in the notch, which cannot be seen over the lock
    /// screen, so suppressing the system HUD there left the volume keys with
    /// no feedback at all. The exception is the lock screen music panel, which
    /// carries its own slider; unsuppressing then would put two indicators on
    /// screen at once.
    @MainActor
    func updateNativeHUDSuppressionForLockState(isLocked: Bool) {
        // Readiness first, then the record of what has been applied. The other
        // order marked a request applied that this guard had in fact dropped,
        // and every later request for the same state returned early on the
        // strength of it -- so a lock that arrived before setup finished left
        // the HUD in the wrong hands for the rest of the session.
        guard isSetupComplete, changesObserver != nil else { return }

        // Handing the HUD over restarts OSDUIHelper, so only act on a change.
        guard isLocked != lastNativeHUDLockState else { return }
        lastNativeHUDLockState = isLocked

        if SystemHUDPlacement.yieldsToNativeHUD(isLocked: isLocked) {
            SystemOSDManager.enableSystemHUD()
        } else {
            SystemOSDManager.disableSystemHUD()
            // disableSystemHUD arms the watcher, which polls; on unlock the
            // helper is already awake and can draw one more HUD before the
            // first poll lands. Freeze it now as well.
            SystemOSDManager.suppressNativeOSDNow()
        }
    }

    @MainActor
    private func stopSystemObserver() async {
        guard !isSystemOperationInProgress else { return }
        
        isSystemOperationInProgress = true
        changesObserver?.stopObserving()
        changesObserver = nil
        
        // Re-enable system HUD when we stop observing
        SystemOSDManager.enableSystemHUD()
        
        debugLog("System observer stopped")
        isSystemOperationInProgress = false
    }
    
    deinit {
        cancellables.removeAll()
        Task { @MainActor in
            await stopSystemObserver()
        }
    }
}