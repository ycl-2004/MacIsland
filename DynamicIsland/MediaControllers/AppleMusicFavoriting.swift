/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

/// Favouriting the track Music.app is playing.
///
/// Music.app is scriptable and favouriting is a plain read/write property on
/// `current track` -- no MusicKit, no developer token, and no Apple Music
/// subscription, which is what had this feature stuck. Anything in the library
/// can be favourited whether or not the user subscribes to anything.
///
/// The Now Playing source fronts whatever app is playing; when that app is
/// Music.app, this script is how it favourites.
enum AppleMusicFavoriting {
    /// Only ever true while Music.app is already running.
    ///
    /// Scripting an app that is not running launches it, and a heart appearing
    /// in the notch is not a reason to open Music.
    @MainActor
    static var isAvailable: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == MediaAppBundleID.appleMusic }
    }

    static func isCurrentTrackFavorited() async -> Bool? {
        guard await isAvailable else { return nil }
        for property in propertyNames {
            guard let descriptor = try? await AppleScriptHelper.execute(
                "tell application \"Music\" to return \(property) of current track"
            ) else { continue }
            return descriptor.booleanValue
        }
        return nil
    }

    @discardableResult
    static func setCurrentTrackFavorited(_ favorited: Bool) async -> Bool {
        guard await isAvailable else { return false }
        for property in propertyNames {
            do {
                try await AppleScriptHelper.executeVoid(
                    "tell application \"Music\" to set \(property) of current track to \(favorited)"
                )
                return true
            } catch {
                continue
            }
        }
        return false
    }

    /// `favorited` and `loved` are the same property under the same AppleEvent
    /// code (`pLov`); Music.app renamed it when Love became Favorite. A script
    /// is compiled against the name, though, so the one the running version
    /// does not know fails to compile -- and Atoll still supports macOS 14,
    /// where it is `loved`. Try the current name first and fall back, rather
    /// than branching on an OS version that only approximates which Music.app
    /// is installed.
    private static let propertyNames = ["favorited", "loved"]
}
