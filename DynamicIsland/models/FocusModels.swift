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

// The focus mode a notification or assertion resolves to, with its
// display names, SF Symbols and accent colors.

import SwiftUI

enum FocusModeType: String, CaseIterable {
    case doNotDisturb = "com.apple.donotdisturb.mode"
    case work = "com.apple.focus.work"
    case personal = "com.apple.focus.personal"
    case sleep = "com.apple.focus.sleep"
    case driving = "com.apple.focus.driving"
    case fitness = "com.apple.focus.fitness"
    case gaming = "com.apple.focus.gaming"
    case mindfulness = "com.apple.focus.mindfulness"
    case reading = "com.apple.focus.reading"
    case reduceInterruptions = "com.apple.focus.reduce-interruptions"
    case custom = "com.apple.focus.custom"
    case unknown = ""

    var displayName: String {
        switch self {
    case .doNotDisturb: return String(localized: "Do Not Disturb")
        case .work: return "Work"
        case .personal: return "Personal"
        case .sleep: return "Sleep"
        case .driving: return "Driving"
        case .fitness: return "Fitness"
        case .gaming: return "Gaming"
        case .mindfulness: return "Mindfulness"
        case .reading: return "Reading"
        case .reduceInterruptions: return "Reduce Interr."
        case .custom: return "Focus"
        case .unknown: return "Focus Mode"
        }
    }

    var sfSymbol: String {
        switch self {
        case .doNotDisturb: return "moon.fill"
        case .work: return "briefcase.fill"
        case .personal: return "person.fill"
        case .sleep: return "bed.double.fill"
        case .driving: return "car.fill"
        case .fitness: return "figure.run"
        case .gaming: return "gamecontroller.fill"
        case .mindfulness: return "circle.hexagongrid"
        case .reading: return "book.closed.fill"
        case .reduceInterruptions: return "apple.intelligence"
        case .custom: return "app.badge"
        case .unknown: return "moon.fill"
        }
    }

    var internalSymbolName: String? {
        switch self {
        case .work: return "person.lanyardcard.fill"
        case .mindfulness: return "apple.mindfulness"
        case .gaming: return "rocket.fill"
        default: return nil
        }
    }

    var activeIcon: Image {
        resolvedActiveIcon()
    }

    func resolvedActiveIcon(usePrivateSymbol: Bool = true) -> Image {
        if usePrivateSymbol,
           let internalSymbolName,
           let image = Image(internalSystemName: internalSymbolName) {
            return image
        }

        return Image(
            systemName: self == .custom
            ? self.getCustomIconFromFile()
            : sfSymbol
        )
    }

    var accentColor: Color {
        switch self {
        case .doNotDisturb:
            return Color(red: 0.370, green: 0.360, blue: 0.902)
        case .work:
            return Color(red: 0.414, green: 0.769, blue: 0.863, opacity: 1.0)
        case .personal:
            return Color(red: 0.748, green: 0.354, blue: 0.948, opacity: 1.0)
        case .sleep:
            return Color(red: 0.341, green: 0.384, blue: 0.980)
        case .driving:
            return Color(red: 0.988, green: 0.561, blue: 0.153)
        case .fitness:
            return Color(red: 0.176, green: 0.804, blue: 0.459)
        case .gaming:
            return Color(red: 0.043, green: 0.518, blue: 1.000, opacity: 1.0)
        case .mindfulness:
            return Color(red: 0.361, green: 0.898, blue: 0.883, opacity: 1.0)
        case .reading:
            return Color(red: 1.000, green: 0.622, blue: 0.044, opacity: 1.0)
        case .reduceInterruptions:
            return Color(red: 0.686, green: 0.322, blue: 0.871, opacity: 1.0)
        case .custom:
            return self.getCustomAccentColorFromFile()
        case .unknown:
            return Color(red: 0.370, green: 0.360, blue: 0.902)
        }
    }

    var inactiveSymbol: String {
        switch self {
        case .doNotDisturb:
            return "moon.circle.fill"
        default:
            return sfSymbol
        }
    }
}

extension FocusModeType {
    init(identifier: String) {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLowercased = normalized.lowercased()

        guard !normalized.isEmpty else {
            self = .doNotDisturb
            return
        }

        // 1. Exact rawValue match (e.g., "com.apple.focus.work", "com.apple.donotdisturb.mode").
        if let direct = FocusModeType(rawValue: normalized) ?? FocusModeType(rawValue: normalizedLowercased) {
            self = direct
            return
        }

        // 2. Sleep focus is reported as `com.apple.sleep.sleep-mode` by duetexpertd,
        //    not as the rawValue `com.apple.focus.sleep`, so handle it explicitly here.
        if normalizedLowercased == "com.apple.sleep.sleep-mode" {
            self = .sleep
            return
        }

        // 3. macOS custom Focus modes use `com.apple.donotdisturb.mode.<symbol>`.
        //    Must be checked BEFORE the generic prefix match, otherwise the prefix
        //    `com.apple.donotdisturb.mode` would incorrectly resolve to .doNotDisturb.
        if normalizedLowercased.hasPrefix("com.apple.donotdisturb.mode.") {
            let suffix = String(normalizedLowercased.dropFirst("com.apple.donotdisturb.mode.".count))
            if !suffix.isEmpty && suffix != "default" {
                self = .custom
                return
            }
        }

        // 4. Prefix match for known built-in modes (e.g., com.apple.focus.personal-time -> .personal).
        if let resolved = FocusModeType.allCases.first(where: {
            guard !$0.rawValue.isEmpty else { return false }
            return normalized.hasPrefix($0.rawValue) || normalizedLowercased.hasPrefix($0.rawValue)
        }) {
            self = resolved
            return
        }

        // 5. Anything else under com.apple.focus is custom.
        if normalizedLowercased.hasPrefix("com.apple.focus") {
            self = .custom
            return
        }

        self = .doNotDisturb
    }

    static func resolve(identifier: String?, name: String?) -> FocusModeType {
        if let name, !name.isEmpty {
            if let match = FocusModeType.allCases.first(where: {
                guard !$0.displayName.isEmpty else { return false }
                return $0.displayName.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                return match
            }

            // Also try matching the name against known raw identifiers (e.g., a log line may emit "work" or "sleep" as the name).
            let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch lower {
            case "work": return .work
            case "personal", "personal-time": return .personal
            case "sleep", "sleep-mode": return .sleep
            case "driving": return .driving
            case "fitness": return .fitness
            case "gaming": return .gaming
            case "mindfulness": return .mindfulness
            case "reading": return .reading
            case "reduce-interruptions", "reduce interruptions": return .reduceInterruptions
            case "do not disturb", "dnd", "donotdisturb", "do-not-disturb", "default": return .doNotDisturb
            default: break
            }
        }

        if let identifier, !identifier.isEmpty {
            return FocusModeType(identifier: identifier)
        }

        // If a name was provided but didn't match any known English mode names, the
        // system is likely reporting a localized (non-English) name such as "Travail"
        // for Work on a French macOS. Treat it as a custom/unidentified focus mode
        // instead of incorrectly falling back to Do Not Disturb.
        if let name, !name.isEmpty {
            return .custom
        }

        return .doNotDisturb
    }

    func getCustomIconFromFile() -> String {
        return FocusMetadataReader.shared.getIcon(
            for: DoNotDisturbManager.shared.currentFocusModeName,
            identifier: DoNotDisturbManager.shared.currentFocusModeIdentifier
        )
    }

    func getCustomAccentColorFromFile() -> Color {
        return FocusMetadataReader.shared.getAccentColor(
            for: DoNotDisturbManager.shared.currentFocusModeName,
            identifier: DoNotDisturbManager.shared.currentFocusModeIdentifier
        )
    }
}
