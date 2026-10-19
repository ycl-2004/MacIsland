import AVFoundation
import Defaults
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Atoll

@MainActor
final class FileConvertTests: XCTestCase {
    private func folder() throws -> URL {
        let url = AppRuntimeEnvironment.testDirectory.appendingPathComponent("FileConvert-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func names(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition did not become true")
        throw NSError(domain: "FileConvertTestTimeout", code: 1)
    }

    // MARK: Service: shared mechanism, with stand-in converters

    func testChoicesPreferHigherPriorityHideMissingEnginesAndSkipTheSameType() {
        let service = FileConversionService(converters: [
            FakeConverter(routes: [ConversionRoute(inputs: [.image], outputs: [.png, .jpeg, .webP])]),
            FakeConverter(routes: [ConversionRoute(inputs: [.png], outputs: [.webP])], priority: 10),
            FakeConverter(routes: [ConversionRoute(inputs: [.png], outputs: [.gif])], isAvailable: false),
        ])
        let choices = service.choices(for: .png)
        XCTAssertEqual(choices.map(\.format), [.jpeg, .webP])
        XCTAssertEqual(choices.last?.converter.priority, 10)
    }

    func testSeveralFilesOfferOnlyTheFormatsTheyShare() throws {
        let dir = try folder()
        let files = ["a.png", "b.jpg", "c.txt"].map { dir.appendingPathComponent($0) }
        try files.forEach { try Data().write(to: $0) }
        let service = FileConversionService()
        let images = service.formats(for: Array(files.prefix(2)))
        XCTAssertTrue(images.contains(.tiff))
        XCTAssertFalse(images.contains(.png))
        XCTAssertFalse(images.contains(.jpeg))
        XCTAssertEqual(service.formats(for: [files[0], files[2]]), [])
    }

    func testResultLandsBesideTheOriginalWithoutReplacingAndStagingIsRemoved() async throws {
        let dir = try folder(), staging = try folder()
        let source = dir.appendingPathComponent("photo.png")
        try Data("source".utf8).write(to: source)
        try Data("existing".utf8).write(to: dir.appendingPathComponent("photo.jpg"))
        let trash = TrashRecorder()
        let service = FileConversionService(converters: [FakeConverter(routes: [ConversionRoute(inputs: [.png], outputs: [.jpeg])])],
                                            stagingRoot: { staging }, trash: trash.record)
        let outcome = try await service.convert(source, to: .jpeg, keepOriginal: true)
        XCTAssertEqual(outcome.outputs.map(\.lastPathComponent), ["photo 2.jpg"])
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("photo.jpg"), encoding: .utf8), "existing")
        XCTAssertEqual(try names(in: dir), ["photo 2.jpg", "photo.jpg", "photo.png"])
        XCTAssertFalse(outcome.originalTrashed)
        XCTAssertTrue(trash.urls.isEmpty)
        XCTAssertEqual(try names(in: staging), [])
    }

    func testOriginalGoesToTheTrashOnlyAfterASuccessfulConversion() async throws {
        let dir = try folder(), staging = try folder()
        let source = dir.appendingPathComponent("report.png")
        try Data("source".utf8).write(to: source)
        let route = [ConversionRoute(inputs: [.png], outputs: [.jpeg])]
        let trash = TrashRecorder()

        let failing = FileConversionService(converters: [FakeConverter(routes: route, fails: true)], stagingRoot: { staging }, trash: trash.record)
        do {
            _ = try await failing.convert(source, to: .jpeg, keepOriginal: false)
            XCTFail("A failed conversion must throw")
        } catch {}
        XCTAssertTrue(trash.urls.isEmpty)
        XCTAssertEqual(try names(in: dir), ["report.png"])

        let working = FileConversionService(converters: [FakeConverter(routes: route)], stagingRoot: { staging }, trash: trash.record)
        let outcome = try await working.convert(source, to: .jpeg, keepOriginal: false)
        XCTAssertTrue(outcome.originalTrashed)
        XCTAssertEqual(trash.urls, [source])

        trash.fails = true
        let kept = try await working.convert(source, to: .jpeg, keepOriginal: false)
        XCTAssertFalse(kept.originalTrashed)
        XCTAssertNotNil(kept.trashFailure)
        XCTAssertEqual(kept.outputs.map(\.lastPathComponent), ["report 2.jpg"])
        XCTAssertEqual(try names(in: staging), [])
    }

    func testCancelledConversionLeavesNothingBehind() async throws {
        let dir = try folder(), staging = try folder()
        let source = dir.appendingPathComponent("clip.png")
        try Data("source".utf8).write(to: source)
        let service = FileConversionService(
            converters: [FakeConverter(routes: [ConversionRoute(inputs: [.png], outputs: [.jpeg])], delay: .seconds(5))],
            stagingRoot: { staging }, trash: TrashRecorder().record)
        let task = Task { try await service.convert(source, to: .jpeg, keepOriginal: false) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancellation must throw")
        } catch {
            XCTAssertEqual(error as? ConversionError, .cancelled)
        }
        XCTAssertEqual(try names(in: dir), ["clip.png"])
        XCTAssertEqual(try names(in: staging), [])
    }

    // MARK: Converters: what each one owns

    func testImageToJPEGFlattensTransparencyOntoWhite() async throws {
        let dir = try folder(), staging = try folder()
        let png = dir.appendingPathComponent("clear.png")
        try writeImage(transparentPixels: 8, as: .png, to: png)
        let output = try await ImageConverter().convert(png, to: .jpeg, in: staging)
        XCTAssertEqual(output.map(\.lastPathComponent), ["clear.jpg"])
        let pixel = try XCTUnwrap(firstPixel(of: output[0]))
        XCTAssertGreaterThan(pixel, 245, "Transparent areas should become white, not black")
    }

    func testPDFBecomesOneImagePerPage() async throws {
        let dir = try folder(), staging = try folder()
        let pdf = dir.appendingPathComponent("doc.pdf")
        var box = CGRect(x: 0, y: 0, width: 200, height: 100)
        let context = try XCTUnwrap(CGContext(pdf as CFURL, mediaBox: &box, nil))
        for _ in 0..<2 { context.beginPDFPage(nil); context.endPDFPage() }
        context.closePDF()
        let output = try await PDFPageConverter().convert(pdf, to: .png, in: staging)
        XCTAssertEqual(output.map(\.lastPathComponent), ["doc-1.png", "doc-2.png"])
        let image = try XCTUnwrap(CGImageSourceCreateWithURL(output[0] as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        XCTAssertEqual(image.width, Int(200 * PDFPageConverter.scale))
    }

    func testTextDocumentKeepsItsTextThroughWord() async throws {
        let dir = try folder(), staging = try folder()
        let rtf = try writeRTF("Hello 世界", in: dir)
        let output = try await TextDocumentConverter().convert(rtf, to: .docx, in: staging)
        let reopened = try NSAttributedString(url: output[0], options: [:], documentAttributes: nil)
        XCTAssertTrue(reopened.string.contains("Hello 世界"))
    }

    func testAudioBecomesAAC() async throws {
        let dir = try folder(), staging = try folder()
        let wav = dir.appendingPathComponent("tone.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22_050))
        buffer.frameLength = 22_050
        for frame in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][frame] = sin(Float(frame) * 0.06) * 0.4 }
        do {
            let file = try AVAudioFile(forWriting: wav, settings: format.settings)
            try file.write(from: buffer)
        }
        let output = try await AudioConverter().convert(wav, to: .m4a, in: staging)
        XCTAssertGreaterThan(try AVAudioFile(forReading: output[0]).length, 0)
    }

    func testVideoRemuxesNativelyAndFFmpegMakesAnAnimatedGIF() async throws {
        guard ExternalConversionTool.ffmpeg.executable != nil else { throw XCTSkip("FFmpeg is not installed") }
        let dir = try folder()
        let clip = dir.appendingPathComponent("clip.mov")
        try await ExternalConversionTool.ffmpeg.run(["-nostdin", "-loglevel", "error", "-f", "lavfi",
            "-i", "testsrc=duration=1:size=64x64:rate=10", "-pix_fmt", "yuv420p", "-c:v", "libx264", clip.path], timeout: 60)
        let mp4 = try await VideoConverter().convert(clip, to: .mp4, in: try folder())
        let duration = try await AVURLAsset(url: mp4[0]).load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0.5)
        let gif = try await FFmpegConverter().convert(clip, to: .gif, in: try folder())
        let frames = CGImageSourceCreateWithURL(gif[0] as CFURL, nil).map(CGImageSourceGetCount) ?? 0
        XCTAssertGreaterThan(frames, 1)
    }

    func testLibreOfficeMakesAPDFFromWord() async throws {
        guard ExternalConversionTool.libreOffice.executable != nil else { throw XCTSkip("LibreOffice is not installed") }
        let dir = try folder()
        let rtf = try writeRTF("Quarterly report", in: dir)
        let docx = try await TextDocumentConverter().convert(rtf, to: .docx, in: dir)
        let pdf = try await LibreOfficeConverter().convert(docx[0], to: .pdf, in: try folder())
        XCTAssertTrue(try XCTUnwrap(PDFDocument(url: pdf[0])?.string).contains("Quarterly report"))
    }

    // MARK: Model and notch routing

    func testModelAcceptsFileDropsWithinTheLimitAndExplainsFolders() async throws {
        let dir = try folder()
        let png = dir.appendingPathComponent("a.png")
        try writeImage(transparentPixels: 4, as: .png, to: png)
        let key = Defaults.Key<Bool>("file-convert-\(UUID())", default: true)
        let model = FileConvertModel(enabledKey: key)
        XCTAssertFalse(model.receive([NSItemProvider(object: "text" as NSString)]))
        XCTAssertFalse(model.receive((0...FileConvertModel.maximumFiles).map { _ in NSItemProvider(object: png as NSURL) }))
        XCTAssertNotNil(model.message)
        XCTAssertTrue(model.receive([NSItemProvider(object: png as NSURL)]))
        try await waitUntil { !model.isWorking && model.items.count == 1 }
        XCTAssertTrue(model.formats.contains(.jpeg))
        model.load([dir, png])
        XCTAssertEqual(model.items.map(\.url), [png])
        XCTAssertNotNil(model.message, "Skipping a folder needs an explanation")
        Defaults[key] = false
        XCTAssertFalse(model.receive([NSItemProvider(object: png as NSURL)]))
    }

    func testModelConvertsEveryFileAndClearDropsLateResults() async throws {
        let dir = try folder(), staging = try folder()
        let files = ["a.png", "b.png"].map { dir.appendingPathComponent($0) }
        try files.forEach { try Data("x".utf8).write(to: $0) }
        let keep = Defaults.Key<Bool>("file-convert-keep-\(UUID())", default: false)
        let trash = TrashRecorder()
        let route = [ConversionRoute(inputs: [.png], outputs: [.jpeg])]
        let model = FileConvertModel(service: FileConversionService(converters: [FakeConverter(routes: route)],
                                                                    stagingRoot: { staging }, trash: trash.record),
                                     enabledKey: Defaults.Key<Bool>("file-convert-on-\(UUID())", default: true), keepOriginalKey: keep)
        model.load(files)
        model.convert(to: .jpeg)
        try await waitUntil { !model.isWorking }
        XCTAssertTrue(model.items.allSatisfy { if case .converted = $0.status { return true } else { return false } })
        XCTAssertTrue(model.items.allSatisfy { $0.note != nil })
        XCTAssertEqual(trash.urls, files)
        XCTAssertTrue(model.formats.isEmpty, "Trashed originals can't be converted again")

        let slow = FileConvertModel(service: FileConversionService(converters: [FakeConverter(routes: route, delay: .seconds(5))],
                                                                   stagingRoot: { staging }, trash: trash.record),
                                    enabledKey: Defaults.Key<Bool>("file-convert-on-\(UUID())", default: true), keepOriginalKey: keep)
        let late = dir.appendingPathComponent("c.png")
        try Data("x".utf8).write(to: late)
        slow.load([late])
        slow.convert(to: .jpeg)
        try await waitUntil { slow.items.first?.status == .converting }
        slow.clear()
        XCTAssertFalse(slow.isWorking)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(slow.items.isEmpty)
        XCTAssertEqual(try names(in: staging), [])
    }

    func testOpenConvertTabKeepsItsDropsAndAClosedNotchOpensItWhenShelfIsOff() async throws {
        let dir = try folder()
        let png = dir.appendingPathComponent("a.png")
        try writeImage(transparentPixels: 4, as: .png, to: png)
        let (vm, coordinator) = notch()
        let saved = (Defaults[.dynamicShelf], Defaults[.enableFileConvertFeature])
        Defaults[.dynamicShelf] = true
        Defaults[.enableFileConvertFeature] = true
        defer {
            Defaults[.dynamicShelf] = saved.0
            Defaults[.enableFileConvertFeature] = saved.1
            vm.destroy()
        }
        let model = FileConvertModel(enabledKey: Defaults.Key<Bool>("file-convert-on-\(UUID())", default: true))

        coordinator.currentView = .fileConvert
        vm.open()
        vm.revealDropTarget()
        XCTAssertEqual(coordinator.currentView, .fileConvert)
        XCTAssertFalse(vm.receiveShelfDrop([NSItemProvider(object: "text" as NSString)]))
        XCTAssertTrue(vm.receiveNotchDrop([NSItemProvider(object: png as NSURL)], convertModel: model))
        try await waitUntil { model.items.count == 1 }

        vm.close()
        Defaults[.dynamicShelf] = false
        vm.revealDropTarget()
        XCTAssertEqual(coordinator.currentView, .fileConvert)
        XCTAssertEqual(vm.notchState, .open)
    }

    func testRestingADragOnATabSwitchesToIt() async throws {
        let (vm, coordinator) = notch()
        defer { vm.destroy() }
        coordinator.currentView = .home
        vm.beginSpringLoad(.fileConvert, after: 0.01)
        try await waitUntil { coordinator.currentView == .fileConvert }
        vm.beginSpringLoad(.home, after: 0.01)
        vm.beginSpringLoad(.shelf, after: 0.05)
        vm.cancelSpringLoad()
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(coordinator.currentView, .fileConvert, "Home has no drops, and a cancelled rest switches nothing")
    }

    // MARK: Fixtures

    private func notch() -> (DynamicIslandViewModel, DynamicIslandViewCoordinator) {
        let vm = DynamicIslandViewModel()
        let coordinator = DynamicIslandViewCoordinator(availability: {
            NotchTabAvailability(home: true, shelf: true, timer: false, stats: false, agents: false,
                                 extraSpace: false, colorPicker: false, fileConvert: true)
        }, observeDefaults: false)
        vm.coordinator = coordinator
        return (vm, coordinator)
    }

    private func writeImage(transparentPixels size: Int, as type: UTType, to url: URL) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    /// The red channel of the top-left pixel.
    private func firstPixel(of url: URL) -> UInt8? {
        guard let image = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return pixel[0]
    }

    private func writeRTF(_ text: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent("note.rtf")
        let document = NSAttributedString(string: text)
        try document.data(from: NSRange(location: 0, length: document.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            .write(to: url)
        return url
    }
}

private struct FakeConverter: FileConverter {
    let routes: [ConversionRoute]
    var priority = 0
    var isAvailable = true
    var fails = false
    var delay: Duration?

    init(routes: [ConversionRoute], priority: Int = 0, isAvailable: Bool = true, fails: Bool = false, delay: Duration? = nil) {
        self.routes = routes; self.priority = priority; self.isAvailable = isAvailable; self.fails = fails; self.delay = delay
    }

    func convert(_ source: URL, to format: ConversionFormat, in staging: URL) async throws -> [URL] {
        if let delay { try await Task.sleep(for: delay) }
        if fails { throw ConversionError.unreadable }
        let output = stagedURL(for: source, as: format, in: staging)
        try Data("converted".utf8).write(to: output)
        return [output]
    }
}

private final class TrashRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URL] = []
    private var failing = false
    var urls: [URL] { lock.withLock { recorded } }
    var fails: Bool {
        get { lock.withLock { failing } }
        set { lock.withLock { failing = newValue } }
    }

    func record(_ url: URL) throws {
        try lock.withLock {
            if failing { throw CocoaError(.fileWriteNoPermission) }
            recorded.append(url)
        }
    }
}
