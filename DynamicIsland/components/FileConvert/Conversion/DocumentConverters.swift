import AppKit
import UniformTypeIdentifiers

/// Text documents through NSAttributedString, which reads and writes Word,
/// ODT, RTF, HTML and plain text. Layout-heavy documents lose some formatting,
/// so PDF output is left to LibreOffice.
struct TextDocumentConverter: FileConverter {
    static let maximumBytes = 50 * 1024 * 1024
    private static let documentTypes: [String: NSAttributedString.DocumentType] = [
        ConversionFormat.docx.id: .officeOpenXML, ConversionFormat.odt.id: .openDocument,
        ConversionFormat.rtf.id: .rtf, ConversionFormat.html.id: .html, ConversionFormat.text.id: .plain,
    ]

    var routes: [ConversionRoute] {
        [ConversionRoute(inputs: [.wordDocument, .legacyWordDocument, .openDocumentText, .rtf, .html, .plainText],
                         outputs: [.docx, .odt, .rtf, .html, .text])]
    }

    func convert(_ source: URL, to format: ConversionFormat, in staging: URL) async throws -> [URL] {
        let values = try? source.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        guard (values?.fileSize ?? 0) <= Self.maximumBytes else { throw ConversionError.tooLarge("50 MB") }
        guard let documentType = Self.documentTypes[format.id] else { throw ConversionError.unsupported }
        // The HTML importer uses WebKit, which has to run on the main thread.
        let data = values?.contentType?.conforms(to: .html) == true
            ? try await MainActor.run { try Self.reencode(source, as: documentType) }
            : try Self.reencode(source, as: documentType)
        try Task.checkCancellation()
        let destination = stagedURL(for: source, as: format, in: staging)
        try data.write(to: destination)
        return [destination]
    }

    private static func reencode(_ url: URL, as documentType: NSAttributedString.DocumentType) throws -> Data {
        let document: NSAttributedString
        do { document = try NSAttributedString(url: url, options: [:], documentAttributes: nil) }
        catch { throw ConversionError.unreadable }
        do {
            return try document.data(from: NSRange(location: 0, length: document.length),
                                     documentAttributes: [.documentType: documentType,
                                                          .characterEncoding: String.Encoding.utf8.rawValue])
        } catch { throw ConversionError.unsupported }
    }
}

/// Office documents, spreadsheets and presentations to PDF with their layout,
/// when LibreOffice is installed.
struct LibreOfficeConverter: FileConverter {
    var routes: [ConversionRoute] {
        [ConversionRoute(inputs: [.wordDocument, .legacyWordDocument, .openDocumentText, .rtf,
                                  .excelWorkbook, .legacyExcelWorkbook, .openDocumentSpreadsheet,
                                  .powerPointPresentation, .legacyPowerPointPresentation, .openDocumentPresentation],
                         outputs: [.pdf])]
    }
    var priority: Int { 10 }
    var isAvailable: Bool { ExternalConversionTool.libreOffice.executable != nil }

    func convert(_ source: URL, to format: ConversionFormat, in staging: URL) async throws -> [URL] {
        // A private profile lets this run beside an open LibreOffice window,
        // which would otherwise take the job and exit without converting. It
        // lives in this run's temporary area, removed when the app quits.
        let profile = AtollTemporaryFiles.directory(.fileConvert).appendingPathComponent("LibreOfficeProfile", isDirectory: true)
        try await ExternalConversionTool.libreOffice.run([
            "-env:UserInstallation=\(profile.absoluteString)", "--headless", "--norestore", "--nolockcheck",
            "--convert-to", format.id, "--outdir", staging.path, source.path,
        ], timeout: 180)
        // LibreOffice can exit successfully without writing anything.
        let output = stagedURL(for: source, as: format, in: staging)
        guard FileManager.default.fileExists(atPath: output.path) else { throw ConversionError.noOutput }
        return [output]
    }
}
