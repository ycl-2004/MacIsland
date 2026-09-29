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

import Foundation

// Access model types
@_exported import struct Foundation.URL


/// Saves the shelf list as `items.json`.
///
/// An empty shelf leaves nothing on disk: the file and its folder are removed
/// as the last item goes (or when an empty list is found at launch) and come
/// back with the next save that has something in it.
final class ShelfPersistenceService {
    static let shared = ShelfPersistenceService()

    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("items.json") }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private(set) var needsRecovery = false
    private(set) var lastError: String?
    private var recoveryCopySaved = false
    private var hasRecoveryCopy = false
    var permitsCleanup: Bool { !needsRecovery && !hasRecoveryCopy && lastError == nil }
    var recoveryWarning: String? {
        needsRecovery || hasRecoveryCopy ? String(localized: "Some Shelf data could not be read. The original data has been kept.") : nil
    }

    /// `directory` is only ever passed by tests: the default is the one the
    /// running app uses, which a test must not touch.
    init(directory: URL = ShelfPersistenceService.defaultDirectory) {
        self.directory = directory
        encoder.outputFormatting = [.prettyPrinted]
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        hasRecoveryCopy = files.contains { $0.hasPrefix("items.recovery-") }
    }

    static var defaultDirectory: URL {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        return support
            .appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)
    }

    func load() -> [ShelfItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            if let items = try? decoder.decode([ShelfItem].self, from: data) {
                if items.isEmpty { try removeStore() }
                return items
            }
            needsRecovery = true
            lastError = String(localized: "Some Shelf data could not be read. The original data has been kept.")
            guard let array = try JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
            return array.compactMap { value in
                guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) else { return nil }
                return try? decoder.decode(ShelfItem.self, from: data)
            }
        } catch {
            needsRecovery = true
            lastError = String(localized: "Some Shelf data could not be read. The original data has been kept.")
            return []
        }
    }

    @discardableResult
    func save(_ items: [ShelfItem]) -> Bool {
        do {
            if needsRecovery && !recoveryCopySaved {
                // Preserve the exact source before any mutation overwrites it.
                let backup = directory.appendingPathComponent("items.recovery-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: fileURL, to: backup)
                recoveryCopySaved = true
                hasRecoveryCopy = true
            }
            if items.isEmpty { try removeStore() }
            else {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try encoder.encode(items).write(to: fileURL, options: .atomic)
            }
            lastError = nil
            return true
        } catch {
            lastError = String(localized: "Shelf changes could not be saved. Check available disk space and folder access.")
            return false
        }
    }

    private func removeStore() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) { try fm.removeItem(at: fileURL) }
        // Other files, including recovery copies, must remain intact.
        rmdir(directory.path)
    }
}
