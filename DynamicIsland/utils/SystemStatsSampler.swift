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
import IOKit
import IOKit.graphics
import Darwin

/// Owns hardware handles and counter baselines away from MainActor.
/// Actor isolation keeps stateful IOReport / Mach reads serialized.
/// https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/#Actors
actor SystemStatsSampler: StatsSampling {
    /// Cached host port to avoid leaking Mach send rights.
    /// Every call to `mach_host_self()` acquires a new send right that must be
    /// explicitly deallocated; caching it once prevents port exhaustion over time.
    private let hostPort: mach_port_t = mach_host_self()
    private let totalPhysicalMemory: UInt64 = {
        var stats = host_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let initHostPort = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_info(initHostPort, HOST_BASIC_INFO, $0, &count)
            }
        }
        mach_port_deallocate(mach_task_self_, initHostPort)
        if result == KERN_SUCCESS {
            return UInt64(stats.max_mem)
        }
        return UInt64(ProcessInfo.processInfo.physicalMemory)
    }()


    private var snapshot = StatsSnapshot()
    private var generation: UUID?
    private var historyRevision: UInt64 = 0
    private var previousNetworkStats: (bytesIn: UInt64, bytesOut: UInt64)?
    private var previousNetworkTimestamp: Date?
    private var previousDiskStats: (bytesRead: UInt64, bytesWritten: UInt64)?
    private var previousDiskTimestamp: Date?
    private var previousCPULoadInfo: host_cpu_load_info?
    private var previousCpuInfo: processor_info_array_t?
    private var previousCpuInfoCount: mach_msg_type_number_t = 0
    private var processorCount: natural_t = 0
    private var previousInterfaceCounters: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var interfaceTotals: [String: NetworkTotals] = [:]
    private let gpuCollector = GPUInfoCollector()
    private var cpuSensorCollector: CPUSensorCollector?
    private let maxHistoryPoints = 30

    deinit {
        if let previousCpuInfo {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: previousCpuInfo),
                          vm_size_t(previousCpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }
        mach_port_deallocate(mach_task_self_, hostPort)
    }

    func sample(demand: StatsSamplingDemand, generation: UUID, historyRevision: UInt64) -> StatsSnapshot? {
        guard !Task.isCancelled else { return nil }
        if self.generation != generation {
            resetSession()
            self.generation = generation
        }
        if self.historyRevision != historyRevision {
            snapshot.clearHistory()
            self.historyRevision = historyRevision
        }
        var next = snapshot
        if demand.cpu {
            next.cpuBreakdown = getCPULoadBreakdown()
            next.cpuUsage = next.cpuBreakdown.activeUsage
            updateHistory(value: next.cpuUsage, history: &next.cpuHistory)
        } else {
            previousCPULoadInfo = nil
        }
        if demand.memory {
            let memory = getMemorySnapshot()
            next.memoryUsage = memory.usage
            next.memoryBreakdown = memory.breakdown
            updateHistory(value: memory.usage, history: &next.memoryHistory)
        }
        if demand.gpu {
            let gpu = getGPUMetrics()
            next.gpuUsage = gpu.usage
            next.gpuBreakdown = gpu.breakdown
            next.gpuDevices = gpu.devices
            updateHistory(value: gpu.usage, history: &next.gpuHistory)
        }
        if demand.cpuDetails {
            next.cpuCoreUsage = collectCPUCoreUsage()
            next.cpuLoadAverage = getLoadAverage()
            next.cpuUptime = ProcessInfo.processInfo.systemUptime
            if cpuSensorCollector == nil { cpuSensorCollector = CPUSensorCollector() }
            next.cpuTemperature = cpuSensorCollector!.readTemperature()
            if let frequency = cpuSensorCollector!.readFrequency() { next.cpuFrequency = frequency }
        } else {
            releaseCoreBaseline()
            cpuSensorCollector?.resetFrequencySample()
        }
        if demand.network {
            let counters = getNetworkStats()
            let now = Date()
            let interval = previousNetworkTimestamp.map { now.timeIntervalSince($0) } ?? 0
            let incoming = previousNetworkStats.map { counters.bytesIn >= $0.bytesIn ? counters.bytesIn - $0.bytesIn : 0 } ?? 0
            let outgoing = previousNetworkStats.map { counters.bytesOut >= $0.bytesOut ? counters.bytesOut - $0.bytesOut : 0 } ?? 0
            next.networkDownload = interval > 0.1 ? Double(incoming) / interval / 1_048_576 : 0
            next.networkUpload = interval > 0.1 ? Double(outgoing) / interval / 1_048_576 : 0
            next.networkTotals.downloadedMB += Double(incoming) / 1_048_576
            next.networkTotals.uploadedMB += Double(outgoing) / 1_048_576
            updateHistory(value: next.networkDownload, history: &next.networkDownloadHistory)
            updateHistory(value: next.networkUpload, history: &next.networkUploadHistory)
            if demand.networkDetails { next.networkInterfaces = collectNetworkInterfaces(deltaTime: interval) }
            else { previousInterfaceCounters.removeAll() }
            previousNetworkStats = counters; previousNetworkTimestamp = now
        } else {
            previousNetworkStats = nil; previousNetworkTimestamp = nil
            previousInterfaceCounters.removeAll()
        }
        if demand.disk {
            let counters = getDiskStats()
            let now = Date()
            let interval = previousDiskTimestamp.map { now.timeIntervalSince($0) } ?? 0
            let read = previousDiskStats.map { counters.bytesRead >= $0.bytesRead ? counters.bytesRead - $0.bytesRead : 0 } ?? 0
            let written = previousDiskStats.map { counters.bytesWritten >= $0.bytesWritten ? counters.bytesWritten - $0.bytesWritten : 0 } ?? 0
            next.diskRead = interval > 0.1 ? Double(read) / interval / 1_048_576 : 0
            next.diskWrite = interval > 0.1 ? Double(written) / interval / 1_048_576 : 0
            next.diskTotals.readMB += Double(read) / 1_048_576
            next.diskTotals.writtenMB += Double(written) / 1_048_576
            updateHistory(value: next.diskRead, history: &next.diskReadHistory)
            updateHistory(value: next.diskWrite, history: &next.diskWriteHistory)
            previousDiskStats = counters; previousDiskTimestamp = now
        } else {
            previousDiskStats = nil; previousDiskTimestamp = nil
        }
        next.lastUpdated = Date()
        guard !Task.isCancelled else { return nil }
        snapshot = next
        return next
    }

    private func releaseCoreBaseline() {
        if let previousCpuInfo {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: previousCpuInfo),
                          vm_size_t(previousCpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }
        previousCpuInfo = nil; previousCpuInfoCount = 0; processorCount = 0
    }

    private func resetSession() {
        releaseCoreBaseline()
        previousCPULoadInfo = nil
        previousNetworkStats = nil; previousNetworkTimestamp = nil
        previousDiskStats = nil; previousDiskTimestamp = nil
        previousInterfaceCounters.removeAll(); interfaceTotals.removeAll()
        cpuSensorCollector?.resetFrequencySample()
        snapshot.resetSession()
    }

    private func updateHistory(value: Double, history: inout [Double]) {
        // Remove first element and append new value
        if history.count >= maxHistoryPoints {
            history.removeFirst()
        }
        history.append(value)
    }

    private func getCPULoadBreakdown() -> CPULoadBreakdown {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return snapshot.cpuBreakdown
        }

        let clamped: (Double) -> Double = { value in
            return min(max(value, 0), 100)
        }

        let breakdown: CPULoadBreakdown

        if let previous = previousCPULoadInfo {
            let userDiff = Double(info.cpu_ticks.0 - previous.cpu_ticks.0)
            let systemDiff = Double(info.cpu_ticks.1 - previous.cpu_ticks.1)
            let idleDiff = Double(info.cpu_ticks.2 - previous.cpu_ticks.2)
            let niceDiff = Double(info.cpu_ticks.3 - previous.cpu_ticks.3)
            let total = userDiff + systemDiff + idleDiff + niceDiff

            if total > 0 {
                let userPercent = ((userDiff + niceDiff) / total) * 100
                let systemPercent = (systemDiff / total) * 100
                let idlePercent = (idleDiff / total) * 100
                breakdown = CPULoadBreakdown(
                    user: clamped(userPercent),
                    system: clamped(systemPercent),
                    idle: clamped(idlePercent)
                )
            } else {
                breakdown = snapshot.cpuBreakdown
            }
        } else {
            let totalTicks = Double(info.cpu_ticks.0 + info.cpu_ticks.1 + info.cpu_ticks.2 + info.cpu_ticks.3)
            if totalTicks > 0 {
                let userPercent = ((Double(info.cpu_ticks.0) + Double(info.cpu_ticks.3)) / totalTicks) * 100
                let systemPercent = (Double(info.cpu_ticks.1) / totalTicks) * 100
                let idlePercent = (Double(info.cpu_ticks.2) / totalTicks) * 100
                breakdown = CPULoadBreakdown(
                    user: clamped(userPercent),
                    system: clamped(systemPercent),
                    idle: clamped(idlePercent)
                )
            } else {
                breakdown = snapshot.cpuBreakdown
            }
        }

        previousCPULoadInfo = info
        return breakdown
    }

    private func getLoadAverage() -> LoadAverage {
        var loads = [Double](repeating: 0, count: 3)
        let result = loads.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return getloadavg(baseAddress, 3)
        }
        guard result == 3 else {
            return snapshot.cpuLoadAverage
        }
        return LoadAverage(oneMinute: loads[0], fiveMinutes: loads[1], fifteenMinutes: loads[2])
    }

    private func getMemorySnapshot() -> (usage: Double, breakdown: MemoryBreakdown) {
        // Memory usage monitoring using host_statistics64
        var vmStatistics = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let vmResult = withUnsafeMutablePointer(to: &vmStatistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &size)
            }
        }

        guard vmResult == KERN_SUCCESS else {
            return (snapshot.memoryUsage, snapshot.memoryBreakdown)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let freeBytes = UInt64(vmStatistics.free_count) * pageSize
        let speculativeBytes = UInt64(vmStatistics.speculative_count) * pageSize
        let activeBytes = UInt64(vmStatistics.active_count) * pageSize
        let inactiveBytes = UInt64(vmStatistics.inactive_count) * pageSize
        let wiredBytes = UInt64(vmStatistics.wire_count) * pageSize
        let compressedBytes = UInt64(vmStatistics.compressor_page_count) * pageSize
        let purgeableBytes = UInt64(vmStatistics.purgeable_count) * pageSize
        let externalBytes = UInt64(vmStatistics.external_page_count) * pageSize

        let totalMemoryBytes: UInt64
        if totalPhysicalMemory > 0 {
            totalMemoryBytes = totalPhysicalMemory
        } else {
            totalMemoryBytes = freeBytes + speculativeBytes + activeBytes + inactiveBytes + wiredBytes + compressedBytes
        }
        guard totalMemoryBytes > 0 else {
            return (0.0, .zero)
        }

        let usedWithoutCache = activeBytes + inactiveBytes + speculativeBytes + wiredBytes + compressedBytes
        let cacheBytes = purgeableBytes + externalBytes
        let usedBytes = usedWithoutCache > cacheBytes ? usedWithoutCache - cacheBytes : 0
        let clampedUsedBytes = min(usedBytes, totalMemoryBytes)
        let freeComputedBytes = totalMemoryBytes > clampedUsedBytes ? totalMemoryBytes - clampedUsedBytes : 0
        let nonAppBytes = wiredBytes + compressedBytes
        let appBytes = clampedUsedBytes > nonAppBytes ? clampedUsedBytes - nonAppBytes : 0

        var pressureLevelRaw: Int32 = 0
        var pressureSize = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevelRaw, &pressureSize, nil, 0)
        let pressureLevel: MemoryPressureLevel
        switch pressureLevelRaw {
        case 2:
            pressureLevel = .warning
        case 4:
            pressureLevel = .critical
        default:
            pressureLevel = .normal
        }
        let pressure = MemoryPressure(rawValue: Int(pressureLevelRaw), level: pressureLevel)

        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0)
        let swapInfo = MemorySwap(
            totalBytes: UInt64(swapUsage.xsu_total),
            usedBytes: UInt64(swapUsage.xsu_used),
            freeBytes: UInt64(swapUsage.xsu_avail)
        )

        let usage = Double(clampedUsedBytes) / Double(totalMemoryBytes) * 100.0
        let breakdown = MemoryBreakdown(
            totalBytes: totalMemoryBytes,
            usedBytes: clampedUsedBytes,
            freeBytes: freeComputedBytes,
            wiredBytes: wiredBytes,
            activeBytes: activeBytes,
            inactiveBytes: inactiveBytes,
            compressedBytes: compressedBytes,
            appBytes: appBytes,
            cacheBytes: cacheBytes,
            swap: swapInfo,
            pressure: pressure
        )

        return (min(100.0, max(0.0, usage)), breakdown)
    }

    private func getGPUMetrics() -> GPUMetricsSnapshot {
        let devices = gpuCollector.collectDevices()
        guard !devices.isEmpty else {
            return .zero
        }
        let utilizationValues = devices.compactMap { $0.utilization }
        let usage: Double
        if utilizationValues.isEmpty {
            usage = 0
        } else {
            usage = utilizationValues.reduce(0, +) / Double(utilizationValues.count)
        }
        let breakdown = makeGPUBreakdown(from: devices)
        return GPUMetricsSnapshot(usage: usage, breakdown: breakdown, devices: devices)
    }

    private func makeGPUBreakdown(from devices: [GPUDeviceMetrics]) -> GPUBreakdown {
        guard let primary = devices.first(where: { ($0.utilization ?? 0) > 0 || ($0.renderUtilization ?? 0) > 0 || ($0.tilerUtilization ?? 0) > 0 }) else {
            return .zero
        }
        let fallbackTotal = max((primary.renderUtilization ?? 0) + (primary.tilerUtilization ?? 0), 0)
        let total = max(primary.utilization ?? fallbackTotal, 0)
        if total.isZero {
            return GPUBreakdown(
                render: primary.renderUtilization ?? 0,
                compute: primary.tilerUtilization ?? 0,
                video: 0,
                other: 0
            )
        }
        let render = min(primary.renderUtilization ?? 0, total)
        let tiler = min(primary.tilerUtilization ?? 0, max(total - render, 0))
        let remaining = max(total - render - tiler, 0)
        let compute = remaining * 0.6
        let video = remaining * 0.25
        let other = max(remaining - compute - video, 0)
        return GPUBreakdown(render: render, compute: compute, video: video, other: other)
    }

    private func collectCPUCoreUsage() -> [CPUCoreUsage] {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCPUsU: natural_t = 0
        let result = host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo)
        guard result == KERN_SUCCESS, let cpuInfo else {
            return snapshot.cpuCoreUsage
        }
        let cpuCount = Int(numCPUsU)
        var usages: [CPUCoreUsage] = []
        usages.reserveCapacity(cpuCount)
        let cpuStateMax = Int(CPU_STATE_MAX)
        if let previousCpuInfo, previousCpuInfoCount >= numCpuInfo {
            for cpu in 0..<cpuCount {
                let base = cpu * cpuStateMax
                let user = cpuInfo[base + Int(CPU_STATE_USER)] - previousCpuInfo[base + Int(CPU_STATE_USER)]
                let system = cpuInfo[base + Int(CPU_STATE_SYSTEM)] - previousCpuInfo[base + Int(CPU_STATE_SYSTEM)]
                let nice = cpuInfo[base + Int(CPU_STATE_NICE)] - previousCpuInfo[base + Int(CPU_STATE_NICE)]
                let idle = cpuInfo[base + Int(CPU_STATE_IDLE)] - previousCpuInfo[base + Int(CPU_STATE_IDLE)]
                let inUse = user + system + nice
                let total = inUse + idle
                let percent = total > 0 ? Double(inUse) / Double(total) : 0
                usages.append(CPUCoreUsage(id: cpu, usage: max(0, min(percent * 100, 100))))
            }
        } else {
            for cpu in 0..<cpuCount {
                let base = cpu * cpuStateMax
                let user = cpuInfo[base + Int(CPU_STATE_USER)]
                let system = cpuInfo[base + Int(CPU_STATE_SYSTEM)]
                let nice = cpuInfo[base + Int(CPU_STATE_NICE)]
                let idle = cpuInfo[base + Int(CPU_STATE_IDLE)]
                let inUse = user + system + nice
                let total = inUse + idle
                let percent = total > 0 ? Double(inUse) / Double(total) : 0
                usages.append(CPUCoreUsage(id: cpu, usage: max(0, min(percent * 100, 100))))
            }
        }
        if let previousCpuInfo {
            let size = vm_size_t(previousCpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: previousCpuInfo), size)
        }
        previousCpuInfo = cpuInfo
        previousCpuInfoCount = numCpuInfo
        processorCount = numCPUsU
        return usages
    }

    private func collectNetworkInterfaces(deltaTime: TimeInterval) -> [NetworkInterfaceMetrics] {
        var interfacesPointer: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&interfacesPointer) == 0, let startPointer = interfacesPointer else {
            return snapshot.networkInterfaces
        }
        defer { freeifaddrs(startPointer) }
        struct InterfaceAccumulator {
            var name: String
            var flags: UInt32
            var bytesIn: UInt64
            var bytesOut: UInt64
            var ipv4: String?
            var ipv6: String?
        }
        var accumulators: [String: InterfaceAccumulator] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = startPointer
        while let current = pointer {
            let interface = current.pointee
            let name = String(cString: interface.ifa_name)
            var accumulator = accumulators[name] ?? InterfaceAccumulator(name: name, flags: interface.ifa_flags, bytesIn: 0, bytesOut: 0, ipv4: nil, ipv6: nil)
            if let addr = interface.ifa_addr {
                switch Int32(addr.pointee.sa_family) {
                case AF_LINK:
                    if let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                        accumulator.bytesIn = UInt64(data.pointee.ifi_ibytes)
                        accumulator.bytesOut = UInt64(data.pointee.ifi_obytes)
                    }
                case AF_INET:
                    accumulator.ipv4 = stringFromSockaddr(addr)
                case AF_INET6:
                    accumulator.ipv6 = stringFromSockaddr(addr)
                default:
                    break
                }
            }
            accumulators[name] = accumulator
            pointer = interface.ifa_next
        }
        var results: [NetworkInterfaceMetrics] = []
        var updatedCounters: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
        for accumulator in accumulators.values {
            guard shouldIncludeInterface(name: accumulator.name) else { continue }
            let previous = previousInterfaceCounters[accumulator.name] ?? (accumulator.bytesIn, accumulator.bytesOut)
            let deltaIn = accumulator.bytesIn >= previous.bytesIn ? accumulator.bytesIn - previous.bytesIn : 0
            let deltaOut = accumulator.bytesOut >= previous.bytesOut ? accumulator.bytesOut - previous.bytesOut : 0
            let speedDivider = max(deltaTime, 0.001)
            let downloadSpeed = Double(deltaIn) / speedDivider / 1_048_576
            let uploadSpeed = Double(deltaOut) / speedDivider / 1_048_576
            var totals = interfaceTotals[accumulator.name] ?? .zero
            totals.downloadedMB += Double(deltaIn) / 1_048_576
            totals.uploadedMB += Double(deltaOut) / 1_048_576
            interfaceTotals[accumulator.name] = totals
            let metrics = NetworkInterfaceMetrics(
                name: accumulator.name,
                displayName: interfaceDisplayName(for: accumulator.name),
                type: interfaceType(for: accumulator.name),
                ipv4: accumulator.ipv4,
                ipv6: accumulator.ipv6,
                isActive: interfaceIsActive(flags: accumulator.flags),
                currentDownload: max(downloadSpeed, 0),
                currentUpload: max(uploadSpeed, 0),
                totalDownloaded: totals.downloadedMB,
                totalUploaded: totals.uploadedMB
            )
            results.append(metrics)
            updatedCounters[accumulator.name] = (accumulator.bytesIn, accumulator.bytesOut)
        }
        previousInterfaceCounters = updatedCounters
        return results.sorted { lhs, rhs in
            if lhs.type == rhs.type {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return networkTypeSortOrder(lhs.type) < networkTypeSortOrder(rhs.type)
        }
    }

    private func stringFromSockaddr(_ addressPointer: UnsafePointer<sockaddr>?) -> String? {
        guard let addressPointer else { return nil }
        let family = Int32(addressPointer.pointee.sa_family)
        switch family {
        case AF_INET:
            var addr = addressPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            return String(cString: buffer)
        case AF_INET6:
            var addr = addressPointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
            return String(cString: buffer)
        default:
            return nil
        }
    }

    private func shouldIncludeInterface(name: String) -> Bool {
        guard !name.hasPrefix("lo"),
              !name.hasPrefix("gif"),
              !name.hasPrefix("stf"),
              !name.hasPrefix("awdl"),
              !name.hasPrefix("llw"),
              !name.hasPrefix("utun"),
              !name.hasPrefix("p2p") else {
            return false
        }
        return true
    }

    private func interfaceIsActive(flags: UInt32) -> Bool {
        let isUp = (flags & UInt32(IFF_UP)) == UInt32(IFF_UP)
        let isRunning = (flags & UInt32(IFF_RUNNING)) == UInt32(IFF_RUNNING)
        return isUp && isRunning
    }

    private func interfaceDisplayName(for name: String) -> String {
        if name.hasPrefix("en") {
            return name == "en0" ? "Wi-Fi" : "Ethernet"
        }
        if name.hasPrefix("bridge") {
            return "Bridge"
        }
        if name.hasPrefix("pd") {
            return "USB"
        }
        if name.hasPrefix("vmnet") {
            return "Virtual"
        }
        if name.hasPrefix("ap") {
            return "Hotspot"
        }
        if name.hasPrefix("awdl") {
            return "AirDrop"
        }
        return name.uppercased()
    }

    private func interfaceType(for name: String) -> NetworkInterfaceType {
        if name.hasPrefix("en") {
            if name == "en0" {
                return .wifi
            }
            return .ethernet
        }
        if name.hasPrefix("bridge") || name.hasPrefix("vmnet") {
            return .ethernet
        }
        if name.hasPrefix("ap") {
            return .wifi
        }
        if name.hasPrefix("pdp_ip") {
            return .cellular
        }
        if name.hasPrefix("lo") {
            return .loopback
        }
        return .other
    }

    private func networkTypeSortOrder(_ type: NetworkInterfaceType) -> Int {
        switch type {
        case .wifi:
            return 0
        case .ethernet:
            return 1
        case .cellular:
            return 2
        case .other:
            return 3
        case .loopback:
            return 4
        }
    }

    private func getNetworkStats() -> (bytesIn: UInt64, bytesOut: UInt64) {
        // Use BSD sockets to get network interface statistics
        var totalBytesIn: UInt64 = 0
        var totalBytesOut: UInt64 = 0

        var ifaddrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrs) == 0 else {
            return (totalBytesIn, totalBytesOut)
        }

        defer { freeifaddrs(ifaddrs) }

        var ptr = ifaddrs
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee,
                  interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            // Skip loopback and virtual interfaces, but include en0, en1, etc. and Wi-Fi interfaces
            guard !name.hasPrefix("lo") &&
                  !name.hasPrefix("gif") &&
                  !name.hasPrefix("stf") &&
                  !name.hasPrefix("bridge") &&
                  !name.hasPrefix("utun") &&
                  !name.hasPrefix("awdl") else {
                continue
            }

            // Only count active interfaces (en0, en1, etc.)
            if name.hasPrefix("en") || name.contains("Wi-Fi") {
                if let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    totalBytesIn += UInt64(data.pointee.ifi_ibytes)
                    totalBytesOut += UInt64(data.pointee.ifi_obytes)
                }
            }
        }

        return (totalBytesIn, totalBytesOut)
    }

    private func getDiskStats() -> (bytesRead: UInt64, bytesWritten: UInt64) {
        // Use IOKit to get disk I/O statistics from IOStorage service
        var totalBytesRead: UInt64 = 0
        var totalBytesWritten: UInt64 = 0

        let matchingDict = IOServiceMatching("IOStorage")
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)

        guard result == KERN_SUCCESS else {
            return (totalBytesRead, totalBytesWritten)
        }

        defer { IOObjectRelease(iterator) }

        var service: io_registry_entry_t = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var properties: Unmanaged<CFMutableDictionary>?
            let propertiesResult = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)

            guard propertiesResult == KERN_SUCCESS,
                  let props = properties?.takeRetainedValue() as? [String: Any],
                  let statistics = props["Statistics"] as? [String: Any] else {
                continue
            }

            // Use the correct property names for APFS/modern filesystems
            if let bytesRead = statistics["Bytes read from block device"] as? UInt64 {
                totalBytesRead += bytesRead
            }

            if let bytesWritten = statistics["Bytes written to block device"] as? UInt64 {
                totalBytesWritten += bytesWritten
            }
        }

        return (totalBytesRead, totalBytesWritten)
    }
}
