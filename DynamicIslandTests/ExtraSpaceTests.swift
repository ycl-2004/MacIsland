import AppKit
import SwiftUI
import XCTest
@testable import Atoll

@MainActor
final class ExtraSpaceTests: XCTestCase {
    func testExtraSpaceUsesTheSameDefaultHeightAsOtherMainTabs() {
        let vm = DynamicIslandViewModel()
        defer { vm.destroy() }
        XCTAssertEqual(vm.calculateDynamicNotchSize(for: .extraSpace), vm.calculateDynamicNotchSize(for: .agents))
    }

    func testKeyboardUndoReachesTheFocusedNativeEditor() async throws {
        let url = try temporaryDocument()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ExtraSpaceStore(fileURL: url, saveDelay: 60)
        try await waitUntil { store.isLoaded }
        let hosting = NSHostingView(rootView: ExtraSpaceEditor(
            store: store, screenID: UUID().uuidString, onFocusChange: { _ in }, onClose: {}
        ))
        hosting.sizingOptions = []
        let window = DynamicIslandWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 150), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = hosting
        window.alphaValue = 0
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(50))
        let editor = try XCTUnwrap(findScrollView(in: hosting)?.documentView as? ExtraSpaceTextView)
        window.makeFirstResponder(editor)
        try await exerciseKeyboardEdits(editor, in: window, store: store)
        store.flushPendingSave()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Initial pasted")
    }

    private func exerciseKeyboardEdits(_ editor: ExtraSpaceTextView, in window: NSWindow, store: ExtraSpaceStore) async throws {
        func press(_ key: String, _ modifiers: NSEvent.ModifierFlags, direct: Bool = false) async throws {
            // Separate real keyboard events also occupy separate run-loop turns.
            try await Task.sleep(for: .milliseconds(20))
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: key == "z" ? 6 : 9) else {
                XCTFail("Could not create an editing key event")
                return
            }
            if direct { editor.keyDown(with: event) } else {
                XCTAssertTrue(window.performKeyEquivalent(with: event))
            }
        }
        func check(_ expected: String, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(editor.string, expected, file: file, line: line)
            XCTAssertEqual(store.text, expected, file: file, line: line)
        }
        let clipboard = NSPasteboard.withUniqueName()
        defer { clipboard.releaseGlobally() }
        editor.clipboard = clipboard
        editor.insertText("Initial", replacementRange: editor.selectedRange())
        check("Initial")
        clipboard.setString(" pasted", forType: .string)
        try await press("v", .command)
        check("Initial pasted")
        try await press("z", .command)
        check("Initial")
        try await press("z", [.command, .shift])
        check("Initial pasted")
        try await press("z", .control, direct: true)
        check("Initial")
        try await press("z", [.control, .shift], direct: true)
        check("Initial pasted")

        // Replacing a selection, deleting it, and undoing must update the model.
        editor.setSelectedRange(NSRange(location: 0, length: 7))
        clipboard.clearContents()
        clipboard.setString("Changed", forType: .string)
        try await press("v", .control, direct: true)
        check("Changed pasted")
        try await press("z", .command)
        check("Initial pasted")
        editor.setSelectedRange(NSRange(location: 7, length: 7))
        try await Task.sleep(for: .milliseconds(20))
        editor.delete(nil)
        check("Initial")
        try await press("z", .command)
        check("Initial pasted")
        try await press("a", .command)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 14))
        try await press("c", .command)
        XCTAssertEqual(clipboard.string(forType: .string), "Initial pasted")
        editor.setSelectedRange(NSRange(location: 7, length: 7))
        try await press("x", .command)
        check("Initial")
        XCTAssertEqual(clipboard.string(forType: .string), " pasted")
        try await press("z", .command)
        check("Initial pasted")
    }

    func testSaveEndsEditingAndReadingSwipeClosesWithoutScrollingOrEditing() async throws {
        let url = try temporaryDocument()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let content = String(repeating: "Reference text\n", count: 250)
        try content.write(to: url, atomically: true, encoding: .utf8)
        let store = ExtraSpaceStore(fileURL: url, saveDelay: 60)
        try await waitUntil { store.isLoaded }
        let screenID = UUID().uuidString
        var closed = 0
        func root(_ editing: Bool, focus: Int) -> ExtraSpaceEditor {
            ExtraSpaceEditor(store: store, screenID: screenID, isEditing: editing, focusRequest: focus, onFocusChange: { _ in }, onClose: { closed += 1 })
        }
        let hosting = NSHostingView(rootView: root(false, focus: 0))
        hosting.sizingOptions = []
        let window = DynamicIslandWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 150), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = hosting
        window.alphaValue = 0
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(50))
        let scroll = try XCTUnwrap(findScrollView(in: hosting) as? ExtraSpaceScrollView)
        let editor = try XCTUnwrap(scroll.documentView as? ExtraSpaceTextView)
        XCTAssertFalse(editor.isEditable)

        hosting.rootView = root(true, focus: 1)
        try await waitUntil { editor.isEditable && window.firstResponder === editor }
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertText("Edited\n", replacementRange: editor.selectedRange())
        XCTAssertEqual(store.text, "Edited\n" + content)
        XCTAssertTrue(store.isDirty)
        hosting.rootView = root(false, focus: 1)
        try await waitUntil { !editor.isEditable && window.firstResponder !== editor && !store.isDirty }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Edited\n" + content)

        scroll.closeDirection = .up
        scroll.closeSensitivity = 200
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 500))
        let origin = scroll.contentView.bounds.origin
        let cgEvent = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -250, wheel2: 0, wheel3: 0))
        let event = try XCTUnwrap(NSEvent(cgEvent: cgEvent))
        scroll.scrollWheel(with: event)
        XCTAssertEqual(closed, 1)
        XCTAssertEqual(scroll.contentView.bounds.origin, origin)
        XCTAssertFalse(editor.isEditable)
        // Momentum from the same swipe must not close a second time.
        scroll.scrollWheel(with: event)
        XCTAssertEqual(closed, 1)

        hosting.rootView = root(true, focus: 2)
        try await waitUntil { editor.isEditable }
        scroll.scrollWheel(with: event)
        XCTAssertEqual(closed, 1, "Editing keeps the gesture inside the text")
        try await waitUntil { scroll.contentView.bounds.origin != origin }
    }

    func testDoubleClickAndCommandSSwitchTheRealTabBetweenEditingAndReading() async throws {
        for content in ["", "Existing reference\n"] {
            let url = try temporaryDocument()
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            try content.write(to: url, atomically: true, encoding: .utf8)
            let store = ExtraSpaceStore(fileURL: url, saveDelay: 60)
            try await waitUntil { store.isLoaded }
            let vm = DynamicIslandViewModel()
            defer { vm.destroy() }
            let hosting = NSHostingView(rootView: NotchExtraSpaceView(store: store)
                .environmentObject(vm).frame(width: 640, height: 160))
            hosting.sizingOptions = []
            let window = DynamicIslandWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 160), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.contentView = hosting
            window.alphaValue = 0
            window.orderFrontRegardless()
            defer { window.orderOut(nil); window.contentView = nil; window.close() }
            try await Task.sleep(for: .milliseconds(50))
            let scroll = try XCTUnwrap(findScrollView(in: hosting) as? ExtraSpaceScrollView)
            let editor = try XCTUnwrap(scroll.documentView as? ExtraSpaceTextView)
            XCTAssertFalse(editor.isEditable)
            let doubleClick = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 30, y: 60), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1))

            // Covers the real tab's callbacks, including an empty text area.
            editor.mouseDown(with: doubleClick)
            try await waitUntil { editor.isEditable && window.firstResponder === editor }
            XCTAssertTrue(scroll.isEditing)
            editor.setSelectedRange(NSRange(location: (content as NSString).length, length: 0))
            editor.insertText("Edited", replacementRange: editor.selectedRange())
            XCTAssertTrue(window.performKeyEquivalent(with: try keyboardEvent("s", modifiers: .command, in: window)))
            try await waitUntil { !editor.isEditable && !scroll.isEditing && window.firstResponder !== editor && !store.isDirty }
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), content + "Edited")

            // Re-enter, then save unfinished input-method composition too.
            editor.mouseDown(with: doubleClick)
            try await waitUntil { editor.isEditable && window.firstResponder === editor }
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            editor.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertTrue(editor.hasMarkedText())
            XCTAssertTrue(window.performKeyEquivalent(with: try keyboardEvent("s", modifiers: .command, in: window)))
            try await waitUntil { !editor.isEditable && !editor.hasMarkedText() && !store.isDirty }
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), content + "Edited中文")
        }
    }

    func testToolbarPasteIsOneUndoableEdit() async throws {
        let url = try temporaryDocument()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ExtraSpaceStore(fileURL: url, saveDelay: 60)
        try await waitUntil { store.isLoaded }
        let screenID = UUID().uuidString
        func content(_ request: Int) -> ExtraSpaceEditor {
            ExtraSpaceEditor(store: store, screenID: screenID, pasteRequest: request, onFocusChange: { _ in }, onClose: {})
        }
        let hosting = NSHostingView(rootView: content(0))
        hosting.sizingOptions = []
        let window = DynamicIslandWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 150), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = hosting
        window.alphaValue = 0
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(50))
        let editor = try XCTUnwrap(findScrollView(in: hosting)?.documentView as? ExtraSpaceTextView)
        window.makeFirstResponder(editor)
        editor.insertText("Before", replacementRange: editor.selectedRange())
        try await waitUntil { store.text == "Before" }
        let clipboard = NSPasteboard.withUniqueName()
        defer { clipboard.releaseGlobally() }
        clipboard.setString("\n粘贴的资料 🏝️", forType: .string)
        editor.clipboard = clipboard
        try await Task.sleep(for: .milliseconds(20))
        hosting.rootView = content(1)
        try await waitUntil { store.text == "Before\n粘贴的资料 🏝️" }
        XCTAssertTrue(window.performKeyEquivalent(with: try keyboardEvent("z", modifiers: .command, in: window)))
        try await waitUntil { store.text == "Before" }
        store.flushPendingSave()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Before")
    }

    func testAutosaveCoalescesEditsAndImmediateSaveKeepsTheNewestText() async throws {
        let url = try temporaryDocument()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ExtraSpaceStore(fileURL: url, saveDelay: 0.1)
        try await waitUntil { store.isLoaded }
        XCTAssertEqual(store.text, "")

        for index in 0..<50 { store.updateText("Draft \(index)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try await waitUntil { !store.isDirty }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Draft 49")

        store.updateText("Older snapshot")
        store.saveNow()
        store.updateText("最新内容\nSecond line 🏝️")
        store.saveNow()
        try await waitUntil { !store.isDirty }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), store.text)
    }

    func testTerminationFlushAndReopeningPreserveUnicodeAndNewlines() async throws {
        let url = try temporaryDocument()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ExtraSpaceStore(fileURL: url, saveDelay: 60)
        try await waitUntil { store.isLoaded }
        let content = "暂存资料\n\nhttps://example.com\nCopy & paste: 👨‍👩‍👧‍👦\n"
        store.updateText(content)
        store.flushPendingSave()
        XCTAssertFalse(store.isDirty)

        let reopened = ExtraSpaceStore(fileURL: url)
        try await waitUntil { reopened.isLoaded }
        XCTAssertEqual(reopened.text, content)

        reopened.updateText("")
        reopened.flushPendingSave()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "")
    }

    func testUnreadableDocumentCannotBeOverwrittenByAnEmptyEditor() async throws {
        let url = try temporaryDocument()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = Data([0xff, 0xfe, 0xff])
        try original.write(to: url)
        let store = ExtraSpaceStore(fileURL: url)
        try await waitUntil { store.errorMessage != nil }
        XCTAssertFalse(store.isLoaded)
        store.updateText("Accidental replacement")
        store.flushPendingSave()
        XCTAssertEqual(try Data(contentsOf: url), original)

        try "Recovered text".write(to: url, atomically: true, encoding: .utf8)
        store.retry()
        try await waitUntil { store.isLoaded }
        XCTAssertEqual(store.text, "Recovered text")
    }

    func testSaveFailureRetainsTheDraftAndCanBeRetried() async throws {
        let url = try temporaryDocument()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ExtraSpaceStore(fileURL: url, saveDelay: 60)
        try await waitUntil { store.isLoaded }
        store.updateText("Keep this draft")
        // A file in place of the containing folder creates a deterministic I/O failure.
        try FileManager.default.removeItem(at: url.deletingLastPathComponent())
        try Data().write(to: url.deletingLastPathComponent())
        store.flushPendingSave()
        XCTAssertTrue(store.isDirty)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.text, "Keep this draft")
        try FileManager.default.removeItem(at: url.deletingLastPathComponent())
        store.retry()
        try await waitUntil { !store.isDirty }
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Keep this draft")
    }

    func testLongNativeEditorRestoresSelectionAndScrollPositionAfterRemount() async throws {
        let url = try temporaryDocument()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let content = String(repeating: "资料：paste text here, then scroll to read it. 🏝️\n", count: 2500)
        try content.write(to: url, atomically: true, encoding: .utf8)
        let store = ExtraSpaceStore(fileURL: url)
        try await waitUntil { store.isLoaded }
        let screenID = UUID().uuidString
        func editor(_ generation: Int) -> some View {
            ExtraSpaceEditor(store: store, screenID: screenID, onFocusChange: { _ in }, onClose: {})
                .id(generation)
        }
        let hosting = NSHostingView(rootView: editor(0))
        hosting.sizingOptions = []
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 150), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.alphaValue = 0
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(100))
        hosting.layoutSubtreeIfNeeded()

        let first = try XCTUnwrap(findScrollView(in: hosting))
        let textView = try XCTUnwrap(first.documentView as? NSTextView)
        XCTAssertFalse(textView.isRichText)
        XCTAssertTrue(textView.allowsUndo)
        XCTAssertEqual(textView.string, content)
        XCTAssertGreaterThan(textView.frame.height, first.contentView.bounds.height)
        XCTAssertLessThanOrEqual(textView.frame.width, first.contentView.bounds.width + 1)
        textView.setSelectedRange(NSRange(location: 14, length: 5))
        first.contentView.scroll(to: NSPoint(x: 0, y: 900))
        first.reflectScrolledClipView(first.contentView)
        let savedOrigin = first.contentView.bounds.origin
        XCTAssertGreaterThan(savedOrigin.y, 0)

        hosting.rootView = editor(1)
        try await Task.sleep(for: .milliseconds(100))
        hosting.layoutSubtreeIfNeeded()
        let reopened = try XCTUnwrap(findScrollView(in: hosting))
        let reopenedText = try XCTUnwrap(reopened.documentView as? NSTextView)
        XCTAssertEqual(reopenedText.selectedRange(), NSRange(location: 14, length: 5))
        XCTAssertEqual(reopened.contentView.bounds.origin.y, savedOrigin.y, accuracy: 1)
        XCTAssertEqual(reopenedText.string, content)

        let preview = URL(fileURLWithPath: "/tmp/atoll-extra-space-editor.png")
        if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: preview)
        }
    }

    func testNativeTypingCompositionAndUndoUpdateTheSameDocument() async throws {
        let url = try temporaryDocument()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ExtraSpaceStore(fileURL: url, saveDelay: 60)
        try await waitUntil { store.isLoaded }
        let hosting = NSHostingView(rootView: ExtraSpaceEditor(
            store: store, screenID: UUID().uuidString, onFocusChange: { _ in }, onClose: {}
        ))
        hosting.sizingOptions = []
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 280), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.alphaValue = 0
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(50))
        let textView = try XCTUnwrap(findScrollView(in: hosting)?.documentView as? NSTextView)

        window.makeFirstResponder(textView)

        textView.insertText("中文资料\n", replacementRange: NSRange(location: 0, length: 0))
        try await waitUntil { store.text == "中文资料\n" }
        textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: textView.selectedRange())
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(textView.hasMarkedText(), "SwiftUI updates must preserve active input-method composition")
        textView.insertText("你", replacementRange: textView.markedRange())
        XCTAssertFalse(textView.hasMarkedText())
        try await waitUntil { store.text == "中文资料\n你" }

        textView.undoManager?.removeAllActions()
        textView.insertText("UNDO", replacementRange: textView.selectedRange())
        XCTAssertTrue(textView.undoManager?.canUndo == true)
        textView.undoManager?.undo()
        try await waitUntil { store.text == "中文资料\n你" }
        textView.undoManager?.redo()
        try await waitUntil { store.text == "中文资料\n你UNDO" }
        textView.undoManager?.undo()
        try await waitUntil { store.text == "中文资料\n你" }
        store.flushPendingSave()
    }

    func testTwoEditorsShareTextWithoutKeepingInvalidUndoRanges() async throws {
        let url = try temporaryDocument()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ExtraSpaceStore(fileURL: url, saveDelay: 60)
        try await waitUntil { store.isLoaded }
        let hosting = NSHostingView(rootView: HStack {
            ExtraSpaceEditor(store: store, screenID: UUID().uuidString, onFocusChange: { _ in }, onClose: {})
            ExtraSpaceEditor(store: store, screenID: UUID().uuidString, onFocusChange: { _ in }, onClose: {})
        })
        hosting.sizingOptions = []
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 280), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.alphaValue = 0
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(50))
        func editors(in view: NSView) -> [ExtraSpaceTextView] {
            if let text = view as? ExtraSpaceTextView { return [text] }
            return view.subviews.flatMap { editors(in: $0) }
        }
        let views = editors(in: hosting)
        XCTAssertEqual(views.count, 2)
        guard views.count == 2 else { return }
        views[1].insertText("Second", replacementRange: NSRange(location: 0, length: 0))
        try await waitUntil { views[0].string == "Second" }
        views[0].insertText("First ", replacementRange: NSRange(location: 0, length: 0))
        try await waitUntil { views[1].string == "First Second" }
        XCTAssertEqual(store.text, "First Second")
        XCTAssertFalse(views[1].undoManager?.canUndo == true)
        store.flushPendingSave()
    }

    func testTabAndSettingsRenderWithTheExistingVisualSystem() async throws {
        let url = try temporaryDocument()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ExtraSpaceStore(fileURL: url)
        try await waitUntil { store.isLoaded }
        store.updateText("临时资料\n\n在这里贴上需要稍后阅读的内容。\nKeep a link, a draft, or some reference text here.\n\nhttps://example.com\n\n向下滚动，可以继续查看整段文字。")
        let vm = DynamicIslandViewModel()
        defer { vm.destroy() }
        let tab = NotchExtraSpaceView(store: store)
            .environmentObject(vm)
            .environment(\.colorScheme, .dark)
            .frame(width: 640, height: 160)
            .background(.black)
        try await savePreview(tab, to: "/tmp/atoll-extra-space-tab.png", size: NSSize(width: 640, height: 160))
        let settings = ExtraSpaceSettings()
            .formStyle(.grouped)
            .environmentObject(SettingsHighlightCoordinator())
            .environment(\.colorScheme, .dark)
            .frame(width: 640, height: 360)
        try await savePreview(settings, to: "/tmp/atoll-extra-space-settings.png", size: NSSize(width: 640, height: 360))
        store.flushPendingSave()
    }

    private func savePreview<Content: View>(_ content: Content, to path: String, size: NSSize) async throws {
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        let window = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.alphaValue = 0
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(100))
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func temporaryDocument() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-extra-space-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("content.txt")
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !predicate() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for the expected editor/persistence state", file: file, line: line)
                throw NSError(domain: "ExtraSpaceTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for persistence"])
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func keyboardEvent(_ key: String, modifiers: NSEvent.ModifierFlags, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: key == "z" ? 6 : 9))
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        return view.subviews.compactMap { findScrollView(in: $0) }.first
    }
}
