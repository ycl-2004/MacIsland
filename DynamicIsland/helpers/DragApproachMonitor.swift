import AppKit

/// Opens the notch while a file drag is still just below it. A drag aimed at a
/// closed notch tends to push into the top edge, where macOS opens Mission
/// Control's Spaces bar instead, and no system setting turns that off for files.
///
/// Finder's drag session keeps mouse-dragged events from event monitors, so a
/// press elsewhere starts a short poll that ends with the press. Nothing runs
/// while the mouse button is up.
@MainActor
final class DragApproachMonitor {
    /// How far beside and below the closed notch a file drag opens it.
    static let reach = CGSize(width: 60, height: 48)
    static let pollInterval: TimeInterval = 1.0 / 30

    private let pasteboard: NSPasteboard
    private let isPressed: () -> Bool
    private let pointerIsNear: () -> Bool
    private let onApproach: () -> Void
    private var pressMonitor: Any?
    private var poll: Timer?
    private var changeCountAtPress = 0

    var isPolling: Bool { poll != nil }

    init(pasteboard: NSPasteboard = NSPasteboard(name: .drag),
         isPressed: @escaping () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 },
         pointerIsNear: @escaping () -> Bool,
         onApproach: @escaping () -> Void) {
        self.pasteboard = pasteboard
        self.isPressed = isPressed
        self.pointerIsNear = pointerIsNear
        self.onApproach = onApproach
    }

    func start() {
        guard pressMonitor == nil else { return }
        pressMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.pressBegan() }
        }
    }

    func stop() {
        if let pressMonitor { NSEvent.removeMonitor(pressMonitor) }
        pressMonitor = nil
        endPoll()
    }

    /// A drag writes the drag pasteboard as it starts, so a count unchanged
    /// since the press means whatever is there belongs to an earlier drag.
    func pressBegan() {
        changeCountAtPress = pasteboard.changeCount
        guard poll == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    /// Cheap checks first: the pasteboard is only read near the notch.
    func check() {
        guard isPolling else { return }
        guard isPressed() else { return endPoll() }
        guard pointerIsNear(), pasteboard.changeCount != changeCountAtPress,
              pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        else { return }
        endPoll()
        onApproach()
    }

    private func endPoll() {
        poll?.invalidate()
        poll = nil
    }
}
