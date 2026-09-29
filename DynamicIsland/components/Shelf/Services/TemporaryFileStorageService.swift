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
        let folder = AtollTemporaryFiles.directory(.shelf).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let name = Self.safeFilename(suggestedName ?? source.lastPathComponent)
        let destination = folder.appendingPathComponent(name)
        let lease = ShelfFileLifetime.shared.acquire([folder])
        var copied = false
        defer { lease.finish(handoff: copied) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try source.accessSecurityScopedResource { try FileManager.default.copyItem(at: $0, to: destination) }
            copied = true
            return destination
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
    }

    static func safeFilename(_ name: String) -> String {
        let leaf = (name as NSString).lastPathComponent
        return leaf.isEmpty || leaf == "." || leaf == ".." ? "Untitled.dat" : leaf
    }

    // MARK: - Private Implementation
    
    private func writeTempFile(for type: TempFileType) -> URL? {
        let tempDir = AtollTemporaryFiles.directory(.shelf)
        let uuid = UUID().uuidString
        
        switch type {
        case .data(let data, let suggestedName):
            let filename = Self.safeFilename(suggestedName ?? "Untitled.dat")
            let dirURL = tempDir.appendingPathComponent(uuid, isDirectory: true)
            let fileURL = dirURL.appendingPathComponent(filename)
            
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                try data.write(to: fileURL)
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
                print("❌ Failed to convert text to data")
                return nil
            }
            
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                try data.write(to: fileURL)
                return fileURL
            } catch {
                try? FileManager.default.removeItem(at: dirURL)
                return nil
            }
            
        }
    }
    
    func createZip(from urls: [URL], suggestedName: String? = nil) async -> URL? {
        await Task.detached(priority: .utility) { self.writeZip(from: urls, suggestedName: suggestedName) }.value
    }

    private func writeZip(from urls: [URL], suggestedName: String?) -> URL? {
        let tempDir = AtollTemporaryFiles.directory(.shelf)
        let uuid = UUID().uuidString
        let workingDir = tempDir.appendingPathComponent("zip_\(uuid)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: workingDir, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create zip working directory: \(error)")
            return nil
        }

        let lease = ShelfFileLifetime.shared.acquire([workingDir])
        var completed = false
        defer {
            if !completed { try? FileManager.default.removeItem(at: workingDir) }
            lease.finish(handoff: completed)
        }

        // Helper to run zip process
        func runZip(arguments: [String], currentDirectory: URL) -> Bool {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            proc.arguments = arguments
            proc.currentDirectoryURL = currentDirectory
            do {
                try proc.run()
                proc.waitUntilExit()
                return proc.terminationStatus == 0
            } catch {
                print("❌ Failed to run zip: \(error)")
                return false
            }
        }

        // Single-item optimization: do not copy contents into the working dir.
        if urls.count == 1, let src = urls.first {
            let isDir = (try? src.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let baseName = src.lastPathComponent
            let archiveName: String
            if isDir {
                // Folder: name as FolderName.zip and include the folder itself in the archive
                archiveName = "\(baseName).zip"
                let archiveURL = workingDir.appendingPathComponent(archiveName)
                // Run zip from the parent directory so the folder is stored as top-level entry
                let parent = src.deletingLastPathComponent()
                let args = ["-r", "-q", archiveURL.path, baseName]
                let ok = runZip(arguments: args, currentDirectory: parent)
                if ok {
                    completed = true
                    return archiveURL
                } else {
                    return nil
                }
            } else {
                // File: include the file only (no parent folders). Name should include original extension.
                archiveName = "\(baseName).zip"
                let archiveURL = workingDir.appendingPathComponent(archiveName)
                let parent = src.deletingLastPathComponent()
                // -j to junk paths and store only the file
                let args = ["-j", "-q", archiveURL.path, baseName]
                let ok = runZip(arguments: args, currentDirectory: parent)
                if ok {
                    completed = true
                    return archiveURL
                } else {
                    return nil
                }
            }
        }

        // Multi-item: copy items into working dir (so their relative structure is preserved), zip, then remove copies.
        for src in urls {
            let dest = workingDir.appendingPathComponent(src.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    // Avoid collision by appending a suffix
                    let unique = "\(UUID().uuidString)_\(src.lastPathComponent)"
                    try FileManager.default.copyItem(at: src, to: workingDir.appendingPathComponent(unique))
                } else {
                    try FileManager.default.copyItem(at: src, to: dest)
                }
            } catch {
                return nil
            }
        }

        let archiveName = Self.safeFilename(suggestedName ?? "Archive.zip")
        let archiveURL = workingDir.appendingPathComponent(archiveName)
        let args = ["-r", "-q", archiveURL.path, "."]
        let ok = runZip(arguments: args, currentDirectory: workingDir)
        if ok {
            // Remove the copied (uncompressed) items so the temp folder contains only the archive
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: workingDir, includingPropertiesForKeys: nil)
                for file in contents {
                    if file.standardizedFileURL != archiveURL.standardizedFileURL {
                        try FileManager.default.removeItem(at: file)
                    }
                }
            } catch {
                print("⚠️ Failed to cleanup working directory after zip: \(error)")
            }
            completed = true
            return archiveURL
        } else {
            return nil
        }
    }
}
