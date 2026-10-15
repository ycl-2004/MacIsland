import AppKit
import Combine
import Defaults
import SwiftUI
import XCTest
@testable import Atoll

@MainActor
final class ScreenRecordingPresentationTests: XCTestCase {
    private func layout(
        state: NotchState = .closed,
        enabled: Bool = true,
        indicator: Bool = true,
        hidden: Bool = false,
        recording: Bool = true
    ) -> RecordingHUDLayout {
        makeRecordingHUDLayout(
            notchState: state,
            screenRecordingDetectionEnabled: enabled,
            showRecordingIndicator: indicator,
            hideOnClosed: hidden,
            isRecording: recording
        )
    }

    func testSideIndicatorRespectsDetectionAndVisibilitySettings() {
        XCTAssertTrue(layout().isVisible)
        for hiddenLayout in [layout(state: .open), layout(enabled: false),
                             layout(indicator: false), layout(hidden: true), layout(recording: false)] {
            XCTAssertFalse(hiddenLayout.isVisible)
            let contentSize = CGSize(width: 420, height: 32)
            XCTAssertEqual(hiddenLayout.addingIndicator(to: contentSize), contentSize)
        }
    }

    func testRecordingAddsOnlySmallGuttersWithoutReplacingMainActivitySize() {
        // Idle, music/download, inline title strip and taller battery content.
        for size in [CGSize(width: 200, height: 32), CGSize(width: 380, height: 32),
                     CGSize(width: 600, height: 32), CGSize(width: 350, height: 107)] {
            let result = layout().addingIndicator(to: size)
            XCTAssertEqual(result.width - size.width, 24)
            XCTAssertEqual(result.height, size.height)
        }
        XCTAssertEqual(RecordingHUDLayout.dotDiameter, 6)
    }

    func testRecordingAloneDoesNotActivateTheMainPrivacyActivity() {
        let privacy = PrivacyIndicatorManager.shared
        let oldState = (privacy.cameraActive, privacy.microphoneActive, privacy.screenRecordingActive)
        let oldSettings = (Defaults[.enableCameraDetection], Defaults[.enableMicrophoneDetection])
        defer {
            (privacy.cameraActive, privacy.microphoneActive, privacy.screenRecordingActive) = oldState
            Defaults[.enableCameraDetection] = oldSettings.0
            Defaults[.enableMicrophoneDetection] = oldSettings.1
        }
        Defaults[.enableCameraDetection] = true
        Defaults[.enableMicrophoneDetection] = true
        privacy.cameraActive = false
        privacy.microphoneActive = false
        privacy.screenRecordingActive = true
        XCTAssertFalse(privacy.hasCameraOrMicrophoneIndicator)
        privacy.cameraActive = true
        XCTAssertTrue(privacy.hasCameraOrMicrophoneIndicator)
        Defaults[.enableCameraDetection] = false
        XCTAssertFalse(privacy.hasCameraOrMicrophoneIndicator)
        privacy.microphoneActive = true
        XCTAssertTrue(privacy.hasCameraOrMicrophoneIndicator)
        Defaults[.enableMicrophoneDetection] = false
        XCTAssertFalse(privacy.hasCameraOrMicrophoneIndicator)
    }

    func testLegacyHoverAndStopSettingsCannotExpandTheIndicator() {
        let oldStyle = Defaults[.recordingHoverStyle]
        let oldControls = Defaults[.recordingControlMode]
        defer {
            Defaults[.recordingHoverStyle] = oldStyle
            Defaults[.recordingControlMode] = oldControls
        }
        for style in RecordingHoverStyle.allCases {
            for controls in RecordingControlMode.allCases {
                Defaults[.recordingHoverStyle] = style
                Defaults[.recordingControlMode] = controls
                XCTAssertEqual(layout().addingIndicator(to: CGSize(width: 200, height: 32)),
                               CGSize(width: 224, height: 32))
            }
        }
    }

    func testCaptureStartAndStopLeaveOtherActivityAndSelectedTabAlone() async throws {
        let coordinator = DynamicIslandViewCoordinator.shared
        let oldExpansion = coordinator.expandingView
        let oldView = coordinator.currentView
        let statsEnabled = Defaults[.enableStatsFeature]
        Defaults[.enableStatsFeature] = true
        defer {
            Defaults[.enableStatsFeature] = statsEnabled
            coordinator.expandingView = oldExpansion
            coordinator.currentView = oldView
        }
        let manager = ScreenRecordingManager(stopController: NoOpRecordingStopController())
        defer { manager.updateRecordingState(false) }

        for activity in [SneakContentType.download, .timer, .battery, .music] {
            coordinator.expandingView = ExpandedItem(show: true, type: activity, value: 0.42, autoHideDuration: 60)
            coordinator.currentView = .stats
            XCTAssertEqual(coordinator.currentView, .stats, "Fixture must expose Stats before capture begins")
            for isRecording in [true, true, false] {
                manager.updateRecordingState(isRecording)
                // Flush asynchronous coordinator writes too: the old implementation
                // replaced this HUD in a Task on both start and stop.
                try await Task.sleep(for: .milliseconds(20))
                XCTAssertEqual(manager.isRecording, isRecording)
                XCTAssertTrue(coordinator.expandingView.show)
                XCTAssertEqual(coordinator.expandingView.type, activity)
                XCTAssertEqual(coordinator.expandingView.value, 0.42)
                XCTAssertEqual(coordinator.currentView, .stats)
            }
        }
    }

    func testElapsedTimeRedrawsOnlyTheClock() async throws {
        let manager = ScreenRecordingManager(stopController: NoOpRecordingStopController())
        defer { manager.updateRecordingState(false) }
        manager.updateRecordingState(true)
        var stateChanges = 0
        let subscription = manager.objectWillChange.sink { stateChanges += 1 }
        defer { subscription.cancel() }
        for _ in 0..<200 where manager.clock.duration < 1 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertGreaterThanOrEqual(manager.clock.duration, 1)
        XCTAssertEqual(manager.clock.formatted, "0:01")
        XCTAssertEqual(stateChanges, 0, "A ticking clock must not redraw every observer of the recording state")
    }

    func testSwiftUIIndicatorPreservesPrimaryContentHeight() {
        let manager = ScreenRecordingManager.shared
        let wasRecording = manager.isRecording
        manager.isRecording = true
        defer { manager.isRecording = wasRecording }

        for size in [CGSize(width: 200, height: 32), CGSize(width: 380, height: 32),
                     CGSize(width: 350, height: 107)] {
            let view = RecordingLiveActivity(layout: layout(), closedNotchSize: CGSize(width: 200, height: 32)) {
                Color.blue.frame(width: size.width, height: size.height)
            }
            let hosting = NSHostingView(rootView: view)
            let renderedSize = hosting.fittingSize
            XCTAssertEqual(renderedSize.width, size.width + 24, accuracy: 0.5)
            XCTAssertEqual(renderedSize.height, size.height, accuracy: 0.5)
        }
    }

    func testSideIndicatorRendersAlongsideMainInformation() async throws {
        let manager = ScreenRecordingManager.shared
        let wasRecording = manager.isRecording
        manager.isRecording = true
        defer { manager.isRecording = wasRecording }
        let view = RecordingLiveActivity(layout: layout(), closedNotchSize: CGSize(width: 200, height: 32)) {
            Text("Other information remains visible")
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .frame(width: 280, height: 32)
        }
        .padding(.horizontal, 12)
        .background(.black)
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        let window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 328, height: 32),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.alphaValue = 0
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(200))
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        attachPreview(try XCTUnwrap(bitmap.representation(using: .png, properties: [:])),
                      named: "Recording side indicator with main information")
    }
}

private struct NoOpRecordingStopController: ScreenRecordingStopControlling {
    func requestStop() async -> Bool { false }
}
