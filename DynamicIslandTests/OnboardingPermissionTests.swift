import AppKit
import EventKit
import SwiftUI
import XCTest
@testable import Atoll

@MainActor
final class OnboardingPermissionTests: XCTestCase {
    func testNewInstallationNeedsSetup() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: temporaryDefaultsSuite()))
        XCTAssertTrue(OnboardingLifecycle.shouldPresent(in: defaults))
    }

    func testFinishingNotchGreetingDoesNotFinishAnInterruptedSetup() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: temporaryDefaultsSuite()))
        OnboardingLifecycle.begin(in: defaults)
        defaults.set(false, forKey: "firstLaunch")
        XCTAssertTrue(OnboardingLifecycle.shouldPresent(in: defaults))
    }

    func testExistingInstallationIsNotForcedThroughSetupAgain() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: temporaryDefaultsSuite()))
        defaults.set(false, forKey: "firstLaunch")
        XCTAssertFalse(OnboardingLifecycle.shouldPresent(in: defaults))
        XCTAssertNil(defaults.object(forKey: OnboardingLifecycle.completionKey))
    }

    func testCompletionSurvivesRelaunchAndPreservesFeatureChoices() throws {
        let suite = try temporaryDefaultsSuite()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: "showMirror")
        defaults.set(false, forKey: "showCalendar")
        OnboardingLifecycle.begin(in: defaults)
        OnboardingLifecycle.complete(in: defaults)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertFalse(OnboardingLifecycle.shouldPresent(in: reopened))
        XCTAssertTrue(reopened.bool(forKey: "showMirror"))
        XCTAssertFalse(reopened.bool(forKey: "showCalendar"))
    }

    func testCalendarAndRemindersRemainIndependentlyUsable() {
        let calendarOnly = FeaturePermissionSnapshot(events: .fullAccess, reminders: .denied)
        let remindersOnly = FeaturePermissionSnapshot(events: .denied, reminders: .fullAccess)
        let writeOnly = FeaturePermissionSnapshot(events: .writeOnly, reminders: .denied)
        XCTAssertTrue(calendarOnly.canReadCalendar)
        XCTAssertTrue(remindersOnly.canReadCalendar)
        XCTAssertFalse(writeOnly.canReadCalendar)
    }

    func testRenderSetupPagesInEnglishAndChinese() async throws {
        // Render actual SwiftUI pages in an isolated XCTest host. This exercises
        // native layout without opening system permission prompts or live agents.
        for locale in ["en", "zh-Hans", "zh-Hant"] {
            for step in OnboardingStep.allCases {
                let view = OnboardingView(initialStep: step, onFinish: {}, onOpenSettings: {})
                    .environment(\.locale, Locale(identifier: locale))
                try await render(view, size: NSSize(width: 540, height: 640),
                                 name: "onboarding-\(locale)-\(step.rawValue)", dark: locale == "zh-Hans")
            }
        }
        try await render(OnboardingDataUseView().environment(\.locale, Locale(identifier: "zh-Hans")),
                         size: NSSize(width: 526, height: 420), name: "data-use-zh-Hans", dark: false)
    }

    private func render<V: View>(_ view: V, size: NSSize, name: String, dark: Bool) async throws {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        XCTAssertGreaterThan(bitmap.pixelsWide, 500)
        attachPreview(try XCTUnwrap(bitmap.representation(using: .png, properties: [:])), named: name)
    }
}
