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
import AppKit
import UniformTypeIdentifiers

enum TempFileType {
    case data(Data, suggestedName: String?)
    case text(String)
}

class TemporaryFileStorageService {
    static let shared = TemporaryFileStorageService()
    
    // MARK: - Public Interface
    
    /// Disk work runs outside the main actor; ordinary file drops stay as references.
    func createTempFile(for type: TempFileType) async -> URL? {
        await Task.detached(priority: .utility) { self.writeTempFile(for: type) }.value
    }

    func removeTemporaryFileIfNeeded(at url: URL) {
        guard ShelfFileLifetime.shared.owns(url) else { return }
        ShelfFileLifetime.shared.requestCleanup()
    }

    /// Must be called inside an item-provider completion: its URL expires on return.
    func copyProviderFile(_ source: URL, suggestedName: String?) -> URL? {
        ShelfStorageBudget.lock.lock()
        defer { ShelfStorageBudget.lock.unlock() }
        let root = AtollTemporaryFiles.directory(.shelf)
        guard let size = try? ShelfStorageBudget.size(source, limit: ShelfStorageBudget.maximumItemBytes),
              ShelfStorageBudget.permits(size, root: root) else { return nil }
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let name = Self.safeFilename(suggestedName ?? source.lastPathComponent)
        let destination = folder.appendingPathComponent(name)
        let lease = ShelfFileLifetime.shared.acquire([folder])
        var copied = false
        defer { lease.finish(handoff: copied) }
        do {
            try PrivateContentFile.prepareDirectory(folder)
            try source.accessSecurityScopedResource { try ShelfStorageBudget.copy($0, to: destination) }
            guard (try ShelfStorageBudget.size(destination, limit: ShelfStorageBudget.maximumItemBytes)) <= size else { throw CocoaError(.fileReadTooLarge) }
            try Self.makePrivate(destination)
            copied = true
            return destination
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
    }

    private static func makePrivate(_ url: URL) throws {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        func apply(_ target: URL) throws {
            let values = try target.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { return }
            try FileManager.default.setAttributes([.posixPermissions: values.isDirectory == true ? 0o700 : 0o600], ofItemAtPath: target.path)
        }
        try apply(url)
        if let iterator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) {
            for case let child as URL in iterator { try apply(child) }
        }
    }

    static func safeFilename(_ name: String) -> String {
        let leaf = (name as NSString).lastPathComponent
        return leaf.isEmpty || leaf == "." || leaf == ".." ? "Untitled.dat" : leaf
    }

    // MARK: - Private Implementation
    
    private func writeTempFile(for type: TempFileType) -> URL? {
        ShelfStorageBudget.lock.lock()
        defer { ShelfStorageBudget.lock.unlock() }
        let tempDir = AtollTemporaryFiles.directory(.shelf)
        let uuid = UUID().uuidString
        let bytes: Int
        switch type { case .data(let data, _): bytes = data.count; case .text(let text): bytes = text.utf8.count }
        guard ShelfStorageBudget.permits(bytes, root: tempDir) else { return nil }
        switch type {
        case .data(let data, let suggestedName):
            let filename = Self.safeFilename(suggestedName ?? "Untitled.dat")
            let dirURL = tempDir.appendingPathComponent(uuid, isDirectory: true)
            let fileURL = dirURL.appendingPathComponent(filename)
            
            do {
                try PrivateContentFile.write(data, to: fileURL, keepingPrevious: false)
                return fileURL
            } catch {
                try? FileManager.default.removeItem(at: dirURL)
                return nil
            }
            
        case .text(let string):
            let filename = "\(uuid).txt"
            let dirURL = tempDir.appendingPathComponent(uuid, isDirectory: true)
            let fileURL = dirURL.appendingPathComponent(filename)
            
            guard let data = string.data(using: .utf8) else {
                Logger.log("Failed to convert text to data", category: .error)
                return nil
            }
            
            do {
                try PrivateContentFile.write(data, to: fileURL, keepingPrevious: false)
                return fileURL
            } catch {
                try? FileManager.default.removeItem(at: dirURL)
                return nil
            }
            
        }
    }
    
    func createZip(from urls: [URL], suggestedName: String? = nil) async -> URL? {
        await Task.detached(priority: .utility) { await self.writeZip(from: urls, suggestedName: suggestedName) }.value
    }

    private func writeZip(from urls: [URL], suggestedName: String?) async -> URL? {
        guard urls.count <= 50 else { return nil }
        var inputBytes = 0
        for url in urls {
            guard let size = try? ShelfStorageBudget.size(url, limit: ShelfStorageBudget.maximumItemBytes) else { return nil }
            inputBytes += size
            guard inputBytes <= ShelfStorageBudget.maximumItemBytes else { return nil }
        }
        let tempDir = AtollTemporaryFiles.directory(.shelf)
        let reservation = inputBytes * 2 + 2 * 1024 * 1024
        guard ShelfStorageBudget.reserve(reservation, root: tempDir) else { return nil }
        defer { ShelfStorageBudget.release(reservation) }
        let uuid = UUID().uuidString
        let workingDir = tempDir.appendingPathComponent("zip_\(uuid)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: workingDir, withIntermediateDirectories: true)
        } catch {
            Logger.log("Failed to create zip working directory: \(error)", category: .error)
            return nil
        }

        let lease = ShelfFileLifetime.shared.acquire([workingDir])
        var completed = false
        defer {
            if !completed { try? FileManager.default.removeItem(at: workingDir) }
            lease.finish(handoff: completed)
        }

        // Helper to run zip process
        func runZip(arguments: [String], currentDirectory: URL) async -> Bool {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            proc.arguments = arguments
            proc.currentDirectoryURL = currentDirectory
            do {
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                return try await ProcessRunner.run(proc, timeout: 60) == .exited(0)
            } catch {
                Logger.log("Failed to run zip: \(error)", category: .error)
                return false
            }
        }

        // Snapshot first, so files changing elsewhere cannot grow the archive
        // without bound. Keep output outside the payload to avoid name collisions.
        let payload = workingDir.appendingPathComponent("contents", isDirectory: true)
        do { try PrivateContentFile.prepareDirectory(payload) } catch { return nil }
        for src in urls {
            let dest = payload.appendingPathComponent(src.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    // Avoid collision by appending a suffix
                    let unique = "\(UUID().uuidString)_\(src.lastPathComponent)"
                    try ShelfStorageBudget.copy(src, to: payload.appendingPathComponent(unique))
                } else {
                    try ShelfStorageBudget.copy(src, to: dest)
                }
            } catch {
                return nil
            }
        }

        let archiveName = Self.safeFilename(suggestedName ?? (urls.count == 1 ? urls[0].lastPathComponent + ".zip" : "Archive.zip"))
        let archiveURL = workingDir.appendingPathComponent(archiveName)
        let args = ["-r", "-q", archiveURL.path, "."]
        let ok = await runZip(arguments: args, currentDirectory: payload)
        if ok {
            guard (try? ShelfStorageBudget.size(archiveURL, limit: ShelfStorageBudget.maximumItemBytes)) != nil else { return nil }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archiveURL.path)
            // Remove the copied (uncompressed) items so the temp folder contains only the archive
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: workingDir, includingPropertiesForKeys: nil)
                for file in contents {
                    if file.standardizedFileURL != archiveURL.standardizedFileURL {
                        try FileManager.default.removeItem(at: file)
                    }
                }
            } catch {
                Logger.log("Failed to cleanup working directory after zip: \(error)", category: .warning)
            }
            completed = true
            return archiveURL
        } else {
            return nil
        }
    }
}
