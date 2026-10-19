import Foundation
import UniformTypeIdentifiers

/// Chooses a converter, places its results beside the original and handles
/// the original. Knows converters only through the registry.
struct FileConversionService: Sendable {
    struct Outcome: Equatable, Sendable {
        let outputs: [URL]
        let originalTrashed: Bool
        /// Set when the original was meant to go to the Trash but stayed.
        let trashFailure: String?
    }

    let converters: [any FileConverter]
    private let stagingRoot: @Sendable () -> URL
    private let trash: @Sendable (URL) throws -> Void

    init(converters: [any FileConverter] = FileConverterRegistry.converters,
         stagingRoot: @escaping @Sendable () -> URL = { AtollTemporaryFiles.directory(.fileConvert) },
         trash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.converters = converters
        self.stagingRoot = stagingRoot
        self.trash = trash
    }

    static func contentType(of url: URL) -> UTType? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? UTType(filenameExtension: url.pathExtension)
    }

    /// One available converter per format, in registry and route order.
    func choices(for type: UTType) -> [(format: ConversionFormat, converter: any FileConverter)] {
        var order: [String] = []
        var picked: [String: (format: ConversionFormat, converter: any FileConverter)] = [:]
        for converter in converters where converter.isAvailable {
            for format in converter.outputs(for: type) {
                if let current = picked[format.id] {
                    guard converter.priority > current.converter.priority else { continue }
                } else {
                    order.append(format.id)
                }
                picked[format.id] = (format, converter)
            }
        }
        return order.compactMap { picked[$0] }
    }

    /// Formats every file can be converted to, in the first file's order.
    func formats(for files: [URL]) -> [ConversionFormat] {
        let lists = files.map { url in Self.contentType(of: url).map { choices(for: $0).map(\.format) } ?? [] }
        guard let first = lists.first else { return [] }
        return first.filter { format in lists.allSatisfy { $0.contains(format) } }
    }

    /// Converts into a private staging folder first, so a failed or cancelled
    /// conversion never leaves a partial file next to the original, and the
    /// original is only touched after every result is in place.
    func convert(_ source: URL, to format: ConversionFormat, keepOriginal: Bool) async throws -> Outcome {
        guard let type = Self.contentType(of: source),
              let converter = choices(for: type).first(where: { $0.format == format })?.converter else {
            throw ConversionError.unsupported
        }
        let fileManager = FileManager.default
        let staging = stagingRoot().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fileManager.removeItem(at: staging) }

        let produced: [URL]
        do {
            produced = try await converter.convert(source, to: format, in: staging)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw ConversionError.cancelled
        }
        let stagingPath = staging.standardizedFileURL.path + "/"
        guard !produced.isEmpty, produced.allSatisfy({ file in
            file.standardizedFileURL.path.hasPrefix(stagingPath)
                && ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
        }) else { throw ConversionError.noOutput }

        let folder = source.deletingLastPathComponent()
        var placed: [URL] = []
        do {
            for file in produced { placed.append(try Self.place(file, in: folder)) }
        } catch {
            placed.forEach { try? fileManager.removeItem(at: $0) }
            if (error as? CocoaError)?.code == .fileWriteNoPermission { throw ConversionError.folderNotWritable }
            throw error
        }
        guard !keepOriginal else { return Outcome(outputs: placed, originalTrashed: false, trashFailure: nil) }
        do {
            // The Trash, not deletion, so a mistaken conversion can be undone.
            try trash(source)
            return Outcome(outputs: placed, originalTrashed: true, trashFailure: nil)
        } catch {
            return Outcome(outputs: placed, originalTrashed: false, trashFailure: error.localizedDescription)
        }
    }

    /// Moves without overwriting; a taken name becomes "name 2.ext", "name 3.ext", …
    static func place(_ file: URL, in folder: URL) throws -> URL {
        let base = file.deletingPathExtension().lastPathComponent, ext = file.pathExtension
        for attempt in 1...999 {
            let name = attempt == 1 ? file.lastPathComponent : "\(base) \(attempt).\(ext)"
            let destination = folder.appendingPathComponent(name)
            do {
                try FileManager.default.moveItem(at: file, to: destination)
                return destination
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}
