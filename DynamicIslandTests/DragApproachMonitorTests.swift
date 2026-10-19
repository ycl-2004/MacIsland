import AppKit
import XCTest
@testable import Atoll

@MainActor
final class DragApproachMonitorTests: XCTestCase {
    func testOnlyANewFileDragNearTheNotchOpensItOncePerPress() throws {
        let drag = NSPasteboard.withUniqueName()
        defer { drag.releaseGlobally() }
        var pressed = true, near = true, opens = 0
        let monitor = DragApproachMonitor(pasteboard: drag, isPressed: { pressed }, pointerIsNear: { near },
                                          onApproach: { opens += 1 })
        defer { monitor.stop() }
        let url = AppRuntimeEnvironment.testDirectory.appendingPathComponent("approach-\(UUID()).txt")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = url as NSURL
        func dragging(_ object: NSPasteboardWriting) {
            drag.clearContents()
            drag.writeObjects([object])
        }

        dragging(file)
        monitor.pressBegan()
        monitor.check()
        XCTAssertEqual(opens, 0, "A file left from an earlier drag is not this press's drag")

        dragging("text" as NSString)
        monitor.check()
        XCTAssertEqual(opens, 0, "Only files open the notch early")

        near = false
        dragging(file)
        monitor.check()
        XCTAssertEqual(opens, 0)
        XCTAssertTrue(monitor.isPolling)

        near = true
        monitor.check()
        monitor.check()
        XCTAssertEqual(opens, 1)
        XCTAssertFalse(monitor.isPolling, "One opening per press")

        monitor.pressBegan()
        pressed = false
        monitor.check()
        XCTAssertFalse(monitor.isPolling, "Releasing the button ends the poll")
        XCTAssertEqual(opens, 1)
    }
}
