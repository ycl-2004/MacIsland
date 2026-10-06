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

// Value types published by `StatsManager`: per-subsystem snapshots that
// the stats views render.

import Foundation

struct MemoryBreakdown: Equatable {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let freeBytes: UInt64
    let wiredBytes: UInt64
    let activeBytes: UInt64
    let inactiveBytes: UInt64
    let compressedBytes: UInt64
    let appBytes: UInt64
    let cacheBytes: UInt64
    let swap: MemorySwap
    let pressure: MemoryPressure

    static let zero = MemoryBreakdown(
        totalBytes: 0,
        usedBytes: 0,
        freeBytes: 0,
        wiredBytes: 0,
        activeBytes: 0,
        inactiveBytes: 0,
        compressedBytes: 0,
        appBytes: 0,
        cacheBytes: 0,
        swap: .zero,
        pressure: .unknown
    )

    var usedPercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }

    var freePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(freeBytes) / Double(totalBytes) * 100
    }

    var appPercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(appBytes) / Double(totalBytes) * 100
    }

    var cachePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(cacheBytes) / Double(totalBytes) * 100
    }
}

struct MemorySwap: Equatable {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let freeBytes: UInt64

    static let zero = MemorySwap(totalBytes: 0, usedBytes: 0, freeBytes: 0)
}

enum MemoryPressureLevel: String, Equatable {
    case normal
    case warning
    case critical
}

struct MemoryPressure: Equatable {
    let rawValue: Int
    let level: MemoryPressureLevel

    static let unknown = MemoryPressure(rawValue: 0, level: .normal)
}

struct CPUCoreUsage: Identifiable, Equatable {
    let id: Int
    let usage: Double
}

struct GPUBreakdown: Equatable {
    let render: Double
    let compute: Double
    let video: Double
    let other: Double

    static let zero = GPUBreakdown(render: 0, compute: 0, video: 0, other: 0)

    var totalUsage: Double {
        render + compute + video + other
    }
}

struct GPUMetricsSnapshot {
    let usage: Double
    let breakdown: GPUBreakdown
    let devices: [GPUDeviceMetrics]

    static let zero = GPUMetricsSnapshot(usage: 0, breakdown: .zero, devices: [])
}

enum NetworkInterfaceType: String {
    case wifi
    case ethernet
    case loopback
    case cellular
    case other
}

struct NetworkInterfaceMetrics: Identifiable, Equatable {
    let name: String
    let displayName: String
    let type: NetworkInterfaceType
    let ipv4: String?
    let ipv6: String?
    let isActive: Bool
    let currentDownload: Double
    let currentUpload: Double
    let totalDownloaded: Double
    let totalUploaded: Double

    var id: String { name }
}

struct DiskDeviceMetrics: Identifiable, Equatable {
    let id: String
    let name: String
    let path: URL
    let totalBytes: UInt64
    let freeBytes: UInt64
    let isRoot: Bool
    let isRemovable: Bool

    var usedBytes: UInt64 {
        totalBytes > freeBytes ? totalBytes - freeBytes : 0
    }

    var usagePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }
}

struct GPUDeviceMetrics: Identifiable, Equatable {
    let id: String
    let vendor: String?
    let model: String
    let isActive: Bool
    let utilization: Double?
    let renderUtilization: Double?
    let tilerUtilization: Double?
    let temperature: Double?
    let fanSpeed: Int?
    let coreClock: Int?
    let memoryClock: Int?
    let cores: Int?

    var formattedVendorModel: String {
        if let vendor {
            return vendor == model ? model : "\(vendor) \(model)".trimmingCharacters(in: .whitespaces)
        }
        return model
    }

    var utilizationText: String {
        guard let utilization else { return "—" }
        return StatsFormatting.percentage(utilization)
    }

    var temperatureText: String {
        guard let temperature else { return "—" }
        return String(format: "%.0f°C", temperature)
    }
}

struct NetworkTotals: Equatable {
    var downloadedMB: Double
    var uploadedMB: Double

    static let zero = NetworkTotals(downloadedMB: 0, uploadedMB: 0)
}

struct DiskTotals: Equatable {
    var readMB: Double
    var writtenMB: Double

    static let zero = DiskTotals(readMB: 0, writtenMB: 0)
}
