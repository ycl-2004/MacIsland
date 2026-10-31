import AppKit
import Defaults
import SwiftUI
import XCTest
@testable import Atoll

/// Diagnostic render probe. Snapshots are inspected alongside routing tests.
@MainActor
final class ShelfWorkspaceRenderProbeTests: XCTestCase {
    func testRenderToolCombinationsAndLoadedConversion() async throws {
        let keys: [Defaults.Key<Bool>] = [.dynamicShelf, .shelfFileDropEnabled, .shelfAirDropEnabled, .enableFileConvertFeature, .fileConvertKeepOriginal]
        let saved = keys.map { Defaults[$0] }
        let vm = DynamicIslandViewModel()
        let shelf = ShelfStateViewModel.shared
        await shelf.awaitInitialLoad()
        shelf.removeAll()
        let model = FileConvertModel.shared
        model.clear()
        let output = URL(fileURLWithPath: "/tmp/atoll-shelf-workspace-20261020", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer {
            shelf.removeAll()
            model.clear()
            zip(keys, saved).forEach { Defaults[$0] = $1 }
            vm.destroy()
        }
        Defaults[.dynamicShelf] = true
        for mask in 0..<8 {
            Defaults[.shelfFileDropEnabled] = mask & 1 != 0
            Defaults[.shelfAirDropEnabled] = mask & 2 != 0
            Defaults[.enableFileConvertFeature] = mask & 4 != 0
            try await snapshot(NotchShelfView().environmentObject(vm), size: NSSize(width: 640, height: 150),
                               to: output.appendingPathComponent("tools-\(mask).png"))
        }
        keys.forEach { Defaults[$0] = true }
        shelf.add([ShelfItem(kind: .text(string: "Draft for the next release"))])
        let source = output.appendingPathComponent("Product screenshot with a long name.png")
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor.orange.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        image.unlockFocus()
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: source)
        model.load([source])
        try await snapshot(NotchShelfView().environmentObject(vm), size: NSSize(width: 640, height: 150),
                           to: output.appendingPathComponent("loaded.png"))
        model.convert(to: .jpeg)
        for _ in 0..<300 where model.isWorking { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.hasResults)
        try await snapshot(NotchShelfView().environmentObject(vm), size: NSSize(width: 640, height: 150),
                           to: output.appendingPathComponent("converted.png"))
        try await snapshot(Shelf().environmentObject(SettingsHighlightCoordinator()).formStyle(.grouped), size: NSSize(width: 600, height: 900),
                           to: output.appendingPathComponent("settings.png"))
    }

    private func snapshot<Content: View>(_ content: Content, size: NSSize, to url: URL) async throws {
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height)
            .background(Color.black).environment(\.colorScheme, .dark))
        host.sizingOptions = []
        let window = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(250))
        host.layoutSubtreeIfNeeded()
        host.needsDisplay = true
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}
