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
        panel
            .onDrop(of: [.fileURL], isTargeted: $vm.convertDropTargeting) { providers in
                vm.receiveConvertDrop(providers, model: model)
            }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("File Convert")
                .font(.notch(.caption, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            if model.isWorking && !model.items.isEmpty {
                Button { model.cancel() } label: { Image(systemName: "stop.circle") }
                    .help("Stop conversion")
                    .accessibilityLabel("Stop conversion")
            } else if model.hasResults {
                Button { model.revealResults() } label: { Image(systemName: "folder") }
                    .help("Show in Finder")
                    .accessibilityLabel("Show in Finder")
            }
            if !model.items.isEmpty && !model.isWorking {
                Button { model.clear() } label: { Image(systemName: "xmark.circle") }
                    .help("Clear conversion list")
                    .accessibilityLabel("Clear conversion list")
            }
            Menu {
                Toggle("Keep original", isOn: $keepOriginal)
                    .disabled(model.isWorking)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(keepOriginal ? Text("Keep original: On. The original stays next to the converted file.")
                               : Text("Keep original: Off. After conversion, the original moves to the Trash."))
            .accessibilityLabel("Conversion options")
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
                VStack(spacing: 8) {
                    header
                    if model.items.isEmpty {
                        emptyState
                    } else {
                        content
                    }
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
                .font(.system(.body, design: .rounded)).fontWeight(.medium)
                .foregroundStyle(vm.convertDropTargeting ? .inkSecondary : .inkTertiary)
                .multilineTextAlignment(.center)
            Text(model.message ?? String(localized: "Images, PDFs, documents, audio and video"))
                .font(.notch(.micro))
                .foregroundStyle(model.message == nil ? .inkTertiary : .statusAttention)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.items) { row($0) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            formatPicker
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
            VStack(alignment: .leading, spacing: 1) {
                Text(outputs.count == 1 ? outputs[0].lastPathComponent : String(localized: "\(outputs.count) files"))
                if let note = item.note {
                    Text(note)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(note)
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
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(model.formats) { format in
                            Button(format.label) { model.convert(to: format) }
                                .buttonStyle(FormatChipStyle())
                                .disabled(model.isWorking)
                                .fixedSize()
                        }
                    }
                }
                .scrollIndicators(.automatic)
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
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isHovering || configuration.isPressed ? Color.fillControlHover : Color.fillControl,
                        in: RoundedRectangle(cornerRadius: NotchRadius.control, style: .continuous))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(.notchQuick, value: isHovering)
    }
}
