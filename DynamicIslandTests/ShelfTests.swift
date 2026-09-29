import XCTest
import AppKit
import UniformTypeIdentifiers
@testable import Atoll

/// The shelf's file handling, run against a folder of each test's own -- never
/// the running app's shelf list or temporary folder -- and removed afterwards.
final class ShelfTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShelfTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Rename

    private let report = URL(fileURLWithPath: "/Users/someone/Desktop/Report.pdf")

    func testARenameStaysInTheFilesFolder() throws {
        let renamed = try ShelfActionService.renamedURL(for: report, to: "Final.pdf")
        XCTAssertEqual(renamed?.path, "/Users/someone/Desktop/Final.pdf")
    }

    func testTheSameNameIsNotARename() throws {
        XCTAssertNil(try ShelfActionService.renamedURL(for: report, to: "  Report.pdf "))
    }

    func testANameThatWouldMoveTheFileIsRefused() {
        for name in ["../Report.pdf", "Archive/Report.pdf", "Q1:Q2.pdf", ".", ".."] {
            XCTAssertThrowsError(try ShelfActionService.renamedURL(for: report, to: name), name) { error in
                XCTAssertEqual(error as? ShelfActionService.RenameError, .invalidName, name)
            }
        }
    }

    func testAnEmptyNameIsRefused() {
        XCTAssertThrowsError(try ShelfActionService.renamedURL(for: report, to: " \n")) { error in
            XCTAssertEqual(error as? ShelfActionService.RenameError, .emptyName)
        }
    }

    // MARK: - Saved list

    @MainActor
    func testSavedItemsComeBack() {
        let store = ShelfPersistenceService(directory: folder.appendingPathComponent("Shelf"))
        let items = [
            ShelfItem(kind: .text(string: "note")),
            ShelfItem(kind: .link(url: URL(string: "https://example.com")!))
        ]
        store.save(items)
        XCTAssertEqual(store.load().map(\.id), items.map(\.id))
    }

    @MainActor
    func testEmptyingTheShelfLeavesNothingOnDisk() {
        let directory = folder.appendingPathComponent("Shelf")
        let store = ShelfPersistenceService(directory: directory)
        store.save([ShelfItem(kind: .text(string: "note"))])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("items.json").path))

        store.save([])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    @MainActor
    func testAnEmptyListFoundAtLaunchIsRemoved() throws {
        let directory = folder.appendingPathComponent("Shelf")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: directory.appendingPathComponent("items.json"))

        XCTAssertTrue(ShelfPersistenceService(directory: directory).load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    @MainActor
    func testEmptyingTheShelfSparesOtherFilesInItsFolder() throws {
        let directory = folder.appendingPathComponent("Shelf")
        let store = ShelfPersistenceService(directory: directory)
        store.save([ShelfItem(kind: .text(string: "note"))])
        let other = directory.appendingPathComponent("other")
        try Data().write(to: other)

        store.save([])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("items.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
    }

    // MARK: - Temporary files

    func testTheSweepKeepsFilesInUseAndFilesJustMade() throws {
        let fm = FileManager.default
        let inUse = folder.appendingPathComponent("a/photo.png")
        let unused = folder.appendingPathComponent("b/old.txt")
        let justMade = folder.appendingPathComponent("c/new.txt")
        for file in [inUse, unused, justMade] {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
        }
        let anHourAgo = Date(timeIntervalSinceNow: -3600)
        for entry in ["a", "b"] {
            try fm.setAttributes([.creationDate: anHourAgo], ofItemAtPath: folder.appendingPathComponent(entry).path)
        }

        AtollTemporaryFiles.removeEntries(
            of: folder,
            notIn: [inUse],
            createdBefore: Date(timeIntervalSinceNow: -AtollTemporaryFiles.unusedEntryMinimumAge)
        )

        XCTAssertTrue(fm.fileExists(atPath: inUse.path))
        XCTAssertFalse(fm.fileExists(atPath: folder.appendingPathComponent("b").path))
        XCTAssertTrue(fm.fileExists(atPath: justMade.path))
    }

    @MainActor
    func testCorruptStoreIsPreservedAndNeverTreatedAsEmpty() throws {
        let file = folder.appendingPathComponent("items.json")
        let corrupt = Data("{broken".utf8)
        try corrupt.write(to: file)
        let store = ShelfPersistenceService(directory: folder)
        XCTAssertTrue(store.load().isEmpty)
        XCTAssertTrue(store.needsRecovery)
        XCTAssertFalse(store.permitsCleanup)
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
        XCTAssertTrue(store.save([ShelfItem(kind: .text(string: "new"))]))
        let backups = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("items.recovery-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), corrupt)
        let reloaded = ShelfPersistenceService(directory: folder)
        XCTAssertEqual(reloaded.load().count, 1)
        XCTAssertFalse(reloaded.permitsCleanup, "A recovery copy may refer to still-needed files")
    }

    @MainActor
    func testSaveFailureIsObservable() throws {
        let blocked = folder.appendingPathComponent("not-a-directory")
        try Data().write(to: blocked)
        let store = ShelfPersistenceService(directory: blocked)
        XCTAssertFalse(store.save([ShelfItem(kind: .text(string: "note"))]))
        XCTAssertNotNil(store.lastError)
        XCTAssertFalse(store.permitsCleanup)
    }

    private func oldFile(_ path: String) throws -> URL {
        let file = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: file)
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: file.deletingLastPathComponent().path)
        return file
    }

    func testActiveLeaseSurvivesClearAndReleasesExactlyOnce() async throws {
        let file = try oldFile("owned/a/note.txt")
        let lifetime = ShelfFileLifetime(directory: folder.appendingPathComponent("owned"))
        let lease = lifetime.acquire([file])
        lifetime.setReferences([], allowCleanup: true)
        let active = await lifetime.resourceCounts()
        XCTAssertEqual(active.active, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        lease.finish(); lease.finish()
        let ended = await lifetime.resourceCounts()
        XCTAssertEqual(ended.active, 0)
        XCTAssertEqual(ended.handoffs, 0)
        XCTAssertFalse(ended.scheduled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testHandoffSurvivesRelaunchAndExpiresPerFile() async throws {
        let file = try oldFile("owned/a/note.txt")
        let directory = folder.appendingPathComponent("owned")
        let now = Date()
        var lifetime: ShelfFileLifetime? = ShelfFileLifetime(directory: directory, now: { now })
        let lease = lifetime!.acquire([file])
        lifetime!.setReferences([], allowCleanup: true)
        lease.finish(handoff: true)
        let handedOff = await lifetime!.resourceCounts()
        XCTAssertEqual(handedOff.handoffs, 1)
        XCTAssertTrue(handedOff.scheduled)
        lifetime = nil
        var relaunched: ShelfFileLifetime? = ShelfFileLifetime(directory: directory, now: { now.addingTimeInterval(300) })
        relaunched!.setReferences([], allowCleanup: true)
        _ = await relaunched!.resourceCounts()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        relaunched = nil
        let expired = ShelfFileLifetime(directory: directory, now: { now.addingTimeInterval(601) })
        expired.setReferences([], allowCleanup: true)
        let final = await expired.resourceCounts()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(final.handoffs, 0)
        XCTAssertFalse(final.scheduled)
    }

    func testOtherHandoffsDoNotExtendAnEarlierFilesExpiry() async throws {
        let first = try oldFile("owned/a/one.txt")
        let second = try oldFile("owned/b/two.txt")
        let directory = folder.appendingPathComponent("owned")
        let now = Date()
        let expirations = [first.resolvingSymlinksInPath().path: now.addingTimeInterval(-1), second.resolvingSymlinksInPath().path: now.addingTimeInterval(300)]
        try JSONEncoder().encode(expirations).write(to: directory.appendingPathComponent(".handoffs.json"))
        let lifetime = ShelfFileLifetime(directory: directory)
        lifetime.setReferences([], allowCleanup: true)
        let counts = await lifetime.resourceCounts()
        XCTAssertEqual(counts.handoffs, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testOwnershipRejectsPrefixCollisionsAndEscapingSymlinks() throws {
        let outside = try oldFile("owned-other/a/original.txt")
        let directory = folder.appendingPathComponent("owned")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let link = directory.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let lifetime = ShelfFileLifetime(directory: directory)
        XCTAssertFalse(lifetime.owns(outside))
        XCTAssertFalse(lifetime.owns(link))
        XCTAssertTrue(lifetime.owns(directory.appendingPathComponent("safe.txt")))
    }

    func testCorruptHandoffLedgerDisablesDestructiveCleanup() async throws {
        let file = try oldFile("owned/a/note.txt")
        let directory = folder.appendingPathComponent("owned")
        let ledger = directory.appendingPathComponent(".handoffs.json")
        let data = Data("corrupt".utf8)
        try data.write(to: ledger)
        let lifetime = ShelfFileLifetime(directory: directory)
        lifetime.setReferences([], allowCleanup: true)
        _ = await lifetime.resourceCounts()
        XCTAssertTrue(lifetime.needsRecovery)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try Data(contentsOf: ledger), data)
    }

    func testRepeatedUseLeavesNoActiveLeaseOrIdleWake() async throws {
        let file = try oldFile("owned/a/note.txt")
        let lifetime = ShelfFileLifetime(directory: folder.appendingPathComponent("owned"))
        lifetime.setReferences([file], allowCleanup: true)
        for _ in 0..<100 {
            let lease = lifetime.acquire([file])
            lease.finish()
        }
        let retained = await lifetime.resourceCounts()
        XCTAssertEqual(retained.active, 0)
        XCTAssertFalse(retained.scheduled)
        lifetime.setReferences([], allowCleanup: true)
        let cleared = await lifetime.resourceCounts()
        XCTAssertEqual(cleared.active, 0)
        XCTAssertFalse(cleared.scheduled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    @MainActor
    func testClipboardOwnershipReplacementReleasesFilesWithoutPolling() async throws {
        let file = try oldFile("owned/a/note.txt")
        let lifetime = ShelfFileLifetime(directory: folder.appendingPathComponent("owned"))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let clipboard = ShelfClipboard(pasteboard: pasteboard, lifetime: lifetime)
        XCTAssertTrue(clipboard.write([file as NSURL], fileURLs: [file]))
        XCTAssertTrue(clipboard.holdsFiles)
        lifetime.setReferences([], allowCleanup: true)
        _ = await lifetime.resourceCounts()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        NSPasteboard(name: pasteboard.name).clearContents()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(clipboard.holdsFiles)
        let counts = await lifetime.resourceCounts()
        XCTAssertEqual(counts.active, 0)
        XCTAssertEqual(counts.handoffs, 1)
    }

    @MainActor
    func testTextAndLinkMetadataAppearImmediatelyAndUpdate() {
        let item = ShelfItem(kind: .text(string: "hello"))
        let model = ShelfItemViewModel(item: item)
        XCTAssertEqual(model.displayName, "hello")
        XCTAssertNotNil(model.icon)
        var changed = item
        changed.kind = .link(url: URL(string: "https://example.com/path")!)
        model.update(changed)
        XCTAssertEqual(model.displayName, "https://example.com/path")
        XCTAssertNotNil(model.icon)
        changed.kind = .file(bookmark: Data())
        changed.cachedDisplayName = "Renamed.pdf"
        changed.cachedPath = "/fixture/Renamed.pdf"
        model.update(changed)
        XCTAssertEqual(model.displayName, "Renamed.pdf")
        XCTAssertNil(model.thumbnail)
    }

    @MainActor
    func testShareWaitsForCompletionInsteadOfTwoSecondTimeout() async throws {
        var began = 0
        var ended = 0
        var succeeded: Bool?
        let delegate = SharingLifecycleDelegate(id: UUID(), onEnd: { succeeded = $0 }, onBegin: { began += 1 }, onFinish: { ended += 1 })
        delegate.markServiceBegan()
        try await Task.sleep(for: .milliseconds(2200))
        XCTAssertEqual(began, 1)
        XCTAssertEqual(ended, 0)
        let service = try XCTUnwrap(NSSharingService(named: .sendViaAirDrop))
        delegate.sharingService(service, didShareItems: [])
        delegate.sharingService(service, didShareItems: [])
        XCTAssertEqual(ended, 1)
        XCTAssertEqual(succeeded, true)
    }

    @MainActor
    func testCancelledShareBalancesInteractionOnce() {
        var ended = 0
        var succeeded: Bool?
        let delegate = SharingLifecycleDelegate(id: UUID(), onEnd: { succeeded = $0 }, onBegin: {}, onFinish: { ended += 1 })
        delegate.markPickerBegan()
        let picker = NSSharingServicePicker(items: ["fixture"])
        delegate.sharingServicePicker(picker, didChoose: nil)
        delegate.sharingServicePicker(picker, didChoose: nil)
        XCTAssertEqual(ended, 1)
        XCTAssertEqual(succeeded, false)
    }

    func testCancelledProviderDoesNotLeaveAWaitingTask() async throws {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { _ in Progress(totalUnitCount: 1) }
        let task = Task { await provider.extractText() }
        await Task.yield()
        task.cancel()
        let value = await task.value
        XCTAssertNil(value)
    }

    func testProviderFilenameCannotEscapeDestination() {
        XCTAssertEqual(TemporaryFileStorageService.safeFilename("../../outside.txt"), "outside.txt")
        XCTAssertEqual(TemporaryFileStorageService.safeFilename(".."), "Untitled.dat")
    }

    func testThumbnailWorkIsBoundedAndCancellationEmptiesQueue() async throws {
        let lifetime = ShelfFileLifetime(directory: folder.appendingPathComponent("owned"))
        let service = ThumbnailService(lifetime: lifetime)
        let tasks = (0..<80).map { index in
            Task { await service.thumbnail(for: self.folder.appendingPathComponent("missing-\(index).png"), size: CGSize(width: 56, height: 56)) }
        }
        await Task.yield()
        let busy = await service.resourceCounts()
        XCTAssertLessThanOrEqual(busy.running, ThumbnailService.maximumConcurrent)
        tasks.forEach { $0.cancel() }
        for task in tasks { _ = await task.value }
        await service.clear()
        let idle = await service.resourceCounts()
        XCTAssertEqual(idle.cached, 0)
        XCTAssertEqual(idle.bytes, 0)
        XCTAssertEqual(idle.running, 0)
        XCTAssertEqual(idle.queued, 0)
    }

    @MainActor
    func testThumbnailCacheStaysWithinEntryAndPixelBudgets() async throws {
        let lifetime = ShelfFileLifetime(directory: folder.appendingPathComponent("owned"))
        let service = ThumbnailService(lifetime: lifetime)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        var generated = 0
        for index in 0..<60 {
            let file = folder.appendingPathComponent("thumbnail-\(index).png")
            try data.write(to: file)
            let image = await service.thumbnail(for: file, size: CGSize(width: 56, height: 56))
            if image != nil { generated += 1 }
            let counts = await service.resourceCounts()
            XCTAssertLessThanOrEqual(counts.cached, ThumbnailService.maximumEntries)
            XCTAssertLessThanOrEqual(counts.bytes, ThumbnailService.maximumBytes)
            XCTAssertLessThanOrEqual(counts.running, ThumbnailService.maximumConcurrent)
        }
        XCTAssertEqual(generated, 60)
        let warm = await service.resourceCounts()
        XCTAssertEqual(warm.cached, 48)
        print("Shelf cache verification: generated=\(generated), entries=\(warm.cached), accountedBytes=\(warm.bytes)")
        await service.clear()
        let empty = await service.resourceCounts()
        XCTAssertEqual(empty.cached, 0)
        XCTAssertEqual(empty.bytes, 0)
        XCTAssertEqual(empty.queued, 0)
        XCTAssertEqual(empty.running, 0)
    }

    @MainActor
    func testPreviewKeepsOrdinaryURLsAndReleasesOnHide() async throws {
        let file = try oldFile("owned/a/preview.txt")
        let lifetime = ShelfFileLifetime(directory: folder.appendingPathComponent("owned"))
        let preview = QuickLookService(lifetime: lifetime)
        preview.show(urls: [file])
        XCTAssertEqual(preview.urls, [file])
        XCTAssertEqual(preview.selectedURL, file)
        lifetime.setReferences([], allowCleanup: true)
        _ = await lifetime.resourceCounts()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        // Replacing the preview acquires its next lease before releasing the first.
        preview.show(urls: [file])
        _ = await lifetime.resourceCounts()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        preview.hide()
        let counts = await lifetime.resourceCounts()
        XCTAssertEqual(counts.active, 0)
        XCTAssertFalse(preview.isQuickLookOpen)
        XCTAssertTrue(preview.urls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
