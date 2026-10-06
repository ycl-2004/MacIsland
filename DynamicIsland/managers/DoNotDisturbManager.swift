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
import Combine
import Defaults
import Foundation
import SwiftUI

final class DoNotDisturbManager: ObservableObject {
    static let shared = DoNotDisturbManager()

    @Published private(set) var isMonitoring = false
    @Published var isDoNotDisturbActive = false
    @Published var currentFocusModeName: String = ""
    @Published var currentFocusModeIdentifier: String = ""

    // Used by the brief-toast UI to show an ON toast when the active mode switches while Focus stays enabled.
    @Published var focusToastTrigger: UUID = UUID()

    /// Briefly `true` after focus turns OFF while toast mode is enabled,
    /// keeping the standalone DoNotDisturbLiveActivity mounted long enough
    /// for the "Off" dismissal animation to play out.
    @Published private(set) var isFocusToastDismissing: Bool = false

    private let notificationCenter = DistributedNotificationCenter.default()
    private let metadataExtractionQueue = DispatchQueue(label: "com.dynamicisland.focus.metadata", qos: .userInitiated)
    private let pollingQueue = DispatchQueue(label: "com.dynamicisland.focus.polling", qos: .utility)
    private let focusLogStream = FocusLogStream()
    private let assertionsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
    private var pollingSource: DispatchSourceTimer?
    private var lastAssertionsModificationDate: Date?
    private var modeCancellable: AnyCancellable?
    /// Periodic task that verifies focus is still active when `isDoNotDisturbActive` is true.
    /// Catches cases where the disabled notification fails to fire.
    private var stateVerificationTask: Task<Void, Never>?

    @Published private(set) var monitoringMode: FocusMonitoringMode = Defaults[.focusMonitoringMode]

    /// Timestamp of the last notification-driven state change.
    /// Used to suppress assertions polling from overriding a fresh notification for a short window.
    private var lastNotificationTimestamp: Date = .distantPast
    private static let notificationCooldown: TimeInterval = 4.0

    /// Delayed task that clears retained metadata after the OFF animation completes.
    private var metadataClearTask: Task<Void, Never>?

    /// Task that resets `isFocusToastDismissing` after the OFF toast animation.
    private var toastDismissTask: Task<Void, Never>?

    private init() {
        focusLogStream.onMetadataUpdate = { [weak self] identifier, name in
            self?.handleLogMetadataUpdate(identifier: identifier, name: name)
        }

        modeCancellable = Defaults.publisher(.focusMonitoringMode, options: [])
            .sink { [weak self] change in
                guard let self else { return }

                DispatchQueue.main.async {
                    self.monitoringMode = change.newValue
                }

                self.applyMonitoringModeChange(change.newValue)
            }
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        notificationCenter.addObserver(
            self,
            selector: #selector(handleFocusEnabled(_:)),
            name: .focusModeEnabled,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(handleFocusDisabled(_:)),
            name: .focusModeDisabled,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        isMonitoring = true
        applyMonitoringModeChange(Defaults[.focusMonitoringMode])
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        notificationCenter.removeObserver(self, name: .focusModeEnabled, object: nil)
        notificationCenter.removeObserver(self, name: .focusModeDisabled, object: nil)

        focusLogStream.stop()
        stopAssertionsPolling()
        stateVerificationTask?.cancel()
        stateVerificationTask = nil
        metadataClearTask?.cancel()
        metadataClearTask = nil
        cancelFocusToastDismiss()
        isMonitoring = false

        DispatchQueue.main.async {
            self.isDoNotDisturbActive = false
            self.currentFocusModeIdentifier = ""
            self.currentFocusModeName = ""
        }
    }

    @objc private func handleFocusEnabled(_ notification: Notification) {
        lastNotificationTimestamp = Date()
        apply(notification: notification, isActive: true)
    }

    @objc private func handleFocusDisabled(_ notification: Notification) {
        lastNotificationTimestamp = Date()
        apply(notification: notification, isActive: false)
    }

    private func apply(notification: Notification, isActive: Bool) {
        metadataExtractionQueue.async { [weak self] in
            guard let self = self else { return }

            let metadata = self.extractMetadata(from: notification)
            self.publishMetadata(identifier: metadata.identifier, name: metadata.name, isActive: isActive, source: notification.name.rawValue)
        }
    }

    private func publishMetadata(identifier: String?, name: String?, isActive: Bool?, source: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let trimmedIdentifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)

            let isGenericFocusIdentifier = (trimmedIdentifier?.lowercased() == "com.apple.focus")
            let usableIdentifier = (trimmedIdentifier?.isEmpty == false && !isGenericFocusIdentifier) ? trimmedIdentifier : nil
            let usableName = (trimmedName?.isEmpty == false) ? trimmedName : nil

            let previousIdentifier = self.currentFocusModeIdentifier
            let previousName = self.currentFocusModeName
            let previousActive = self.isDoNotDisturbActive

            // When neither identifier nor name is available, only update the active
            // state without overwriting existing mode metadata. This prevents the
            // assertions-poll (which often lacks metadata) from reverting a correct
            // mode set by the log-stream or notification handler.
            if usableIdentifier == nil && usableName == nil {
                if let isActive = isActive, isActive != previousActive {
                    withAnimation(.smooth(duration: 0.25)) {
                        self.isDoNotDisturbActive = isActive
                    }
                    // First activation with no prior mode: default to DND.
                    if isActive && previousIdentifier.isEmpty {
                        self.currentFocusModeIdentifier = FocusModeType.doNotDisturb.rawValue
                        self.currentFocusModeName = FocusModeType.doNotDisturb.displayName
                    }
                    debugPrint("[DoNotDisturbManager] Focus active-only update -> source: \(source) | isActive: \(isActive)")
                }
                return
            }

            let resolvedMode = FocusModeType.resolve(identifier: usableIdentifier, name: usableName)

            let finalIdentifier: String = usableIdentifier ?? resolvedMode.rawValue

            // Compute display name
            let finalName: String
            if resolvedMode == .custom, !FullDiskAccessAuthorization.hasPermission() {
                // Use the provided name if it looks like a real display name (not an
                // icon slug like "graduationcap.fill"). Slugs always contain a dot.
                if let tn = trimmedName, !tn.isEmpty, !tn.contains(".") {
                    finalName = tn
                } else {
                    finalName = "Focus"
                }
            } else if resolvedMode == .custom, FullDiskAccessAuthorization.hasPermission() {
                // With FDA, prefer the real name from ModeConfigurations.json (fixes slug names like graduationcap.fill).
                let lookedUp = FocusMetadataReader.shared.getDisplayName(for: trimmedName ?? "", identifier: finalIdentifier)
                if !lookedUp.isEmpty {
                    finalName = lookedUp
                } else if let tn = trimmedName, !tn.isEmpty, !tn.contains(".") {
                    finalName = tn
                } else {
                    finalName = "Focus"
                }
            } else if let name = trimmedName, !name.isEmpty {
                let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                switch lower {
                case "work":
                    finalName = "Work"
                case "personal", "personal-time":
                    finalName = "Personal"
                case "reduce-interruptions":
                    finalName = "Reduce Interruptions"
                case "sleep", "sleep-mode":
                    finalName = "Sleep"
                case "driving":
                    finalName = "Driving"
                case "default", "dnd", "do-not-disturb", "do not disturb", "donotdisturb":
                    finalName = "Do Not Disturb"
                default:
                    finalName = name
                }
            } else if !resolvedMode.displayName.isEmpty {
                finalName = resolvedMode.displayName
            } else {
                finalName = "Focus"
            }

            let identifierChanged = finalIdentifier != previousIdentifier
            let nameChanged = finalName != previousName
            let shouldToggleActive = isActive.map { $0 != previousActive } ?? false

            if identifierChanged {
                self.currentFocusModeIdentifier = finalIdentifier
            }

            if nameChanged {
                self.currentFocusModeName = finalName.localizedCaseInsensitiveContains("Reduce Interruptions") ? "Reduce Interr." : finalName
            }

            // If Focus remains active and the mode switches (e.g., DND -> Sleep), trigger an ON toast for the new mode.
            if isActive == nil, previousActive == true, identifierChanged {
                self.focusToastTrigger = UUID()
            }

            if identifierChanged || nameChanged || shouldToggleActive {
                debugPrint("[DoNotDisturbManager] Focus update -> source: \(source) | identifier: \(trimmedIdentifier ?? "<nil>") | name: \(trimmedName ?? "<nil>") | resolved: \(resolvedMode.rawValue)")
            }

            guard let isActive = isActive, shouldToggleActive else { return }

            withAnimation(.smooth(duration: 0.25)) {
                self.isDoNotDisturbActive = isActive
            }

            // If Focus turned OFF, retain metadata briefly for the OFF toast,
            // then clear it so stale state doesn't linger.
            if isActive == false {
                self.currentFocusModeIdentifier = previousIdentifier
                self.currentFocusModeName = previousName
                self.scheduleMetadataClear()
                self.beginFocusToastDismissIfNeeded()
            } else {
                // Focus turned ON — cancel any pending metadata clear and toast dismiss.
                self.metadataClearTask?.cancel()
                self.metadataClearTask = nil
                self.cancelFocusToastDismiss()
            }

            // Start or stop periodic verification based on new state.
            self.updateStateVerification(focusActive: isActive)
        }
    }

    /// When focus is believed to be active, periodically verify the assertions
    /// file. If the file shows no active assertions, reset `isDoNotDisturbActive`
    /// to `false`. This catches the case where `_NSDoNotDisturbDisabledNotification`
    /// fails to fire.
    private func updateStateVerification(focusActive: Bool) {
        stateVerificationTask?.cancel()
        stateVerificationTask = nil

        guard focusActive else { return }

        stateVerificationTask = Task { @MainActor [weak self] in
            // Wait a bit before starting verification to let notifications settle.
            try? await Task.sleep(for: .seconds(5))

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, self.isDoNotDisturbActive else { break }

                // Check the assertions file directly (if FDA is available).
                let focusStillActive = await self.verifyFocusActiveFromAssertions()
                if !focusStillActive {
                    withAnimation(.smooth(duration: 0.25)) {
                        self.isDoNotDisturbActive = false
                    }
                    self.scheduleMetadataClear()
                    self.beginFocusToastDismissIfNeeded()
                    debugPrint("[DoNotDisturbManager] State verification: focus no longer active, resetting.")
                    break
                }
            }
        }
    }

    /// Read the assertions file directly to verify whether focus is truly active.
    /// Returns `true` if the file confirms active assertions, or if the check
    /// cannot be performed (e.g. no FDA) — erring on the side of not falsely resetting.
    private nonisolated func verifyFocusActiveFromAssertions() async -> Bool {
        guard FullDiskAccessAuthorization.hasPermission() else {
            // Can't verify without FDA — conservatively assume still active.
            return true
        }

        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")

        guard let data = try? Data(contentsOf: url),
              !data.isEmpty,
              let root = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
              let dataArray = root["data"] as? [[String: Any]],
              let firstItem = dataArray.first else {
            // File unreadable/empty — assume focus is off.
            return false
        }

        let assertions = (firstItem["storeAssertionRecords"] as? [Any]) ?? []
        return !assertions.isEmpty
    }

    private func scheduleMetadataClear() {
        metadataClearTask?.cancel()
        metadataClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !self.isDoNotDisturbActive else { return }
            self.currentFocusModeIdentifier = ""
            self.currentFocusModeName = ""
        }
    }

    /// Sets `isFocusToastDismissing` to `true` for ~2.5 seconds when focus turns
    /// OFF while toast mode is enabled. This keeps the standalone DND live activity
    /// mounted long enough for the "Off" toast animation, without permanently
    /// occupying the live-activity slot.
    private func beginFocusToastDismissIfNeeded() {
        guard Defaults[.focusIndicatorNonPersistent] else { return }

        toastDismissTask?.cancel()
        isFocusToastDismissing = true

        toastDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.smooth(duration: 0.25)) {
                self.isFocusToastDismissing = false
            }
        }
    }

    /// Cancels any in-progress toast dismiss countdown (e.g. when focus turns back ON).
    private func cancelFocusToastDismiss() {
        toastDismissTask?.cancel()
        toastDismissTask = nil
        isFocusToastDismissing = false
    }

    private func handleLogMetadataUpdate(identifier: String?, name: String?) {
        metadataExtractionQueue.async { [weak self] in
            guard let self = self else { return }
            let trimmedIdentifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)

            let hasIdentifier = (trimmedIdentifier?.isEmpty == false)
            let hasName = (trimmedName?.isEmpty == false)

            guard hasIdentifier || hasName else { return }

            self.publishMetadata(identifier: trimmedIdentifier, name: trimmedName, isActive: nil, source: "log-stream")
        }
    }

    private func extractMetadata(from notification: Notification) -> (name: String?, identifier: String?) {
        var identifier: String?
        var name: String?

        let identifierKeys = [
            "FocusModeIdentifier",
            "focusModeIdentifier",
            "FocusModeUUID",
            "focusModeUUID",
            "UUID",
            "uuid",
            "identifier",
            "Identifier"
        ]

        let nameKeys = [
            "FocusModeName",
            "focusModeName",
            "FocusMode",
            "focusMode",
            "displayName",
            "display_name",
            "name",
            "Name"
        ]

        var candidates: [Any] = []
        if let userInfo = notification.userInfo {
            candidates.append(userInfo)
        }

        if let object = notification.object {
            candidates.append(object)
        }

        debugPrint("[DoNotDisturbManager] raw focus payload -> name: \(notification.name.rawValue), object: \(String(describing: notification.object)), userInfo: \(String(describing: notification.userInfo))")

        for candidate in candidates {
            if identifier == nil {
                identifier = firstMatch(for: identifierKeys, in: candidate)
            }

            if name == nil {
                name = firstMatch(for: nameKeys, in: candidate)
            }

            if identifier != nil && name != nil {
                break
            }
        }

        if identifier == nil || name == nil {
            for candidate in candidates {
                if let decoded = decodeFocusPayloadIfNeeded(candidate) {
                    if identifier == nil {
                        identifier = firstMatch(for: identifierKeys, in: decoded)
                    }

                    if name == nil {
                        name = firstMatch(for: nameKeys, in: decoded)
                    }

                    if identifier != nil && name != nil {
                        break
                    }
                }
            }
        }

        if identifier == nil || name == nil {
            for candidate in candidates {
                if let object = candidate as? NSObject {
                    if identifier == nil, let extractedIdentifier = extractIdentifier(fromFocusObject: object) {
                        identifier = extractedIdentifier
                    }

                    if name == nil, let extractedName = extractDisplayName(fromFocusObject: object) {
                        name = extractedName
                    }

                    if identifier != nil && name != nil {
                        break
                    }
                }
            }
        }

        if identifier == nil || name == nil {
            var descriptionSources: [Any] = candidates

            for candidate in candidates {
                if let decoded = decodeFocusPayloadIfNeeded(candidate) {
                    descriptionSources.append(decoded)
                }
            }

            for candidate in descriptionSources {
                let description = String(describing: candidate)

                if identifier == nil, let inferredIdentifier = FocusMetadataDecoder.extractIdentifier(from: description) {
                    identifier = inferredIdentifier
                }

                if name == nil, let inferredName = FocusMetadataDecoder.extractName(from: description) {
                    name = inferredName
                }

                if identifier != nil && name != nil {
                    break
                }
            }
        }

        if identifier == nil || name == nil {
            if let logMetadata = focusLogStream.latestMetadata() {
                if identifier == nil {
                    identifier = logMetadata.identifier
                }

                if name == nil {
                    name = logMetadata.name
                }
            }
        }

        return (name, identifier)
    }

}

private extension Notification.Name {
    static let focusModeEnabled = Notification.Name("_NSDoNotDisturbEnabledNotification")
    static let focusModeDisabled = Notification.Name("_NSDoNotDisturbDisabledNotification")
}

private extension DoNotDisturbManager {
    func applyMonitoringModeChange(_ mode: FocusMonitoringMode) {
        guard isMonitoring else { return }

        if mode == .useDevTools {
            stopAssertionsPolling()
            focusLogStream.start()
            checkInitialFocusStateViaLog()
        } else {
            focusLogStream.stop()
            startAssertionsPolling()
        }
    }

    /// When using the log-stream mode, `log stream` only delivers future events — it misses any
    /// focus mode that was already active when Atoll launched. This one-shot `log show` reads
    /// recent duetexpertd debug logs to find the most recent `semanticModeIdentifier` event and
    /// seeds the initial focus state from it. Tries progressively larger windows so the common
    /// case (focus toggled recently) resolves in ~1-2s without scanning a full day of logs.
    private func checkInitialFocusStateViaLog() {
        metadataExtractionQueue.async { [weak self] in
            guard let self else { return }

            for window in ["5m", "1h", "24h"] {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
                task.arguments = [
                    "show",
                    "--last", window,
                    "--debug",
                    "--style", "compact",
                    "--predicate", "process == \"duetexpertd\" AND eventMessage CONTAINS \"semanticModeIdentifier\""
                ]
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = Pipe()

                guard (try? task.run()) != nil else { return }
                task.waitUntilExit()

                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let lines = output.components(separatedBy: "\n").filter {
                    $0.contains("semanticModeIdentifier") && !$0.hasPrefix("Filtering")
                }

                guard let lastLine = lines.last(where: { !$0.isEmpty }) else { continue }

                // starting: 0 means focus ended — nothing to activate.
                guard !lastLine.contains("starting: 0") else { return }

                let identifier = FocusMetadataDecoder.extractIdentifier(from: lastLine)
                let name = FocusMetadataDecoder.extractName(from: lastLine)
                guard identifier != nil || name != nil else { return }

                self.publishMetadata(identifier: identifier, name: name, isActive: true, source: "log-initial")
                return
            }
        }
    }

    func startAssertionsPolling() {
        stopAssertionsPolling()
        lastAssertionsModificationDate = nil

        let timer = DispatchSource.makeTimerSource(queue: pollingQueue)
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(2), leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            self?.pollAssertionsState()
        }
        timer.resume()
        pollingSource = timer
    }

    func stopAssertionsPolling() {
        pollingSource?.cancel()
        pollingSource = nil
        lastAssertionsModificationDate = nil
    }

    func pollAssertionsState() {
        guard FullDiskAccessAuthorization.hasPermission() else { return }

        // Skip if a notification just arrived — let the notification take precedence
        // to avoid a race where the file hasn't been flushed yet.
        if Date().timeIntervalSince(lastNotificationTimestamp) < DoNotDisturbManager.notificationCooldown {
            return
        }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: assertionsURL.path),
           let modifiedAt = attributes[.modificationDate] as? Date,
              let lastObservedModificationDate = lastAssertionsModificationDate,
           modifiedAt <= lastObservedModificationDate {
            return
        }

        // Update last-observed modification date before reading content.
        if let attributes = try? FileManager.default.attributesOfItem(atPath: assertionsURL.path),
           let modifiedAt = attributes[.modificationDate] as? Date {
            lastAssertionsModificationDate = modifiedAt
        }

        // Default to OFF — if the file can't be read or parsed, treat as no active focus.
        var isActive = false
        var identifier: String?
        var name: String?

        if let data = try? Data(contentsOf: assertionsURL),
           !data.isEmpty,
           let root = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
           let dataArray = root["data"] as? [[String: Any]],
           let firstItem = dataArray.first {

            let assertions = (firstItem["storeAssertionRecords"] as? [Any]) ?? []
            isActive = !assertions.isEmpty

            if isActive {
                let identifierKeys = [
                    "modeIdentifier",
                    "FocusModeIdentifier",
                    "focusModeIdentifier",
                    "identifier",
                    "Identifier",
                    "focusModeUUID",
                    "UUID",
                    "uuid"
                ]

                let nameKeys = [
                    "activityDisplayName",
                    "displayName",
                    "FocusModeName",
                    "focusModeName",
                    "focusMode",
                    "name",
                    "Name"
                ]

                identifier = firstMatch(for: identifierKeys, in: assertions)
                name = firstMatch(for: nameKeys, in: assertions)
            }
        }

        publishMetadata(identifier: identifier, name: name, isActive: isActive, source: "assertions-poll")
    }
}

// MARK: - Focus Mode Types
