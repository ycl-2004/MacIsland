import Foundation

/// A settings transaction, never a content backup. Removing an entry on a
/// subsequent manual edit prevents Undo from undoing the user's later choice.
struct FeaturePresetChange: Codable, Equatable, Identifiable {
    let id: String
    let before: Bool
    let applied: Bool
}

struct FeaturePresetSnapshot: Codable, Equatable {
    var changes: [FeaturePresetChange]

    mutating func userChanged(_ key: String) {
        changes.removeAll { $0.id == key }
    }

    func restorable(current: (String) -> Bool) -> [FeaturePresetChange] {
        changes.filter { current($0.id) == $0.applied }
    }
}
