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

/// Graphs request basic readings; popovers request their additional detail.
struct StatsSamplingDemand: Equatable, Sendable {
    var cpu = false
    var memory = false
    var gpu = false
    var network = false
    var disk = false
    var cpuDetails = false
    var networkDetails = false
    var diskDetails = false
    var processes = false
}

/// One coherent publication per sample, rather than one per metric mutation.
struct StatsSnapshot: Equatable {
    var cpuUsage: Double = 0.0
    var memoryUsage: Double = 0.0
    var gpuUsage: Double = 0.0
    var networkDownload: Double = 0.0 // MB/s
    var networkUpload: Double = 0.0   // MB/s
    var diskRead: Double = 0.0        // MB/s
    var diskWrite: Double = 0.0       // MB/s
    var lastUpdated: Date = .distantPast
    var cpuBreakdown: CPULoadBreakdown = .zero
    var cpuLoadAverage: LoadAverage = .zero
    var cpuCoreUsage: [CPUCoreUsage] = []
    var cpuUptime: TimeInterval = 0
    var cpuTemperature: CPUTemperatureMetrics = CPUTemperatureMetrics(celsius: nil)
    var cpuFrequency: CPUFrequencyMetrics?
    var memoryBreakdown: MemoryBreakdown = .zero
    var gpuBreakdown: GPUBreakdown = .zero
    var gpuDevices: [GPUDeviceMetrics] = []
    var networkTotals: NetworkTotals = .zero
    var diskTotals: DiskTotals = .zero
    var networkInterfaces: [NetworkInterfaceMetrics] = []
    var cpuHistory: [Double] = Array(repeating: 0, count: 30)
    var memoryHistory: [Double] = Array(repeating: 0, count: 30)
    var gpuHistory: [Double] = Array(repeating: 0, count: 30)
    var networkDownloadHistory: [Double] = Array(repeating: 0, count: 30)
    var networkUploadHistory: [Double] = Array(repeating: 0, count: 30)
    var diskReadHistory: [Double] = Array(repeating: 0, count: 30)
    var diskWriteHistory: [Double] = Array(repeating: 0, count: 30)

    mutating func clearHistory() {
        cpuHistory = Array(repeating: 0, count: 30)
        memoryHistory = cpuHistory; gpuHistory = cpuHistory
        networkDownloadHistory = cpuHistory; networkUploadHistory = cpuHistory
        diskReadHistory = cpuHistory; diskWriteHistory = cpuHistory
    }

    mutating func resetSession() {
        networkTotals = .zero; diskTotals = .zero
        cpuCoreUsage = []; networkInterfaces = []
        cpuTemperature = CPUTemperatureMetrics(celsius: nil)
        cpuFrequency = nil
    }
}

protocol StatsSampling: Sendable {
    func sample(demand: StatsSamplingDemand, generation: UUID, historyRevision: UInt64) async -> StatsSnapshot?
}
