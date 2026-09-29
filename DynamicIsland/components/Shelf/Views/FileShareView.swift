/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import SwiftUI

/// The shelf's AirDrop zone: drop things on it to send them, or click it to
/// pick files.
struct FileShareView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var airDrop = AirDropService.shared

    @State private var hostView: NSView?
    @State private var isProcessing = false

    var body: some View {
        Button { airDrop.pickFilesAndSend(from: hostView) } label: { dropArea }
            .buttonStyle(.plain)
            .disabled(isProcessing || airDrop.isPickerOpen || airDrop.isSending)
            .help("Drop to send · Click to choose files")
            .background(NSViewHost(view: $hostView))
            .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data, .image], isTargeted: $vm.dropZoneTargeting) { providers in
                guard !isProcessing, !airDrop.isSending else { return false }
                isProcessing = true
                vm.dropEvent = true
                Task { await handleDrop(providers) }
                return true
            }
    }

    /// Visual drop container view with dynamic targeting highlights and border stroke.
    private var dropArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(vm.dropZoneTargeting ? Color.accentColor.opacity(0.18) : .fillWell)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            vm.dropZoneTargeting ? Color.accentColor : .strokeRegular,
                            lineWidth: vm.dropZoneTargeting ? 1.5 : 1
                        )
                )

            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(vm.dropZoneTargeting ? Color.fillCardHover : .fillCard)
                        .frame(width: 55, height: 55)
                    Group {
                        if let icon = airDrop.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 34, height: 34)
                                .clipped()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 34, height: 34)
                        }
                    }
                    .foregroundStyle(vm.dropZoneTargeting ? Color.accentColor : .inkTertiary)
                    .scaleEffect(vm.dropZoneTargeting ? 1.06 : 1.0)
                    .animation(.spring(response: 0.36, dampingFraction: 0.7), value: vm.dropZoneTargeting)
                }

                Text("AirDrop")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.inkSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Text("Drop to send · Click to choose files")
                    .font(.system(size: 12))
                    .foregroundStyle(.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity)

            if isProcessing || airDrop.isPickerOpen {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    )
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private func handleDrop(_ providers: [NSItemProvider]) async {
        isProcessing = true
        defer { isProcessing = false }
        await airDrop.send(providers)
    }
}

// MARK: - Host NSView extractor for anchoring the file picker

private struct NSViewHost: NSViewRepresentable {
    @Binding var view: NSView?

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { self.view = v }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { self.view = nsView }
    }
}
