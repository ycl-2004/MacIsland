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
import Foundation

/// A service providing common actions for `ShelfItem`s: opening, removing and renaming.
@MainActor
enum ShelfActionService {

    static func open(_ item: ShelfItem) {
        switch item.kind {
        case .file:
            let lease = ShelfFileLifetime.shared.acquire([item.resolvedFileURL].compactMap { $0 })
            Task {
                guard let url = await ShelfStateViewModel.shared.resolveAndUpdateBookmarkAsync(for: item) else {
                    lease.finish()
                    ShelfStateViewModel.shared.report(String(localized: "This file is unavailable. Check its location or reconnect the drive."))
                    return
                }
                let opened = NSWorkspace.shared.open(url)
                lease.finish(handoff: opened)
                if !opened { ShelfStateViewModel.shared.report(String(localized: "This file could not be opened.")) }
            }
        case .link(let url):
            NSWorkspace.shared.open(url)
        case .text(let string):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        }
    }

    static func remove(_ item: ShelfItem) {
        ShelfStateViewModel.shared.remove(item)
    }

    enum RenameError: LocalizedError, Equatable {
        case emptyName
        case invalidName

        var errorDescription: String? {
            switch self {
            case .emptyName:
                return String(localized: "The name can't be empty.")
            case .invalidName:
                return String(localized: "The name can't contain “/” or “:”, or be “.” or “..”.")
            }
        }
    }

    /// Where `url` ends up once renamed to `name`; nil when that is the name it
    /// already has.
    ///
    /// A rename keeps the file in its folder. A name that would reach into
    /// another one is refused rather than turned into a move -- which the save
    /// panel this replaced allowed, relocating the original from a "Rename".
    nonisolated static func renamedURL(for url: URL, to name: String) throws -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RenameError.emptyName }
        guard trimmed != ".", trimmed != "..", !trimmed.contains("/"), !trimmed.contains(":") else {
            throw RenameError.invalidName
        }
        guard trimmed != url.lastPathComponent else { return nil }
        return url.deletingLastPathComponent().appendingPathComponent(trimmed)
    }

    /// Renames the file behind `item` in place and points the item at the new name.
    static func rename(_ item: ShelfItem, to name: String) async throws {
        guard case .file(let bookmarkData) = item.kind else { return }
        let lease = ShelfFileLifetime.shared.acquire([item.resolvedFileURL].compactMap { $0 })
        defer { lease.finish() }
        let renamed = try await Task.detached(priority: .userInitiated) { () -> (Data, URL)? in
            guard let url = Bookmark(data: bookmarkData).resolveWithoutMounting() else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            guard let target = try renamedURL(for: url, to: name) else { return nil }
            return try url.accessSecurityScopedResource { url in
                try FileManager.default.moveItem(at: url, to: target)
                do { return (try Bookmark(url: target).data, target) }
                catch {
                    // A failed bookmark must not leave the saved item pointing at a moved file.
                    try FileManager.default.moveItem(at: target, to: url)
                    throw error
                }
            }
        }.value
        guard let (bookmark, target) = renamed else { return }
        ShelfStateViewModel.shared.updateBookmark(for: item, bookmark: bookmark, path: target.standardizedFileURL.path)
    }
}
