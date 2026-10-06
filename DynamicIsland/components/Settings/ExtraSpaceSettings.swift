import Defaults
import SwiftUI

struct ExtraSpaceSettings: View {
    @ObservedObject private var store = ExtraSpaceStore.shared
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
                Label("One continuous text area", systemImage: "text.alignleft")
                Label("Automatically saved on this Mac", systemImage: "internaldrive")
                LabeledContent("Text storage", value: "\(ByteCountFormatter.string(fromByteCount: Int64(store.byteCount), countStyle: .binary)) / 5 MB")
                Button("Show Local Content File") { store.revealContent() }
                if store.hasPreviousVersion {
                    Button("Restore Previous Saved Version") { store.recoverPrevious() }
                }
                if let error = store.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            } footer: {
                Text("Double-click the text area, or click Edit or Paste, to change text. Press ⌘S or click Save to finish editing. While editing, scroll inside the text. After saving, swipe up to close. Your text stays available after closing the notch or restarting Atoll.")
            }
        }
        .navigationTitle("Extra Space")
    }
}
