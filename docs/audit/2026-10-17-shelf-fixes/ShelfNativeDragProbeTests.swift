import AppKit
import Defaults
import SwiftUI
import XCTest
@testable import Atoll

/// Interactive fixture. Use CUA to drag the card onto the local test target.
/// Archived after verification; never sends a file to another app or person.
@MainActor
final class ShelfNativeDragProbeTests: XCTestCase {
    func testNativeDragOfExternallyRenamedFile() async throws {
        let shelf = ShelfStateViewModel.shared
        await shelf.awaitInitialLoad()
        let enabled = Defaults[.dynamicShelf], remove = Defaults[.autoRemoveShelfItems]
        Defaults[.dynamicShelf] = true
        Defaults[.autoRemoveShelfItems] = false
        shelf.removeAll()
        let vm = DynamicIslandViewModel()
        defer { shelf.removeAll(); Defaults[.dynamicShelf] = enabled; Defaults[.autoRemoveShelfItems] = remove; vm.destroy() }
        let folder = AppRuntimeEnvironment.testDirectory.appendingPathComponent("NativeDrag")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = folder.appendingPathComponent("Drag-test.txt"), new = folder.appendingPathComponent("Renamed-test.txt")
        try Data("isolated drag verification".utf8).write(to: old)
        shelf.add([ShelfItem(kind: .file(bookmark: try Bookmark(url: old).data), cachedPath: old.path)])

        let host = NSHostingView(rootView: ShelfView().environmentObject(vm).frame(width: 680, height: 170).background(Color.black))
        host.frame = NSRect(x: 20, y: 180, width: 680, height: 170)
        let receiver = ShelfProbeDropTarget(frame: NSRect(x: 40, y: 30, width: 640, height: 100))
        receiver.registerForDraggedTypes([.fileURL])
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 380))
        container.addSubview(host); container.addSubview(receiver)
        let window = NSWindow(contentRect: container.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Shelf Drag Verification"
        window.contentView = container
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(500))
        try FileManager.default.moveItem(at: old, to: new)
        print("SHELF_NATIVE_DRAG_READY \(Bundle.main.bundleIdentifier ?? "")")
        for _ in 0..<1000 where receiver.received.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(receiver.received.map { $0.resolvingSymlinksInPath() }, [new.resolvingSymlinksInPath()])
        XCTAssertTrue(FileManager.default.fileExists(atPath: new.path))
        XCTAssertEqual(shelf.items.count, 1)
        XCTAssertFalse(ShelfSelectionModel.shared.isDragging)
        print("SHELF_NATIVE_DRAG_RESULT count=\(receiver.received.count) renamed=\(receiver.received.first?.lastPathComponent ?? "none")")
    }
}

private final class ShelfProbeDropTarget: NSView {
    var received: [URL] = []
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        received = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        needsDisplay = true
        return !received.isEmpty
    }
    override func draw(_ dirtyRect: NSRect) {
        (received.isEmpty ? NSColor.darkGray : NSColor.systemGreen).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        let text = received.isEmpty ? "Drop test file here (local verification only)" : "Received renamed file"
        (text as NSString).draw(at: NSPoint(x: 32, y: 40), withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.white])
    }
}
