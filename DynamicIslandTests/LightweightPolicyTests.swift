import Defaults
import AppKit
import SwiftUI
import XCTest
@testable import Atoll

@MainActor
final class LightweightPolicyTests: XCTestCase {
    func testFeatureManagementDestinationRendersInTheSettingsWindow() async throws {
        let hosting = NSHostingView(rootView: SettingsView().frame(width: 700, height: 600))
        hosting.sizingOptions = []
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.alphaValue = 0
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(100))
        NotificationCenter.default.post(name: .atollSettingsDestination, object: "features")
        try await Task.sleep(for: .milliseconds(200))
        hosting.layoutSubtreeIfNeeded()
        var visited = Set<ObjectIdentifier>()
        func accessibilityLabels(_ value: Any, depth: Int = 0) -> [String] {
            guard depth < 20, let object = value as? NSObject, visited.insert(ObjectIdentifier(object)).inserted else { return [] }
            var labels: [String] = []
            let labelSelector = NSSelectorFromString("accessibilityLabel")
            if object.responds(to: labelSelector), let label = object.perform(labelSelector)?.takeUnretainedValue() as? String { labels.append(label) }
            let childrenSelector = NSSelectorFromString("accessibilityChildren")
            if object.responds(to: childrenSelector), let children = object.perform(childrenSelector)?.takeUnretainedValue() as? [Any] {
                labels += children.flatMap { accessibilityLabels($0, depth: depth + 1) }
            }
            return labels
        }
        let labels = accessibilityLabels(hosting)
        XCTAssertTrue(labels.contains { $0.contains("Preview lightweight suggestions") }, "The destination must display Feature Management, not fall back to General. Labels: \(labels)")
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/tmp/atoll-feature-management.png"))
    }

    func testRealDefaultsTransactionRejectsStalePreviewAndPreservesLaterEdits() throws {
        let name = "atoll-preset-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let stats = Defaults.Key<Bool>("stats", default: true, suite: defaults)
        let lyrics = Defaults.Key<Bool>("lyrics", default: true, suite: defaults)
        let keys = [("Stats", stats), ("Lyrics", lyrics)]
        var controller: FeaturePresetController? = FeaturePresetController(defaults: defaults, candidates: keys)
        let stale = try XCTUnwrap(controller).preview
        Defaults[lyrics] = false
        XCTAssertFalse(try XCTUnwrap(controller).apply(stale))
        XCTAssertTrue(Defaults[stats])
        Defaults[lyrics] = true
        XCTAssertTrue(try XCTUnwrap(controller).apply(try XCTUnwrap(controller).preview))
        XCTAssertFalse(Defaults[stats]); XCTAssertFalse(Defaults[lyrics])
        Defaults[stats] = true
        Defaults[stats] = false
        // Round-trip manual changes are excluded from Undo, even though their
        // final value equals the preset. Unchanged settings survive relaunch.
        controller = nil
        let reopened = FeaturePresetController(defaults: defaults, candidates: keys)
        reopened.restore()
        XCTAssertFalse(Defaults[stats]); XCTAssertTrue(Defaults[lyrics])
        XCTAssertNil(reopened.snapshot)
    }

    func testPresetUndoProtectsManualEditsIncludingRoundTrips() {
        var snapshot = FeaturePresetSnapshot(changes: [
            .init(id: "stats", before: true, applied: false),
            .init(id: "lyrics", before: true, applied: false)
        ])
        // A later manual off → on → off must still remain the user's choice.
        snapshot.userChanged("stats")
        XCTAssertEqual(snapshot.restorable(current: { _ in false }).map(\.id), ["lyrics"])
        XCTAssertTrue(snapshot.restorable(current: { _ in true }).isEmpty)
    }

    func testPresetRoundTripAndShelfExclusion() throws {
        let snapshot = FeaturePresetSnapshot(changes: [.init(id: "lyrics", before: true, applied: false)])
        XCTAssertEqual(try JSONDecoder().decode(FeaturePresetSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        XCTAssertFalse(FeaturePresetController.candidates.contains { $0.1.name == "dynamicShelf" })
        XCTAssertFalse(FeaturePresetController.candidates.contains { $0.1.name == "enableExtraSpaceFeature" })
    }

    func testStatsGateAndBackgroundCadence() {
        var policy = AtollRuntimePolicy()
        XCTAssertFalse(policy.shouldSampleStats(enabled: true, keepInBackground: false, alreadySampling: true))
        XCTAssertFalse(policy.shouldSampleStats(enabled: true, keepInBackground: true, alreadySampling: false))
        XCTAssertTrue(policy.shouldSampleStats(enabled: true, keepInBackground: true, alreadySampling: true))
        XCTAssertEqual(policy.statsInterval(configured: 1), 5)
        policy.statsVisible = true
        XCTAssertTrue(policy.shouldSampleStats(enabled: true, keepInBackground: false, alreadySampling: false))
        XCTAssertFalse(policy.shouldSampleStats(enabled: false, keepInBackground: true, alreadySampling: true))
        XCTAssertEqual(policy.statsInterval(configured: 1), 1)
        policy.isLowPower = true
        XCTAssertEqual(policy.statsInterval(configured: 1), 3)
        XCTAssertEqual(policy.statsInterval(configured: 20), 20)
        policy.statsVisible = false
        XCTAssertEqual(policy.statsInterval(configured: .nan), 10)
        policy.isLocked = true
        XCTAssertFalse(policy.shouldSampleStats(enabled: true, keepInBackground: true, alreadySampling: true))
    }

    func testConnectionRefreshSlowsWithoutDisablingEvents() {
        var policy = AtollRuntimePolicy()
        XCTAssertEqual(policy.agentRefreshInterval(conversationOpen: true), .seconds(1))
        XCTAssertEqual(policy.agentRefreshInterval(conversationOpen: false), .seconds(3))
        policy.isLowPower = true
        XCTAssertEqual(policy.agentRefreshInterval(conversationOpen: true), .seconds(3))
        XCTAssertEqual(policy.agentRefreshInterval(conversationOpen: false), .seconds(10))
        policy.isLocked = true
        XCTAssertEqual(policy.agentRefreshInterval(conversationOpen: true), .seconds(15))
    }

    func testStatsStartsFromPublishedVisibilityAndStopsWhenHidden() {
        let previousEnabled = Defaults[.enableStatsFeature]
        let previousBackground = Defaults[.statsStopWhenNotchCloses]
        let monitor = RuntimePolicyMonitor.shared
        let stats = StatsManager.shared
        defer {
            monitor.setStatsSurface("runtime-integration-test", visible: false)
            monitor.setStatsSurface("runtime-other-display-test", visible: false)
            Defaults[.enableStatsFeature] = previousEnabled
            Defaults[.statsStopWhenNotchCloses] = previousBackground
        }
        Defaults[.enableStatsFeature] = true
        Defaults[.statsStopWhenNotchCloses] = true
        monitor.setStatsSurface("runtime-integration-test", visible: true)
        XCTAssertTrue(stats.isMonitoring, "The subscriber must use the published policy, not the monitor's old willSet value.")
        monitor.setStatsSurface("runtime-other-display-test", visible: true)
        monitor.setStatsSurface("runtime-integration-test", visible: false)
        XCTAssertTrue(stats.isMonitoring, "Closing one display cannot stop another visible Stats surface.")
        monitor.setStatsSurface("runtime-other-display-test", visible: false)
        XCTAssertFalse(stats.isMonitoring)
    }

    func testBackgroundStatsResumeAfterUnlockButDoNotColdStart() {
        let previousEnabled = Defaults[.enableStatsFeature]
        let previousBackground = Defaults[.statsStopWhenNotchCloses]
        let stats = StatsManager.shared
        defer {
            stats.stopMonitoring()
            Defaults[.enableStatsFeature] = previousEnabled
            Defaults[.statsStopWhenNotchCloses] = previousBackground
            stats.applyRuntimePolicy(RuntimePolicyMonitor.shared.state)
        }
        Defaults[.enableStatsFeature] = true
        Defaults[.statsStopWhenNotchCloses] = false
        stats.stopMonitoring()
        stats.applyRuntimePolicy(AtollRuntimePolicy())
        XCTAssertFalse(stats.isMonitoring, "Hidden cold-start must remain idle.")
        stats.applyRuntimePolicy(AtollRuntimePolicy(statsVisible: true))
        XCTAssertTrue(stats.isMonitoring)
        stats.applyRuntimePolicy(AtollRuntimePolicy())
        XCTAssertTrue(stats.isMonitoring, "Explicit background sampling stays active when hidden.")
        stats.applyRuntimePolicy(AtollRuntimePolicy(isLocked: true))
        XCTAssertFalse(stats.isMonitoring)
        stats.applyRuntimePolicy(AtollRuntimePolicy())
        XCTAssertTrue(stats.isMonitoring, "Unlock restores previously active background sampling.")
        Defaults[.enableStatsFeature] = false
        stats.applyRuntimePolicy(AtollRuntimePolicy())
        XCTAssertFalse(stats.isMonitoring)
    }
}
