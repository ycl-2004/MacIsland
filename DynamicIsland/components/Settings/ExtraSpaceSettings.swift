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
                SettingsInfoLabel("Extra Space", info: "Adds a text tab to the notch. Turning it off hides the tab and keeps your text.")
            }

            Section {
                KeyboardShortcuts.Recorder("Open Extra Space:", name: .openExtraSpace)
                LabeledContent("Text storage", value: "\(ByteCountFormatter.string(fromByteCount: Int64(store.byteCount), countStyle: .binary)) / 5 MB")
                Button("Show Local Content File") { store.revealContent() }
                if store.hasPreviousVersion {
                    Button("Restore Previous Saved Version") { store.recoverPrevious() }
                }
                if let error = store.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            } header: {
                SettingsInfoLabel("Text", info: "Double-click the text, or click Edit or Paste, to change it. Press ⌘S or click Save when you're done. \(closeHint) Press ⌘F to find text; Export saves a .txt copy. Your text is saved automatically on this Mac.")
            }
        }
        .navigationTitle("Extra Space")
    }
}
