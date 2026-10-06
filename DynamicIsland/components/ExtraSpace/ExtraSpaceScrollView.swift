import AppKit

/// Editing scrolls text; reading reserves the notch's close direction for closing.
final class ExtraSpaceScrollView: NSScrollView {
    var isEditing = true
    var closeDirection: PanDirection?
    var closeSensitivity: CGFloat = 200
    var onSaveAndClose: (() -> Void)?
    private var swipe = SwipeTracker(threshold: 4)
    private var pendingEnd: DispatchWorkItem?
    private var didClose = false

    override func scrollWheel(with event: NSEvent) {
        guard !isEditing, let direction = closeDirection else {
            resetSwipe()
            super.scrollWheel(with: event)
            return
        }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) { resetSwipe() }
        let delta = direction.signed(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
        let steps = swipe.handle(phase: event.phase, momentumPhase: event.momentumPhase, signedDelta: delta, isOverNotch: true)
        for step in steps {
            switch step {
            case let .report(translation, _):
                if translation > closeSensitivity && !didClose {
                    didClose = true
                    onSaveAndClose?()
                }
            case let .endAfter(delay):
                pendingEnd?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.resetSwipe() }
                pendingEnd = work
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            case .cancelEnd:
                pendingEnd?.cancel()
                pendingEnd = nil
            }
        }
        // Consume the close swipe rather than moving the text underneath it.
        if delta > 0 || swipe.isActive || didClose { return }
        super.scrollWheel(with: event)
    }

    private func resetSwipe() {
        pendingEnd?.cancel()
        pendingEnd = nil
        swipe = SwipeTracker(threshold: 4)
        didClose = false
    }

    deinit { pendingEnd?.cancel() }
}
