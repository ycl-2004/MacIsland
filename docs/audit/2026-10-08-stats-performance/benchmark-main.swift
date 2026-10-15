import Foundation
import Combine
import Defaults

@MainActor enum PublicationProbe { static var times: [Double] = [] }

actor MeasuredSampler: StatsSampling {
    private let sampler = SystemStatsSampler()
    private var includeCPUDetails = false
    private(set) var times: [Double] = []
    func setCPUDetails(_ visible: Bool) { includeCPUDetails = visible }
    func sample(demand: StatsSamplingDemand, generation: UUID, historyRevision: UInt64) async -> StatsSnapshot? {
        var actual = demand
        actual.cpuDetails = includeCPUDetails
        let start = DispatchTime.now().uptimeNanoseconds
        let result = await sampler.sample(demand: actual, generation: generation, historyRevision: historyRevision)
        times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        return result
    }
}

@main struct Runner {
    @MainActor static func main() async throws {
        defer { ProbePreferences.suite.removePersistentDomain(forName: ProbePreferences.name) }
        Defaults[.enableStatsFeature] = true
        Defaults[.statsUpdateInterval] = 60
        let sampler = MeasuredSampler()
        let manager = StatsManager(sampler: sampler, observeRuntimePolicy: false)
        var notifications = 0
        let subscription = manager.objectWillChange.sink { notifications += 1 }
        var heartbeatMaxMS: Double = 0
        let heartbeat = Task { @MainActor in
            var previous = DispatchTime.now().uptimeNanoseconds
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000)
                let now = DispatchTime.now().uptimeNanoseconds
                heartbeatMaxMS = max(heartbeatMaxMS, Double(now - previous) / 1_000_000)
                previous = now
            }
        }
        manager.applyRuntimePolicy(AtollRuntimePolicy(statsVisible: true))
        var allRows: [[String: Any]] = []
        print("Revised source benchmark: real manager + sampler, optimized Swift 5 build")
        print("UI drawing, ps and volume capacities excluded; private isolated preference domain")
        for full in [false, true] {
            if full {
                await sampler.setCPUDetails(true)
                Defaults[.showNetworkGraph] = true; Defaults[.showDiskGraph] = true
            }
            let phase = full ? "all graphs + CPU details" : "CPU / memory / GPU overview"
            var enqueues: [Double] = [], commits: [Double] = [], work: [Double] = []
            print("PHASE: \(phase)")
            for index in 0..<25 {
                let previousCount = PublicationProbe.times.count
                let enqueueStart = DispatchTime.now().uptimeNanoseconds
                if !(!full && index == 0) { manager.refresh() }
                let enqueue = Double(DispatchTime.now().uptimeNanoseconds - enqueueStart) / 1_000_000
                notifications = 0
                let deadline = Date().addingTimeInterval(3)
                while PublicationProbe.times.count == previousCount, Date() < deadline {
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
                guard PublicationProbe.times.count > previousCount else { fatalError("Sample timeout") }
                let commit = PublicationProbe.times.last!
                let sampling = await sampler.times.last!
                enqueues.append(enqueue); commits.append(commit); work.append(sampling)
                allRows.append(["phase": phase, "index": index, "enqueue_ms": enqueue,
                                "publication_ms": commit, "collection_ms": sampling, "notifications": notifications])
                print(String(format: "sample %02d enqueue %.3f ms publication %.3f ms background %.3f ms notifications %d", index, enqueue, commit, sampling, notifications))
                if index < 24 { try await Task.sleep(nanoseconds: 1_000_000_000) }
            }
            for (name, values) in [("enqueue",enqueues),("publication",commits),("background collection",work)] {
                let warm = Array(values.dropFirst())
                print(String(format: "%@: warm mean %.3f ms max %.3f ms", name, warm.reduce(0,+)/Double(warm.count), warm.max()!))
            }
            print("Valid readings: GPU devices \(manager.gpuDevices.count), temperature \(manager.cpuTemperature.celsius != nil), frequency \(manager.cpuFrequency != nil), core readings \(manager.cpuCoreUsage.count)")
        }
        print(String(format: "Maximum heartbeat interval (2 ms requested): %.3f ms", heartbeatMaxMS))
        let json = try JSONSerialization.data(withJSONObject: allRows, options: [.prettyPrinted,.sortedKeys])
        try json.write(to: URL(fileURLWithPath: "/tmp/atoll-stats-probe/after/measurements.json"))
        heartbeat.cancel(); manager.stopMonitoring()
        withExtendedLifetime(subscription) {}
    }
}
