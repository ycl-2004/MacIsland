/*
 * Atoll (DynamicIsland)
 * Original work Copyright (C) 2026 ZephyrCodesStuff (https://github.com/ZephyrCodesStuff/rtaudio)
 * Modified work Copyright (C) 2026 Atoll Contributors
 *
 * CoreAudio tap for capturing real-time audio from music applications.
 * Uses macOS 14.2+ Process Tap API for efficient audio capture.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This file is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import AudioToolbox
import CoreAudio
import Defaults
import simd
import os.log

private let audioTapLog = OSLog(subsystem: AtollDiagnostics.subsystem, category: "AudioTap")

// CoreAudio fires this on a high-priority background real-time thread.
let audioIOProc: AudioDeviceIOProc = {
    inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, clientData in

    guard let clientData = clientData else { return noErr }
    let scanner = Unmanaged<AudioTap>.fromOpaque(clientData).takeUnretainedValue()

    let mutableInputData = UnsafeMutablePointer(mutating: inInputData)
    let bufferList = UnsafeMutableAudioBufferListPointer(mutableInputData)

    if let firstBuffer = bufferList.first, let data = firstBuffer.mData {
        // CoreAudio gives us byte size, divide by 4 (Float size) to get array length
        let floatCount = Int32(firstBuffer.mDataByteSize) / Int32(MemoryLayout<Float>.size)

        let floatData = data.assumingMemoryBound(to: Float.self)

        // Pass the mono array directly to C++
        scanner.bridge.processBuffer(floatData, count: floatCount)
        

    }

    return noErr
}

// These four lookups moved to `AudioProcessQuery` when the per-app volume
// taps started needing the same reads. They stay here as thin wrappers so the
// call sites below read the way they always have.
private func getAudioObjectID(for pid: pid_t) -> AudioObjectID? {
    AudioProcessQuery.processObject(for: pid)
}

private func getAudioProcessObjectIDs() -> [AudioObjectID] {
    AudioProcessQuery.processObjectIDs()
}

private func getBundleIdentifier(for audioProcessObject: AudioObjectID) -> String? {
    AudioProcessQuery.bundleIdentifier(for: audioProcessObject)
}

private func getPID(for audioProcessObject: AudioObjectID) -> pid_t? {
    AudioProcessQuery.pid(for: audioProcessObject)
}

enum AudioTapTargetMatcher {
    /// CoreAudio exposes helper processes separately from their parent app. A
    /// player such as TIDAL therefore appears as `com.tidal.desktop.player`
    /// even though the app selected by the user is `com.tidal.desktop`.
    static func targetBundleIdentifier(
        for audioProcessBundleIdentifier: String,
        among targetBundleIdentifiers: [String]
    ) -> String? {
        let processIdentifier = audioProcessBundleIdentifier.lowercased()
        return targetBundleIdentifiers.first { targetIdentifier in
            let normalizedTarget = targetIdentifier.lowercased()
            return processIdentifier == normalizedTarget
                || processIdentifier.hasPrefix(normalizedTarget + ".")
        }
    }
}

/// Runs capture only while a view draws the waveform. The last view to stop
/// ends it after a short grace, so a notch transition that swaps views does
/// not tear the tap down and rebuild it. Everything runs on `queue`.
final class WaveformDemand: @unchecked Sendable {
    private let queue: DispatchQueue
    private let grace: TimeInterval
    private let start: () -> Void
    private let stop: () -> Void
    private var displays = Set<UUID>()
    private var pendingStop: DispatchWorkItem?

    init(queue: DispatchQueue, grace: TimeInterval, start: @escaping () -> Void, stop: @escaping () -> Void) {
        self.queue = queue; self.grace = grace; self.start = start; self.stop = stop
    }

    /// Read on `queue`.
    var isWanted: Bool { !displays.isEmpty }

    func setDisplaying(_ displaying: Bool, id: UUID) {
        queue.async { [self] in
            let wasWanted = isWanted
            if displaying { displays.insert(id) } else { displays.remove(id) }
            guard wasWanted != isWanted else { return }
            pendingStop?.cancel(); pendingStop = nil
            guard !isWanted else { return start() }
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.isWanted else { return }
                self.stop()
            }
            pendingStop = work
            queue.asyncAfter(deadline: .now() + grace, execute: work)
        }
    }
}

/// Singleton class for real-time audio capture from music apps
// Hardware state and restart work belong to audioQueue. UI magnitudes/timer
// belong to MainActor. The realtime callback touches only the immutable bridge,
// whose C++ processor publishes levels atomically.
final class AudioTap: NSObject, @unchecked Sendable {
    static let shared = AudioTap()
    
    let bridge = AudioBridge()
    @MainActor private var displayMagnitudes: [Float] = Array(repeating: 0, count: 6)

    // CoreAudio stuff
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID? = nil
    private var captureIsRunning = false
    @MainActor private var updateTimer: Timer?
    
    // Serial queue to prevent race conditions
    private let audioQueue: DispatchQueue
    private let demand: WaveformDemand
    
    // Debounce restart requests
    private var pendingRestartWorkItem: DispatchWorkItem?

    private let targetBundleIDs = [
        "com.apple.Music",
        "com.spotify.client",
        "com.amazon.music",
        "sh.cider.genten.mac",
        "com.apple.Safari",
        "com.tidal.desktop",
        "tv.plex.plexamp",
        "com.roon.Roon",
        "com.audirvana.Audirvana-Studio",
        "com.vox.vox",
        "com.coppertino.Vox",
    ]

    private override init() {
        let queue = DispatchQueue(label: "com.atoll.audiotap", qos: .userInitiated)
        audioQueue = queue
        demand = WaveformDemand(queue: queue, grace: 5,
                                start: { AudioTap.shared.startCaptureSync() },
                                stop: { AudioTap.shared.stopCaptureSync() })
        super.init()
    }

    /// A view that draws the waveform says when it starts and stops drawing;
    /// a paused, hidden or closed waveform keeps no tap or timer running.
    func setDisplaying(_ displaying: Bool, id: UUID) {
        demand.setDisplaying(displaying, id: id)
    }

    @MainActor @objc private func updateSmoothedMagnitudes() {
        let nsMagnitudes = bridge.getSmoothedMagnitudes()
        let targetLevels = nsMagnitudes.map { $0.floatValue }
        
        let smoothingFactor: Float = 0.4
        
        for index in 0..<min(targetLevels.count, displayMagnitudes.count) {
            let difference = targetLevels[index] - displayMagnitudes[index]
            displayMagnitudes[index] += difference * smoothingFactor
        }
    }

    @MainActor func getSmoothedMagnitudes() -> [Float] {
        return displayMagnitudes
    }

    private func startCaptureSync() {
        // A delayed restart can reach the queue after the user switched off the
        // waveform or the last view stopped drawing. Check at the hardware boundary.
        guard Defaults[.enableRealTimeWaveform], demand.isWanted else { return }
        guard !captureIsRunning else {
            debugLog("⚠️ [AudioTap] Capture already running, skipping start")
            return
        }

        // AirPods/Bluetooth output + Spotify don't mix: process-tapping Spotify into our
        // private aggregate device disturbs the system Now Playing / AVRCP session, so the
        // AirPods pause gesture finds no target and macOS falls back to Siri. Spotify is
        // controlled via AppleScript and registers weakly with MediaRemote, which is why
        // only it is affected (Apple Music etc. stay registered). While a Bluetooth route is
        // active, skip tapping Spotify to preserve media control — the visualizer stays live
        // for Spotify on wired/built-in output and for every other app on any output.
        let bluetoothOutputActive = AudioRouteManager.shared.isDefaultOutputBluetooth()
        let targets = collectTapTargets(bluetoothOutputActive: bluetoothOutputActive)
        let targetProcessObjects = targets.processes
        let bundleIdentifierByProcessObject = targets.bundleIdentifiers

        if targetProcessObjects.isEmpty {
            debugLog("⚠️ [AudioTap] None of our target apps are running right now.")
            return
        }

        let sortedTargetProcessObjects = targetProcessObjects.sorted { lhs, rhs in
            let lhsBundleIdentifier = bundleIdentifierByProcessObject[lhs]?.lowercased() ?? ""
            let rhsBundleIdentifier = bundleIdentifierByProcessObject[rhs]?.lowercased() ?? ""
            return lhsBundleIdentifier == rhsBundleIdentifier
                ? lhs < rhs
                : lhsBundleIdentifier < rhsBundleIdentifier
        }

        let description = CATapDescription()
        description.processes = sortedTargetProcessObjects
        description.isMixdown = true
        description.isMono = true
        
        debugLog("📋 [AudioTap] Creating tap for \(sortedTargetProcessObjects.count) processes: \(sortedTargetProcessObjects)")

        tapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            Logger.log("[AudioTap] Tap Error: \(status) (\(fourCharCodeToString(status)))", category: .error)
            return
        }
        debugLog("✅ [AudioTap] Created process tap with ID: \(tapID)")

        // Get the tap's unique hardware UID
        var tapUID: CFString = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.stride)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        status = withUnsafeMutablePointer(to: &tapUID) { uidPtr in
            AudioObjectGetPropertyData(tapID, &propertyAddress, 0, nil, &propertySize, uidPtr)
        }
        guard status == noErr else {
            Logger.log("[AudioTap] UID Error: \(status) (\(fourCharCodeToString(status)))", category: .error)
            cleanupPartialSetup()
            return
        }
        debugLog("✅ [AudioTap] Got tap UID: \(tapUID)")

        // Create the Aggregate Device (a "virtual microphone" that we can route the tap into)
        let tapList = [[kAudioSubTapUIDKey: tapUID]]
        let aggregateDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Atoll_Virtual_Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,  // Hides it from the user's sound settings
            kAudioAggregateDeviceTapListKey: tapList,
        ]

        aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(
            aggregateDict as CFDictionary, &aggregateDeviceID)
        guard status == noErr else {
            Logger.log("[AudioTap] Aggregate Error: \(status) (\(fourCharCodeToString(status)))", category: .error)
            cleanupPartialSetup()
            return
        }
        debugLog("✅ [AudioTap] Created aggregate device with ID: \(aggregateDeviceID)")

        // Bind the Callback to the device
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        status = AudioDeviceCreateIOProcID(aggregateDeviceID, audioIOProc, selfPointer, &ioProcID)

        guard status == noErr, let validIOProcID = ioProcID else {
            Logger.log("[AudioTap] IOProc Error: \(status) (\(fourCharCodeToString(status)))", category: .error)
            cleanupPartialSetup()
            return
        }
        debugLog("✅ [AudioTap] Created IO proc")

        // Start listening
        status = AudioDeviceStart(aggregateDeviceID, validIOProcID)
        guard status == noErr else {
            Logger.log("[AudioTap] Start Error: \(status) (\(fourCharCodeToString(status)))", category: .error)
            cleanupPartialSetup()
            return
        }

        captureIsRunning = true
        
        DispatchQueue.main.async { [weak self] in
            self?.updateTimer?.invalidate()
            let timer = Timer(timeInterval: 1.0 / 30.0, target: self as Any, selector: #selector(self?.updateSmoothedMagnitudes), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            self?.updateTimer = timer
        }
        
        debugLog("🟢 [AudioTap] CoreAudio CATap flowing through Aggregate Device!")
    }

    /// CoreAudio process objects worth tapping, with their bundle identifiers.
    ///
    /// Electron players commonly render and play from nested helpers; TIDAL,
    /// for example, emits audio from `com.tidal.desktop.player`, while its main
    /// app PID has no audio object. CoreAudio process objects are enumerated
    /// directly, and NSRunningApplication keeps the previous PID translation
    /// as a fallback for applications whose CoreAudio process does not publish
    /// a bundle identifier.
    private func collectTapTargets(bluetoothOutputActive: Bool)
        -> (processes: Set<AudioObjectID>, bundleIdentifiers: [AudioObjectID: String]) {
        var processes = Set<AudioObjectID>()
        var bundleIdentifiers: [AudioObjectID: String] = [:]

        for processObject in getAudioProcessObjectIDs() {
            guard let processBundleIdentifier = getBundleIdentifier(for: processObject),
                  let targetBundleIdentifier = AudioTapTargetMatcher.targetBundleIdentifier(
                    for: processBundleIdentifier,
                    among: targetBundleIDs
                  ) else {
                continue
            }

            if shouldSkipSpotifyTap(
                bundleIdentifier: targetBundleIdentifier,
                bluetoothOutputActive: bluetoothOutputActive
            ) {
                debugLog("⏭️ [AudioTap] Bluetooth output active — skipping Spotify tap to preserve AirPods media control")
                continue
            }

            processes.insert(processObject)
            bundleIdentifiers[processObject] = processBundleIdentifier
            debugLog("🎯 [AudioTap] Found audio process \(processBundleIdentifier) with PID: \(getPID(for: processObject).map(String.init) ?? "unknown"), AudioObjectID: \(processObject)")
        }

        for app in NSWorkspace.shared.runningApplications {
            guard let bundleIdentifier = app.bundleIdentifier,
                  targetBundleIDs.contains(bundleIdentifier) else { continue }
            if shouldSkipSpotifyTap(
                bundleIdentifier: bundleIdentifier,
                bluetoothOutputActive: bluetoothOutputActive
            ) {
                continue
            }
            if let processObject = getAudioObjectID(for: app.processIdentifier),
               processes.insert(processObject).inserted {
                bundleIdentifiers[processObject] = bundleIdentifier
                debugLog("🎯 [AudioTap] Found \(app.localizedName ?? "App") with PID: \(app.processIdentifier), AudioObjectID: \(processObject)")
            }
        }

        return (processes, bundleIdentifiers)
    }

    private func shouldSkipSpotifyTap(
        bundleIdentifier: String,
        bluetoothOutputActive: Bool
    ) -> Bool {
        bluetoothOutputActive
            && bundleIdentifier.caseInsensitiveCompare(MediaAppBundleID.spotify) == .orderedSame
    }
    
    private func cleanupPartialSetup() {
        if let validIOProcID = ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, validIOProcID)
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        tapID = kAudioObjectUnknown
        aggregateDeviceID = kAudioObjectUnknown
        ioProcID = nil
        
        DispatchQueue.main.async { [weak self] in
            self?.updateTimer?.invalidate()
            self?.updateTimer = nil
        }
    }

    func restartCapture() {
        audioQueue.async { [self] in
            pendingRestartWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.stopCaptureSync()
                guard Defaults[.enableRealTimeWaveform] else { return }
                self.startCaptureSync()
            }
            pendingRestartWorkItem = work
            audioQueue.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    func stopCapture() {
        // Never wait for a stalled CoreAudio driver on the main thread.
        audioQueue.async { [self] in
            pendingRestartWorkItem?.cancel()
            pendingRestartWorkItem = nil
            stopCaptureSync()
        }
    }

    private func stopCaptureSync() {
        guard captureIsRunning else { return }

        // Stop listening
        if let validIOProcID = ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, validIOProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, validIOProcID)
        }

        // Destroy resources
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }

        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }

        tapID = kAudioObjectUnknown
        aggregateDeviceID = kAudioObjectUnknown
        ioProcID = nil
        captureIsRunning = false
        
        DispatchQueue.main.async { [weak self] in
            self?.updateTimer?.invalidate()
            self?.updateTimer = nil
            // Reset display magnitudes safely on main thread
            self?.displayMagnitudes = Array(repeating: 0, count: 6)
        }

        debugLog("🔴 [AudioTap] CoreAudio CATap capture stopped")
    }
    

}

// Helper to convert OSStatus to readable string
private func fourCharCodeToString(_ code: OSStatus) -> String {
    let bytes = [
        UInt8((code >> 24) & 0xFF),
        UInt8((code >> 16) & 0xFF),
        UInt8((code >> 8) & 0xFF),
        UInt8(code & 0xFF)
    ]
    if bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) {
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
    return String(code)
}
