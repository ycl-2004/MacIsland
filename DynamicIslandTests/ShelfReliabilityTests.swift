import AppKit
import Combine
import Defaults
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Atoll

@MainActor
final class ShelfReliabilityTests: XCTestCase {
    private func fixture() async throws -> (URL, ShelfStateViewModel, Defaults.Key<Bool>) {
        let folder = AppRuntimeEnvironment.testDirectory.appendingPathComponent("ShelfFix-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let key = Defaults.Key<Bool>("shelf-fix-\(UUID())", default: true)
        let lifetime = ShelfFileLifetime(directory: folder.appendingPathComponent("owned"))
        let model = ShelfStateViewModel(persistence: ShelfPersistenceService(directory: folder.appendingPathComponent("saved")),
            lifetime: lifetime, enabledKey: key, thumbnails: ThumbnailService(lifetime: lifetime))
        await model.awaitInitialLoad()
        return (folder, model, key)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition did not become true")
        throw NSError(domain: "ShelfTestTimeout", code: 1)
    }

    func testFastImportsAndLaterDropsDoNotWaitForSlowProvider() async throws {
        let (_, shelf, _) = try await fixture()
        let slow = ShelfProviderGate()
        defer { slow.finish("slow"); shelf.pauseImports() }
        XCTAssertTrue(shelf.load([slow.provider, NSItemProvider(object: "fast" as NSString)]))
        XCTAssertNotNil(shelf.feedback, "An accepted drop needs immediate feedback")
        XCTAssertTrue(shelf.load([NSItemProvider(object: "next drop" as NSString)]))
        try await waitUntil { shelf.items.count == 2 }
        XCTAssertTrue(shelf.isImporting)
        XCTAssertEqual(Set(shelf.items.map(\.displayName)), ["fast", "next drop"])
        slow.finish("slow")
        try await waitUntil { !shelf.isImporting }
        XCTAssertEqual(shelf.items.count, 3)
    }

    func testImportConcurrencyQueueLimitsAndClearCancelLateCompletions() async throws {
        let (_, shelf, _) = try await fixture()
        let gates = (0..<4).map { _ in ShelfProviderGate() }
        defer { gates.forEach { $0.finish("late") }; shelf.pauseImports() }
        XCTAssertTrue(shelf.load(gates.map(\.provider)))
        try await waitUntil { gates.prefix(3).allSatisfy(\.started) }
        XCTAssertFalse(gates[3].started, "Only three providers may run at once")
        XCTAssertFalse(shelf.load((0..<51).map { NSItemProvider(object: "\($0)" as NSString) }))
        XCTAssertTrue(shelf.load((0..<50).map { NSItemProvider(object: "queued \($0)" as NSString) }))
        XCTAssertTrue(shelf.load((0..<46).map { NSItemProvider(object: "queued more \($0)" as NSString) }))
        XCTAssertFalse(shelf.load([NSItemProvider(object: "over queue limit" as NSString)]))
        shelf.removeAll()
        gates.forEach { $0.finish("late") }
        XCTAssertTrue(shelf.load([NSItemProvider(object: "fresh" as NSString)]))
        try await waitUntil { !shelf.isImporting }
        XCTAssertEqual(shelf.items.map(\.displayName), ["fresh"])
        XCTAssertFalse(gates[3].started, "Clear must discard queued providers")
    }

    func testDisableDuringImportRetainsItemsAndStopsNewImports() async throws {
        let (_, shelf, key) = try await fixture()
        let saved = ShelfItem(kind: .text(string: "retained"))
        shelf.add([saved])
        let gate = ShelfProviderGate()
        shelf.load([gate.provider])
        try await waitUntil { gate.started }
        Defaults[key] = false
        try await waitUntil { !shelf.isImporting }
        gate.finish("late")
        XCTAssertFalse(shelf.load([NSItemProvider(object: "rejected" as NSString)]))
        XCTAssertEqual(shelf.items.map(\.id), [saved.id])
    }

    func testConcurrentImportsStillEnforceItemAndTextBudgets() async throws {
        let (_, shelf, _) = try await fixture()
        shelf.add((0..<198).map { ShelfItem(kind: .text(string: "saved \($0)")) })
        XCTAssertTrue(shelf.load((0..<8).map { NSItemProvider(object: "new \($0)" as NSString) }))
        try await waitUntil { !shelf.isImporting }
        XCTAssertEqual(shelf.items.count, 200)
        shelf.removeAll()
        let full = (0..<5).map { String(repeating: String($0), count: 1024 * 1024) }
        XCTAssertTrue(shelf.load(full.map { NSItemProvider(object: $0 as NSString) }))
        try await waitUntil { !shelf.isImporting }
        XCTAssertEqual(shelf.items.count, 4)
        XCTAssertEqual(shelf.items.reduce(0) { $0 + $1.storageTextBytes }, 4 * 1024 * 1024)
    }

    func testDropIntoOpenOtherTabActuallyImportsAndRejectedDropReturnsFalse() async throws {
        let (_, shelf, key) = try await fixture()
        let vm = DynamicIslandViewModel()
        let coordinator = DynamicIslandViewCoordinator(availability: {
            NotchTabAvailability(home: true, shelf: true, timer: true, stats: false, agents: false,
                extraSpace: false, colorPicker: false)
        }, observeDefaults: false)
        vm.coordinator = coordinator
        let enabled = Defaults[.dynamicShelf]
        Defaults[.dynamicShelf] = true
        defer { Defaults[.dynamicShelf] = enabled; vm.destroy(); shelf.pauseImports() }
        coordinator.currentView = .home
        vm.open()
        vm.revealShelfForDrop()
        XCTAssertEqual(coordinator.currentView, .shelf)
        coordinator.currentView = .timer
        XCTAssertTrue(vm.receiveShelfDrop([NSItemProvider(object: "accepted" as NSString)], shelf: shelf))
        XCTAssertEqual(coordinator.currentView, .shelf)
        XCTAssertTrue(vm.dropEvent)
        try await waitUntil { shelf.items.count == 1 }
        Defaults[key] = false
        vm.dropEvent = false
        XCTAssertFalse(vm.receiveShelfDrop([NSItemProvider(object: "rejected" as NSString)], shelf: shelf))
        XCTAssertFalse(vm.dropEvent)
    }

    func testOpenExtraSpaceKeepsItsOwnDropsAndClosedNotchStillRoutesToShelf() async throws {
        let (_, shelf, _) = try await fixture()
        let vm = DynamicIslandViewModel()
        let coordinator = DynamicIslandViewCoordinator(availability: {
            NotchTabAvailability(home: true, shelf: true, timer: true, stats: false, agents: false,
                extraSpace: true, colorPicker: false)
        }, observeDefaults: false)
        vm.coordinator = coordinator
        let enabled = Defaults[.dynamicShelf]
        Defaults[.dynamicShelf] = true
        defer { Defaults[.dynamicShelf] = enabled; vm.destroy(); shelf.pauseImports() }
        coordinator.currentView = .extraSpace
        vm.open()
        vm.revealShelfForDrop()
        XCTAssertEqual(coordinator.currentView, .extraSpace, "The editor must stay the drop target")
        XCTAssertFalse(vm.receiveShelfDrop([NSItemProvider(object: "editor text" as NSString)], shelf: shelf))
        XCTAssertFalse(shelf.isImporting)
        vm.close()
        coordinator.currentView = .extraSpace
        vm.revealShelfForDrop()
        XCTAssertEqual(coordinator.currentView, .shelf)
        XCTAssertEqual(vm.notchState, .open)
    }

    func testDragPreparationUsesRenamedFileAndPreservesNativeFileTypes() async throws {
        let (folder, shelf, _) = try await fixture()
        let old = folder.appendingPathComponent("old.txt"), new = folder.appendingPathComponent("new.txt")
        try Data("fixture".utf8).write(to: old)
        let item = ShelfItem(kind: .file(bookmark: try Bookmark(url: old).data), cachedPath: old.path)
        shelf.add([item])
        try FileManager.default.moveItem(at: old, to: new)
        let prepared = await ShelfDragPreparation.prepare([item], shelf: shelf)
        let result = try XCTUnwrap(prepared)
        defer { result.lease.finish() }
        XCTAssertEqual(result.fileURLs.map { $0.resolvingSymlinksInPath() }, [new.resolvingSymlinksInPath()])
        XCTAssertEqual(shelf.items.first?.cachedPath, result.fileURLs.first?.standardizedFileURL.path)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        XCTAssertTrue(board.writeObjects(result.writers))
        XCTAssertTrue(board.types?.contains(.fileURL) == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: new.path))
    }

    func testUnavailableAndRemovedItemsNeverProducePartialDrag() async throws {
        let (_, shelf, _) = try await fixture()
        let text = ShelfItem(kind: .text(string: "retained"))
        let missing = ShelfItem(kind: .file(bookmark: Data()), cachedPath: "/does-not-exist/file.txt")
        shelf.add([text, missing])
        let result = await ShelfDragPreparation.prepare([text, missing], shelf: shelf)
        XCTAssertNil(result)
        XCTAssertEqual(shelf.items.count, 2)
        XCTAssertNotNil(shelf.feedback)
        shelf.remove(text)
        let removed = await ShelfDragPreparation.prepare([text], shelf: shelf)
        XCTAssertNil(removed)
    }

    func testCancelledPreparationDoesNotPublishOrHandOff() async throws {
        let (_, shelf, _) = try await fixture()
        let item = ShelfItem(kind: .text(string: "keep"))
        shelf.add([item])
        let task = Task { await ShelfDragPreparation.prepare([item], shelf: shelf) }
        task.cancel()
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(shelf.items, [item])
    }

    func testLongTextLabelsAreBoundedWhileDragPayloadRemainsComplete() async throws {
        let (_, shelf, _) = try await fixture()
        let text = String(repeating: "中文🙂", count: 60_000)
        let item = ShelfItem(kind: .text(string: text))
        shelf.add([item])
        XCTAssertLessThanOrEqual(ShelfItemViewModel(item: item).displayName.unicodeScalars.count, 257)
        XCTAssertLessThanOrEqual(item.displayName.unicodeScalars.count, 257)
        let prepared = await ShelfDragPreparation.prepare([item], shelf: shelf)
        let result = try XCTUnwrap(prepared)
        defer { result.lease.finish() }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        XCTAssertTrue(board.writeObjects(result.writers))
        XCTAssertEqual(board.string(forType: .string), text)
    }

    func testBatchRemovalPublishesOnceAndReconcilesSelection() async throws {
        let (_, shelf, _) = try await fixture()
        let items = (0..<200).map { ShelfItem(kind: .text(string: "\($0)")) }
        shelf.add(items)
        ShelfSelectionModel.shared.selectAll(in: items)
        var publishes = 0
        let observation = shelf.$items.dropFirst().sink { _ in publishes += 1 }
        shelf.remove(Array(items.prefix(150)))
        observation.cancel()
        XCTAssertEqual(publishes, 1)
        XCTAssertEqual(shelf.items.count, 50)
        XCTAssertEqual(ShelfSelectionModel.shared.selectedIDs, Set(items.suffix(50).map(\.id)))
        ShelfSelectionModel.shared.clear()
    }

    func testLazyRowRetainsOffscreenMarqueeGeometry() {
        let ids = (0..<200).map { _ in UUID() }
        let bounds = CGRect(x: 0, y: 0, width: 200 * 123 - 8, height: 120)
        let first = ShelfRowLayout.frame(at: 0, in: bounds)
        let last = ShelfRowLayout.frame(at: 199, in: bounds)
        XCTAssertEqual(ShelfRowLayout.hits(first.union(last), ids: ids, in: bounds), Set(ids))
        XCTAssertEqual(ShelfRowLayout.hits(last.insetBy(dx: 1, dy: 1), ids: ids, in: bounds), [ids[199]])
        let gap = CGRect(x: first.maxX + 1, y: 20, width: 6, height: 40)
        XCTAssertTrue(ShelfRowLayout.hits(gap, ids: ids, in: bounds).isEmpty)
        XCTAssertEqual(ShelfRowLayout.hits(first, ids: ids, in: bounds, rightToLeft: true), [ids[199]])
    }

    func testDisabledShelfDoesNotSupplyClosedActivityAndKeepsItems() async throws {
        let shelf = ShelfStateViewModel.shared
        await shelf.awaitInitialLoad()
        let enabled = Defaults[.dynamicShelf]
        Defaults[.dynamicShelf] = true
        shelf.removeAll()
        defer { shelf.removeAll(); Defaults[.dynamicShelf] = enabled }
        shelf.add([ShelfItem(kind: .text(string: "hidden but retained"))])
        XCTAssertTrue(ContentView().hasShelfActivity)
        Defaults[.dynamicShelf] = false
        XCTAssertFalse(ContentView().hasShelfActivity)
        XCTAssertEqual(shelf.items.count, 1)
    }

    func testLazyShelfRendersBoundedCardsAndMatchesMarqueeFrames() async throws {
        try await verifyLazyShelfFrames(rightToLeft: false)
    }

    func testLazyShelfRightToLeftFramesStayAligned() async throws {
        try await verifyLazyShelfFrames(rightToLeft: true)
    }

    private func verifyLazyShelfFrames(rightToLeft: Bool) async throws {
        let shelf = ShelfStateViewModel.shared
        await shelf.awaitInitialLoad()
        let enabled = Defaults[.dynamicShelf]
        Defaults[.dynamicShelf] = true
        shelf.removeAll()
        let vm = DynamicIslandViewModel()
        defer { shelf.removeAll(); Defaults[.dynamicShelf] = enabled; vm.destroy() }
        shelf.add((0..<200).map { ShelfItem(kind: .text(string: "Card \($0)")) })
        let host = NSHostingView(rootView: ShelfView().environmentObject(vm).frame(width: 680, height: 170)
            .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
        host.sizingOptions = []
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 170), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        func allViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(allViews) }
        try await waitUntil { allViews(host).contains { $0 is ShelfMarqueeSelectionView.MarqueeView } }
        let marquee = try XCTUnwrap(allViews(host).compactMap { $0 as? ShelfMarqueeSelectionView.MarqueeView }.first)
        try await waitUntil { !ShelfItemHitRegistry.shared.frames(in: marquee).isEmpty }
        let registered = ShelfItemHitRegistry.shared.frames(in: marquee)
        XCTAssertLessThan(registered.count, 30, "Offscreen cards must not all be instantiated")
        for entry in registered {
            let index = try XCTUnwrap(shelf.items.firstIndex { $0.id == entry.id })
            let expected = ShelfRowLayout.frame(at: index, in: marquee.bounds, rightToLeft: rightToLeft)
            XCTAssertEqual(entry.frame.minX, expected.minX, accuracy: 1)
            XCTAssertEqual(entry.frame.minY, expected.minY, accuracy: 1)
            XCTAssertEqual(entry.frame.width, expected.width, accuracy: 1)
            XCTAssertEqual(entry.frame.height, expected.height, accuracy: 1)
        }
        let all = ShelfRowLayout.hits(marquee.bounds, ids: shelf.items.map(\.id), in: marquee.bounds)
        XCTAssertEqual(all.count, 200)
        let selection = ShelfSelectionModel.shared
        selection.beginMarquee(mode: .replace)
        selection.updateMarquee(hitIDs: all)
        selection.endMarquee()
        XCTAssertEqual(selection.selectedIDs.count, 200)
        let scroll = try XCTUnwrap(marquee.enclosingScrollView)
        let clip = scroll.contentView
        let end = max(0, (scroll.documentView?.frame.width ?? 0) - clip.bounds.width)
        clip.scroll(to: NSPoint(x: rightToLeft ? 0 : end, y: 0))
        scroll.reflectScrolledClipView(clip)
        host.layoutSubtreeIfNeeded()
        try await waitUntil {
            ShelfItemHitRegistry.shared.frames(in: marquee).contains { $0.id == shelf.items.last?.id }
        }
        let last = try XCTUnwrap(ShelfItemHitRegistry.shared.frames(in: marquee).first { $0.id == shelf.items.last?.id })
        XCTAssertEqual(last.frame.minX, ShelfRowLayout.frame(at: 199, in: marquee.bounds, rightToLeft: rightToLeft).minX, accuracy: 1)
        selection.clear()
    }
}

/// Holds the provider callback until the test releases it, without timing assumptions.
private final class ShelfProviderGate: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: ((Data?, Error?) -> Void)?
    private var value: String?
    private var didStart = false
    var started: Bool { lock.lock(); defer { lock.unlock() }; return didStart }
    lazy var provider: NSItemProvider = {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { [weak self] completion in
            guard let self else { completion(nil, CocoaError(.userCancelled)); return nil }
            self.lock.lock()
            self.didStart = true
            let ready = self.value
            if ready == nil { self.callback = completion }
            self.lock.unlock()
            if let ready { completion(Data(ready.utf8), nil) }
            return Progress(totalUnitCount: 1)
        }
        return provider
    }()
    func finish(_ text: String) {
        lock.lock()
        value = text
        let pending = callback; callback = nil
        lock.unlock()
        pending?(Data(text.utf8), nil)
    }
}
