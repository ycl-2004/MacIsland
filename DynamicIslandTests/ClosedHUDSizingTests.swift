import XCTest
@testable import Atoll

/// The closed-notch HUD sizes that ContentView's layout and AppDelegate's
/// window both read: they must agree with what the HUD draws.
final class ClosedHUDSizingTests: XCTestCase {
    // MARK: - Battery HUD

    func testChargingIsAlwaysCompact() {
        XCTAssertEqual(BatteryTemporaryHUDKind.charging.style(lowBattery: .standard, fullBattery: .standard), .compact)
    }

    func testAlertsFollowTheirOwnSetting() {
        XCTAssertEqual(BatteryTemporaryHUDKind.lowBattery.style(lowBattery: .standard, fullBattery: .compact), .standard)
        XCTAssertEqual(BatteryTemporaryHUDKind.fullBattery.style(lowBattery: .standard, fullBattery: .compact), .compact)
    }

    func testCompactHUDWidensTheNotchWithoutGrowingIt() {
        for kind in [BatteryTemporaryHUDKind.charging, .lowBattery, .fullBattery] {
            let metrics = kind.metrics(style: .compact, closedNotchWidth: 200, baseHeight: 32)
            XCTAssertEqual(metrics.size, CGSize(width: 380, height: 32), "\(kind)")
        }
    }

    func testStandardAlertsDrawBelowTheNotch() {
        let low = BatteryTemporaryHUDKind.lowBattery.metrics(style: .standard, closedNotchWidth: 200, baseHeight: 32)
        XCTAssertEqual(low.size, CGSize(width: 350, height: 107))
        XCTAssertEqual(low.bottomRadius, 40)

        let full = BatteryTemporaryHUDKind.fullBattery.metrics(style: .standard, closedNotchWidth: 200, baseHeight: 32)
        XCTAssertEqual(full.size, CGSize(width: 340, height: 102))
        XCTAssertEqual(full.bottomRadius, 36)
    }

    // MARK: - Inline sneak peek

    private func listeningModeSneak(show: Bool = true, value: CGFloat = -1, icon: String = "ear") -> SneakPeek {
        SneakPeek(show: show, type: .bluetoothAudio, value: value, icon: icon)
    }

    private func activeKind(
        notchState: NotchState = .closed,
        enabled: Bool = true,
        style: SneakPeekStyle = .inline,
        expanding: ExpandedItem = ExpandedItem(show: true, type: .music),
        sneakPeek: SneakPeek = SneakPeek()
    ) -> InlineSneakPeekMetrics.Kind? {
        InlineSneakPeekMetrics.activeKind(
            notchState: notchState,
            sneakPeekEnabled: enabled,
            sneakPeekStyle: style,
            expandingView: expanding,
            sneakPeek: sneakPeek
        )
    }

    func testMusicAndTimerExpansionsShowTheTitleStripInlineOnly() {
        XCTAssertEqual(activeKind(expanding: ExpandedItem(show: true, type: .music)), .titleStrip)
        XCTAssertEqual(activeKind(expanding: ExpandedItem(show: true, type: .timer)), .titleStrip)
        XCTAssertNil(activeKind(expanding: ExpandedItem(show: true, type: .battery)))
        XCTAssertNil(activeKind(expanding: ExpandedItem(show: false, type: .music)))
        XCTAssertNil(activeKind(style: .standard))
    }

    func testNothingIsInlineWhileOpenOrDisabled() {
        XCTAssertNil(activeKind(notchState: .open))
        XCTAssertNil(activeKind(enabled: false))
        XCTAssertNil(activeKind(enabled: false, sneakPeek: listeningModeSneak()))
    }

    func testAListeningModeChangeIsInlineWhateverTheStyle() {
        let idle = ExpandedItem()
        XCTAssertEqual(activeKind(style: .standard, expanding: idle, sneakPeek: listeningModeSneak()), .airPodsListeningMode)
        XCTAssertEqual(activeKind(sneakPeek: listeningModeSneak()), .airPodsListeningMode, "beats the title strip")
        XCTAssertNil(activeKind(style: .standard, expanding: idle, sneakPeek: listeningModeSneak(show: false)))
    }

    func testOnlyANegativeValueWithAModeSymbolIsAListeningModeChange() {
        XCTAssertTrue(InlineSneakPeekMetrics.isAirPodsListeningMode(listeningModeSneak()))
        XCTAssertFalse(InlineSneakPeekMetrics.isAirPodsListeningMode(listeningModeSneak(value: 0.8)))
        XCTAssertFalse(InlineSneakPeekMetrics.isAirPodsListeningMode(listeningModeSneak(icon: "airpods")))
        var battery = listeningModeSneak()
        battery.type = .battery
        XCTAssertFalse(InlineSneakPeekMetrics.isAirPodsListeningMode(battery))
    }
}
