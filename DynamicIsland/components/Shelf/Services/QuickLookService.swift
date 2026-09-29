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

import Foundation
import UniformTypeIdentifiers
import SwiftUI
import QuickLookUI
import AppKit

@MainActor
final class QuickLookService: ObservableObject {
    @Published var urls: [URL] = []
    @Published var selectedURL: URL?

    @Published var isQuickLookOpen: Bool = false

    private var previewPanel: QLPreviewPanel?
    private var fileLease: ShelfFileLease?
    private let lifetime: ShelfFileLifetime

    init(lifetime: ShelfFileLifetime = .shared) { self.lifetime = lifetime }

    func show(urls: [URL], selectFirst: Bool = true, slideshow: Bool = false) {
        guard !urls.isEmpty else { return }
        // Acquire the replacement before releasing the old preview. A file may
        // have been removed from Shelf while the preview was still open.
        let nextLease = lifetime.acquire(urls)
        stopAccessingCurrentURLs()
        fileLease = nextLease
        self.urls = urls
        self.isQuickLookOpen = true
        if selectFirst { self.selectedURL = urls.first }
        // Observe the shared Quick Look preview panel closing so we can relinquish security scope
        let panel = QLPreviewPanel.shared()
        previewPanel = panel
        NotificationCenter.default.addObserver(self, selector: #selector(previewPanelWillClose(_:)), name: NSWindow.willCloseNotification, object: panel)
    }

    func hide() {
        let panel = previewPanel
        stopAccessingCurrentURLs()
        panel?.orderOut(nil)
        selectedURL = nil
        urls.removeAll()
        isQuickLookOpen = false
    }
    
    private func stopAccessingCurrentURLs() {
        fileLease?.finish()
        fileLease = nil
        // If Quick Look panel was closed externally, also remove observer and clear reference
        if let panel = previewPanel {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: panel)
            previewPanel = nil
        }
    }
    
    func showQuickLook(urls: [URL]) {
        show(urls: urls, selectFirst: true, slideshow: false)
    }

    func updateSelection(urls: [URL]) {
        guard isQuickLookOpen else { return }
        if urls.isEmpty { hide(); return }
        show(urls: urls, selectFirst: true)
    }
}

extension QuickLookService {
    @objc private func previewPanelWillClose(_ notification: Notification) {
        guard let panel = notification.object as? QLPreviewPanel, panel === previewPanel else { return }
        stopAccessingCurrentURLs()
        selectedURL = nil
        urls.removeAll()
        isQuickLookOpen = false
    }
}

struct QuickLookPresenter: ViewModifier {
    @ObservedObject var service: QuickLookService

    func body(content: Content) -> some View {
        content
            .quickLookPreview($service.selectedURL, in: service.urls)
            .onChange(of: service.selectedURL) { _, selection in
                if selection == nil && service.isQuickLookOpen { service.hide() }
            }
    }
}

extension View {
    func quickLookPresenter(using service: QuickLookService) -> some View {
        self.modifier(QuickLookPresenter(service: service))
    }
}


final class QuickLookDataSource: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private let urls: [URL]

    init(urls: [URL]) {
        self.urls = urls
        super.init()
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return urls.count
    }
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0 && index < urls.count else { return nil }
        return urls[index] as QLPreviewItem
    }
}
