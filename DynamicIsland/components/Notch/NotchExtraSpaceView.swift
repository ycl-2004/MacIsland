import SwiftUI

struct NotchExtraSpaceView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var store: ExtraSpaceStore
    @State private var pasteRequest = 0
    @State private var focusToken = UUID()
    @State private var isEditing = false
    @State private var focusRequest = 0
    @State private var findRequest = 0
    @State private var exportRequest = 0
    @State private var findToken = UUID()
    @State private var exportToken = UUID()
    @State private var exportError: String?

    init(store: ExtraSpaceStore = .shared) {
        self.store = store
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("Extra Space")
                    .font(.notch(.body, weight: .medium))
                    .foregroundStyle(.inkPrimary)
                Spacer()
                ViewThatFits(in: .horizontal) {
                    toolbar(compact: false).fixedSize()
                    toolbar(compact: true).fixedSize()
                }
            }
            .font(.notch(.caption))
            .buttonStyle(.plain)
            .foregroundStyle(.inkSecondary)

            if let message = store.errorMessage {
                HStack {
                    Label(store.isLoaded ? "Couldn’t save changes" : "Couldn’t load your text", systemImage: "exclamationmark.triangle")
                        .help(message)
                    Spacer()
                    Button("Retry") { store.retry() }
                }
                .font(.notch(.caption))
                .foregroundStyle(.statusAttention)
            }

            if let exportError {
                Text("Couldn’t export text: \(exportError)")
                    .font(.notch(.caption)).foregroundStyle(.statusAttention).textSelection(.enabled)
            }

            ExtraSpaceEditor(
                store: store,
                screenID: vm.screen ?? DynamicIslandViewCoordinator.shared.selectedScreen,
                pasteRequest: pasteRequest,
                isEditing: isEditing,
                focusRequest: focusRequest,
                findRequest: findRequest,
                exportRequest: exportRequest,
                onFindVisibilityChange: { vm.setAutoCloseSuppression($0, token: findToken) },
                onExportFinished: { error in
                    exportError = error
                    vm.setAutoCloseSuppression(false, token: exportToken)
                },
                onBeginEditing: beginEditing,
                onFinishEditing: finishEditing,
                onFocusChange: { vm.setAutoCloseSuppression($0 && isEditing, token: focusToken) },
                onClose: {
                    store.saveNow()
                    vm.close()
                }
            )
            .overlay(alignment: .topLeading) {
                if store.isLoaded && store.text.isEmpty {
                    Text("Double-click or Paste to add text…")
                        .font(.notch(.body))
                        .foregroundStyle(.inkTertiary)
                        .padding(12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background(.fillWell, in: RoundedRectangle(cornerRadius: NotchRadius.control))
            .clipShape(RoundedRectangle(cornerRadius: NotchRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: NotchRadius.control).strokeBorder(.strokeHairline)
            }
            .suppressesNotchSwipeGestures()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .onDisappear {
            vm.setAutoCloseSuppression(false, token: focusToken)
            vm.setAutoCloseSuppression(false, token: findToken)
            vm.setAutoCloseSuppression(false, token: exportToken)
            store.saveNow()
        }
    }

    private func beginEditing() {
        isEditing = true
        focusRequest += 1
    }

    private func finishEditing() {
        isEditing = false
        vm.setAutoCloseSuppression(false, token: focusToken)
    }

    private func toolbar(compact: Bool) -> some View {
        HStack(spacing: 8) {
            if !compact && store.errorMessage == nil {
                Text(store.isLoaded ? (store.isDirty ? "Saving…" : "Saved locally") : "Loading…")
                    .foregroundStyle(.inkTertiary)
            }
            Button {
                isEditing = true
                pasteRequest += 1
            } label: {
                if compact { Image(systemName: "doc.on.clipboard") }
                else { Label("Paste", systemImage: "doc.on.clipboard") }
            }
            .accessibilityLabel("Paste")
            .help("Paste")
            .disabled(!store.isLoaded)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(store.text, forType: .string)
            } label: {
                if compact { Image(systemName: "doc.on.doc") }
                else { Label("Copy all", systemImage: "doc.on.doc") }
            }
            .accessibilityLabel("Copy all")
            .help("Copy all")
            .disabled(!store.isLoaded || store.text.isEmpty)
            Button { findRequest += 1 } label: { Image(systemName: "magnifyingglass") }
                .accessibilityLabel("Find in Extra Space").help("Find text (⌘F)")
                .disabled(!store.isLoaded)
            Button {
                exportError = nil
                vm.setAutoCloseSuppression(true, token: exportToken)
                exportRequest += 1
            } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Export Extra Space as text").help("Export text…")
                .disabled(!store.isLoaded)
            Button {
                if isEditing {
                    finishEditing()
                } else {
                    beginEditing()
                }
            } label: {
                Label(isEditing ? "Save" : "Edit", systemImage: isEditing ? "checkmark" : "pencil")
            }
            .disabled(!store.isLoaded)
            .help(isEditing ? "Save locally and finish editing (⌘S)" : "Edit your text (or double-click the text area)")
        }
    }
}
