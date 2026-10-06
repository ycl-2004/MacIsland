import AppKit
import Combine

/// One local scratchpad. Only its own tab observes text changes; persistence
/// runs on a serial queue so an older save cannot overwrite a newer snapshot.
@MainActor
final class ExtraSpaceStore: ObservableObject {
    static let shared = ExtraSpaceStore()
    nonisolated static let maximumBytes = 5 * 1024 * 1024

    @Published private(set) var text = ""
    @Published private(set) var isLoaded = false
    @Published private(set) var isDirty = false
    @Published var isRelaunching = false
    @Published private(set) var errorMessage: String?

    let fileURL: URL
    private let saveDelay: TimeInterval
    private let persistenceQueue = DispatchQueue(label: "app.atoll.extra-space.persistence", qos: .utility)
    private var pendingSave: DispatchWorkItem?
    private var revision = 0
    private var enqueuedRevision: Int?
    private let writer = Writer()
    @Published private(set) var byteCount = 0
    @Published private(set) var hasPreviousVersion = false
    private var terminationObserver: NSObjectProtocol?

    init(fileURL: URL? = nil, saveDelay: TimeInterval = 0.5) {
        self.fileURL = fileURL ?? AppRuntimeEnvironment.contentURL(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Atoll/ExtraSpace/content.txt"),
            testPath: "ExtraSpace/content.txt")
        self.saveDelay = saveDelay
        load()
        // Final cleanup must finish before AppKit exits; ordinary saves remain
        // asynchronous. https://developer.apple.com/documentation/appkit/nsapplication/willterminatenotification
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushPendingSave() }
        }
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    func updateText(_ newText: String) {
        guard isLoaded, !isRelaunching, text != newText else { return }
        guard newText.utf8.count <= Self.maximumBytes else {
            errorMessage = "Extra Space holds up to 5 MB of text. This change was not applied."
            return
        }
        text = newText
        byteCount = newText.utf8.count
        revision += 1
        if !isDirty { isDirty = true }
        pendingSave?.cancel()
        let snapshot = newText
        let snapshotRevision = revision
        let url = fileURL
        let writer = writer
        let work = DispatchWorkItem { [weak self] in
            let failure = writer.write(snapshot, revision: snapshotRevision, to: url)
            let previous = writer.hasPrevious
            DispatchQueue.main.async {
                self?.didSave(revision: snapshotRevision, failure: failure, hasPrevious: previous)
            }
        }
        pendingSave = work
        persistenceQueue.asyncAfter(deadline: .now() + saveDelay, execute: work)
    }

    /// Leaving the tab or disabling the feature saves immediately, without
    /// clearing the document or making the UI wait for disk access.
    func saveNow() {
        guard isLoaded, isDirty, enqueuedRevision != revision else { return }
        enqueuedRevision = revision
        pendingSave?.cancel()
        pendingSave = nil
        let snapshot = text
        let snapshotRevision = revision
        let url = fileURL
        let writer = writer
        persistenceQueue.async { [weak self] in
            let failure = writer.write(snapshot, revision: snapshotRevision, to: url)
            let previous = writer.hasPrevious
            DispatchQueue.main.async {
                self?.didSave(revision: snapshotRevision, failure: failure, hasPrevious: previous)
            }
        }
    }

    func flushPendingSave() {
        guard isLoaded, isDirty else { return }
        pendingSave?.cancel()
        pendingSave = nil
        let snapshot = text
        let url = fileURL
        let snapshotRevision = revision
        let writer = writer
        let result = persistenceQueue.sync { (writer.write(snapshot, revision: snapshotRevision, to: url), writer.hasPrevious) }
        didSave(revision: revision, failure: result.0, hasPrevious: result.1)
    }

    func retry() {
        if isLoaded { saveNow() } else { load() }
    }

    private func load() {
        let url = fileURL
        errorMessage = nil
        persistenceQueue.async { [weak self] in
            let result: Result<String, Error>
            do {
                let data = try PrivateContentFile.read(url, limit: Self.maximumBytes)
                guard let content = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
                result = .success(content)
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                result = .success("")
            } catch {
                result = .failure(error)
            }
            let previous = FileManager.default.fileExists(atPath: PrivateContentFile.backupURL(url).path)
            DispatchQueue.main.async {
                guard let self else { return }
                self.hasPreviousVersion = previous
                switch result {
                case .success(let content):
                    self.text = content
                    self.byteCount = content.utf8.count
                    self.isLoaded = true
                case .failure(let error):
                    // Do not replace an unreadable document with an empty one.
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func didSave(revision savedRevision: Int, failure: String?, hasPrevious: Bool) {
        if enqueuedRevision == savedRevision { enqueuedRevision = nil }
        guard savedRevision == revision else { return }
        errorMessage = failure
        if failure == nil { isDirty = false; hasPreviousVersion = hasPrevious }
    }

    func reportSizeLimit() { errorMessage = "Extra Space holds up to 5 MB of text. This change was not applied." }

    func revealContent() { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }

    /// Explicit recovery; a bad primary is kept separately before replacement.
    func recoverPrevious() {
        guard !isRelaunching else { return }
        pendingSave?.cancel(); pendingSave = nil
        enqueuedRevision = nil
        let url = fileURL
        persistenceQueue.async { [weak self] in
            let result: Result<String, Error> = Result {
                let data = try PrivateContentFile.read(PrivateContentFile.backupURL(url), limit: Self.maximumBytes)
                guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
                if FileManager.default.fileExists(atPath: url.path) {
                    let recovery = url.appendingPathExtension("recovery")
                    guard !FileManager.default.fileExists(atPath: recovery.path) else { throw CocoaError(.fileWriteFileExists) }
                    try FileManager.default.moveItem(at: url, to: recovery)
                }
                return text
            }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let content):
                    self.isLoaded = true
                    self.text = content
                    self.byteCount = content.utf8.count
                    self.revision += 1
                    self.isDirty = true
                    self.saveNow()
                case .failure(let error): self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Accessed exclusively on persistenceQueue. Repeated Save, tab teardown
    /// and termination barriers reuse an already written revision.
    private final class Writer: @unchecked Sendable {
        var savedRevision: Int?
        var hasPrevious = false
        func write(_ text: String, revision: Int, to url: URL) -> String? {
            guard savedRevision != revision else { return nil }
            do {
                try PrivateContentFile.write(Data(text.utf8), to: url)
                savedRevision = revision
                hasPrevious = FileManager.default.fileExists(atPath: PrivateContentFile.backupURL(url).path)
                return nil
            } catch { return error.localizedDescription }
        }
    }
}
