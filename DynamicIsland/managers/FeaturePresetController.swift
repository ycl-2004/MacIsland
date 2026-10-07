import Combine
import Defaults
import Foundation

@MainActor
final class FeaturePresetController: ObservableObject {
    static let shared = FeaturePresetController()
    private static let snapshotKey = "atoll.lightweightPreset.undo.v1"
    // Shelf is intentionally absent: disabling it removes tray contents.
    static let candidates: [(String, Defaults.Key<Bool>)] = [
        ("Stats", .enableStatsFeature), ("Real-time waveform", .enableRealTimeWaveform),
        ("Lyrics", .enableLyrics), ("Camera mirror", .showMirror),
        ("Lock screen weather", .enableLockScreenWeatherWidget)
    ]
    @Published private(set) var snapshot: FeaturePresetSnapshot?
    private let managedCandidates: [(String, Defaults.Key<Bool>)]
    private let defaults: UserDefaults
    private var writing = false
    private var subscriptions = Set<AnyCancellable>()

    init(defaults: UserDefaults = .standard, candidates: [(String, Defaults.Key<Bool>)]? = nil) {
        self.defaults = defaults
        self.managedCandidates = candidates ?? Self.candidates
        if let data = defaults.data(forKey: Self.snapshotKey), data.count <= 8192,
           let saved = try? JSONDecoder().decode(FeaturePresetSnapshot.self, from: data) {
            let allowed = Set(self.managedCandidates.map { $0.1.name })
            snapshot = FeaturePresetSnapshot(changes: saved.changes.filter { allowed.contains($0.id) })
        }
        for (_, key) in self.managedCandidates {
            Defaults.publisher(key, options: []).sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.writing, self.snapshot != nil else { return }
                    self.snapshot?.userChanged(key.name)
                    self.persist()
                }
            }.store(in: &subscriptions)
        }
    }

    var preview: [FeaturePresetChange] {
        managedCandidates.compactMap { _, key in
            Defaults[key] ? FeaturePresetChange(id: key.name, before: true, applied: false) : nil
        }
    }

    func title(for id: String) -> String {
        managedCandidates.first { $0.1.name == id }?.0 ?? id
    }

    /// Apply the reviewed diff only if it still matches. If settings changed
    /// while the preview was open, refresh the preview instead of applying it.
    func apply(_ reviewed: [FeaturePresetChange]) -> Bool {
        guard reviewed == preview else { return false }
        writing = true
        defer { writing = false }
        snapshot = FeaturePresetSnapshot(changes: reviewed)
        for change in reviewed {
            if let key = managedCandidates.first(where: { $0.1.name == change.id })?.1 { Defaults[key] = change.applied }
        }
        persist()
        return true
    }

    func restore() {
        guard let snapshot else { return }
        writing = true
        defer { writing = false }
        for change in snapshot.restorable(current: { id in
            managedCandidates.first { $0.1.name == id }.map { Defaults[$0.1] } ?? true
        }) {
            if let key = managedCandidates.first(where: { $0.1.name == change.id })?.1 { Defaults[key] = change.before }
        }
        self.snapshot = nil
        persist()
    }

    private func persist() {
        if let snapshot, !snapshot.changes.isEmpty {
            defaults.set(try? JSONEncoder().encode(snapshot), forKey: Self.snapshotKey)
        } else {
            snapshot = nil
            defaults.removeObject(forKey: Self.snapshotKey)
        }
    }
}
