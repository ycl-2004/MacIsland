import Foundation

@main
struct TimerSoundStoreRegression {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("timer-sound-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }
        let picked = root.appendingPathComponent("Downloads", isDirectory: true)
        try fileManager.createDirectory(at: picked, withIntermediateDirectories: true)
        let store = TimerSoundStore(directory: root.appendingPathComponent("TimerSounds", isDirectory: true))

        func kept() -> [String] {
            ((try? fileManager.contentsOfDirectory(atPath: store.directory.path)) ?? []).sorted()
        }

        // Nothing chosen, and a choice whose file has gone.
        precondition(store.selection(forSavedPath: nil) == .bundled)
        precondition(store.selection(forSavedPath: "") == .bundled)
        let gone = picked.appendingPathComponent("一半一半_.mp3").path
        precondition(store.selection(forSavedPath: gone) == .missing(fileName: "一半一半_.mp3"))
        precondition(store.playableURL(forSavedPath: gone) == TimerSoundStore.bundledSoundURL)

        // A chosen file is copied in; deleting the original changes nothing.
        let first = picked.appendingPathComponent("一半一半.mp3")
        try Data("first".utf8).write(to: first)
        let firstCopy = try store.importSound(from: first)
        precondition(firstCopy == store.directory.appendingPathComponent("一半一半.mp3"))
        try fileManager.removeItem(at: first)
        precondition(store.selection(forSavedPath: firstCopy.path) == .custom(firstCopy))
        precondition(store.playableURL(forSavedPath: firstCopy.path) == firstCopy)
        let copied = try Data(contentsOf: firstCopy)
        precondition(copied == Data("first".utf8))

        // Choosing the kept copy again leaves it as it is.
        let reimported = try store.importSound(from: firstCopy)
        precondition(reimported == firstCopy)
        precondition(kept() == ["一半一半.mp3"])

        // A new choice replaces the old one and leaves no staging file.
        let second = picked.appendingPathComponent("bell.m4a")
        try Data("second".utf8).write(to: second)
        let secondCopy = try store.importSound(from: second)
        precondition(kept() == ["bell.m4a"])

        // A failed import keeps the current sound.
        var failed = false
        do { _ = try store.importSound(from: picked.appendingPathComponent("nope.mp3")) } catch { failed = true }
        precondition(failed)
        precondition(kept() == ["bell.m4a"])
        precondition(store.selection(forSavedPath: secondCopy.path) == .custom(secondCopy))

        store.removeImportedSounds()
        precondition(kept().isEmpty)
    }
}
