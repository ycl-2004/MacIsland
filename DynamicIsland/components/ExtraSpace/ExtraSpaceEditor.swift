import AppKit
import Defaults
import SwiftUI

/// AppKit handles composition, selection and undo. Updates from SwiftUI only
/// replace text when another editor changed it, so typing does not reset IME.
/// https://developer.apple.com/documentation/swiftui/nsviewrepresentable
struct ExtraSpaceEditor: NSViewRepresentable {
    @ObservedObject var store: ExtraSpaceStore
    let screenID: String
    var pasteRequest = 0
    var isEditing = true
    var focusRequest = 0
    var onBeginEditing: () -> Void = {}
    var onFinishEditing: () -> Void = {}
    var onFocusChange: (Bool) -> Void
    var onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(store: store, screenID: screenID) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ExtraSpaceScrollView()
        configureScrollView(scrollView)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder

        let textView = ExtraSpaceTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isRichText = false
        textView.isEditable = store.isLoaded && !store.isRelaunching && isEditing
        context.coordinator.shouldBeEditable = textView.isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NotchTextSize.body.rawValue)
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.setAccessibilityLabel(String(localized: "Extra Space text"))
        textView.string = store.text
        textView.delegate = context.coordinator
        textView.onFocusChange = onFocusChange
        textView.onClose = onClose
        textView.onBeginEditing = { if store.isLoaded { onBeginEditing() } }
        textView.onFinishEditing = onFinishEditing
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.observeUndoManager(textView.undoManager)
        context.coordinator.observeScrollView(scrollView)
        context.coordinator.lastPasteRequest = pasteRequest
        context.coordinator.lastFocusRequest = focusRequest

        if let position = Coordinator.positions[screenID] {
            textView.setSelectedRange(position.selection.clamped(to: (store.text as NSString).length))
            DispatchQueue.main.async { [weak scrollView] in
                guard let scrollView else { return }
                scrollView.contentView.scroll(to: position.scrollOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        textView.onFocusChange = onFocusChange
        textView.onClose = onClose
        textView.onBeginEditing = { if store.isLoaded { onBeginEditing() } }
        textView.onFinishEditing = onFinishEditing
        if let scrollView = scrollView as? ExtraSpaceScrollView { configureScrollView(scrollView) }
        let finishesEditing = textView.isEditable && !isEditing
        context.coordinator.shouldBeEditable = store.isLoaded && !store.isRelaunching && isEditing
        if finishesEditing {
            DispatchQueue.main.async { [weak textView, weak coordinator = context.coordinator] in
                guard let textView, let coordinator, textView.isEditable, !coordinator.shouldBeEditable else { return }
                // Changing editability can commit marked text and publish a
                // native change; finish it after SwiftUI's update pass.
                textView.unmarkText()
                textView.isEditable = false
                if textView.window?.firstResponder === textView { textView.window?.makeFirstResponder(nil) }
                textView.onFocusChange?(false)
                coordinator.store.updateText(textView.string)
                coordinator.store.saveNow()
            }
        } else if textView.isEditable != context.coordinator.shouldBeEditable {
            textView.isEditable = context.coordinator.shouldBeEditable
        }
        if textView.string != store.text && !textView.hasMarkedText() {
            let selection = textView.selectedRange()
            textView.string = store.text
            // Undo ranges from another display's older document are no longer valid.
            textView.undoManager?.removeAllActions()
            textView.setSelectedRange(selection.clamped(to: (store.text as NSString).length))
        }
        if context.coordinator.lastPasteRequest != pasteRequest {
            context.coordinator.lastPasteRequest = pasteRequest
            // Pasting publishes model changes; run after SwiftUI's update pass.
            DispatchQueue.main.async { [weak scrollView, weak textView] in
                guard let scrollView, let textView, textView.isEditable, let window = scrollView.window else { return }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(textView)
                textView.pasteAsPlainText(nil)
            }
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { [weak textView] in
                guard let textView, textView.isEditable, let window = textView.window else { return }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(textView)
            }
        }
    }

    private func configureScrollView(_ scrollView: ExtraSpaceScrollView) {
        scrollView.isEditing = isEditing
        scrollView.closeDirection = Defaults[.enableGestures] && Defaults[.closeGestureEnabled]
            ? (Defaults[.reverseScrollGestures] ? .down : .up) : nil
        scrollView.closeSensitivity = Defaults[.gestureSensitivity]
        scrollView.onSaveAndClose = {
            store.saveNow()
            onClose()
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let textView = coordinator.textView else { return }
        Coordinator.positions[coordinator.screenID] = EditorPosition(
            selection: textView.selectedRange(), scrollOrigin: scrollView.contentView.bounds.origin
        )
        coordinator.stopObservingScrollView()
        coordinator.stopObservingUndoManager()
        textView.onFocusChange?(false)
        textView.onFocusChange = nil
        textView.onClose = nil
        textView.onBeginEditing = nil
        textView.onFinishEditing = nil
        if scrollView.window?.firstResponder === textView {
            scrollView.window?.makeFirstResponder(nil)
        }
        textView.delegate = nil
        textView.undoManager?.removeAllActions()
        coordinator.store.saveNow()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        fileprivate static var positions: [String: EditorPosition] = [:]
        let store: ExtraSpaceStore
        let screenID: String
        weak var textView: ExtraSpaceTextView?
        private weak var scrollView: NSScrollView?
        private var scrollObserver: NSObjectProtocol?
        private var undoObservers: [NSObjectProtocol] = []
        var lastPasteRequest = 0
        var lastFocusRequest = 0
        var shouldBeEditable = true

        init(store: ExtraSpaceStore, screenID: String) {
            self.store = store
            self.screenID = screenID
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let manager = textView.editorUndoManager
            if !manager.isUndoing, !manager.isRedoing, manager.groupingLevel == 1 {
                manager.endUndoGrouping()
            }
            store.updateText(textView.string)
        }

        // Let NSTextView obtain its isolated manager through AppKit's delegate.
        // https://developer.apple.com/documentation/appkit/nstextviewdelegate/undomanager(for:)
        func undoManager(for view: NSTextView) -> UndoManager? {
            (view as? ExtraSpaceTextView)?.editorUndoManager
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            if let replacementString,
               let range = Range(affectedCharRange, in: textView.string) {
                let replacedBytes = textView.string[range].utf8.count
                if store.byteCount - replacedBytes + replacementString.utf8.count > ExtraSpaceStore.maximumBytes {
                    store.reportSizeLimit()
                    return false
                }
            }
            (textView as? ExtraSpaceTextView)?.constrainUndoHistory(documentBytes: max(store.byteCount, (replacementString ?? "").utf8.count))
            let manager = textView.undoManager
            // Each native change starts a group and textDidChange closes it.
            // NSTextView retains native typing coalescing within those changes.
            if let manager, !manager.isUndoing, !manager.isRedoing, manager.groupingLevel == 0 {
                manager.beginUndoGrouping()
            }
            return true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            rememberPosition()
        }

        func observeUndoManager(_ manager: UndoManager?) {
            guard let manager else { return }
            // Native undo can change the text storage without textDidChange.
            // Save the final document after the whole undo/redo group completes.
            for name in [NSNotification.Name.NSUndoManagerDidUndoChange, NSNotification.Name.NSUndoManagerDidRedoChange] {
                undoObservers.append(NotificationCenter.default.addObserver(forName: name, object: manager, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, let textView = self.textView else { return }
                        self.store.updateText(textView.string)
                    }
                })
            }
        }

        func stopObservingUndoManager() {
            undoObservers.forEach(NotificationCenter.default.removeObserver)
            undoObservers.removeAll()
        }

        func observeScrollView(_ view: NSScrollView) {
            scrollView = view
            view.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: view.contentView, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.rememberPosition() }
            }
        }

        func stopObservingScrollView() {
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
            scrollObserver = nil
        }

        private func rememberPosition() {
            guard let textView, let scrollView else { return }
            Self.positions[screenID] = EditorPosition(
                selection: textView.selectedRange(), scrollOrigin: scrollView.contentView.bounds.origin
            )
        }

        deinit {
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
            undoObservers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

private struct EditorPosition {
    let selection: NSRange
    let scrollOrigin: NSPoint
}

private extension NSRange {
    func clamped(to length: Int) -> NSRange {
        let start = min(location, length)
        return NSRange(location: start, length: min(self.length, length - start))
    }
}
