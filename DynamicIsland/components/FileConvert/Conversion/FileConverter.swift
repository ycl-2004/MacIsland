import Foundation
import UniformTypeIdentifiers

/// One file format a converter can write. `id` is the extension the result gets.
struct ConversionFormat: Hashable, Sendable, Identifiable {
    let id: String
    let type: UTType
    let label: String

    static let jpeg = Self(id: "jpg", type: .jpeg, label: "JPEG")
    static let png = Self(id: "png", type: .png, label: "PNG")
    static let heic = Self(id: "heic", type: .heic, label: "HEIC")
    static let tiff = Self(id: "tiff", type: .tiff, label: "TIFF")
    static let gif = Self(id: "gif", type: .gif, label: "GIF")
    static let bmp = Self(id: "bmp", type: .bmp, label: "BMP")
    static let webP = Self(id: "webp", type: .webP, label: "WebP")
    static let pdf = Self(id: "pdf", type: .pdf, label: "PDF")
    static let docx = Self(id: "docx", type: .wordDocument, label: "Word")
    static let odt = Self(id: "odt", type: .openDocumentText, label: "ODT")
    static let rtf = Self(id: "rtf", type: .rtf, label: "RTF")
    static let html = Self(id: "html", type: .html, label: "HTML")
    static let text = Self(id: "txt", type: .plainText, label: "Text")
    static let mp4 = Self(id: "mp4", type: .mpeg4Movie, label: "MP4")
    static let mov = Self(id: "mov", type: .quickTimeMovie, label: "MOV")
    static let webm = Self(id: "webm", type: UTType(importedAs: "org.webmproject.webm", conformingTo: .movie), label: "WebM")
    static let m4a = Self(id: "m4a", type: .mpeg4Audio, label: "M4A")
    static let wav = Self(id: "wav", type: .wav, label: "WAV")
    static let aiff = Self(id: "aiff", type: .aiff, label: "AIFF")
    static let mp3 = Self(id: "mp3", type: .mp3, label: "MP3")
    static let flac = Self(id: "flac", type: UTType(importedAs: "org.xiph.flac", conformingTo: .audio), label: "FLAC")
}

extension UTType {
    // Office formats the system declares without a UTType constant.
    static let wordDocument = UTType(importedAs: "org.openxmlformats.wordprocessingml.document")
    static let legacyWordDocument = UTType(importedAs: "com.microsoft.word.doc")
    static let openDocumentText = UTType(importedAs: "org.oasis-open.opendocument.text")
    static let excelWorkbook = UTType(importedAs: "org.openxmlformats.spreadsheetml.sheet")
    static let legacyExcelWorkbook = UTType(importedAs: "com.microsoft.excel.xls")
    static let openDocumentSpreadsheet = UTType(importedAs: "org.oasis-open.opendocument.spreadsheet")
    static let powerPointPresentation = UTType(importedAs: "org.openxmlformats.presentationml.presentation")
    static let legacyPowerPointPresentation = UTType(importedAs: "com.microsoft.powerpoint.ppt")
    static let openDocumentPresentation = UTType(importedAs: "org.oasis-open.opendocument.presentation")
}

/// Inputs that one converter turns into each of `outputs`.
struct ConversionRoute: Sendable {
    let inputs: [UTType]
    let outputs: [ConversionFormat]
}

enum ConversionError: LocalizedError, Equatable {
    case unsupported
    case unreadable
    case tooLarge(String)
    case engineMissing(String)
    case engineFailed(String)
    case noOutput
    case folderNotWritable
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsupported: return String(localized: "This file can’t be converted to that format.")
        case .unreadable: return String(localized: "The file couldn’t be read.")
        case .tooLarge(let limit): return String(localized: "The file is too large to convert (limit \(limit)).")
        case .engineMissing(let name): return String(localized: "\(name) isn’t installed.")
        case .engineFailed(let detail): return detail
        case .noOutput: return String(localized: "The conversion produced no file.")
        case .folderNotWritable: return String(localized: "Can’t save in this folder. Allow access in System Settings › Privacy & Security › Files and Folders.")
        case .cancelled: return String(localized: "Conversion cancelled.")
        }
    }
}

/// A converter declares what it reads and writes; it only implements the
/// conversion itself. Naming, placement next to the original, collision
/// handling and the original's fate belong to `FileConversionService`.
protocol FileConverter: Sendable {
    /// Which inputs this converter maps to which outputs.
    var routes: [ConversionRoute] { get }
    /// When two available converters write the same format for a file, the higher one is used.
    var priority: Int { get }
    /// External engines report false while their tool is missing, hiding their formats.
    var isAvailable: Bool { get }
    /// Writes the result into `staging`, an empty private folder, and returns
    /// every file written. One input may produce several files (PDF pages).
    func convert(_ source: URL, to format: ConversionFormat, in staging: URL) async throws -> [URL]
}

extension FileConverter {
    var priority: Int { 0 }
    var isAvailable: Bool { true }

    /// Formats offered for `type`; converting to the type a file already has is never offered.
    func outputs(for type: UTType) -> [ConversionFormat] {
        routes.filter { route in route.inputs.contains { type.conforms(to: $0) } }
            .flatMap(\.outputs)
            .filter { !type.conforms(to: $0.type) }
    }

    /// The single-result name: the source's base name with the format's extension.
    func stagedURL(for source: URL, as format: ConversionFormat, in staging: URL) -> URL {
        staging.appendingPathComponent(source.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(format.id)
    }
}
