import AppKit
import Combine
import Defaults
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Atoll

/// Diagnostic measurements for the 2026-10-17 assessment, not performance gates.
/// Run only in the isolated host prepared by Tools/verify-stability.py.
@MainActor
final class ShelfAssessmentProbeTests: XCTestCase {
    private func emit(_ name: String, _ fields: [String: Any]) {
        var record = fields
        record["probe"] = name
        let data = try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        print("SHELF_ASSESSMENT " + String(decoding: data, as: UTF8.self))
    }

    private func fixture() throws -> (URL, ShelfStateViewModel) {
        let root = AppRuntimeEnvironment.testDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let key = Defaults.Key<Bool>("shelf-assessment-\(UUID())", default: true)
        let lifetime = ShelfFileLifetime(directory: root.appendingPathComponent("owned"))
        let model = ShelfStateViewModel(persistence: ShelfPersistenceService(directory: root.appendingPathComponent("saved")),
            lifetime: lifetime, enabledKey: key, thumbnails: ThumbnailService(lifetime: lifetime))
        return (root, model)
    }

    func testDelayedProviderFeedbackAndQueue() async throws {
        let (_, model) = try fixture()
        await model.awaitInitialLoad()
        let slow = NSItemProvider()
        slow.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { completion(Data("slow".utf8), nil) }
            return Progress(totalUnitCount: 1)
        }
        let start = CFAbsoluteTimeGetCurrent()
        var arrivals: [[String: Any]] = []
        let observation = model.$items.dropFirst().sink { items in
            arrivals.append(["milliseconds": (CFAbsoluteTimeGetCurrent() - start) * 1000, "count": items.count])
        }
        defer { observation.cancel(); model.pauseImports() }
        model.load([NSItemProvider(object: "fast" as NSString), slow])
        model.load([NSItemProvider(object: "queued" as NSString)])
        try await Task.sleep(for: .milliseconds(150))
        let earlyCount = model.items.count
        let earlyFeedback = model.feedback ?? "<nil>"
        for _ in 0..<200 where model.items.count < 3 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.items.count, 3)
        emit("slow_provider", ["items_at_150ms": earlyCount, "feedback_at_150ms": earlyFeedback, "arrivals": arrivals])
    }

    func testLocalFileImportAndHeartbeat() async throws {
        let (root, _) = try fixture()
        var urls: [URL] = []
        for index in 0..<50 {
            let url = root.appendingPathComponent("file-\(index).txt")
            try Data("fixture".utf8).write(to: url)
            urls.append(url)
        }
        for count in [1, 10, 50] {
            var last = CFAbsoluteTimeGetCurrent()
            var gaps: [Double] = []
            let heartbeat = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(5))
                    let now = CFAbsoluteTimeGetCurrent()
                    gaps.append((now - last) * 1000); last = now
                }
            }
            await Task.yield()
            let start = CFAbsoluteTimeGetCurrent()
            let providers = urls.prefix(count).map { NSItemProvider(object: $0 as NSURL) }
            let items = await ShelfDropService.items(from: providers)
            let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
            heartbeat.cancel(); await heartbeat.value
            XCTAssertEqual(items.count, count)
            emit("local_import", ["count": count, "milliseconds": duration, "max_mainactor_gap_ms": gaps.max() ?? 0])
        }
    }

    func testDragPreviewRenderingCost() throws {
        for count in [40, 4096, 65536, 1048576] {
            let text = String(repeating: "A", count: count)
            var samples: [Double] = []
            for _ in 0..<3 {
                let start = CFAbsoluteTimeGetCurrent()
                let renderer = ImageRenderer(content: DragPreviewView(thumbnail: nil, displayName: text))
                renderer.scale = 2
                XCTAssertNotNil(renderer.nsImage)
                samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            }
            emit("drag_preview", ["text_bytes": count, "render_ms": samples])
        }
    }

    func testBatchMutationAndMissingSource() async throws {
        let (root, model) = try fixture()
        await model.awaitInitialLoad()
        let candidates = (0..<200).map { ShelfItem(kind: .text(string: "item \($0)")) }
        var publishes = 0
        let observation = model.$items.dropFirst().sink { _ in publishes += 1 }
        let addStart = CFAbsoluteTimeGetCurrent()
        model.add(candidates)
        let addMs = (CFAbsoluteTimeGetCurrent() - addStart) * 1000
        let deleteStart = CFAbsoluteTimeGetCurrent()
        for item in candidates { model.remove(item) }
        let deleteMs = (CFAbsoluteTimeGetCurrent() - deleteStart) * 1000
        observation.cancel()
        emit("batch_mutation", ["count": candidates.count, "add_ms": addMs, "remove_one_by_one_ms": deleteMs, "publishes": publishes])
        let source = root.appendingPathComponent("original.txt")
        try Data("fixture".utf8).write(to: source)
        let bookmark = try Bookmark(url: source)
        let item = ShelfItem(kind: .file(bookmark: bookmark.data), cachedPath: source.path)
        try FileManager.default.moveItem(at: source, to: root.appendingPathComponent("renamed.txt"))
        let dragURL = item.resolvedFileURL
        let resolved = await bookmark.resolveAsync()
        emit("renamed_source", ["drag_path_exists": dragURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
            "async_path_exists": resolved.url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
            "paths_differ": dragURL != resolved.url])
    }

    func testShelfLayoutAtCapacity() async throws {
        let shelf = ShelfStateViewModel.shared
        await shelf.awaitInitialLoad()
        Defaults[.dynamicShelf] = true
        shelf.removeAll()
        let vm = DynamicIslandViewModel()
        defer { shelf.removeAll(); vm.destroy() }
        for count in [1, 50, 200] {
            shelf.removeAll()
            shelf.add((0..<count).map { ShelfItem(kind: .text(string: "Draft material \($0 + 1)")) })
            let start = CFAbsoluteTimeGetCurrent()
            let content = ShelfView().environmentObject(vm).padding(12)
                .frame(width: 680, height: 170).background(Color.black)
                .environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: content)
            host.sizingOptions = []
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 170),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
            window.contentView = host
            window.orderFrontRegardless()
            host.layoutSubtreeIfNeeded()
            let initialMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            try await Task.sleep(for: .milliseconds(100))
            let selectionStart = CFAbsoluteTimeGetCurrent()
            ShelfSelectionModel.shared.selectAll(in: shelf.items)
            host.layoutSubtreeIfNeeded()
            let selectionMs = (CFAbsoluteTimeGetCurrent() - selectionStart) * 1000
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            if count == 50 {
                let image = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try image.write(to: URL(fileURLWithPath: "/tmp/atoll-shelf-assessment-layout.png"))
            }
            func views(_ view: NSView) -> Int { 1 + view.subviews.reduce(0) { $0 + views($1) } }
            emit("shelf_layout", ["count": count, "initial_sync_ms": initialMs,
                "select_all_sync_ms": selectionMs, "appkit_views": views(host)])
            window.orderOut(nil); window.contentView = nil; window.close()
        }
    }
}
