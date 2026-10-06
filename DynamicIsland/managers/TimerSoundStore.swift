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

/// The sound a finished timer plays, and Atoll's own copy of a chosen one.
///
/// A chosen file is copied in rather than referenced where it was picked: a
/// sound left in Downloads stops existing as soon as that folder is tidied or
/// the file renamed, and the timer then fell back to the default without
/// saying so.
struct TimerSoundStore {
    enum Selection: Equatable {
        /// Nothing chosen; the bundled sound plays.
        case bundled
        /// A chosen sound, present where it was saved.
        case custom(URL)
        /// A chosen sound whose file is gone; the bundled sound plays instead.
        case missing(fileName: String)
    }

    static let bundledSoundFileName = "timer.mp3"

    static let shared = TimerSoundStore(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("TimerSounds", isDirectory: true)
    )

    static var bundledSoundURL: URL? {
        Bundle.main.url(forResource: bundledSoundFileName, withExtension: nil)
    }

    let directory: URL

    func selection(forSavedPath path: String?) -> Selection {
        guard let path, !path.isEmpty else { return .bundled }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: path) ? .custom(url) : .missing(fileName: url.lastPathComponent)
    }

    /// The chosen sound while it exists, otherwise the bundled one.
    func playableURL(forSavedPath path: String?) -> URL? {
        if case .custom(let url) = selection(forSavedPath: path) { return url }
        return Self.bundledSoundURL
    }

    /// Copies `source` in as the one kept sound and returns the copy. The
    /// previous sound is only removed once the new copy is complete, so a
    /// failed import leaves the current choice working.
    func importSound(from source: URL) throws -> URL {
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        if source.standardizedFileURL == destination.standardizedFileURL { return destination }

        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw CocoaError(.fileReadUnknown) }
        let data = try PrivateContentFile.read(source, limit: 20 * 1024 * 1024)
        // Atomic replacement succeeds before any previous sound is removed.
        try PrivateContentFile.write(data, to: destination, keepingPrevious: false)
        removeImportedSounds(except: destination)
        return destination
    }

    func removeImportedSounds() {
        removeImportedSounds(except: nil)
    }

    private func removeImportedSounds(except kept: URL?) {
        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in contents where url.standardizedFileURL != kept?.standardizedFileURL {
            try? fileManager.removeItem(at: url)
        }
    }
}
