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
import CoreAudio
import SwiftUI
import Combine

// MARK: - CoreAudio Callback Function
// C function pointer for CoreAudio property listener
private func microphonePropertyListener(
    inObjectID: AudioObjectID,
    inNumberAddresses: UInt32,
    inAddresses: UnsafePointer<AudioObjectPropertyAddress>,
    inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let context = inClientData else { return noErr }
    let monitor = Unmanaged<MicrophoneMonitor>.fromOpaque(context).takeUnretainedValue()
    
    DispatchQueue.main.async {
        debugLog("MicrophoneMonitor: 📢 Microphone property changed")
        monitor.checkMicrophoneStatus()
    }
    
    return noErr
}

@MainActor
class MicrophoneMonitor: ObservableObject {
    // MARK: - Published Properties
    @Published var isMicActive: Bool = false
    @Published var activeApp: String? = nil
    @Published var isMonitoring: Bool = false
    
    // MARK: - Private Properties
    private var defaultInputDevice: AudioDeviceID = 0
    private var isListenerRegistered: Bool = false
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Configuration
    // Pure event-driven - no polling
    
    // MARK: - Initialization
    init() {
        // No initial setup needed
    }
    
    deinit {
        // Clean up listener synchronously
        // Remove property listener
        if isListenerRegistered, defaultInputDevice != 0 {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMaster
            )
            
            let context = Unmanaged.passUnretained(self).toOpaque()
            
            AudioObjectRemovePropertyListener(
                defaultInputDevice,
                &address,
                microphonePropertyListener,
                context
            )
        }
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring microphone usage
    func startMonitoring() {
        guard !isMonitoring else {
            debugLog("MicrophoneMonitor: Already monitoring, skipping start")
            return
        }
        
        debugLog("MicrophoneMonitor: 🟢 Starting microphone monitoring...")
        
        isMonitoring = true
        
        // Get default input device
        defaultInputDevice = getDefaultInputDevice()
        guard defaultInputDevice != 0 else {
            debugLog("MicrophoneMonitor: ⚠️ No input device found")
            return
        }
        
        debugLog("MicrophoneMonitor: 🎤 Found input device ID: \(defaultInputDevice)")
        
        debugLog("MicrophoneMonitor: Property exists: \(checkPropertyExists())")
        
        // Setup event listener
        setupPropertyListener()
        
        // Check initial state
        checkMicrophoneStatus()
        
        debugLog("MicrophoneMonitor: ✅ Started monitoring (event-driven only)")
    }
    
    /// Stop monitoring microphone usage
    func stopMonitoring() {
        guard isMonitoring else {
            debugLog("MicrophoneMonitor: Not monitoring, skipping stop")
            return
        }
        
        debugLog("MicrophoneMonitor: 🛑 Stopping monitoring...")
        
        isMonitoring = false
        
        // Remove property listener
        if isListenerRegistered {
            removePropertyListener()
        }
        
        // Reset state
        if isMicActive {
            isMicActive = false
        }
        activeApp = nil
        
        debugLog("MicrophoneMonitor: ✅ Stopped monitoring")
    }
    
    /// Toggle monitoring state
    func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }
    
    // MARK: - Private Methods
    
    /// Get default input device ID
    private func getDefaultInputDevice() -> AudioDeviceID {
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMaster
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        
        if status != noErr {
            Logger.log("MicrophoneMonitor: Failed to get default input device (status: \(status))", category: .warning)
            return 0
        }
        
        return deviceID
    }
    
    /// Check if the property exists on the device
    private func checkPropertyExists() -> Bool {
        guard defaultInputDevice != 0 else { return false }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMaster
        )
        
        let hasProperty = AudioObjectHasProperty(defaultInputDevice, &address)
        debugLog("MicrophoneMonitor: Device \(defaultInputDevice) has property: \(hasProperty)")
        
        return hasProperty
    }
    
    /// Setup CoreAudio property listener
    private func setupPropertyListener() {
        guard defaultInputDevice != 0 else { return }
        
        // Use kAudioDevicePropertyDeviceIsRunningSomewhere (tracks when device is in use anywhere)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMaster
        )
        
        // Pass self as context
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        let status = AudioObjectAddPropertyListener(
            defaultInputDevice,
            &address,
            microphonePropertyListener,
            context
        )
        
        if status == noErr {
            isListenerRegistered = true
            debugLog("MicrophoneMonitor: ✅ Property listener registered")
        } else {
            Logger.log("MicrophoneMonitor: Failed to register property listener (status: \(status))", category: .warning)
        }
    }
    
    /// Remove CoreAudio property listener
    private func removePropertyListener() {
        guard defaultInputDevice != 0, isListenerRegistered else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMaster
        )
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        let status = AudioObjectRemovePropertyListener(
            defaultInputDevice,
            &address,
            microphonePropertyListener,
            context
        )
        
        if status == noErr {
            isListenerRegistered = false
            debugLog("MicrophoneMonitor: ✅ Property listener removed")
        } else {
            debugLog("MicrophoneMonitor: ⚠️ Failed to remove property listener (status: \(status))")
        }
    }
    
    /// Check current microphone status
    func checkMicrophoneStatus() {
        guard defaultInputDevice != 0 else { return }
        
        let isRunning = isDeviceRunning(defaultInputDevice)
        
        // Debug logging
        debugLog("MicrophoneMonitor: 🔍 Checking... current=\(isMicActive), detected=\(isRunning)")
        
        // Update state if changed
        if isRunning != isMicActive {
            debugLog("MicrophoneMonitor: 🔄 State change detected (\(isMicActive) -> \(isRunning))")
            
            withAnimation(.smooth) {
                isMicActive = isRunning
            }
            
            if isRunning {
                debugLog("MicrophoneMonitor: 🎤 Microphone ACTIVE")
                // Could try to identify app here (TODO: investigate)
                activeApp = "Unknown App"
            } else {
                debugLog("MicrophoneMonitor: ⚪ Microphone INACTIVE")
                activeApp = nil
            }
        }
    }
    
    /// Check if audio device is running
    private func isDeviceRunning(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMaster
        )
        
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &isRunning
        )
        
        if status != noErr {
            debugLog("MicrophoneMonitor: ⚠️ Failed to check device running status (status: \(status))")
            return false
        }
        
        return isRunning != 0
    }

}

// MARK: - Extensions

extension MicrophoneMonitor {
    /// Get current microphone status without async
    var currentMicStatus: Bool {
        return isMicActive
    }
    
    /// Check if monitoring is available
    var isMonitoringAvailable: Bool {
        return getDefaultInputDevice() != 0
    }
}
