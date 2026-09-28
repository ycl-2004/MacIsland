import SwiftUI
import Defaults

/// The screen question in the Agents tab: type it, wait for it, read the answer.
struct ScreenQuestionCard: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var manager = ScreenQuestionManager.shared
    @Default(.screenQuestionBackend) private var backendID
    @FocusState private var isQuestionFocused: Bool
    @State private var autoCloseToken = UUID()
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch manager.phase {
            case .idle:
                EmptyView()
            case .composing:
                composer
            case .asking:
                header(title: manager.askedQuestion)
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Asking \(backendName(manager.askedBackendID))…")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Button("Cancel") { manager.cancel() }
                }
            case .answered(let answer):
                header(title: manager.askedQuestion)
                ScrollView {
                    Text(Self.renderMarkdown(answer))
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button(didCopy ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(answer, forType: .string)
                        didCopy = true
                    }
                    Spacer()
                    Button("Done") { manager.dismiss() }
                }
            case .failed(let message):
                header(title: manager.askedQuestion.isEmpty ? String(localized: "Screen question") : manager.askedQuestion)
                ScrollView {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.9))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    if manager.screenshot != nil {
                        Button("Edit Question") { manager.cancel() }
                    }
                    Spacer()
                    Button("Done") { manager.dismiss() }
                }
            }
        }
        .controlSize(.small)
        .padding(10)
        .frame(width: 300, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: manager.phase, initial: true) { _, phase in
            didCopy = false
            // Typing moves the pointer off the notch; keep it open until the question is sent.
            vm.setAutoCloseSuppression(phase == .composing, token: autoCloseToken)
            if phase == .composing { focusQuestionField() }
        }
        .onDisappear { vm.setAutoCloseSuppression(false, token: autoCloseToken) }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if let screenshot = manager.screenshot {
                    Image(nsImage: screenshot)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 88, maxHeight: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                TextField("Ask about this screenshot…", text: $manager.question, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...3)
                    .focused($isQuestionFocused)
                    .onSubmit { manager.ask() }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Picker("", selection: $backendID) {
                    ForEach(AssistantBackendRegistry.all, id: \.sourceID) { backend in
                        Label(backendName(backend.sourceID), systemImage: backend.source?.symbolName ?? "sparkles")
                            .tag(backend.sourceID)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button("Cancel") { manager.dismiss() }
                // Return is handled by the field's onSubmit; a default-action
                // shortcut here as well would send the question twice.
                Button("Ask") { manager.ask() }
                    .disabled(manager.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func header(title: String) -> some View {
        HStack(spacing: 6) {
            if let source = manager.askedBackendID.flatMap(AgentSourceRegistry.source(id:)) {
                Image(systemName: source.symbolName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(source.accentColor)
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
    }

    private func backendName(_ id: String?) -> String {
        id.flatMap(AgentSourceRegistry.source(id:))?.displayName ?? id ?? ""
    }

    /// The notch is a panel that does not take keyboard focus on its own.
    private func focusQuestionField() {
        NSApp.activate()
        let notchWindows = NSApp.windows.compactMap { $0 as? DynamicIslandWindow }.filter(\.isVisible)
        let underPointer = notchWindows.first { $0.frame.contains(NSEvent.mouseLocation) }
        (underPointer ?? notchWindows.first)?.makeKey()
        DispatchQueue.main.async { isQuestionFocused = true }
    }

    /// Agents answer in Markdown; inline styles and line breaks are kept.
    private static func renderMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
