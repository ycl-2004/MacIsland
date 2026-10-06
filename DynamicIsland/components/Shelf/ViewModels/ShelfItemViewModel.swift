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
import AppKit
import SwiftUI

@MainActor
final class ShelfItemViewModel: ObservableObject {
    @Published private(set) var item: ShelfItem
    @Published var thumbnail: NSImage?
    @Published var displayName: String = ""
    @Published var icon: NSImage?
    private var metadataTask: Task<Void, Never>?
    private let selection = ShelfSelectionModel.shared

    init(item: ShelfItem) {
        self.item = item
        applyImmediateMetadata()
    }

    deinit { metadataTask?.cancel() }

    var isSelected: Bool { selection.isSelected(item.id) }

    func update(_ item: ShelfItem) {
        guard self.item != item else { return }
        stopLoading()
        self.item = item
        applyImmediateMetadata()
    }

    private func applyImmediateMetadata() {
        switch item.kind {
        case .file:
            displayName = item.cachedDisplayName ?? item.cachedPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? String(localized: "File")
            icon = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        case .text(let text):
            displayName = text.trimmingCharacters(in: .whitespacesAndNewlines)
            icon = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil)
        case .link(let url):
            displayName = url.absoluteString
            icon = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        }
    }

    func startLoading() {
        guard metadataTask == nil, case .file(let data) = item.kind else { return }
        icon = item.cachedIconData.flatMap(NSImage.init(data:)) ?? icon
        let snapshot = item
        metadataTask = Task { [weak self] in
            let result = await Bookmark(data: data).resolveAsync()
            guard !Task.isCancelled, let url = result.url else { return }
            let name = await Task.detached(priority: .utility) {
                (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.lastPathComponent
            }.value
            guard !Task.isCancelled, self?.item.kind == snapshot.kind else { return }
            self?.displayName = name
            ShelfStateViewModel.shared.applyCachedPath(url.standardizedFileURL.path, for: snapshot.id, resolvedFrom: data)
            let image = await ThumbnailService.shared.thumbnail(for: url, size: CGSize(width: 56, height: 56))
            guard !Task.isCancelled, self?.item.kind == snapshot.kind else { return }
            self?.thumbnail = image
        }
    }

    func stopLoading() {
        metadataTask?.cancel()
        metadataTask = nil
        thumbnail = nil
        applyImmediateMetadata()
    }

    // MARK: - Actions
    func handleClick(event: NSEvent, view: NSView) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift) {
            selection.shiftSelect(to: item, in: ShelfStateViewModel.shared.items)
        } else if flags.contains(.command) {
            selection.toggle(item)
        } else if flags.contains(.control) {
            handleRightClick(event: event, view: view)
        } else {
            if !selection.isSelected(item.id) { selection.selectSingle(item) }
        }
        if event.clickCount == 2 { handleDoubleClick() }
    }

    func handleRightClick(event: NSEvent, view: NSView) {
        if !selection.isSelected(item.id) { selection.selectSingle(item) }
        presentContextMenu(event: event, in: view)
    }

    func handleDoubleClick() {
    let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
        for it in selected { ShelfActionService.open(it) }
    }

    func shareItem(from view: NSView?) {
        guard let view else { return }
        let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
        let preparationLease = ShelfFileLifetime.shared.acquire(selected.compactMap { $0.resolvedFileURL })
        Task {
            defer { preparationLease.finish() }
            var itemsToShare: [Any] = []
            var fileURLs: [URL] = []
            for item in selected {
                switch item.kind {
                case .file:
                    if let url = await ShelfStateViewModel.shared.resolveAndUpdateBookmarkAsync(for: item) {
                        itemsToShare.append(url)
                        fileURLs.append(url)
                    }
                case .text(let string): itemsToShare.append(string)
                case .link(let url): itemsToShare.append(url)
                }
            }
            guard !itemsToShare.isEmpty, itemsToShare.count == selected.count else {
                ShelfStateViewModel.shared.report(String(localized: "Some items could not be shared. Check that the files are available."))
                return
            }
             
            let lease = ShelfFileLifetime.shared.acquire(fileURLs)
            let lifecycle = SharingStateManager.shared.makeDelegate { succeeded in
                lease.finish(handoff: succeeded)
            }
            let picker = NSSharingServicePicker(items: itemsToShare)
            lifecycle.retainPicker(picker)
            picker.delegate = lifecycle
            lifecycle.markPickerBegan()
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
    }

    /// Call this closure to request a QuickLook preview for the given URLs.
    var onQuickLookRequest: (([URL]) -> Void)?

    // MARK: - Context Menu

    private func ensureContextMenuSelection() {
        if !selection.isSelected(item.id) { selection.selectSingle(item) }
    }

    func presentContextMenu(event: NSEvent, in view: NSView) {
        ensureContextMenuSelection()
        let menu = NSMenu()

        func addMenuItem(title: String) {
            let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            // Dispatch keys off the identifier so localized titles cannot break it.
            mi.identifier = NSUserInterfaceItemIdentifier(title)
            menu.addItem(mi)
        }

        let selectedItems = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
        let selectedFileURLs = selectedItems.compactMap { $0.fileURL }
        let selectedLinkURLs: [URL] = selectedItems.compactMap { itm in
            if case .link(let url) = itm.kind { return url }
            return nil
        }
        // URLs valid for Open/Open With (exclude folders)
        let selectedOpenableURLs = selectedItems.compactMap { itm -> URL? in
            if let candidateURL = itm.fileURL { return isDirectory(candidateURL) ? nil : candidateURL }
            if case .link(let url) = itm.kind { return url }
            return nil
        }

        if !selectedOpenableURLs.isEmpty {
            addMenuItem(title: "Open")
        }

        if !selectedOpenableURLs.isEmpty {
            let openWith = NSMenuItem(title: String(localized: "Open With"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()

            // Choose a representative URL to compute apps (prefer current item if not a folder)
            let baseURLForApps: URL? = {
                if let candidateURL = item.fileURL, !isDirectory(candidateURL) { return candidateURL }
                if case .link(let candidateURL) = item.kind { return candidateURL }
                return selectedOpenableURLs.first
            }()

            let openWithApps: [URL] = {
                guard let candidateURL = baseURLForApps else { return [] }
                if candidateURL.isFileURL {
                    var results = NSWorkspace.shared.urlsForApplications(toOpen: candidateURL)
                    if results.isEmpty, let uti = try? candidateURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
                        results = NSWorkspace.shared.urlsForApplications(toOpen: uti)
                    }
                    return Array(Set(results))
                } else {
                    return Array(Set(NSWorkspace.shared.urlsForApplications(toOpen: candidateURL)))
                }
            }()
            let defaultApp = defaultAppURL()

            if openWithApps.isEmpty {
                let noApps = NSMenuItem(title: String(localized: "No Compatible Apps Found"), action: nil, keyEquivalent: "")
                noApps.isEnabled = false
                submenu.addItem(noApps)
            } else {
                if let defaultApp = defaultApp {
                    let appName = appDisplayName(for: defaultApp)
                    let def = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
                    def.representedObject = defaultApp
                    def.image = nsAppIcon(for: defaultApp, size: 16)

                    let title = NSMutableAttributedString(string: appName, attributes: [
                        .font: NSFont.menuFont(ofSize: 0),
                        .foregroundColor: NSColor.labelColor
                    ])
                    let defaultPart = NSAttributedString(string: " (default)", attributes: [
                        .font: NSFont.menuFont(ofSize: 0),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ])
                    title.append(defaultPart)
                    def.attributedTitle = title
                    submenu.addItem(def)

                    if openWithApps.count > 1 || !openWithApps.contains(defaultApp) {
                        submenu.addItem(NSMenuItem.separator())
                    }
                }
                for appURL in openWithApps where appURL != defaultApp {
                    let mi = NSMenuItem(title: appDisplayName(for: appURL), action: nil, keyEquivalent: "")
                    mi.representedObject = appURL
                    mi.image = nsAppIcon(for: appURL, size: 16)
                    submenu.addItem(mi)
                }
            }

            submenu.addItem(NSMenuItem.separator())
            let other = NSMenuItem(title: String(localized: "Other…"), action: nil, keyEquivalent: "")
            other.representedObject = "__OTHER__"
            submenu.addItem(other)

            openWith.submenu = submenu
            menu.addItem(openWith)
        }

        if !selectedFileURLs.isEmpty { addMenuItem(title: "Show in Finder") }
        // Allow Quick Look for files and link URLs
        if !selectedFileURLs.isEmpty || !selectedLinkURLs.isEmpty {
            // Add Quick Look menu item
            let quickLookItem = NSMenuItem(title: String(localized: "Quick Look"), action: nil, keyEquivalent: "")
            quickLookItem.identifier = NSUserInterfaceItemIdentifier("Quick Look")
            menu.addItem(quickLookItem)
            
            // Add Slideshow as alternate menu item (shown when Option key is held)
            let slideshowItem = NSMenuItem(title: String(localized: "Quick Look"), action: nil, keyEquivalent: "")
            slideshowItem.identifier = NSUserInterfaceItemIdentifier("Quick Look")
            slideshowItem.isAlternate = true
            slideshowItem.keyEquivalentModifierMask = [.option]
            menu.addItem(slideshowItem)
        }

        menu.addItem(NSMenuItem.separator())
        addMenuItem(title: "Share…")

        // Add compression option for files/folders (single or multiple)
        if !selectedFileURLs.isEmpty {
            let compressItem = NSMenuItem(title: String(localized: "Compress"), action: nil, keyEquivalent: "")
            compressItem.identifier = NSUserInterfaceItemIdentifier("Compress")
            menu.addItem(compressItem)
        }

        if selectedItems.count == 1, case .file(_) = item.kind { addMenuItem(title: "Rename") }

        // Always show "Copy" for all item types
        addMenuItem(title: "Copy")
        // If there are file URLs, add "Copy Path" as an alternate menu item (Option key)
        if !selectedFileURLs.isEmpty {
            let copyPathItem = NSMenuItem(title: String(localized: "Copy Path"), action: nil, keyEquivalent: "")
            copyPathItem.identifier = NSUserInterfaceItemIdentifier("Copy Path")
            copyPathItem.isAlternate = true
            copyPathItem.keyEquivalentModifierMask = [.option]
            menu.addItem(copyPathItem)
        }

        menu.addItem(NSMenuItem.separator())
        addMenuItem(title: "Remove")

        let actionTarget = MenuActionTarget(item: item, view: view, viewModel: self)

        for menuItem in menu.items {
            if menuItem.isSeparatorItem { continue }
            menuItem.target = actionTarget
            menuItem.action = #selector(MenuActionTarget.handle(_:))

            if let submenu = menuItem.submenu {
                for subItem in submenu.items {
                    if !subItem.isSeparatorItem {
                        subItem.target = actionTarget
                        subItem.action = #selector(MenuActionTarget.handle(_:))
                    }
                }
            }
        }
        
        menu.retainActionTarget(actionTarget)
        
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func isDirectory(_ url: URL) -> Bool {
        return url.accessSecurityScopedResource { scoped in
            (try? scoped.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        }
    }

    private final class MenuActionTarget: NSObject {
        let item: ShelfItem
        weak var view: NSView?
        unowned let viewModel: ShelfItemViewModel

        init(item: ShelfItem, view: NSView, viewModel: ShelfItemViewModel) {
            self.item = item
            self.view = view
            self.viewModel = viewModel
        }

        @MainActor @objc func handle(_ sender: NSMenuItem) {
            // Menu titles are localized; the identifier carries the stable action key.
            let title = sender.identifier?.rawValue ?? sender.title

            if let marker = sender.representedObject as? String, marker == "__OTHER__" {
                openWithPanel()
                return
            }

            if let appURL = sender.representedObject as? URL {
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                
                Task {
                        var allSelectedURLs: [URL] = []

                        for itm in selected {
                            if let fileURL = itm.fileURL {
                                allSelectedURLs.append(fileURL)
                            } else if case .link(let url) = itm.kind {
                                allSelectedURLs.append(url)
                            }
                        }

                        guard !allSelectedURLs.isEmpty else { return }

                        let config = NSWorkspace.OpenConfiguration()

                        let fileURLs = allSelectedURLs.filter { $0.isFileURL }
                        do {
                            if !fileURLs.isEmpty {
                                _ = try await fileURLs.accessSecurityScopedResources { _ in
                                    try await NSWorkspace.shared.open(allSelectedURLs, withApplicationAt: appURL, configuration: config)
                                }
                            } else {
                                try await NSWorkspace.shared.open(allSelectedURLs, withApplicationAt: appURL, configuration: config)
                            }
                        } catch {
                            Logger.log("Failed to open with application: \(error.localizedDescription)", category: .error)
                        }
                }
                return
            }

            switch title {
            case "Quick Look":
                // Handle all selected items for Quick Look, not just the clicked item
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                let urls: [URL] = selected.compactMap { item in
                    if let fileURL = item.fileURL {
                        return fileURL
                    }
                    if case .link(let url) = item.kind {
                        return url
                    }
                    return nil
                }
                if !urls.isEmpty {
                    viewModel.onQuickLookRequest?(urls)
                }

            case "Open":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                for it in selected { ShelfActionService.open(it) }

            case "Share…":
                viewModel.shareItem(from: view)

            case "Rename":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                if selected.count == 1, let single = selected.first { showRenameDialog(for: single) }

            case "Show in Finder":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                Task {
                    let urls = await selected.asyncCompactMap { item -> URL? in
                        if case .file = item.kind {
                            // Use async resolution for user-initiated menu action
                            return await ShelfStateViewModel.shared.resolveAndUpdateBookmarkAsync(for: item)
                        }
                        return nil
                    }
                    if !urls.isEmpty {
                        await urls.accessSecurityScopedResources { accessibleURLs in
                            NSWorkspace.shared.activateFileViewerSelecting(accessibleURLs)
                        }
                    }
                }

            case "Copy Path":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                Task {
                    let paths = await selected.asyncCompactMap { item -> String? in
                        if case .file = item.kind,
                           let url = await ShelfStateViewModel.shared.resolveFileURLAsync(for: item) {
                            return url.path
                        }
                        return nil
                    }
                    if !paths.isEmpty {
                        await MainActor.run {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
                        }
                    }
                }

            case "Copy":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                let changeCount = NSPasteboard.general.changeCount
                let lease = ShelfFileLifetime.shared.acquire(selected.compactMap { $0.resolvedFileURL })
                Task {
                    defer { lease.finish() }
                    var objects: [NSPasteboardWriting] = []
                    var fileURLs: [URL] = []
                    for item in selected {
                        switch item.kind {
                        case .file:
                            if let url = await ShelfStateViewModel.shared.resolveAndUpdateBookmarkAsync(for: item) {
                                objects.append(url as NSURL)
                                fileURLs.append(url)
                            }
                        case .link(let url): objects.append(url as NSURL)
                        case .text(let text): objects.append(text as NSString)
                        }
                    }
                    guard NSPasteboard.general.changeCount == changeCount else { return }
                    guard objects.count == selected.count, ShelfClipboard.shared.write(objects, fileURLs: fileURLs) else {
                        ShelfStateViewModel.shared.report(String(localized: "Some items could not be copied. Check that the files are available."))
                        return
                    }
                }

            case "Remove":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                for it in selected { ShelfActionService.remove(it) }

            case "Compress":
                let selected = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                let fileURLs = selected.compactMap { $0.fileURL }
                guard !fileURLs.isEmpty else { break }

                let lease = ShelfFileLifetime.shared.acquire(fileURLs)
                let generation = ShelfStateViewModel.shared.generation
                Task {
                    defer { lease.finish() }
                    guard let zipTempURL = await TemporaryFileStorageService.shared.createZip(from: fileURLs),
                          let bookmark = try? Bookmark(url: zipTempURL) else {
                        ShelfStateViewModel.shared.report(String(localized: "The archive could not be created. Your files have been kept."))
                        return
                    }
                    let newItem = ShelfItem(kind: .file(bookmark: bookmark.data), isTemporary: true,
                        cachedDisplayName: zipTempURL.lastPathComponent, cachedPath: zipTempURL.standardizedFileURL.path)
                    ShelfStateViewModel.shared.add([newItem], ifUnchanged: generation)
                }
                
            default:
                break
            }
        }

        @MainActor
        private func openWithPanel() {
            // Support both file items and link items
            let targetURL: URL?
            let needsSecurityScope: Bool
            
            if let fileURL = item.fileURL {
                targetURL = fileURL
                needsSecurityScope = true
            } else if case .link(let url) = item.kind {
                targetURL = url
                needsSecurityScope = false
            } else {
                targetURL = nil
                needsSecurityScope = false
            }
            guard let fileURL = targetURL else { return }

            let panel = NSOpenPanel()
            panel.title = "Choose Application"
            panel.message = "Choose an application to open the document \"\(item.displayName)\"."
            panel.prompt = "Open"
            panel.allowsMultipleSelection = false
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.resolvesAliases = true
            if #available(macOS 12.0, *) {
                panel.allowedContentTypes = [.application]
            }
            panel.directoryURL = URL(fileURLWithPath: "/Applications")

            // Compute recommended applications for the selected target
            let recommendedApps: Set<URL> = {
                let apps: [URL]
                if let uti = (try? fileURL.resourceValues(forKeys: [.contentTypeKey]))?.contentType {
                    apps = NSWorkspace.shared.urlsForApplications(toOpen: uti)
                } else {
                    apps = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
                }
                return Set(apps.map { $0.standardizedFileURL })
            }()

            // Delegate to filter entries when in "Recommended Applications" mode
            final class AppChooserDelegate: NSObject, NSOpenSavePanelDelegate {
                enum Mode { case recommended, all }
                var mode: Mode = .recommended
                let recommended: Set<URL>
                init(recommended: Set<URL>) { self.recommended = recommended }
                
                func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
                    let ext = url.pathExtension.lowercased()
                    if ext == "app" {
                        switch mode {
                        case .all:
                            return true
                        case .recommended:
                            // Standardize URLs for reliable comparison
                            let std = url.standardizedFileURL
                            return recommended.contains(std)
                        }
                    }

                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                        return true
                    }
                    
                    return false
                }
            }

            let chooserDelegate = AppChooserDelegate(recommended: recommendedApps)
            panel.delegate = chooserDelegate

            let enableLabel = NSTextField(labelWithString: "Enable:")
            enableLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
            enableLabel.alignment = .natural
            enableLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItems(withTitles: ["Recommended Applications", "All Applications"])
            popup.font = .systemFont(ofSize: NSFont.systemFontSize)
            popup.selectItem(at: 0)
            
            popup.setContentHuggingPriority(.defaultLow, for: .horizontal)
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

            let row = NSStackView(views: [enableLabel, popup])
            row.orientation = .horizontal
            row.spacing = 8
            row.alignment = .centerY
            row.distribution = .fill
            
            // No "Always Open With" here: that rewrote the system-wide default
            // app for the file type, far outside what a shelf action should touch.
            let column = NSStackView(views: [row])
            column.orientation = .vertical
            column.spacing = 12
            column.alignment = .centerX
            column.distribution = .fill
            column.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
            
            panel.accessoryView = column
            panel.isAccessoryViewDisclosed = true

            // Wire up popup to switch filter mode
            class PopupBinder: NSObject {
                weak var popup: NSPopUpButton?
                weak var chooserDelegate: AppChooserDelegate?
                weak var panel: NSOpenPanel?
                init(popup: NSPopUpButton, chooserDelegate: AppChooserDelegate, panel: NSOpenPanel) {
                    self.popup = popup
                    self.chooserDelegate = chooserDelegate
                    self.panel = panel
                }
                @objc func changed(_ sender: Any?) {
                    if popup?.indexOfSelectedItem == 1 {
                        chooserDelegate?.mode = .all
                    } else {
                        chooserDelegate?.mode = .recommended
                    }
                    if let panel = panel {
                        panel.validateVisibleColumns()
                        let currentDir = panel.directoryURL
                        panel.directoryURL = currentDir
                    }
                }
            }
            let binder = PopupBinder(popup: popup, chooserDelegate: chooserDelegate, panel: panel)
            popup.target = binder
            popup.action = #selector(PopupBinder.changed(_:))

            panel.begin { response in
                if response == .OK, let appURL = panel.url {
                    Task {
                        do {
                            let config = NSWorkspace.OpenConfiguration()
                            if needsSecurityScope {
                                _ = try await fileURL.accessSecurityScopedResource { accessibleURL in
                                    try await NSWorkspace.shared.open([accessibleURL], withApplicationAt: appURL, configuration: config)
                                }
                            } else {
                                try await NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config)
                            }
                        } catch {
                            Logger.log("Failed to open with application: \(error.localizedDescription)", category: .error)
                        }
                    }
                }
                // Keep binder/delegate alive until panel finishes
                _ = binder
                _ = chooserDelegate
            }
        }
        
        /// Asks for a new name and renames the file in place.
        @MainActor
        private func showRenameDialog(for item: ShelfItem) {
            guard let fileURL = item.fileURL else { return }
            let currentName = fileURL.lastPathComponent

            let alert = NSAlert()
            alert.messageText = String(localized: "Rename")
            alert.addButton(withTitle: String(localized: "Rename"))
            alert.addButton(withTitle: String(localized: "Cancel"))

            let field = NSTextField(string: currentName)
            field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            // Select the name without its extension, as Finder does. Scheduled
            // into the modal loop because showing the alert selects the whole
            // field; if it does not take, all of it stays selected.
            let stemLength = ((currentName as NSString).deletingPathExtension as NSString).length
            RunLoop.main.perform(inModes: [.modalPanel]) {
                field.currentEditor()?.selectedRange = NSRange(location: 0, length: stemLength)
            }

            // Atoll is rarely the active app while the notch is in use; without
            // this the alert can open behind the window the user is looking at.
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }

            let name = field.stringValue
            Task { @MainActor in
                do { try await ShelfActionService.rename(item, to: name) }
                catch { showErrorAlert(title: String(localized: "Couldn't Rename"), message: error.localizedDescription) }
            }
        }

        @MainActor
        private func showErrorAlert(title: String, message: String) {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()
        }
    }

    // MARK: - Private helpers
    private func appDisplayName(for appURL: URL) -> String {
        (try? appURL.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? appURL.lastPathComponent
    }

    private func nsAppIcon(for appURL: URL, size: CGFloat) -> NSImage? {
        let baseIcon = NSWorkspace.shared.icon(forFile: appURL.path)
        baseIcon.isTemplate = false

        let targetSize = NSSize(width: size, height: size)
        let rendered = NSImage(size: targetSize, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            baseIcon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: [
                .interpolation: NSImageInterpolation.high.rawValue
            ])
            return true
        }

        rendered.size = targetSize
        return rendered
    }

    private func defaultAppURL() -> URL? {
        if let fileURL = item.fileURL {
            return NSWorkspace.shared.urlForApplication(toOpen: fileURL)
        } else if case .link(let url) = item.kind {
            return NSWorkspace.shared.urlForApplication(toOpen: url)
        }
        return nil
    }
}

fileprivate extension Sequence {
    func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var result: [T] = []
        for element in self {
            if let transformed = await transform(element) {
                result.append(transformed)
            }
        }
        return result
    }
}
