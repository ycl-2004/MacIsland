import AppKit
import Combine
import Defaults
import XCTest
@testable import Atoll

private actor HeldStatsSampler: StatsSampling {
    struct Request {
        let demand: StatsSamplingDemand
        let generation: UUID
        let historyRevision: UInt64
        let onMainThread: Bool
        let startedAt: Date
    }
    private(set) var requests: [Request] = []
    private var completions: [Int: CheckedContinuation<StatsSnapshot?, Never>] = [:]

    func sample(demand: StatsSamplingDemand, generation: UUID, historyRevision: UInt64) async -> StatsSnapshot? {
        let index = requests.count
        requests.append(Request(demand: demand, generation: generation, historyRevision: historyRevision,
                                onMainThread: isOnMainThread(), startedAt: Date()))
        return await withCheckedContinuation { completions[index] = $0 }
    }

    private func isOnMainThread() -> Bool { Thread.isMainThread }

    func complete(_ index: Int, usage: Double, history: [Double]? = nil) {
        var snapshot = StatsSnapshot()
        snapshot.cpuUsage = usage
        snapshot.memoryUsage = usage + 1
        snapshot.lastUpdated = Date()
        if let history { snapshot.cpuHistory = history }
        completions.removeValue(forKey: index)?.resume(returning: snapshot)
    }

    func finishAll() {
        let pending = completions.values
        completions.removeAll()
        for completion in pending { completion.resume(returning: nil) }
    }
}

@MainActor
final class StatsPerformanceTests: XCTestCase {
    private func withManager(start: Bool = true,
                             _ body: (StatsManager, HeldStatsSampler) async throws -> Void) async throws {
        let boolKeys: [Defaults.Key<Bool>] = [.enableStatsFeature, .statsStopWhenNotchCloses,
            .showCpuGraph, .showMemoryGraph, .showGpuGraph, .showNetworkGraph, .showDiskGraph]
        let saved = boolKeys.map { Defaults[$0] }
        let interval = Defaults[.statsUpdateInterval]
        let sampler = HeldStatsSampler()
        let manager = StatsManager(sampler: sampler, observeRuntimePolicy: false)
        defer {
            manager.stopMonitoring()
            for (key, value) in zip(boolKeys, saved) { Defaults[key] = value }
            Defaults[.statsUpdateInterval] = interval
        }
        Defaults[.enableStatsFeature] = true
        Defaults[.statsStopWhenNotchCloses] = true
        Defaults[.statsUpdateInterval] = 60
        Defaults[.showCpuGraph] = true; Defaults[.showMemoryGraph] = true; Defaults[.showGpuGraph] = true
        Defaults[.showNetworkGraph] = false; Defaults[.showDiskGraph] = false
        if start { manager.applyRuntimePolicy(AtollRuntimePolicy(statsVisible: true)) }
        do {
            try await body(manager, sampler)
            manager.stopMonitoring()
            await sampler.finishAll()
        } catch {
            manager.stopMonitoring()
            await sampler.finishAll()
            throw error
        }
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw NSError(domain: "StatsPerformanceTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for a sample transition"])
    }

    func testSlowSampleLeavesMainActorResponsiveAndCoalescesRequests() async throws {
        try await withManager { manager, sampler in
            try await waitUntil { await sampler.requests.count == 1 }
            // The sampler is still held here; UI-side work must remain usable.
            for _ in 0..<100 { manager.refresh() }
            XCTAssertTrue(manager.isMonitoring)
            let countBeforeCompletion = await sampler.requests.count
            XCTAssertEqual(countBeforeCompletion, 1)
            let request = await sampler.requests[0]
            XCTAssertFalse(request.onMainThread)
            await sampler.complete(0, usage: 42)
            try await waitUntil { await sampler.requests.count == 2 }
            XCTAssertEqual(manager.cpuUsage, 42)
            await sampler.complete(1, usage: 43)
            try await waitUntil { manager.cpuUsage == 43 }
            let finalCount = await sampler.requests.count
            XCTAssertEqual(finalCount, 2, "Extra refreshes must become only one follow-up.")
        }
    }

    func testOneCoherentPublicationPerSample() async throws {
        try await withManager { manager, sampler in
            var published: [StatsSnapshot] = []
            var changes = 0
            let snapshots = manager.$snapshot.dropFirst().sink { published.append($0) }
            let events = manager.objectWillChange.sink { changes += 1 }
            try await waitUntil { await sampler.requests.count == 1 }
            await sampler.complete(0, usage: 42)
            try await waitUntil { manager.cpuUsage == 42 }
            XCTAssertEqual(changes, 1)
            XCTAssertEqual(published.count, 1)
            XCTAssertEqual(published[0].cpuUsage, 42)
            XCTAssertEqual(published[0].memoryUsage, 43)
            XCTAssertNotEqual(published[0].lastUpdated, .distantPast)
            withExtendedLifetime((snapshots, events)) {}
        }
    }

    func testStoppedSampleCannotPublishLateResults() async throws {
        try await withManager { manager, sampler in
            try await waitUntil { await sampler.requests.count == 1 }
            manager.stopMonitoring()
            await sampler.complete(0, usage: 99)
            for _ in 0..<5 { await Task.yield() }
            XCTAssertFalse(manager.isMonitoring)
            XCTAssertEqual(manager.cpuUsage, 0)
            XCTAssertEqual(manager.lastUpdated, .distantPast)
        }
    }

    func testRestartRejectsPreviousGeneration() async throws {
        try await withManager { manager, sampler in
            try await waitUntil { await sampler.requests.count == 1 }
            manager.stopMonitoring()
            manager.applyRuntimePolicy(AtollRuntimePolicy(statsVisible: true))
            try await waitUntil { await sampler.requests.count == 2 }
            let requests = await sampler.requests
            XCTAssertNotEqual(requests[0].generation, requests[1].generation)
            await sampler.complete(0, usage: 99)
            await sampler.complete(1, usage: 11)
            try await waitUntil { manager.cpuUsage == 11 }
            XCTAssertTrue(manager.isMonitoring)
            XCTAssertEqual(manager.cpuUsage, 11)
        }
    }

    func testClearHistoryRejectsAnInFlightOldHistory() async throws {
        try await withManager { manager, sampler in
            try await waitUntil { await sampler.requests.count == 1 }
            manager.clearHistory()
            await sampler.complete(0, usage: 99, history: Array(repeating: 99, count: 30))
            try await waitUntil { await sampler.requests.count == 2 }
            XCTAssertTrue(manager.cpuHistory.allSatisfy { $0 == 0 })
            let requests = await sampler.requests
            XCTAssertGreaterThan(requests[1].historyRevision, requests[0].historyRevision)
            await sampler.complete(1, usage: 11, history: Array(repeating: 0, count: 29) + [11])
            try await waitUntil { manager.cpuUsage == 11 }
            XCTAssertEqual(manager.cpuHistory.last, 11)
            XCTAssertFalse(manager.cpuHistory.contains(99))
        }
    }

    func testDetailDemandIsIndependentAcrossWindows() async throws {
        try await withManager(start: false) { manager, _ in
            XCTAssertFalse(manager.samplingDemand.disk)
            XCTAssertFalse(manager.samplingDemand.cpuDetails)
            XCTAssertFalse(manager.samplingDemand.processes)
            let first = UUID(), second = UUID()
            manager.setDetailSurface(first, kind: .cpu, visible: true)
            manager.setDetailSurface(second, kind: .cpu, visible: true)
            XCTAssertTrue(manager.samplingDemand.cpuDetails)
            XCTAssertTrue(manager.samplingDemand.processes)
            manager.setDetailSurface(first, kind: .cpu, visible: false)
            XCTAssertTrue(manager.samplingDemand.cpuDetails)
            manager.setDetailSurface(second, kind: .cpu, visible: false)
            XCTAssertFalse(manager.samplingDemand.cpuDetails)
            XCTAssertFalse(manager.samplingDemand.processes)
            manager.setDetailSurface(first, kind: .disk, visible: true)
            XCTAssertTrue(manager.samplingDemand.disk)
            XCTAssertTrue(manager.samplingDemand.diskDetails)
            manager.setDetailSurface(first, kind: .disk, visible: false)
            XCTAssertFalse(manager.samplingDemand.disk)
        }
    }

    func testTimerRequestsSamplesDuringControlTracking() async throws {
        try await withManager(start: false) { manager, sampler in
            // Start once with a 1 s timer, without a cancelled setup request.
            Defaults[.statsUpdateInterval] = 1
            manager.applyRuntimePolicy(AtollRuntimePolicy(statsVisible: true))
            try await waitUntil { await sampler.requests.count == 1 }
            await sampler.complete(0, usage: 1)
            try await waitUntil { manager.cpuUsage == 1 }
            let trackingEnded = runControlTrackingLoop()
            try await waitUntil { await sampler.requests.count == 2 }
            let timerRequest = await sampler.requests[1]
            XCTAssertLessThan(timerRequest.startedAt, trackingEnded,
                              "A default-mode timer would only resume after tracking ends.")
            await sampler.complete(1, usage: 2)
            try await waitUntil { manager.cpuUsage == 2 }
        }
    }

    private func runControlTrackingLoop() -> Date {
        let timer = Timer(timeInterval: 0.02, repeats: true) { _ in }
        RunLoop.main.add(timer, forMode: .eventTracking)
        defer { timer.invalidate() }
        let deadline = Date().addingTimeInterval(1.15)
        while Date() < deadline { RunLoop.main.run(mode: .eventTracking, before: deadline) }
        return Date()
    }

    func testProcessIdentitySurvivesMetricUpdates() {
        let first = ProcessStats(pid: 42, name: "Fixture", cpuUsage: 1, memoryUsage: 100, icon: nil)
        let updated = ProcessStats(pid: 42, name: "Fixture", cpuUsage: 5, memoryUsage: 200, icon: nil)
        XCTAssertEqual(first.id, updated.id)
    }

    func testOverviewSamplerSkipsDetailAndDisabledHardware() async throws {
        let result = await SystemStatsSampler().sample(demand: StatsSamplingDemand(cpu: true, memory: true),
                                                      generation: UUID(), historyRevision: 0)
        let snapshot = try XCTUnwrap(result)
        XCTAssertTrue(snapshot.gpuDevices.isEmpty)
        XCTAssertTrue(snapshot.cpuCoreUsage.isEmpty)
        XCTAssertNil(snapshot.cpuTemperature.celsius)
        XCTAssertNil(snapshot.cpuFrequency)
        XCTAssertEqual(snapshot.diskRead, 0)
        XCTAssertTrue(snapshot.networkInterfaces.isEmpty)
        XCTAssertGreaterThan(snapshot.memoryBreakdown.totalBytes, 0)
        XCTAssertEqual(snapshot.cpuHistory.count, 30)
    }
}
