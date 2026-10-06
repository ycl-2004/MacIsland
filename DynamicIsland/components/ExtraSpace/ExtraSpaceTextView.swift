import AppKit

final class ExtraSpaceTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?
    var onClose: (() -> Void)?
    var onBeginEditing: (() -> Void)?
    var onFinishEditing: (() -> Void)?
    var clipboard: NSPasteboard = .general
    let editorUndoManager: UndoManager = {
        let manager = UndoManager()
        // Coordinator brackets native mutations; grouping is independent of
        // SwiftUI callbacks and the accessory app's run-loop event grouping.
        // https://developer.apple.com/documentation/foundation/undomanager/groupsbyevent
        manager.groupsByEvent = false
        manager.levelsOfUndo = 200
        return manager
    }()
    private var largestUndoDocumentBytes = 0
    func constrainUndoHistory(documentBytes: Int) {
        largestUndoDocumentBytes = max(largestUndoDocumentBytes, documentBytes)
        let levels = min(200, max(2, (16 * 1024 * 1024) / max(1, largestUndoDocumentBytes)))
        if levels < editorUndoManager.levelsOfUndo {
            // Large whole-document replacements can otherwise retain gigabytes.
            // Keep the new edit undoable, and release the preceding large history.
            editorUndoManager.removeAllActions()
            editorUndoManager.levelsOfUndo = levels
        }
    }
    private var windowObservers: [NSObjectProtocol] = []

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // In reading mode the double click enters editing; once editing,
        // AppKit keeps its normal word-selection behavior.
        // https://developer.apple.com/documentation/appkit/nsevent/clickcount
        if !isEditable, event.clickCount == 2, let onBeginEditing {
            onBeginEditing()
            return
        }
        super.mouseDown(with: event)
    }

    // This accessory app's notch cannot depend on an Edit menu for shortcuts.
    // Handle them only while this editor is the first responder.
    // https://developer.apple.com/documentation/appkit/nsresponder/performkeyequivalent(with:)
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleEditingShortcut(event) || super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if !handleEditingShortcut(event) { super.keyDown(with: event) }
    }

    private func handleEditingShortcut(_ event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let isCommand = flags == .command
        if isCommand, event.charactersIgnoringModifiers?.lowercased() == "s" {
            if isEditable { onFinishEditing?() }
            return true
        }
        guard !hasMarkedText() else { return false }
        let isControl = flags == .control
        let isRedo = flags == [.command, .shift] || flags == [.control, .shift]
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z" where isCommand || isControl || isRedo:
            guard isEditable else { return true }
            breakUndoCoalescing()
            if isRedo {
                if editorUndoManager.canRedo { editorUndoManager.redo() }
            } else if editorUndoManager.canUndo {
                editorUndoManager.undo()
            }
        case "v" where isCommand || isControl:
            pasteAsPlainText(nil)
        case "a" where isCommand:
            selectAll(nil)
        case "c" where isCommand:
            copy(nil)
        case "x" where isCommand:
            if isEditable { cut(nil) }
        default:
            return false
        }
        return true
    }

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    override func copy(_ sender: Any?) {
        guard selectedRange().length > 0 else { return }
        clipboard.clearContents()
        clipboard.setString((string as NSString).substring(with: selectedRange()), forType: .string)
    }

    override func cut(_ sender: Any?) {
        guard isEditable, selectedRange().length > 0 else { return }
        copy(sender)
        delete(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        guard isEditable else { return }
        // A paste is one independent edit, so Undo restores the pre-paste text.
        // https://developer.apple.com/documentation/appkit/nstextview/breakundocoalescing()
        breakUndoCoalescing()
        // Use AppKit's paste operation rather than treating pasted text as typing.
        // https://developer.apple.com/documentation/appkit/nstextview/readselection(from:type:)
        if clipboard.availableType(from: [.string]) != nil {
            _ = readSelection(from: clipboard, type: .string)
        } else if clipboard === NSPasteboard.general {
            super.pasteAsPlainText(sender)
        }
        breakUndoCoalescing()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(window?.isKeyWindow == true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.onFocusChange?(self.window?.isKeyWindow == true && self.window?.firstResponder === self)
                }
            })
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() { super.cancelOperation(sender) } else { onClose?() }
    }

    deinit { windowObservers.forEach(NotificationCenter.default.removeObserver) }
}
