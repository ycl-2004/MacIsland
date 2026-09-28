import AppKit

@main
struct SwipeTrackerRegression {
    typealias Step = SwipeTracker.Step

    static func main() {
        let none: NSEvent.Phase = []

        // A flick: a short touch, then momentum carries it past the notch's open
        // threshold (200). Momentum counts, and the swipe ends only once, at the
        // end of the momentum.
        var flick = SwipeTracker(threshold: 4)
        precondition(flick.handle(phase: .began, momentumPhase: none, signedDelta: 2, isOverNotch: true) == [.cancelEnd])
        precondition(flick.handle(phase: .changed, momentumPhase: none, signedDelta: 60, isOverNotch: true) == [.report(62, .began)])
        precondition(flick.handle(phase: .ended, momentumPhase: none, signedDelta: 0, isOverNotch: true) == [.endAfter(SwipeTracker.momentumGrace)])
        precondition(flick.handle(phase: none, momentumPhase: .began, signedDelta: 90, isOverNotch: true) == [.cancelEnd, .report(152, .changed)])
        precondition(flick.handle(phase: none, momentumPhase: .changed, signedDelta: 80, isOverNotch: true) == [.cancelEnd, .report(232, .changed)])
        precondition(flick.handle(phase: none, momentumPhase: .ended, signedDelta: 0, isOverNotch: true) == [.report(232, .ended)])
        precondition(flick.end() == nil, "a finished swipe must not end twice")

        // One swipe reports .began once, however long it runs.
        var long = SwipeTracker(threshold: 4)
        _ = long.handle(phase: .began, momentumPhase: none, signedDelta: 0, isOverNotch: true)
        precondition(long.handle(phase: .changed, momentumPhase: none, signedDelta: 250, isOverNotch: true) == [.report(250, .began)])
        precondition(long.handle(phase: none, momentumPhase: .began, signedDelta: 300, isOverNotch: true) == [.cancelEnd, .report(550, .changed)])

        // A new touch during momentum ends the old swipe and starts a fresh one.
        precondition(long.handle(phase: .began, momentumPhase: none, signedDelta: 1, isOverNotch: true) == [.report(550, .ended), .cancelEnd])
        precondition(long.translation == 1 && !long.isActive && long.isTracking, "the new touch counts from its own first delta")

        // Lifting the fingers with no momentum: the delayed end reports it.
        var slow = SwipeTracker(threshold: 4)
        _ = slow.handle(phase: .began, momentumPhase: none, signedDelta: 10, isOverNotch: true)
        precondition(slow.handle(phase: .ended, momentumPhase: none, signedDelta: 0, isOverNotch: true) == [.endAfter(SwipeTracker.momentumGrace)])
        precondition(slow.end() == .report(10, .ended))

        // Scrolling anywhere else on screen never reaches the handlers, endings included.
        var elsewhere = SwipeTracker(threshold: 4)
        precondition(elsewhere.handle(phase: .began, momentumPhase: none, signedDelta: 50, isOverNotch: false) == [])
        precondition(elsewhere.handle(phase: .ended, momentumPhase: none, signedDelta: 0, isOverNotch: false) == [])
        precondition(elsewhere.handle(phase: none, momentumPhase: .ended, signedDelta: 0, isOverNotch: false) == [])
        precondition(elsewhere.end() == nil)

        // A swipe that started over the notch still ends if the pointer has left.
        var left = SwipeTracker(threshold: 4)
        _ = left.handle(phase: .began, momentumPhase: none, signedDelta: 30, isOverNotch: true)
        precondition(left.handle(phase: none, momentumPhase: .ended, signedDelta: 0, isOverNotch: false) == [.report(30, .ended)])

        // Moving back the other way starts the count again; noise is ignored.
        var back = SwipeTracker(threshold: 4)
        _ = back.handle(phase: .began, momentumPhase: none, signedDelta: 3, isOverNotch: true)
        _ = back.handle(phase: .changed, momentumPhase: none, signedDelta: -5, isOverNotch: true)
        precondition(back.translation == 0)
        precondition(back.handle(phase: .changed, momentumPhase: none, signedDelta: 0.1, isOverNotch: true) == [])
        precondition(back.translation == 0)

        // A mouse wheel has no phases: each notch rearms the idle end.
        var wheel = SwipeTracker(threshold: 4)
        precondition(wheel.handle(phase: none, momentumPhase: none, signedDelta: 10, isOverNotch: true) == [.endAfter(SwipeTracker.wheelIdle), .report(10, .began)])
        precondition(wheel.handle(phase: none, momentumPhase: none, signedDelta: 10, isOverNotch: true) == [.endAfter(SwipeTracker.wheelIdle), .report(20, .changed)])
        precondition(wheel.end() == .report(20, .ended))

        print("SwipeTrackerRegression passed")
    }
}
