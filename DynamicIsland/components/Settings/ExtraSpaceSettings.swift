import KeyboardShortcuts
import Defaults
import SwiftUI

struct ExtraSpaceSettings: View {
    @Default(.enableGestures) private var enableGestures
    @Default(.closeGestureEnabled) private var closeGestureEnabled
    @Default(.reverseScrollGestures) private var reverseScrollGestures
    @ObservedObject private var store = ExtraSpaceStore.shared
    private var closeHint: String {
        guard enableGestures && closeGestureEnabled else { return String(localized: "Close gestures are off; press Escape to close.") }
        return reverseScrollGestures ? String(localized: "After saving, swipe down to close.") : String(localized: "After saving, swipe up to close.")
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableExtraSpaceFeature) {
                    Text("Enable Extra Space")
                }
                .settingsHighlight(id: "extraSpace-Enable Extra Space")
            } header: {
                Text("Extra Space")
            } footer: {
                Text("Show Extra Space alongside Home, Stats and Agents. Turning it off hides the tab and keeps your text.")
            }

            Section {
                KeyboardShortcuts.Recorder("Open Extra Space:", name: .openExtraSpace)
                Label("One continuous text area", systemImage: "text.alignleft")
                Label("Automatically saved on this Mac", systemImage: "internaldrive")
                LabeledContent("Text storage", value: "\(ByteCountFormatter.string(fromByteCount: Int64(store.byteCount), countStyle: .binary)) / 5 MB")
                Button("Show Local Content File") { store.revealContent() }
                if store.hasPreviousVersion {
                    Button("Restore Previous Saved Version") { store.recoverPrevious() }
                }
                if let error = store.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            } footer: {
                Text("Double-click the text area, or click Edit or Paste, to change text. Press ⌘S or click Save to finish editing. While editing, scroll inside the text. \(closeHint) Use ⌘F to find text and Export to save a .txt copy. Your text stays available after closing the notch or restarting Atoll.")
            }
        }
        .navigationTitle("Extra Space")
    }
}
