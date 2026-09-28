import Foundation

@main
struct TimerCountdownRegression {
    static func main() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

        var countdown = TimerCountdown(duration: 300, startingAt: start)

        // Rounded up while counting down: a full second shows until it has passed.
        precondition(countdown.displayedSeconds(at: at(0)) == 300)
        precondition(countdown.displayedSeconds(at: at(0.5)) == 300)
        precondition(countdown.displayedSeconds(at: at(1)) == 299)
        precondition(countdown.displayedSeconds(at: at(299.2)) == 1)

        // 0:00 exactly when time is up, then whole seconds of overtime.
        precondition(countdown.displayedSeconds(at: at(300)) == 0)
        precondition(countdown.displayedSeconds(at: at(300.5)) == 0)
        precondition(countdown.displayedSeconds(at: at(301)) == -1)

        // No ticks for 1000 s (the Mac asleep): still measured from the end date.
        precondition(countdown.displayedSeconds(at: at(1_000)) == -700)

        // A pause keeps the exact time left, however long it lasts.
        countdown.pause(at: at(10.4))
        precondition(abs(countdown.timeLeft(at: at(500)) - 289.6) < 0.0001)
        precondition(countdown.displayedSeconds(at: at(500)) == 290)
        countdown.pause(at: at(510))
        precondition(abs(countdown.timeLeft(at: at(510)) - 289.6) < 0.0001)

        countdown.resume(at: at(600))
        precondition(countdown.displayedSeconds(at: at(600 + 289.5)) == 1)
        precondition(countdown.displayedSeconds(at: at(600 + 289.6)) == 0)
        countdown.resume(at: at(700))
        precondition(countdown.displayedSeconds(at: at(600 + 289.6)) == 0)
    }
}
