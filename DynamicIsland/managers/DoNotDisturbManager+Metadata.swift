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

// Where `DoNotDisturbManager` gets focus metadata from: notification
// payloads, the unified log stream, and ModeConfigurations.json on disk.

import Foundation
import SwiftUI

// MARK: - Metadata helpers

extension DoNotDisturbManager {
    func firstMatch(for keys: [String], in value: Any) -> String? {
        if let dictionary = value as? [AnyHashable: Any] {
            for key in keys {
                if let candidate = dictionary[key], let string = normalizedString(from: candidate) {
                    return string
                }
            }

            for nestedValue in dictionary.values {
                if let nestedMatch = firstMatch(for: keys, in: nestedValue) {
                    return nestedMatch
                }
            }
        } else if let array = value as? [Any] {
            for element in array {
                if let nestedMatch = firstMatch(for: keys, in: element) {
                    return nestedMatch
                }
            }
        }

        return nil
    }

    func normalizedString(from value: Any) -> String? {
        switch value {
        case let string as String:
            let cleaned = FocusMetadataDecoder.cleanedString(string)
            return cleaned.isEmpty ? nil : cleaned
        case let number as NSNumber:
            return FocusMetadataDecoder.cleanedString(number.stringValue)
        case let uuid as UUID:
            return uuid.uuidString
        case let uuid as NSUUID:
            return uuid.uuidString
        case let data as Data:
            if let decoded = decodeFocusPayload(from: data) {
                if let nested = firstMatch(for: ["identifier", "Identifier", "uuid", "UUID"], in: decoded) {
                    return nested
                }
                if let name = firstMatch(for: ["name", "Name", "displayName", "display_name"], in: decoded) {
                    return name
                }
            }
            if let string = String(data: data, encoding: .utf8) {
                let cleaned = FocusMetadataDecoder.cleanedString(string)
                return cleaned.isEmpty ? nil : cleaned
            }
            return nil
        case let dict as [AnyHashable: Any]:
            // Attempt to pull common keys from nested dictionaries
            if let nested = firstMatch(for: ["identifier", "Identifier", "uuid", "UUID"], in: dict) {
                return nested
            }
            if let name = firstMatch(for: ["name", "Name", "displayName", "display_name"], in: dict) {
                return name
            }
            return nil
        default:
            return nil
        }
    }

    func decodeFocusPayloadIfNeeded(_ value: Any) -> Any? {
        switch value {
        case let data as Data:
            return decodeFocusPayload(from: data)
        case let data as NSData:
            return decodeFocusPayload(from: data as Data)
        default:
            return nil
        }
    }

    func decodeFocusPayload(from data: Data) -> Any? {
        guard !data.isEmpty else { return nil }

        if let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            return propertyList
        }

        if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return jsonObject
        }

        if let string = String(data: data, encoding: .utf8) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }

    func extractIdentifier(fromFocusObject object: NSObject) -> String? {
        if let array = object as? [Any] {
            for element in array {
                if let nested = element as? NSObject, let identifier = extractIdentifier(fromFocusObject: nested) {
                    return identifier
                }
            }
            return nil
        }

        if let identifier = focusString(object, selector: "modeIdentifier") {
            return identifier
        }

        if let identifier = focusString(object, selector: "identifier") {
            return identifier
        }

        if let details = focusObject(object, selector: "details"), let identifier = extractIdentifier(fromFocusObject: details) {
            return identifier
        }

        if let metadata = focusObject(object, selector: "activeModeAssertionMetadata"), let identifier = extractIdentifier(fromFocusObject: metadata) {
            return identifier
        }

        if let configuration = focusObject(object, selector: "activeModeConfiguration"), let identifier = extractIdentifier(fromFocusObject: configuration) {
            return identifier
        }

        if let modeConfiguration = focusObject(object, selector: "modeConfiguration"), let identifier = extractIdentifier(fromFocusObject: modeConfiguration) {
            return identifier
        }

        if let mode = focusObject(object, selector: "mode") {
            return extractIdentifier(fromFocusObject: mode)
        }

        if let identifiers = focusObject(object, selector: "activeModeIdentifiers") {
            if let stringArray = identifiers as? [String] {
                if let first = stringArray.compactMap({ FocusMetadataDecoder.cleanedString($0) }).first(where: { !$0.isEmpty }) {
                    return first
                }
            } else if let array = identifiers as? NSArray {
                for case let string as String in array {
                    let trimmed = FocusMetadataDecoder.cleanedString(string)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
        }

        return nil
    }

    func extractDisplayName(fromFocusObject object: NSObject) -> String? {
        if let array = object as? [Any] {
            for element in array {
                if let nested = element as? NSObject, let name = extractDisplayName(fromFocusObject: nested) {
                    return name
                }
            }
            return nil
        }

        if let name = focusString(object, selector: "name") {
            return name
        }

        if let name = focusString(object, selector: "displayName") {
            return name
        }

        if let name = focusString(object, selector: "activityDisplayName") {
            return name
        }

        if let descriptor = focusObject(object, selector: "symbolDescriptor"), let name = focusString(descriptor, selector: "name") {
            return name
        }

        if let mode = focusObject(object, selector: "mode"), let name = extractDisplayName(fromFocusObject: mode) {
            return name
        }

        if let details = focusObject(object, selector: "details"), let name = extractDisplayName(fromFocusObject: details) {
            return name
        }

        if let configuration = focusObject(object, selector: "modeConfiguration"), let name = extractDisplayName(fromFocusObject: configuration) {
            return name
        }

        return nil
    }

    func focusObject(_ object: NSObject, selector selectorName: String) -> NSObject? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }
        guard let value = object.perform(selector)?.takeUnretainedValue() else { return nil }
        return value as? NSObject
    }

    func focusString(_ object: NSObject, selector selectorName: String) -> String? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }
        guard let value = object.perform(selector)?.takeUnretainedValue() else { return nil }

        switch value {
        case let string as String:
            return FocusMetadataDecoder.cleanedString(string)
        case let string as NSString:
            return FocusMetadataDecoder.cleanedString(string as String)
        case let number as NSNumber:
            return FocusMetadataDecoder.cleanedString(number.stringValue)
        default:
            return nil
        }
    }

}

final class FocusLogStream {
    private let queue = DispatchQueue(label: "com.dynamicisland.focus.logstream", qos: .utility)
    private var process: Process?
    private var pipe: Pipe?
    private var buffer = Data()
    private var isRunning = false
    private var didTerminate = false

    private let metadataLock = NSLock()
    private var lastIdentifier: String?
    private var lastName: String?

    var onMetadataUpdate: ((String?, String?) -> Void)?

    func start() {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isRunning else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = [
                "stream",
                "--no-backtrace",
                "--style",
                "compact",
                "--level",
                "info",
                "--predicate",
                "process == \"duetexpertd\" AND eventMessage CONTAINS \"semanticModeIdentifier\""
            ]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self else { return }
                let data = handle.availableData

                if data.isEmpty {
                    self.queue.async { [weak self] in
                        self?.handleTermination()
                    }
                    return
                }

                self.queue.async { [weak self] in
                    self?.handleIncomingData(data)
                }
            }

            process.terminationHandler = { [weak self] _ in
                self?.queue.async {
                    self?.handleTermination()
                }
            }

            do {
                try process.run()
                self.process = process
                self.pipe = pipe
                self.isRunning = true
                self.didTerminate = false
                debugPrint("[FocusLogStream] Started unified log tail for duetexpertd/donotdisturbd Focus metadata")
            } catch {
                debugPrint("[FocusLogStream] Failed to start log stream: \(error)")
                pipe.fileHandleForReading.readabilityHandler = nil
                self.process = nil
                self.pipe = nil
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isRunning else { return }
            self.handleTermination(terminateProcess: true)
        }
    }

    func latestMetadata() -> (identifier: String?, name: String?)? {
        metadataLock.lock()
        let identifier = lastIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = lastName?.trimmingCharacters(in: .whitespacesAndNewlines)
        metadataLock.unlock()

        let normalizedIdentifier = (identifier?.isEmpty == false) ? identifier : nil
        let normalizedName = (name?.isEmpty == false) ? name : nil

        if normalizedIdentifier == nil && normalizedName == nil {
            return nil
        }

        return (normalizedIdentifier, normalizedName)
    }

    private func handleIncomingData(_ data: Data) {
        buffer.append(data)
        guard buffer.count <= 1024 * 1024 else {
            buffer.removeAll(keepingCapacity: false)
            return
        }
        let newline: UInt8 = 0x0A

        while let newlineIndex = buffer.firstIndex(of: newline) {
            let lineData = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(buffer.startIndex...newlineIndex)

            let trimmedLineData: Data
            if let lastByte = lineData.last, lastByte == 0x0D {
                trimmedLineData = lineData.dropLast()
            } else {
                trimmedLineData = lineData
            }

            guard !trimmedLineData.isEmpty,
                  let line = String(data: trimmedLineData, encoding: .utf8) else {
                continue
            }

            processLine(line)
        }
    }

    private func processLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("Filtering the log data") || trimmed.hasPrefix("Timestamp") {
            return
        }

        if trimmed.lowercased().contains("error") && trimmed.lowercased().contains("predicate") {
            debugPrint("[FocusLogStream] log stream error: \(trimmed)")
        }

        // Clear only when logs explicitly indicate no active mode (helps avoid wiping state during transitions).
        if trimmed.contains("active mode assertion: (null)") || trimmed.contains("activeModeIdentifier: (null)") {
            clearMetadata()
            return
        }

        var updatedIdentifier: String?
        var updatedName: String?

        // Special-case parsing for donotdisturbd logs which include a full DNDMode description.
        // Example: <DNDMode: ... name: Lock In; modeIdentifier: com.apple.donotdisturb.mode.graduationcap.fill; ...>
        if trimmed.contains("<DNDMode:") {
            func extractField(_ key: String) -> String? {
                guard let keyRange = trimmed.range(of: key) else { return nil }
                let suffix = trimmed[keyRange.upperBound...]
                guard let end = suffix.range(of: ";") else { return nil }
                let value = suffix[..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }

            if let identifier = extractField("modeIdentifier:") { updatedIdentifier = identifier }
            if let name = extractField("name:") { updatedName = name }
        }

        if updatedIdentifier == nil, let identifier = FocusMetadataDecoder.extractIdentifier(from: trimmed), !identifier.isEmpty {
            updatedIdentifier = identifier
        }

        if updatedName == nil, let name = FocusMetadataDecoder.extractName(from: trimmed), !name.isEmpty {
            updatedName = name
        }

        guard updatedIdentifier != nil || updatedName != nil else { return }

        var identifierToSend: String?
        var nameToSend: String?

        metadataLock.lock()
        if let identifier = updatedIdentifier, !identifier.isEmpty {
            lastIdentifier = identifier
        }

        if let name = updatedName, !name.isEmpty {
            lastName = name
        }

        identifierToSend = lastIdentifier
        nameToSend = lastName
        metadataLock.unlock()

        notifyMetadataUpdate(identifier: identifierToSend, name: nameToSend)
    }

    private func clearMetadata() {
        metadataLock.lock()
        lastIdentifier = nil
        lastName = nil
        metadataLock.unlock()
        notifyMetadataUpdate(identifier: nil, name: nil)
    }

    private func handleTermination(terminateProcess: Bool = false) {
        if didTerminate { return }
        didTerminate = true
        if terminateProcess, let process, process.isRunning {
            process.terminate()
        }

        pipe?.fileHandleForReading.readabilityHandler = nil
        pipe?.fileHandleForReading.closeFile()
        pipe = nil

        process = nil
        buffer.removeAll(keepingCapacity: false)
        isRunning = false
        clearMetadata()
        debugPrint("[FocusLogStream] Stopped unified log tail for duetexpertd/donotdisturbd Focus metadata")
    }

    private func notifyMetadataUpdate(identifier: String?, name: String?) {
        guard let handler = onMetadataUpdate else { return }
        handler(identifier, name)
    }
}

enum FocusNotificationParsing {
    static let identifierPattern: NSRegularExpression? = {
        let pattern = "com\\.apple\\.(?:focus|donotdisturb|sleep)[A-Za-z0-9_.-]*"
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()

    static let identifierDetailPatterns: [NSRegularExpression] = {
        let patterns = [
            "modeIdentifier:\\s*'([^'\\s]+)'",
            "activityIdentifier:\\s*([A-Za-z0-9._-]+)",
            "semanticModeIdentifier:\\s*([A-Za-z0-9._-]+)"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    static let namePatterns: [NSRegularExpression] = {
        let patterns = [
            "(?i)(?:focusModeName|focusMode|displayName|name)\\s*=\\s*\"([^\"]+)\"",
            "(?i)(?:focusModeName|focusMode|displayName|name)\\s*=\\s*([^;\\n]+)",
            "activityDisplayName:\\s*([^;>\\n]+)",
            "semanticType:\\s*([A-Za-z][A-Za-z0-9 _-]+)",
            "modeIdentifier:\\s*'com\\.apple\\.focus\\.([A-Za-z0-9._-]+)'"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()
}

enum FocusMetadataDecoder {
    static func cleanedString(_ string: String) -> String {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        return trimmed
    }

    static func extractIdentifier(from description: String) -> String? {
        let fullRange = NSRange(description.startIndex..<description.endIndex, in: description)

        if let regex = FocusNotificationParsing.identifierPattern,
           let match = regex.firstMatch(in: description, options: [], range: fullRange),
           match.numberOfRanges > 0,
           let identifierRange = Range(match.range(at: 0), in: description) {
            let candidate = cleanedString(String(description[identifierRange]))
            if !candidate.isEmpty {
                return candidate
            }
        }

        for regex in FocusNotificationParsing.identifierDetailPatterns {
            if let match = regex.firstMatch(in: description, options: [], range: fullRange),
               match.numberOfRanges > 1,
               let identifierRange = Range(match.range(at: 1), in: description) {
                let candidate = cleanedString(String(description[identifierRange]))
                if !candidate.isEmpty {
                    return candidate
                }
            }
        }

        return nil
    }

    static func extractName(from description: String) -> String? {
        let fullRange = NSRange(description.startIndex..<description.endIndex, in: description)

        for regex in FocusNotificationParsing.namePatterns {
            if let match = regex.firstMatch(in: description, options: [], range: fullRange),
               match.numberOfRanges > 1,
               let nameRange = Range(match.range(at: 1), in: description) {
                let candidate = cleanedString(String(description[nameRange]))
                if !candidate.isEmpty {
                    return candidate
                }
            }
        }

        return nil
    }
}

final class FocusMetadataReader {
    private let pathToDatabase:URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB/ModeConfigurations.json")

    struct DNDConfigRoot: Codable {
        let data: [DNDDataEntry]
    }

    struct DNDDataEntry: Codable {
        let modeConfigurations: [String: DNDModeWrapper]
    }

    struct DNDModeWrapper: Codable {
        let mode: DNDMode
    }

    struct DNDMode: Codable {
        let name: String
        let modeIdentifier: String
        let symbolImageName: String?
        let tintColorName: String?
    }

    private init(){}

    static let shared = FocusMetadataReader()

    private func getModeConfig(for focusName: String, identifier: String? = nil) -> DNDMode? {
        guard FullDiskAccessAuthorization.hasPermission() else { return nil }

        let trimmedName = focusName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIdentifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let data = try Data(contentsOf: pathToDatabase)
            let root = try JSONDecoder().decode(DNDConfigRoot.self, from: data)

            for entry in root.data {
                for wrapper in entry.modeConfigurations.values {
                    let mode = wrapper.mode

                    if let id = trimmedIdentifier, !id.isEmpty,
                       mode.modeIdentifier.compare(id, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                        return mode
                    }

                    if !trimmedName.isEmpty,
                       mode.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                        return mode
                    }
                }
            }
        } catch {
            Logger.log("ModeConfigurations.json decode error: \(error)", category: .warning)
        }

        return nil
    }

    func getDisplayName(for focus: String, identifier: String? = nil) -> String {
        guard let mode = getModeConfig(for: focus, identifier: identifier) else { return "" }
        return mode.name
    }

    /// Fetch the icon for the current focus from disk. If the focus is not found return the placeholder `app.badge`
    /// - Returns A string representing the sfSymbol of the current focus
    func getIcon(for focus: String, identifier: String? = nil) -> String {
        guard let mode = getModeConfig(for: focus, identifier: identifier) else { return "app.badge" }
        return mode.symbolImageName ?? "app.badge"
    }

    /// Fetch the accent color for the current focus from disk. If the focus is not found return the placeholder `Color.indigo`
    /// - Returns A Color representing the accent color for the current focus
    func getAccentColor(for focus: String, identifier: String? = nil) -> Color {
        guard let mode = getModeConfig(for: focus, identifier: identifier),
              let colorName = mode.tintColorName else { return .indigo }

        return Color.stringToColor(for: colorName)
    }
}

private extension Color {
    static func stringToColor(for string:String) -> Color {
        let cleanName = string.lowercased()
            .replacingOccurrences(of: "system", with: "")
            .replacingOccurrences(of: "color", with: "")

        switch cleanName {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "cyan": return .cyan
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "gray", "grey": return .gray
        default: return .indigo
        }
    }
}
