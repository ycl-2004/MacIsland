import AppKit
import Defaults
import SwiftUI
import XCTest
@testable import Atoll

/// The camera housing has no pixels, so a tab drawn under it can be neither
/// seen nor clicked. These render the real tab row rather than trusting the
/// width budget's own arithmetic.
@MainActor
final class NotchHousingClearanceTests: XCTestCase {
    func testEveryTabFitsLeftOfTheHousingAtTheMinimumWidth() throws {
        let features: [Defaults.Key<Bool>] = [.showCalendar, .dynamicShelf, .enableFileConvertFeature, .enableTimerFeature,
                                              .enableStatsFeature, .enableAgentsFeature, .enableExtraSpaceFeature]
        let saved = features.map { Defaults[$0] }
        let savedMode = Defaults[.timerDisplayMode], savedOrder = Defaults[.notchTabOrder]
        defer {
            zip(features, saved).forEach { Defaults[$0] = $1 }
            Defaults[.timerDisplayMode] = savedMode
            Defaults[.notchTabOrder] = savedOrder
        }
        features.forEach { Defaults[$0] = true }
        Defaults[.timerDisplayMode] = .tab
        let count = enabledStandardTabCount()
        XCTAssertEqual(count, 7, "Every standard tab should be on for the widest row")

        let row = NSHostingView(rootView: TabSelectionView().environmentObject(DynamicIslandViewModel()))
        let rowWidth = row.fittingSize.width
        let width = recommendedMinimumNotchWidth(forTabCount: count)
        let gap = min(getClosedNotchSize().width, DynamicIslandHeader.maximumHousingGap)
        let room = (width - gap) / 2 - 2 * DynamicIslandHeader.tabRowInset
        XCTAssertGreaterThan(rowWidth, CGFloat(count) * TabButton.rowSpacing, "The row should have rendered its tabs")
        XCTAssertLessThanOrEqual(rowWidth, room, "The last tab would sit under the camera housing")
    }

    func testFewTabsKeepTheFamiliarWidth() {
        XCTAssertEqual(recommendedMinimumNotchWidth(forTabCount: 4), 640)
        XCTAssertGreaterThan(recommendedMinimumNotchWidth(forTabCount: 7), recommendedMinimumNotchWidth(forTabCount: 6))
    }
}
