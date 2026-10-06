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

final class GPUInfoCollector {
    func collectDevices() -> [GPUDeviceMetrics] {
        var devices: [GPUDeviceMetrics] = []
        let matching = IOServiceMatching(kIOAcceleratorClassName)
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return devices
        }
        defer { IOObjectRelease(iterator) }
        var index = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let properties = copyProperties(for: service),
               let device = makeDevice(from: properties, index: index) {
                devices.append(device)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
            index += 1
        }
        return devices
    }

    private func copyProperties(for service: io_registry_entry_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return dict
    }

    private func makeDevice(from dict: [String: Any], index: Int) -> GPUDeviceMetrics? {
        guard let ioClass = dict["IOClass"] as? String else { return nil }
        let stats = dict["PerformanceStatistics"] as? [String: Any] ?? [:]
        let vendor = vendorName(from: ioClass) ?? (dict["vendor"] as? String)
        let model = sanitizedModel(primary: stats["model"] as? String,
                                   secondary: dict["model"] as? String,
                                   vendorFallback: vendor)
        let id = "\(model)#\(index + 1)"
        let utilization = percentValue(for: ["Device Utilization %", "GPU Activity(%)"], in: stats)
        let renderUtilization = percentValue(for: ["Renderer Utilization %"], in: stats)
        let tilerUtilization = percentValue(for: ["Tiler Utilization %"], in: stats)
        let temperature = numericValue(for: ["Temperature(C)", "temperature"], in: stats)
        let fanSpeed = intValue(for: ["Fan Speed(%)"], in: stats)
        let coreClock = intValue(for: ["Core Clock(MHz)"], in: stats)
        let memoryClock = intValue(for: ["Memory Clock(MHz)"], in: stats)
        let cores = (dict["gpu-core-count"] as? NSNumber)?.intValue ?? (dict["Cores"] as? Int)
        let isActive = isAcceleratorActive(from: dict)
        return GPUDeviceMetrics(
            id: id,
            vendor: vendor,
            model: model,
            isActive: isActive,
            utilization: utilization,
            renderUtilization: renderUtilization,
            tilerUtilization: tilerUtilization,
            temperature: temperature,
            fanSpeed: fanSpeed,
            coreClock: coreClock,
            memoryClock: memoryClock,
            cores: cores
        )
    }

    private func vendorName(from ioClass: String) -> String? {
        let value = ioClass.lowercased()
        if value.contains("nvidia") {
            return "NVIDIA"
        } else if value.contains("amd") {
            return "AMD"
        } else if value.contains("intel") {
            return "Intel"
        } else if value.contains("agx") || value.contains("apple") {
            return "Apple"
        }
        return nil
    }

    private func sanitizedModel(primary: String?, secondary: String?, vendorFallback: String?) -> String {
        let normalizedPrimary = normalizedString(primary)
        if let normalizedPrimary, !normalizedPrimary.isEmpty {
            return normalizedPrimary
        }
        let normalizedSecondary = normalizedString(secondary)
        if let normalizedSecondary, !normalizedSecondary.isEmpty {
            return normalizedSecondary
        }
        if let vendorFallback, !vendorFallback.isEmpty {
            return "\(vendorFallback) Graphics"
        }
        return "GPU"
    }

    private func normalizedString(_ raw: String?) -> String? {
        guard var value = raw else { return nil }
        value = value.replacingOccurrences(of: "\0", with: "")
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func percentValue(for keys: [String], in dict: [String: Any]) -> Double? {
        for key in keys {
            if let number = dict[key] as? NSNumber {
                return clampPercent(number.doubleValue)
            }
            if let value = dict[key] as? Double {
                return clampPercent(value)
            }
            if let value = dict[key] as? Int {
                return clampPercent(Double(value))
            }
        }
        return nil
    }

    private func numericValue(for keys: [String], in dict: [String: Any]) -> Double? {
        for key in keys {
            if let number = dict[key] as? NSNumber {
                return number.doubleValue
            }
            if let value = dict[key] as? Double {
                return value
            }
            if let value = dict[key] as? Int {
                return Double(value)
            }
        }
        return nil
    }

    private func intValue(for keys: [String], in dict: [String: Any]) -> Int? {
        for key in keys {
            if let number = dict[key] as? NSNumber {
                return number.intValue
            }
            if let value = dict[key] as? Int {
                return value
            }
        }
        return nil
    }

    private func isAcceleratorActive(from dict: [String: Any]) -> Bool {
        guard let agcInfo = dict["AGCInfo"] as? [String: Any] else {
            return true
        }
        if let poweredOff = agcInfo["poweredOffByAGC"] as? NSNumber {
            return poweredOff.intValue == 0
        }
        if let poweredOff = agcInfo["poweredOffByAGC"] as? Int {
            return poweredOff == 0
        }
        return true
    }

    private func clampPercent(_ value: Double) -> Double {
        return min(max(value, 0), 100)
    }
}
