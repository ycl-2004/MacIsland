/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import Combine
import Defaults
import AppKit
import Darwin

@MainActor
final class StatsManager: ObservableObject {
    static let shared = StatsManager()
    @Published private(set) var isMonitoring = false
    @Published private(set) var snapshot = StatsSnapshot()
    @Published private(set) var topCPUProcesses: [ProcessStats] = []
    @Published private(set) var diskDevices: [DiskDeviceMetrics] = []

    var cpuUsage: Double { snapshot.cpuUsage }
    var memoryUsage: Double { snapshot.memoryUsage }
    var gpuUsage: Double { snapshot.gpuUsage }
    var networkDownload: Double { snapshot.networkDownload }
    var networkUpload: Double { snapshot.networkUpload }
    var diskRead: Double { snapshot.diskRead }
    var diskWrite: Double { snapshot.diskWrite }
    var lastUpdated: Date { snapshot.lastUpdated }
    var cpuBreakdown: CPULoadBreakdown { snapshot.cpuBreakdown }
    var cpuLoadAverage: LoadAverage { snapshot.cpuLoadAverage }
    var cpuCoreUsage: [CPUCoreUsage] { snapshot.cpuCoreUsage }
    var cpuUptime: TimeInterval { snapshot.cpuUptime }
    var cpuTemperature: CPUTemperatureMetrics { snapshot.cpuTemperature }
    var cpuFrequency: CPUFrequencyMetrics? { snapshot.cpuFrequency }
    var memoryBreakdown: MemoryBreakdown { snapshot.memoryBreakdown }
    var gpuBreakdown: GPUBreakdown { snapshot.gpuBreakdown }
    var gpuDevices: [GPUDeviceMetrics] { snapshot.gpuDevices }
    var networkTotals: NetworkTotals { snapshot.networkTotals }
    var diskTotals: DiskTotals { snapshot.diskTotals }
    var networkInterfaces: [NetworkInterfaceMetrics] { snapshot.networkInterfaces }
    var cpuHistory: [Double] { snapshot.cpuHistory }
    var memoryHistory: [Double] { snapshot.memoryHistory }
    var gpuHistory: [Double] { snapshot.gpuHistory }
    var networkDownloadHistory: [Double] { snapshot.networkDownloadHistory }
    var networkUploadHistory: [Double] { snapshot.networkUploadHistory }
    var diskReadHistory: [Double] { snapshot.diskReadHistory }
    var diskWriteHistory: [Double] { snapshot.diskWriteHistory }

    private let sampler: any StatsSampling
    private var samplingTask: Task<Void, Never>?
    private var sampleRequested = false
    private var monitoringGeneration = UUID()
    private var historyRevision: UInt64 = 0
    private var detailSurfaces: [UUID: ProcessRankingType] = [:]
    private var monitoringTimer: Timer?
    private var scheduledInterval: TimeInterval?
    private var runtimePolicy = AtollRuntimePolicy()
    private var resumeBackgroundAfterUnlock = false
    private var cancellables = Set<AnyCancellable>()
    private var cachedProcessStats: [ProcessStats] = []
    private var lastProcessStatsUpdate: Date = .distantPast
    private let processStatsUpdateInterval: TimeInterval = 2
    private let maxProcessEntries = 20
    private var processRefreshGeneration = UUID()
    private var processRefreshTask: Task<Void, Never>?
    private var isProcessRefreshInFlight = false
    private var lastDiskDevicesUpdate: Date = .distantPast
    private let diskDevicesUpdateInterval: TimeInterval = 30
    private var isDiskDevicesRefreshInFlight = false

    /// Dependency injection also lets lifecycle tests hold and release samples.
    init(sampler: any StatsSampling = SystemStatsSampler(), observeRuntimePolicy: Bool = true) {
        self.sampler = sampler
        guard observeRuntimePolicy else { return }
        // Keep the emitted value: @Published sends before the monitor assigns it.
        RuntimePolicyMonitor.shared.$state.removeDuplicates().sink { [weak self] policy in
            self?.applyRuntimePolicy(policy)
        }.store(in: &cancellables)
        Defaults.publisher(.enableStatsFeature, options: []).sink { [weak self] _ in
            self?.applyRuntimePolicy(RuntimePolicyMonitor.shared.state)
        }.store(in: &cancellables)
        Defaults.publisher(.statsStopWhenNotchCloses, options: []).sink { [weak self] _ in
            self?.applyRuntimePolicy(RuntimePolicyMonitor.shared.state)
        }.store(in: &cancellables)
        Defaults.publisher(.statsUpdateInterval, options: []).sink { [weak self] change in
            self?.handleUpdateIntervalChange(change.newValue)
        }.store(in: &cancellables)
        for key in [Defaults.Keys.showCpuGraph, Defaults.Keys.showMemoryGraph, Defaults.Keys.showGpuGraph, Defaults.Keys.showNetworkGraph, Defaults.Keys.showDiskGraph] {
            Defaults.publisher(key, options: []).sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }.store(in: &cancellables)
        }
    }

    deinit {
        monitoringTimer?.invalidate()
        samplingTask?.cancel()
        processRefreshTask?.cancel()
    }

    var samplingDemand: StatsSamplingDemand {
        let details = Set(detailSurfaces.values)
        return StatsSamplingDemand(
            cpu: Defaults[.showCpuGraph] || details.contains(.cpu),
            memory: Defaults[.showMemoryGraph] || details.contains(.memory),
            gpu: Defaults[.showGpuGraph] || details.contains(.gpu),
            network: Defaults[.showNetworkGraph] || details.contains(.network),
            disk: Defaults[.showDiskGraph] || details.contains(.disk),
            cpuDetails: details.contains(.cpu),
            networkDetails: details.contains(.network),
            diskDetails: details.contains(.disk),
            processes: !details.isDisjoint(with: [.cpu, .memory, .gpu]))
    }

    func setDetailSurface(_ id: UUID, kind: ProcessRankingType, visible: Bool) {
        let previous = samplingDemand
        if visible { detailSurfaces[id] = kind } else { detailSurfaces.removeValue(forKey: id) }
        guard previous != samplingDemand else { return }
        if !samplingDemand.processes {
            processRefreshGeneration = UUID()
            processRefreshTask?.cancel(); processRefreshTask = nil
            isProcessRefreshInFlight = false
        }
        refresh()
    }

    func updateMonitoringState(notchIsOpen: Bool, currentView: String) {
        RuntimePolicyMonitor.shared.setStatsSurface("legacy", visible: notchIsOpen && currentView == "stats")
    }

    func applyRuntimePolicy(_ policy: AtollRuntimePolicy) {
        runtimePolicy = policy
        if !Defaults[.enableStatsFeature] { resumeBackgroundAfterUnlock = false }
        if policy.isLocked && isMonitoring { resumeBackgroundAfterUnlock = true }
        let wasSampling = isMonitoring || (!policy.isLocked && resumeBackgroundAfterUnlock)
        if !policy.isLocked { resumeBackgroundAfterUnlock = false }
        if policy.shouldSampleStats(enabled: Defaults[.enableStatsFeature],
                                    keepInBackground: !Defaults[.statsStopWhenNotchCloses],
                                    alreadySampling: wasSampling) {
            if !isMonitoring { startMonitoring() }
            else { scheduleMonitoringTimer() }
        } else { stopMonitoring() }
    }

    func startMonitoring() {
        guard !isMonitoring, runtimePolicy.shouldSampleStats(
            enabled: Defaults[.enableStatsFeature], keepInBackground: !Defaults[.statsStopWhenNotchCloses], alreadySampling: true
        ) else { return }
        monitoringGeneration = UUID()
        processRefreshGeneration = UUID()
        snapshot.resetSession()
        isMonitoring = true
        scheduleMonitoringTimer()
        refresh()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        monitoringTimer?.invalidate(); monitoringTimer = nil; scheduledInterval = nil
        monitoringGeneration = UUID()
        samplingTask?.cancel(); samplingTask = nil; sampleRequested = false
        processRefreshGeneration = UUID()
        processRefreshTask?.cancel(); processRefreshTask = nil
        isMonitoring = false
        cachedProcessStats.removeAll(); topCPUProcesses = []
        lastProcessStatsUpdate = .distantPast; isProcessRefreshInFlight = false
        lastDiskDevicesUpdate = .distantPast; diskDevices = []
        snapshot.resetSession()
    }

    private func scheduleMonitoringTimer() {
        let configured = Defaults[.statsUpdateInterval]
        let validated = validatedUpdateInterval(configured)
        if !configured.isFinite || abs(validated - configured) > 0.0001 { Defaults[.statsUpdateInterval] = validated }
        let interval = runtimePolicy.statsInterval(configured: validated)
        guard scheduledInterval != interval || monitoringTimer == nil else { return }
        monitoringTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // This timer is registered only on the main run loop. Request the
            // work synchronously so nested tracking loops need not drain a Task.
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Continue requesting background work during Cocoa control tracking.
        // https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/RunLoopManagement/RunLoopManagement.html
        RunLoop.main.add(timer, forMode: .common)
        monitoringTimer = timer; scheduledInterval = interval
    }

    private func handleUpdateIntervalChange(_ newValue: Double) {
        let validated = validatedUpdateInterval(newValue)
        if !newValue.isFinite || abs(validated - newValue) > 0.0001 {
            Defaults[.statsUpdateInterval] = validated
            return
        }
        guard isMonitoring else { return }
        Task { @MainActor [weak self] in self?.scheduleMonitoringTimer() }
    }

    private func validatedUpdateInterval(_ value: Double) -> TimeInterval {
        value.isFinite ? min(60, max(1, value)) : 1
    }

    /// At most one sample is pending; extra requests become one follow-up.
    func refresh() {
        guard isMonitoring else { return }
        refreshDiskDevicesIfNeeded()
        refreshProcessStatsIfNeeded()
        guard samplingTask == nil else { sampleRequested = true; return }
        let generation = monitoringGeneration
        let revision = historyRevision
        let demand = samplingDemand
        let sampler = self.sampler
        samplingTask = Task.detached(priority: .utility) { [weak self] in
            guard let self, !Task.isCancelled else { return }
            let result = await sampler.sample(demand: demand, generation: generation, historyRevision: revision)
            guard !Task.isCancelled else { return }
            await self.finishSample(result, generation: generation, revision: revision, demand: demand)
        }
    }

    private func finishSample(_ result: StatsSnapshot?, generation: UUID, revision: UInt64,
                              demand: StatsSamplingDemand) {
        guard isMonitoring, monitoringGeneration == generation else { return }
        samplingTask = nil
        if demand == samplingDemand, revision == historyRevision, let result {
            self.snapshot = result
        } else if demand != samplingDemand || revision != historyRevision {
            sampleRequested = true
        }
        if sampleRequested {
            sampleRequested = false
            refresh()
        }
    }

    func clearHistory() {
        historyRevision &+= 1
        snapshot.clearHistory()
        refresh()
    }

    private func refreshDiskDevicesIfNeeded() {
        guard isMonitoring, samplingDemand.diskDetails,
              Date().timeIntervalSince(lastDiskDevicesUpdate) >= diskDevicesUpdateInterval,
              !isDiskDevicesRefreshInFlight else { return }
        isDiskDevicesRefreshInFlight = true
        let generation = monitoringGeneration
        Task.detached(priority: .utility) { [weak self] in
            guard let owner = self else { return }
            let devices = StatsManager.collectDiskDevices()
            await MainActor.run {
                owner.isDiskDevicesRefreshInFlight = false
                guard owner.isMonitoring, owner.monitoringGeneration == generation else {
                    owner.refreshDiskDevicesIfNeeded()
                    return
                }
                owner.lastDiskDevicesUpdate = Date()
                guard owner.samplingDemand.diskDetails, let devices, owner.diskDevices != devices else { return }
                owner.diskDevices = devices
            }
        }
    }

    nonisolated private static func collectDiskDevices() -> [DiskDeviceMetrics]? {
        // The plain available capacity is cheap; the important/opportunistic
        // figures make the system size purgeable space, so they are read only
        // for a volume that does not report the plain one.
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsRootFileSystemKey,
            .volumeIsRemovableKey,
            .volumeIsLocalKey
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsLocalKey], options: [.skipHiddenVolumes]) else {
            return nil
        }
        var devices: [DiskDeviceMetrics] = []
        for url in urls {
            guard (try? url.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal == true else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            guard values.volumeIsLocal == true else { continue }
            guard let totalCapacity = values.volumeTotalCapacity.flatMap({ Int64($0) }), totalCapacity > 0 else { continue }
            let name = values.volumeName ?? url.lastPathComponent
            let freeCapacityValue: Int64
            if let free = values.volumeAvailableCapacity {
                freeCapacityValue = Int64(free)
            } else if let fallback = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityForOpportunisticUsageKey]) {
                freeCapacityValue = fallback.volumeAvailableCapacityForImportantUsage
                    ?? fallback.volumeAvailableCapacityForOpportunisticUsage ?? 0
            } else {
                freeCapacityValue = 0
            }
            let clampedFree = max(freeCapacityValue, 0)
            let device = DiskDeviceMetrics(
                id: url.path,
                name: name,
                path: url,
                totalBytes: UInt64(totalCapacity),
                freeBytes: UInt64(clampedFree),
                isRoot: values.volumeIsRootFileSystem ?? false,
                isRemovable: values.volumeIsRemovable ?? false
            )
            devices.append(device)
        }
        return devices.sorted { lhs, rhs in
            if lhs.isRoot != rhs.isRoot {
                return lhs.isRoot
            }
            if lhs.isRemovable != rhs.isRemovable {
                return !lhs.isRemovable
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Computed Properties for UI
    var cpuUsageString: String {
        return String(format: "%.1f%%", cpuUsage)
    }
    
    var memoryUsageString: String {
        return String(format: "%.1f%%", memoryUsage)
    }
    
    var gpuUsageString: String {
        return String(format: "%.1f%%", gpuUsage)
    }
    
    var networkDownloadString: String {
        StatsFormatting.throughput(networkDownload)
    }
    
    var networkUploadString: String {
        StatsFormatting.throughput(networkUpload)
    }
    
    var diskReadString: String {
        return String(format: "%.1f MB/s", diskRead)
    }
    
    var diskWriteString: String {
        return String(format: "%.1f MB/s", diskWrite)
    }
    
    var maxCpuUsage: Double {
        return cpuHistory.max() ?? 0.0
    }
    
    var maxMemoryUsage: Double {
        return memoryHistory.max() ?? 0.0
    }
    
    var maxGpuUsage: Double {
        return gpuHistory.max() ?? 0.0
    }
    
    var avgCpuUsage: Double {
        let nonZeroValues = cpuHistory.filter { $0 > 0 }
        guard !nonZeroValues.isEmpty else { return 0.0 }
        return nonZeroValues.reduce(0, +) / Double(nonZeroValues.count)
    }
    
    var avgMemoryUsage: Double {
        let nonZeroValues = memoryHistory.filter { $0 > 0 }
        guard !nonZeroValues.isEmpty else { return 0.0 }
        return nonZeroValues.reduce(0, +) / Double(nonZeroValues.count)
    }
    
    var avgGpuUsage: Double {
        let nonZeroValues = gpuHistory.filter { $0 > 0 }
        guard !nonZeroValues.isEmpty else { return 0.0 }
        return nonZeroValues.reduce(0, +) / Double(nonZeroValues.count)
    }
    
    // MARK: - Process Monitoring Methods
    @MainActor
    func getProcessesRankedByCPU() -> [ProcessStats] {
        refreshProcessStatsIfNeeded()
        return cachedProcessStats.sorted { $0.cpuUsage > $1.cpuUsage }
    }
    
    @MainActor
    func getProcessesRankedByMemory() -> [ProcessStats] {
        refreshProcessStatsIfNeeded()
        return cachedProcessStats.sorted { $0.memoryUsage > $1.memoryUsage }
    }
    
    @MainActor
    func getProcessesRankedByGPU() -> [ProcessStats] {
        // For now, rank by CPU usage as GPU per-process stats are complex to obtain
        refreshProcessStatsIfNeeded()
        return cachedProcessStats.sorted { $0.cpuUsage > $1.cpuUsage }
    }
    
    @MainActor
    private func refreshProcessStatsIfNeeded() {
        guard isMonitoring, samplingDemand.processes else { return }
        let now = Date()
        guard now.timeIntervalSince(lastProcessStatsUpdate) >= processStatsUpdateInterval else { return }
        guard !isProcessRefreshInFlight else { return }

        isProcessRefreshInFlight = true
        let generation = processRefreshGeneration
        let limit = maxProcessEntries
        processRefreshTask = Task.detached { [weak self] in
            guard let self else { return }
            let processes = await StatsManager.collectTopProcesses(limit: limit)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.processRefreshGeneration == generation, self.isMonitoring, self.samplingDemand.processes else { return }
                self.processRefreshTask = nil
                self.cachedProcessStats = processes
                self.lastProcessStatsUpdate = Date()
                self.isProcessRefreshInFlight = false
                self.topCPUProcesses = processes
            }
        }
    }

    nonisolated private static func collectTopProcesses(limit: Int) async -> [ProcessStats] {
        guard limit > 0 else { return [] }

        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-Aceo", "pid,pcpu,comm", "-r"]

        guard let result = try? await ProcessRunner.capture(task, timeout: 3, limit: 2 * 1024 * 1024),
              result.outcome == .exited(0), !result.truncated,
              let output = String(data: result.output, encoding: .utf8), !output.isEmpty else { return [] }

        var results: [ProcessStats] = []

        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > 1 else { return [] }

        for line in lines.dropFirst() {
            guard let parsed = parseProcessLine(String(line)) else { continue }
            let (pid, cpuUsage, command) = parsed
            let (displayName, icon) = runningApplicationInfo(for: pid, fallbackCommand: command)
            let memoryUsage = residentMemory(for: pid)

            let process = ProcessStats(
                pid: pid,
                name: displayName,
                cpuUsage: cpuUsage,
                memoryUsage: memoryUsage,
                icon: icon
            )

            results.append(process)
            if results.count >= limit { break }
        }

        return results
    }

    nonisolated private static func parseProcessLine(_ rawLine: String) -> (pid_t, Double, String)? {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let scanner = Scanner(string: trimmed)
        scanner.charactersToBeSkipped = .whitespaces

          guard let pidToken = scanner.scanCharacters(from: .decimalDigits),
              let pidValue = Int32(pidToken) else { return nil }

          let cpuCharacterSet = CharacterSet(charactersIn: "0123456789.,")
          guard let cpuToken = scanner.scanCharacters(from: cpuCharacterSet) else { return nil }
        let normalizedCPU = cpuToken.replacingOccurrences(of: ",", with: ".")
        guard let cpuValue = Double(normalizedCPU), cpuValue.isFinite, cpuValue >= 0 else { return nil }
        _ = scanner.scanCharacters(from: .whitespaces)
        let remainingIndex = scanner.currentIndex
        let command = String(trimmed[remainingIndex...]).trimmingCharacters(in: .whitespaces)

        return (pidValue, cpuValue, command.isEmpty ? "Unknown" : command)
    }

    nonisolated private static func runningApplicationInfo(for pid: pid_t, fallbackCommand: String) -> (String, NSImage?) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ((name?.isEmpty ?? true) ? fallbackCommand : name!, app.icon)
        }
        return (fallbackCommand, nil)
    }

    nonisolated private static func residentMemory(for pid: pid_t) -> UInt64 {
        var taskInfo = proc_taskinfo()
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size))
        guard result == MemoryLayout<proc_taskinfo>.size else { return 0 }
        return taskInfo.pti_resident_size
    }
}
