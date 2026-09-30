import AppKit
import Defaults
import SwiftUI
import XCTest
@testable import Atoll

@MainActor
final class TimerHUDTests: XCTestCase {
    func testRestartResetsRunningPausedAndOvertimeTimers() {
        let timer = TimerManager.shared
        let preset = Defaults[.timerPresets].first
        defer { timer.forceStopTimer() }

        for state in ["running", "paused", "overtime"] {
            timer.startTimer(duration: 3661, name: "Focus", preset: preset)
            let oldSession = timer.activeSessionID
            timer.remainingTime = 42
            timer.elapsedTime = 3619
            if state == "paused" { timer.pauseTimer() }
            if state == "overtime" {
                timer.remainingTime = -9
                timer.isFinished = true
                timer.isOvertime = true
            }

            XCTAssertTrue(timer.canRestart, state)
            timer.restartTimer()

            XCTAssertEqual(timer.remainingTime, 3661, state)
            XCTAssertEqual(timer.totalDuration, 3661, state)
            XCTAssertEqual(timer.elapsedTime, 0, state)
            XCTAssertEqual(timer.timerName, "Focus", state)
            XCTAssertEqual(timer.activePresetId, preset?.id, state)
            XCTAssertNotEqual(timer.activeSessionID, oldSession, state)
            XCTAssertTrue(timer.isTimerActive, state)
            XCTAssertFalse(timer.isPaused, state)
            XCTAssertFalse(timer.isFinished, state)
            XCTAssertFalse(timer.isOvertime, state)
        }
    }

    func testRestartDoesNotReplaceAMirroredClockTimerOrStartAnIdleTimer() {
        let timer = TimerManager.shared
        timer.forceStopTimer()
        XCTAssertFalse(timer.canRestart)
        timer.restartTimer()
        XCTAssertFalse(timer.isTimerActive)

        timer.adoptExternalTimer(name: "Clock", totalDuration: 3600, remaining: 123, isPaused: true)
        defer { timer.endExternalTimer(triggerSmoothClose: false) }
        let session = timer.activeSessionID
        XCTAssertFalse(timer.canRestart)
        timer.restartTimer()
        XCTAssertEqual(timer.activeSource, .external)
        XCTAssertEqual(timer.activeSessionID, session)
        XCTAssertEqual(timer.remainingTime, 123)
        XCTAssertTrue(timer.isPaused)
    }

    func testEveryTimeFormatFitsItsStableCountdownReservation() {
        let timer = TimerManager.shared
        defer { timer.forceStopTimer() }
        for duration: TimeInterval in [5, 60, 3600, 359999, 360000, 3600000] {
            timer.startTimer(duration: duration)
            let initialWidth = TimerHUDMetrics.countdownWidth(totalDuration: duration, remainingTime: duration)
            for remaining in [duration, 3600, 3599, 600, 599, 60, 59, 1, 0, -1, -59, -60, -3599, -3600, -359999] {
                timer.remainingTime = remaining
                timer.isOvertime = remaining < 0
                let text = timer.formattedRemainingTime()
                let width = TimerHUDMetrics.countdownWidth(totalDuration: duration, remainingTime: remaining)
                XCTAssertEqual(width, initialWidth, "duration=\(duration), time=\(text)")
                XCTAssertLessThanOrEqual(TimerHUDMetrics.textWidth(text, font: TimerHUDMetrics.countdownFont), width, text)
            }
        }
    }

    func testRenderedTimerKeepsBothWingsCentredAndTheHousingEmpty() throws {
        // Argument-domain overrides stay in this test process and do not change
        // the preferences of the user's running Atoll.
        let defaults = UserDefaults.standard
        let previousArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(previousArguments.merging([
            "timerShowsCountdown": true,
            "timerShowsLabel": false,
            "timerShowsProgress": true,
            "timerProgressStyle": TimerProgressStyle.ring.rawValue,
            "timerControlWindowEnabled": true
        ]) { _, new in new }, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }

        let timer = TimerManager.shared
        timer.startTimer(duration: 360000, name: "Layout verification")
        defer { timer.forceStopTimer() }
        let vm = DynamicIslandViewModel()
        vm.closedNotchSize = CGSize(width: 185, height: 37)
        vm.hideOnClosed = false
        defer { vm.destroy() }
        let output = URL(fileURLWithPath: "/tmp/atoll-timer-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        var initialPixelWidth: Int?
        for remaining: TimeInterval in [360000, 36000, 3600, 3599, 60, 59, 5, 0, -1, -3600] {
            timer.remainingTime = remaining
            timer.isOvertime = remaining < 0
            timer.isFinished = remaining <= 0
            timer.isPaused = remaining == 60
            let renderer = ImageRenderer(content: TimerLiveActivity()
                .environmentObject(vm)
                .environment(\.colorScheme, .dark)
                .background(.black))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            let bitmap = NSBitmapImageRep(cgImage: image)
            let time = timer.formattedRemainingTime()
            if initialPixelWidth == nil { initialPixelWidth = image.width }
            XCTAssertEqual(image.width, initialPixelWidth, time)

            let housingWidth = 370
            let wingWidth = (image.width - housingWidth) / 2
            var leftInk: [Int] = []
            var rightInk: [Int] = []
            for x in 0..<image.width {
                let hasInk = (0..<image.height).contains { y in
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                    // SwiftUI additionally dims disabled controls: their PNG
                    // background is only 6/255, but still part of the slot.
                    return max(color.redComponent, color.greenComponent, color.blueComponent) > 1.0 / 255.0
                }
                guard hasInk else { continue }
                if x < wingWidth { leftInk.append(x) }
                else if x >= wingWidth + housingWidth { rightInk.append(x) }
                else { XCTFail("Content enters the physical housing: \(time), x=\(x)") }
            }
            let leftCentre = Double(try XCTUnwrap(leftInk.first) + XCTUnwrap(leftInk.last)) / 2
            let rightCentre = Double(try XCTUnwrap(rightInk.first) + XCTUnwrap(rightInk.last)) / 2
            XCTAssertEqual(leftCentre, Double(wingWidth) / 2, accuracy: 6, time)
            XCTAssertEqual(rightCentre, Double(image.width) - Double(wingWidth) / 2, accuracy: 3, time)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appendingPathComponent("timer-\(Int(remaining)).png"))
        }
    }
}
