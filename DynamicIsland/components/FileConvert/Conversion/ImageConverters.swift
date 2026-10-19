import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Image to image (and single-page PDF) through ImageIO, which ships with macOS.
struct ImageConverter: FileConverter {
    /// What this Mac's ImageIO can encode; HEIC needs suitable hardware.
    private static let writable = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
    private static let multiFrame: Set<String> = [ConversionFormat.gif.id, ConversionFormat.tiff.id, ConversionFormat.pdf.id]
    private static let opaque: Set<String> = [ConversionFormat.jpeg.id, ConversionFormat.bmp.id]
    static let maximumFrames = 500

    var routes: [ConversionRoute] {
        [ConversionRoute(inputs: [.image], outputs: [.jpeg, .png, .heic, .tiff, .gif, .bmp, .pdf]
            .filter { Self.writable.contains($0.type.identifier) })]
    }

    func convert(_ source: URL, to format: ConversionFormat, in staging: URL) async throws -> [URL] {
        // Nonisolated async work runs off the main actor and keeps the caller's cancellation.
        let destination = stagedURL(for: source, as: format, in: staging)
        try Self.write(source, as: format, to: destination)
        return [destination]
    }

    private static func write(_ source: URL, as format: ConversionFormat, to destination: URL) throws {
        guard let input = CGImageSourceCreateWithURL(source as CFURL, nil) else { throw ConversionError.unreadable }
        let available = CGImageSourceGetCount(input)
        guard available > 0 else { throw ConversionError.unreadable }
        let frames = multiFrame.contains(format.id) ? min(available, maximumFrames) : 1
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, format.type.identifier as CFString, frames, nil) else {
            throw ConversionError.unsupported
        }
        let quality = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        for index in 0..<frames {
            try Task.checkCancellation()
            if opaque.contains(format.id) {
                // JPEG has no alpha; transparent areas would otherwise turn black.
                guard let flattened = flattenedImage(input, at: index) else { throw ConversionError.unreadable }
                CGImageDestinationAddImage(output, flattened, quality)
            } else {
                // Copies metadata, including the orientation tag, with the pixels.
                CGImageDestinationAddImageFromSource(output, input, index, quality)
            }
        }
        guard CGImageDestinationFinalize(output) else { throw ConversionError.unreadable }
    }

    /// Full-size frame with its orientation applied, composited over white.
    private static func flattenedImage(_ source: CGImageSource, at index: Int) -> CGImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: max(width, height, 1)] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(.white)
        context.fill(bounds)
        context.draw(image, in: bounds)
        return context.makeImage()
    }
}

/// PDF pages to images through PDFKit; every page becomes its own file.
struct PDFPageConverter: FileConverter {
    static let maximumPages = 100
    /// 144 dpi: sharp on Retina screens without very large files.
    static let scale: CGFloat = 2

    var routes: [ConversionRoute] { [ConversionRoute(inputs: [.pdf], outputs: [.png, .jpeg])] }

    func convert(_ source: URL, to format: ConversionFormat, in staging: URL) async throws -> [URL] {
        try Self.render(source, as: format, base: stagedURL(for: source, as: format, in: staging))
    }

    private static func render(_ source: URL, as format: ConversionFormat, base: URL) throws -> [URL] {
        guard let document = PDFDocument(url: source), document.pageCount > 0, !document.isLocked else {
            throw ConversionError.unreadable
        }
        guard document.pageCount <= maximumPages else {
            throw ConversionError.tooLarge(String(localized: "\(maximumPages) pages"))
        }
        let name = base.deletingPathExtension().lastPathComponent
        var written: [URL] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index), let image = image(of: page) else { throw ConversionError.unreadable }
            let destination = document.pageCount == 1 ? base
                : base.deletingLastPathComponent().appendingPathComponent("\(name)-\(index + 1)").appendingPathExtension(format.id)
            guard let output = CGImageDestinationCreateWithURL(destination as CFURL, format.type.identifier as CFString, 1, nil) else {
                throw ConversionError.unsupported
            }
            CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            guard CGImageDestinationFinalize(output) else { throw ConversionError.unreadable }
            written.append(destination)
        }
        return written
    }

    private static func image(of page: PDFPage) -> CGImage? {
        let box = page.bounds(for: .cropBox)
        let quarterTurns = (page.rotation / 90) % 2 != 0
        let size = CGSize(width: (quarterTurns ? box.height : box.width) * scale,
                          height: (quarterTurns ? box.width : box.height) * scale)
        guard size.width >= 1, size.height >= 1, size.width * size.height <= 100_000_000,
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(.white)
        context.fill(CGRect(origin: .zero, size: size))
        context.scaleBy(x: scale, y: scale)
        // Applies the page's rotation and crop-box origin before drawing.
        page.transform(context, for: .cropBox)
        page.draw(with: .cropBox, to: context)
        return context.makeImage()
    }
}
