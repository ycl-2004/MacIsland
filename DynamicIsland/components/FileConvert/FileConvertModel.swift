import AppKit
import Defaults
import UniformTypeIdentifiers

/// The notch tab's state: dropped files, the formats they share, and each
/// file's result. Conversions run one file at a time.
@MainActor
final class FileConvertModel: ObservableObject {
    static let shared = FileConvertModel()
    static let maximumFiles = 20

    enum Status: Equatable {
        case ready
        case converting
        case converted([URL])
        case failed(String)
    }

    struct Item: Identifiable {
        let id = UUID()
        let url: URL
        let icon: NSImage
        var status: Status = .ready
        /// What happened to the original, when that differs from the setting's promise.
        var note: String?
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var formats: [ConversionFormat] = []
    @Published private(set) var isWorking = false
    @Published private(set) var message: String?

    private let service: FileConversionService
    private let enabledKey: Defaults.Key<Bool>
    private let keepOriginalKey: Defaults.Key<Bool>
    private var task: Task<Void, Never>?
    /// A cleared or replaced list must not receive a cancelled run's late results.
    private var generation = UUID()

    init(service: FileConversionService = FileConversionService(),
         enabledKey: Defaults.Key<Bool> = .enableFileConvertFeature,
         keepOriginalKey: Defaults.Key<Bool> = .fileConvertKeepOriginal) {
        self.service = service
        self.enabledKey = enabledKey
        self.keepOriginalKey = keepOriginalKey
    }

    var hasResults: Bool { items.contains { if case .converted = $0.status { return true } else { return false } } }

    /// Accepts file drags only. The URLs arrive asynchronously; returning true
    /// tells the system the drop was taken.
    func receive(_ providers: [NSItemProvider]) -> Bool {
        guard Defaults[enabledKey], !isWorking else { return false }
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty else { return false }
        guard files.count <= Self.maximumFiles else {
            message = String(localized: "Drop up to \(Self.maximumFiles) files at a time.")
            return false
        }
        let generation = restart()
        isWorking = true
        task = Task { [weak self] in
            var urls: [URL] = []
            for provider in files {
                if let url = await provider.extractFileURL() { urls.append(url) }
            }
            guard let self, self.generation == generation else { return }
            self.isWorking = false
            self.load(urls)
        }
        return true
    }

    /// Replaces the list. Folders are skipped: only their files can be converted.
    func load(_ urls: [URL]) {
        let files = urls.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        items = files.map { Item(url: $0, icon: NSWorkspace.shared.icon(forFile: $0.path)) }
        formats = service.formats(for: files)
        if files.count < urls.count {
            message = String(localized: "Folders can’t be converted. Drop the files inside instead.")
        } else if !files.isEmpty && formats.isEmpty {
            message = files.count == 1
                ? String(localized: "There’s no conversion for this kind of file.")
                : String(localized: "These files have no format in common. Drop files of one kind.")
        } else {
            message = nil
        }
    }

    func convert(to format: ConversionFormat) {
        guard !isWorking, formats.contains(format) else { return }
        let keepOriginal = Defaults[keepOriginalKey]
        let generation = self.generation
        isWorking = true
        message = nil
        task = Task { [weak self] in
            guard let self else { return }
            for id in self.items.map(\.id) {
                guard !Task.isCancelled, self.generation == generation,
                      let url = self.items.first(where: { $0.id == id })?.url else { break }
                self.update(id) { $0.status = .converting; $0.note = nil }
                do {
                    let outcome = try await self.service.convert(url, to: format, keepOriginal: keepOriginal)
                    guard self.generation == generation else { return }
                    self.update(id) {
                        $0.status = .converted(outcome.outputs)
                        if outcome.originalTrashed { $0.note = String(localized: "Original moved to the Trash") }
                        if outcome.trashFailure != nil { $0.note = String(localized: "Original kept: it couldn’t be moved to the Trash") }
                    }
                } catch {
                    guard self.generation == generation else { return }
                    let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.update(id) { $0.status = .failed(reason) }
                }
            }
            guard self.generation == generation else { return }
            self.isWorking = false
            // Trashed originals can't be converted again; kept ones can.
            if !keepOriginal { self.formats = [] }
        }
    }

    func cancel() { task?.cancel() }

    func clear() {
        restart()
        items = []
        formats = []
        message = nil
    }

    func revealResults() {
        let outputs = items.flatMap { item -> [URL] in
            if case .converted(let urls) = item.status { return urls } else { return [] }
        }
        guard !outputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(outputs)
    }

    /// Quit waits for a running engine to stop so no child process outlives the app.
    func stopForTermination() async {
        let running = task
        restart()
        await running?.value
    }

    @discardableResult
    private func restart() -> UUID {
        task?.cancel()
        task = nil
        isWorking = false
        generation = UUID()
        return generation
    }

    private func update(_ id: UUID, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }
}
