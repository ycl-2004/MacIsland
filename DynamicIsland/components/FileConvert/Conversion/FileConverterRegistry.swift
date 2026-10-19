/// Every converter File Convert offers. A new converter is its own type plus one line here.
enum FileConverterRegistry {
    static let converters: [any FileConverter] = [
        ImageConverter(),
        PDFPageConverter(),
        TextDocumentConverter(),
        LibreOfficeConverter(),
        AudioConverter(),
        VideoConverter(),
        FFmpegConverter(),
    ]
}
