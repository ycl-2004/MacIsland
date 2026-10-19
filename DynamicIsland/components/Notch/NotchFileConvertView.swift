import Defaults
import SwiftUI

/// Drop files, pick a format, and the results appear beside the originals.
@MainActor
struct NotchFileConvertView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var model: FileConvertModel
    @Default(.fileConvertKeepOriginal) private var keepOriginal

    init(model: FileConvertModel? = nil) {
        self.model = model ?? .shared
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            panel
        }
        .onDrop(of: [.fileURL], isTargeted: $vm.convertDropTargeting) { providers in
            vm.receiveConvertDrop(providers, model: model)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Convert")
                .font(.notch(.body, weight: .medium))
                .foregroundStyle(.inkPrimary)
            Spacer()
            if model.isWorking && !model.items.isEmpty {
                Button { model.cancel() } label: { Label("Stop", systemImage: "stop.circle") }
            } else if model.hasResults {
                Button { model.revealResults() } label: { Label("Show in Finder", systemImage: "folder") }
            }
            if !model.items.isEmpty && !model.isWorking {
                Button { model.clear() } label: { Label("Clear", systemImage: "xmark.circle") }
            }
            Toggle("Keep original", isOn: $keepOriginal)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(model.isWorking)
                .help(keepOriginal ? Text("The original file stays next to the converted one.")
                                   : Text("After a successful conversion, the original moves to the Trash."))
        }
        .font(.notch(.caption))
        .buttonStyle(.plain)
        .foregroundStyle(.inkSecondary)
    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: NotchRadius.panel, style: .continuous)
            .fill(vm.convertDropTargeting ? Color.accentColor.opacity(0.12) : .fillWell)
            .overlay(
                RoundedRectangle(cornerRadius: NotchRadius.panel, style: .continuous)
                    .strokeBorder(
                        vm.convertDropTargeting ? Color.accentColor : .strokeRegular,
                        style: StrokeStyle(lineWidth: vm.convertDropTargeting ? 1.5 : 1,
                                           dash: model.items.isEmpty && !vm.convertDropTargeting ? [4, 4] : [])
                    )
            )
            .overlay {
                Group {
                    if model.items.isEmpty { emptyState } else { content }
                }
                .padding(12)
            }
            .animation(vm.animation, value: vm.convertDropTargeting)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if model.isWorking {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .imageScale(.large)
                    .foregroundStyle(vm.convertDropTargeting ? Color.accentColor : .inkSecondary)
            }
            Text("Drop files to convert")
                .font(.system(.title3, design: .rounded)).fontWeight(.medium)
                .foregroundStyle(vm.convertDropTargeting ? .inkSecondary : .inkTertiary)
            Text(model.message ?? String(localized: "Images, PDFs, documents, audio and video. Saved next to the original."))
                .font(.notch(.caption))
                .foregroundStyle(model.message == nil ? .inkTertiary : .statusAttention)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.items) { row($0) }
                }
            }
            .frame(maxWidth: .infinity)
            Divider().overlay(Color.strokeHairline)
            formatPicker.frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func row(_ item: FileConvertModel.Item) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: item.icon).resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent)
                    .font(.notch(.footnote))
                    .foregroundStyle(.inkPrimary)
                    .lineLimit(1).truncationMode(.middle)
                detail(item)
                    .font(.notch(.micro))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            switch item.status {
            case .converting: ProgressView().controlSize(.mini)
            case .converted: Image(systemName: "checkmark.circle.fill").foregroundStyle(.statusSuccess)
            case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.statusAttention)
            case .ready: EmptyView()
            }
        }
    }

    @ViewBuilder
    private func detail(_ item: FileConvertModel.Item) -> some View {
        switch item.status {
        case .ready:
            Text(item.url.deletingLastPathComponent().lastPathComponent).foregroundStyle(.inkTertiary)
        case .converting:
            Text("Converting…").foregroundStyle(.inkTertiary)
        case .converted(let outputs):
            // The file name gives way first; what happened to the original stays readable.
            HStack(spacing: 0) {
                Text(outputs.count == 1 ? outputs[0].lastPathComponent : String(localized: "\(outputs.count) files"))
                    .layoutPriority(0)
                if let note = item.note {
                    Text(verbatim: " · ").fixedSize()
                    Text(note).fixedSize().layoutPriority(1)
                }
            }
            .foregroundStyle(.inkSecondary)
        case .failed(let reason):
            Text(reason).foregroundStyle(.statusAttention).help(reason)
        }
    }

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.formats.isEmpty {
                Text(model.message ?? (model.hasResults ? String(localized: "Done. Drop more files to convert again.") : ""))
                    .font(.notch(.caption))
                    .foregroundStyle(model.message == nil ? .inkTertiary : .statusAttention)
            } else {
                Text("Convert to").font(.notch(.caption)).foregroundStyle(.inkTertiary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(model.formats) { format in
                        Button(format.label) { model.convert(to: format) }
                            .buttonStyle(FormatChipStyle())
                            .disabled(model.isWorking)
                    }
                }
            }
        }
    }
}

private struct FormatChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { FormatChip(configuration: configuration) }
}

/// A view, not the style itself, so it can keep hover state.
private struct FormatChip: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.notch(.caption, weight: .medium))
            .foregroundStyle(isEnabled ? Color.inkPrimary : Color.inkTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(isHovering || configuration.isPressed ? Color.fillControlHover : Color.fillControl,
                        in: RoundedRectangle(cornerRadius: NotchRadius.control, style: .continuous))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(.notchQuick, value: isHovering)
    }
}
