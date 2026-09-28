import Foundation

@main
struct SavedRowOrderRegression {
    static func main() {
        let identity: (String) -> String = { $0 }

        // Nothing saved: the default order stands.
        precondition(SavedRowOrder.apply([], to: ["home", "stats", "agents"], key: identity) == ["home", "stats", "agents"])

        // A saved order rearranges; items it has never seen follow in default order.
        precondition(SavedRowOrder.apply(["agents", "home"], to: ["home", "shelf", "stats", "agents"], key: identity)
            == ["agents", "home", "shelf", "stats"])

        // Saved keys for items that are not shown are ignored.
        precondition(SavedRowOrder.apply(["timer", "stats", "home"], to: ["home", "stats"], key: identity) == ["stats", "home"])

        // First drag with nothing saved: the visible order becomes the saved order.
        precondition(SavedRowOrder.merging(["stats", "home", "agents"], into: []) == ["stats", "home", "agents"])

        // A hidden item keeps its slot while the visible ones are rearranged around it...
        let saved = ["home", "timer", "stats", "agents"]
        let merged = SavedRowOrder.merging(["agents", "stats", "home"], into: saved)
        precondition(merged == ["agents", "timer", "stats", "home"])

        // ...and comes back to that slot when it is shown again.
        precondition(SavedRowOrder.apply(merged, to: ["home", "timer", "stats", "agents"], key: identity)
            == ["agents", "timer", "stats", "home"])

        // A newly visible item joins the saved order at the end.
        precondition(SavedRowOrder.merging(["shelf", "home"], into: ["home"]) == ["shelf", "home"])

        print("SavedRowOrderRegression passed")
    }
}
