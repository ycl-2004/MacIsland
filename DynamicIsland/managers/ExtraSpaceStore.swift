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
    private var pendingSave: Task<Void, Never>?
    private var revision = 0
    private var enqueuedRevision: Int?
    private let writer = Writer()
    private struct SaveSnapshot { let text: String; let revision: Int }
    private struct SaveResult { let revision: Int; let failure: String?; let hasPrevious: Bool }
    private lazy var snapshotWriter = LatestSnapshotWriter<SaveSnapshot, SaveResult>(
        queue: persistenceQueue,
        write: { [writer, fileURL] snapshot in
            let failure = writer.write(snapshot.text, revision: snapshot.revision, to: fileURL)
            return SaveResult(revision: snapshot.revision, failure: failure, hasPrevious: writer.hasPrevious)
        },
        didWrite: { [weak self] result in
            DispatchQueue.main.async {
                self?.didSave(revision: result.revision, failure: result.failure, hasPrevious: result.hasPrevious)
            }
        })
    @Published private(set) var byteCount = 0
    @Published private(set) var hasPreviousVersion = false

    init(fileURL: URL? = nil, saveDelay: TimeInterval = 0.5) {
        self.fileURL = fileURL ?? AppRuntimeEnvironment.contentURL(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Atoll/ExtraSpace/content.txt"),
            testPath: "ExtraSpace/content.txt")
        self.saveDelay = saveDelay
        load()
        // Quit/restart saving belongs to AppTerminationCoordinator, before
        // AppKit commits to termination. A willTerminate observer cannot cancel.
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
        let delay = saveDelay
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self else { return }
            self.pendingSave = nil
            self.saveNow()
        }
    }

    /// Leaving the tab or disabling the feature saves immediately, without
    /// clearing the document or making the UI wait for disk access.
    func saveNow() {
        guard isLoaded, isDirty, enqueuedRevision != revision else { return }
        enqueuedRevision = revision
        pendingSave?.cancel()
        pendingSave = nil
        snapshotWriter.submit(SaveSnapshot(text: text, revision: revision))
    }

    func flushPendingSave() {
        guard isLoaded, isDirty else { return }
        saveNow()
        guard let result = snapshotWriter.flushSynchronously() else { return }
        didSave(revision: result.revision, failure: result.failure, hasPrevious: result.hasPrevious)
    }

    /// Queue a barrier after the initial read and its main-queue publication.
    /// A lazily-created store must not look like a user edit during Quit.
    func awaitInitialLoad() async {
        await withCheckedContinuation { continuation in
            persistenceQueue.async {
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    func saveForTermination() async -> String? {
        if !isLoaded { await awaitInitialLoad() }
        guard isLoaded, isDirty else { return nil }
        saveNow()
        guard let result = await snapshotWriter.flush() else { return nil }
        didSave(revision: result.revision, failure: result.failure, hasPrevious: result.hasPrevious)
        return result.failure ?? (isDirty ? "Text changed while saving. Please try again." : nil)
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
        snapshotWriter.discardPending()
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
