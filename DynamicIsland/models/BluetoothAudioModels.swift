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

// Bluetooth audio device model types consumed by the Bluetooth HUD:
// connected-device snapshots, AirPods listening modes, and the per-type
// presentation metadata (names, SF Symbols, bundled looping animations).

import Foundation
import AppKit

struct BluetoothAudioDevice: Identifiable {
    let id: UUID
    let name: String
    let address: String
    let batteryLevel: Int?  // 0-100, nil if not available
    let deviceType: BluetoothAudioDeviceType

    init(
        id: UUID = UUID(),
        name: String,
        address: String,
        batteryLevel: Int?,
        deviceType: BluetoothAudioDeviceType
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.batteryLevel = batteryLevel
        self.deviceType = deviceType
    }
}

struct AirPodsListeningModeEvent: Identifiable {
    let id = UUID()
    let device: BluetoothAudioDevice
    let mode: AirPodsListeningMode
}

enum AirPodsListeningMode: Equatable {
    case noiseCancellation
    case transparency
    case adaptive
    case conversationAwareness
    case off

    var displayName: String {
        switch self {
        case .noiseCancellation:
            return String(localized: "Noise Cancellation")
        case .transparency:
            return String(localized: "Transparency")
        case .adaptive:
            return String(localized: "Adaptive Audio")
        case .conversationAwareness:
            return String(localized: "Conversation Awareness")
        case .off:
            return String(localized: "Off")
        }
    }

    var sfSymbol: String {
        switch self {
        case .noiseCancellation:
            return "ear.badge.waveform"
        case .transparency:
            return "ear"
        case .adaptive:
            return "waveform"
        case .conversationAwareness:
            return "person.wave.2"
        case .off:
            return "airpods.pro"
        }
    }

    static func fromHUDSymbol(_ symbol: String) -> AirPodsListeningMode? {
        switch symbol {
        case "ear.badge.waveform", "airpods.mode.noise-cancellation":
            return .noiseCancellation
        case "ear", "airpods.mode.transparency":
            return .transparency
        case "waveform", "airpods.mode.adaptive":
            return .adaptive
        case "person.wave.2", "airpods.mode.conversation-awareness":
            return .conversationAwareness
        case "airpods.pro", "airpods.mode.off":
            return .off
        default:
            return nil
        }
    }

    static func from(userInfo: [AnyHashable: Any]?) -> AirPodsListeningMode? {
        guard let userInfo else { return nil }

        let modeKeys = [
            "listeningMode",
            "ListeningMode",
            "noiseControlMode",
            "NoiseControlMode",
            "activeNoiseControlMode",
            "ANCMode",
            "ancMode",
            "adaptiveAudioMode",
            "AdaptiveAudioMode",
            "conversationAwareness",
            "ConversationAwareness",
            "conversationDetect",
            "ConversationDetect"
        ]

        for key in modeKeys {
            if let value = userInfo[key], let mode = from(value) {
                return mode
            }
        }

        return from(userInfo.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
    }

    static func from(_ value: Any) -> AirPodsListeningMode? {
        if let mode = value as? AirPodsListeningMode {
            return mode
        }

        if let number = value as? NSNumber {
            return fromPrivateValue(number.intValue)
        }

        if let string = value as? String {
            return from(string)
        }

        return from("\(value)")
    }

    static func fromPrivateValue(_ value: Int) -> AirPodsListeningMode? {
        switch value {
        case 0:
            return .off
        case 1:
            return .noiseCancellation
        case 2:
            return .transparency
        case 3:
            return .adaptive
        case 4:
            return .conversationAwareness
        default:
            return nil
        }
    }

    private static func from(_ rawValue: String) -> AirPodsListeningMode? {
        let value = rawValue.lowercased()

        if value.contains("lsnm anc") || value.contains("listeningmode anc") || value == "anc" {
            return .noiseCancellation
        }

        if value.contains("lsnm transparency") || value == "transparency" {
            return .transparency
        }

        if value.contains("lsnm autoanc") || value.contains("autoanc") {
            return .adaptive
        }

        if value.contains("lsnm normal") || value == "normal" {
            return .off
        }

        if value.contains("conversation") || value.contains("conversational") {
            return .conversationAwareness
        }

        if value.contains("adaptive") {
            return .adaptive
        }

        if value.contains("transparency") || value.contains("transparent") || value.contains("ambient") {
            return .transparency
        }

        if value.contains("noise cancellation") ||
           value.contains("noisecancellation") ||
           value.contains("noise cancelling") ||
           value.contains("noisecancelling") ||
           value.contains("anc") {
            return .noiseCancellation
        }

        if value.contains("listeningmode = 0") ||
           value.contains("listeningmode=0") ||
           value.contains("noisecontrolmode = 0") ||
           value.contains("noisecontrolmode=0") ||
           value.contains(" off") ||
           value.hasSuffix("off") {
            return .off
        }

        return nil
    }
}

extension BluetoothAudioDevice {
    func withBatteryLevel(_ batteryLevel: Int?) -> BluetoothAudioDevice {
        BluetoothAudioDevice(
            id: id,
            name: name,
            address: address,
            batteryLevel: batteryLevel,
            deviceType: deviceType
        )
    }
}

enum BluetoothAudioDeviceType {
    case airpods
    case airpodsGen3
    case airpodsGen4
    case airpodsPro
    case airpodsPro3
    case airpodsMax
    case beats
    case beatsstudio
    case beatssolo
    case headphones
    case speaker
    case generic

    var sfSymbol: String {
        switch self {
        case .airpods:
            return "airpods"
        case .airpodsGen3:
            return "airpods.gen3"
        case .airpodsGen4:
            return "airpods.gen4"
        case .airpodsPro:
            return "airpods.pro"
        case .airpodsPro3:
            return "airpods.pro"
        case .airpodsMax:
            return "airpodsmax"
        case .beats:
            return "beats.headphones"
        case .beatsstudio:
            return "beats.headphones"
        case .beatssolo:
            return "beats.headphones"
        case .headphones:
            return "headphones"
        case .speaker:
            return "hifispeaker.fill"
        case .generic:
            return "bluetooth.circle.fill"
        }
    }

    var displayName: String {
        switch self {
        case .airpods: return "AirPods"
        case .airpodsGen3: return "AirPods (Gen 3)"
        case .airpodsGen4: return "AirPods (Gen 4)"
        case .airpodsPro: return "AirPods Pro"
        case .airpodsPro3: return "AirPods Pro 3"
        case .airpodsMax: return "AirPods Max"
        case .beats: return "Beats"
        case .beatsstudio: return "Beats Studio"
        case .beatssolo: return "Beats Solo"
        case .headphones: return String(localized: "Headphones")
        case .speaker: return String(localized: "Speaker")
        case .generic: return String(localized: "Bluetooth Device")
        }
    }

    /// Inline HUD only: base filename (no extension) for a looping .mov animation.
    var inlineHUDAnimationBaseName: String {
        String(describing: self)
    }
}

extension BluetoothAudioDeviceType {
    /// Resolves the bundled looping HUD animation for this device type.
    ///
    /// Returns `nil` when the movie is missing *or* when the bundled file is not a real
    /// QuickTime/MP4 movie (for example an un-fetched Git LFS pointer, which is a small
    /// text file that ships with the correct name and extension but decodes to nothing).
    /// Callers can then fall back to the SF Symbol instead of rendering an empty frame.
    /// Memoised so the validation runs once per device type.
    ///
    /// This is read from `body` — `InlineHUD` evaluates it on every HUD render
    /// — and validation opens the file and walks its atom chain. Bundled
    /// resources cannot change while the app runs, so the answer is computed
    /// once and kept, including a negative answer.
    private static let animationURLCacheLock = NSLock()
    private static var animationURLCache: [BluetoothAudioDeviceType: URL?] = [:]

    var inlineHUDAnimationURL: URL? {
        BluetoothAudioDeviceType.animationURLCacheLock.lock()
        defer { BluetoothAudioDeviceType.animationURLCacheLock.unlock() }

        if let cached = BluetoothAudioDeviceType.animationURLCache[self] {
            return cached
        }

        let resolved = resolvedInlineHUDAnimationURL
        BluetoothAudioDeviceType.animationURLCache[self] = resolved
        return resolved
    }

    private var resolvedInlineHUDAnimationURL: URL? {
        // Each candidate is validated in turn: a stub in the subdirectory must
        // not mask a real movie sitting at the bundle root.
        let candidates = [
            Bundle.main.url(
                forResource: inlineHUDAnimationBaseName,
                withExtension: "mov",
                subdirectory: "BluetoothHUDAnimations"
            ),
            Bundle.main.url(
                forResource: inlineHUDAnimationBaseName,
                withExtension: "mov"
            )
        ].compactMap { $0 }

        return candidates.first { BluetoothAudioDeviceType.isPlayableMovieFile(at: $0) }
    }

    /// Atom types a QuickTime/ISO BMFF file may legitimately start with. Only
    /// the *first* atom is checked against this list — enough to reject a text
    /// file such as an un-fetched Git LFS pointer — because a valid container
    /// may carry all sorts of top-level atoms after it, and rejecting an
    /// unfamiliar one would silently disable a perfectly good animation.
    ///
    /// The padding and placeholder types (`free`, `skip`, `wide`, `pnot`) are
    /// included because real files do start with them: QuickTime writers emit
    /// `wide` before `mdat` to reserve room for a 64-bit size, and editors
    /// leave `free`/`skip` where data was removed. The assets here begin
    /// `ftyp` → `wide` → `mdat` → `moov`.
    private static let leadingAtomTypes: Set<String> = ["ftyp", "moov", "mdat", "free", "skip", "wide", "pnot"]

    /// Upper bound on the atom walk. These are small bundled assets, so a
    /// chain this long means the file is not what it claims; the bound stops a
    /// malformed one from being walked indefinitely.
    private static let maximumAtomCount = 128

    /// Walks the top-level atom chain and reports whether the file is a
    /// structurally complete movie.
    ///
    /// The chain must tile the file exactly and include a `moov`, which is
    /// where the playable metadata lives; in these assets it is the last atom,
    /// so the walk necessarily reaches EOF. This rejects both an un-fetched Git
    /// LFS pointer and a truncated or header-only file, either of which would
    /// otherwise reach the player and draw nothing.
    private static func isPlayableMovieFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        guard let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(UInt64.init),
              fileSize >= 8 else { return false }

        var offset: UInt64 = 0
        var sawMovieAtom = false
        var atomCount = 0

        while offset + 8 <= fileSize {
            atomCount += 1
            guard atomCount <= BluetoothAudioDeviceType.maximumAtomCount else { return false }

            guard (try? handle.seek(toOffset: offset)) != nil,
                  let header = try? handle.read(upToCount: 16),
                  header.count >= 8 else { return false }
            let bytes = [UInt8](header)

            // Atom types are four printable ISO 646 characters, so ASCII
            // decoding is exact rather than an assumption; anything that fails
            // to decode is not a container header.
            guard let atomType = String(bytes: bytes[4 ..< 8], encoding: .ascii),
                  atomType.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value <= 0x7E }) else { return false }
            if offset == 0, !leadingAtomTypes.contains(atomType) { return false }

            let declaredSize = bytes[0 ..< 4].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            let extent: UInt64

            switch declaredSize {
            case 0:
                // The atom runs to the end of the file.
                extent = fileSize - offset
            case 1:
                // Extended size: the real length is the next 64 bits.
                guard bytes.count >= 16 else { return false }
                extent = bytes[8 ..< 16].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                guard extent >= 16 else { return false }
            case 2 ... 7:
                // Smaller than the header it must contain.
                return false
            default:
                extent = declaredSize
            }

            // Subtract rather than add: `extent` comes straight off the file
            // and can be UInt64.max, and `offset + extent` would trap before
            // the bound is ever tested. The loop condition keeps
            // `offset <= fileSize`, so this cannot underflow.
            guard extent >= 8, extent <= fileSize - offset else { return false }
            if atomType == "moov" { sawMovieAtom = true }
            offset += extent
        }

        // The chain has to account for the whole file, with the movie metadata
        // present — a header-only file tiles cleanly but cannot play.
        return sawMovieAtom && offset == fileSize
    }

    var isAirPods: Bool {
        switch self {
        case .airpods, .airpodsGen3, .airpodsGen4, .airpodsPro, .airpodsPro3, .airpodsMax:
            return true
        default:
            return false
        }
    }
}
