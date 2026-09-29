/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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

/// Sends what is dropped on the shelf's share zone, or picked from it, with
/// AirDrop.
///
/// This used to enumerate every sharing service at runtime and let the user
/// choose one. AirDrop is the only one the zone is used for, so it is the only
/// one it knows: nothing is discovered, cached or stored as a preference.
@MainActor
final class AirDropService: ObservableObject {
    static let shared = AirDropService()

    @Published private(set) var isPickerOpen = false

    /// AirDrop's own icon for the drop zone, looked up once.
    private(set) lazy var icon: NSImage? = NSSharingService(named: .sendViaAirDrop)?.image

    /// Prevents overlapping transfers; cleared by the actual service callback.
    @Published private(set) var isSending = false

    private init() {}

    /// Lets the user pick files, then sends them.
    func pickFilesAndSend(from view: NSView?) {
        guard !isPickerOpen, !isSending else { return }
        isPickerOpen = true
        SharingStateManager.shared.beginInteraction()
        // Atoll is rarely the active app while the notch is in use; without this
        // the panel can open behind the window the user is looking at.
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = String(localized: "Select Files for AirDrop")

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            self?.isPickerOpen = false
            SharingStateManager.shared.endInteraction()
            if response == .OK {
                self?.send(panel.urls)
            }
        }

        if let window = view?.window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    /// Sends the links, files and text in a drop.
    func send(_ providers: [NSItemProvider]) async {
        guard !isSending else { return }
        isSending = true
        let items = await ShelfDropService.items(from: providers)
        var urls: [URL] = []
        for item in items {
            switch item.kind {
            case .file: if let url = item.resolvedFileURL { urls.append(url) }
            case .link(let url): urls.append(url)
            case .text(let text):
                if let url = await TemporaryFileStorageService.shared.createTempFile(for: .text(text)) { urls.append(url) }
            }
        }
        isSending = false
        guard urls.count == providers.count else {
            ShelfFileLifetime.shared.requestCleanup()
            ShelfStateViewModel.shared.report(String(localized: "Some items could not be read. AirDrop was not started."))
            return
        }
        send(urls)
    }

    private func send(_ urls: [URL]) {
        guard !isSending, !urls.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls)
        else {
            ShelfStateViewModel.shared.report(String(localized: "AirDrop is unavailable for these items."))
            ShelfFileLifetime.shared.requestCleanup()
            return
        }

        isSending = true
        let lease = ShelfFileLifetime.shared.acquire(urls)
        let delegate = SharingStateManager.shared.makeDelegate { [weak self] succeeded in
            lease.finish(handoff: succeeded)
            self?.isSending = false
        }
        delegate.retainService(service)
        delegate.markServiceBegan()
        service.delegate = delegate
        service.perform(withItems: urls)
    }
}
