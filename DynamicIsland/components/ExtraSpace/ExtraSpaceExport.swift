import AppKit
import UniformTypeIdentifiers

enum ExtraSpaceExport {
    /// Exports an immutable snapshot off the UI thread. The local scratchpad
    /// and its undo history are independent of the user-selected destination.
    static func write(_ text: String, to url: URL) async throws {
        try await Task.detached(priority: .utility) {
            try Data(text.utf8).write(to: url, options: .atomic)
        }.value
    }

    // https://developer.apple.com/documentation/appkit/nssavepanel
    @MainActor static func present(text: String, in window: NSWindow,
                                   completion: @escaping (String?) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Extra Space.txt"
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { completion(nil); return }
            Task { @MainActor in
                do { try await write(text, to: url); completion(nil) }
                catch { completion(error.localizedDescription) }
            }
        }
    }
}
