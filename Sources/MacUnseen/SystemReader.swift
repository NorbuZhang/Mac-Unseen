// SPDX-License-Identifier: MPL-2.0

import Darwin
import Foundation
import IOKit

enum SystemReader {
    static func readSystem(
        preserving previous: SystemSnapshot = SystemSnapshot(),
        includeStatic: Bool = true,
        includeDiskUsage: Bool = true
    ) -> SystemSnapshot {
        var snapshot = previous
        if includeStatic {
            snapshot.modelIdentifier = sysctlString("hw.model") ?? ""
            snapshot.modelName = modelDisplayName(for: snapshot.modelIdentifier)
            snapshot.chipName = sysctlString("machdep.cpu.brand_string") ?? ""
            snapshot.processorCount = ProcessInfo.processInfo.processorCount
            snapshot.memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
        }
        snapshot.memoryUsed = memoryUsed(total: snapshot.memoryTotal)
        snapshot.uptime = ProcessInfo.processInfo.systemUptime

        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 {
            snapshot.loadAverages = loads
        }

        if includeDiskUsage {
            if let values = try? URL(fileURLWithPath: "/").resourceValues(
                forKeys: [
                    .volumeTotalCapacityKey,
                    .volumeAvailableCapacityForImportantUsageKey,
                ]
            ) {
                let total = Double(values.volumeTotalCapacity ?? 0)
                let available = Double(
                    values.volumeAvailableCapacityForImportantUsage ?? 0
                )
                snapshot.diskTotal = total
                snapshot.diskUsed = max(0, total - available)
            }
        }

        snapshot.thermalState = switch ProcessInfo.processInfo.thermalState {
        case .nominal: "正常"
        case .fair: "轻度升温"
        case .serious: "较高"
        case .critical: "严重"
        @unknown default: "未知"
        }
        return snapshot
    }

    static func readBattery(
        preserving previous: BatterySnapshot = BatterySnapshot(),
        includeStatic: Bool = true,
        includeSlow: Bool = true
    ) -> BatterySnapshot {
        var snapshot = previous
        guard let matching = IOServiceMatching("AppleSmartBattery") else {
            return snapshot
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else {
            return snapshot
        }
        defer { IOObjectRelease(service) }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS,
        let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any]
        else {
            return snapshot
        }

        snapshot.percentage = validated(
            number("CurrentCapacity", in: properties),
            range: 0...100
        )
        snapshot.temperature = normalizedCurrentBatteryTemperature(
            number("Temperature", in: properties)
        )
        snapshot.voltage = validated(
            number("Voltage", in: properties).map { $0 / 1000.0 },
            range: 5...30
        )
        snapshot.amperage = validated(
            signedNumber("InstantAmperage", in: properties).map {
                $0 / 1000.0
            },
            range: -30...30
        )
        if includeSlow {
            snapshot.cycleCount = integer("CycleCount", in: properties)
        }
        if includeStatic {
            snapshot.designCapacity = batteryCapacity(
                "DesignCapacity", in: properties
            )
            snapshot.maximumCapacity = batteryCapacity(
                "NominalChargeCapacity", in: properties
            )
            snapshot.rawMaximumCapacity = batteryCapacity(
                "AppleRawMaxCapacity", in: properties
            )
            if snapshot.maximumCapacity == nil {
                snapshot.maximumCapacity = snapshot.rawMaximumCapacity
            }
        }
        snapshot.rawCurrentCapacity = batteryCapacity(
            "AppleRawCurrentCapacity", in: properties
        )
        snapshot.charging = bool("IsCharging", in: properties)
        snapshot.externalConnected = bool("ExternalConnected", in: properties)

        if let batteryData = dictionary("BatteryData", in: properties) {
            if includeStatic {
                if snapshot.designCapacity == nil {
                    snapshot.designCapacity = batteryCapacity(
                        "DesignCapacity",
                        in: batteryData
                    )
                }
                if snapshot.maximumCapacity == nil {
                    snapshot.maximumCapacity = batteryCapacity(
                        "NominalChargeCapacity",
                        in: batteryData
                    )
                }
                if snapshot.rawMaximumCapacity == nil {
                    snapshot.rawMaximumCapacity = batteryCapacity(
                        "AppleRawMaxCapacity",
                        in: batteryData
                    )
                }
            }
            snapshot.cellVoltages = numberArray("CellVoltage", in: batteryData)
                .map { $0 / 1000.0 }
                .filter { (2...5.5).contains($0) }
            if includeSlow {
                snapshot.cellResistance = numberArray(
                    "WeightedRa",
                    in: batteryData
                ).filter { (0...100_000).contains($0) }

                if let lifetime = dictionary("LifetimeData", in: batteryData) {
                    let rawMinimumTemperature = signedNumber(
                        "MinimumTemperature", in: lifetime
                    )
                    let rawMaximumTemperature = signedNumber(
                        "MaximumTemperature", in: lifetime
                    )
                    (
                        snapshot.historicalMinTemperature,
                        snapshot.historicalMaxTemperature
                    ) = normalizedHistoricalBatteryTemperatures(
                        minimum: rawMinimumTemperature,
                        maximum: rawMaximumTemperature
                    )
                    snapshot.historicalMaxChargeCurrent = validated(
                        signedNumber(
                            "MaximumChargeCurrent", in: lifetime
                        ).map { abs($0) / 1000.0 },
                        range: 0...50
                    )
                    snapshot.historicalMaxDischargeCurrent = validated(
                        signedNumber(
                            "MaximumDischargeCurrent", in: lifetime
                        ).map { abs($0) / 1000.0 },
                        range: 0...50
                    )
                }
            }
        }

        snapshot.adapterName = nil
        snapshot.adapterRatedWatts = nil
        snapshot.negotiatedVoltage = nil
        snapshot.negotiatedCurrent = nil
        snapshot.pdProfiles = []
        let adapter = dictionary("AdapterDetails", in: properties)
            ?? dictionary("AppleRawAdapterDetails", in: properties)
        if let adapter {
            snapshot.adapterName = adapter["Name"] as? String
            snapshot.adapterRatedWatts = validated(
                number("Watts", in: adapter),
                range: 0...500
            )
            snapshot.negotiatedVoltage = validated(
                number("AdapterVoltage", in: adapter).map {
                    $0 / 1000.0
                },
                range: 0...60
            )
            snapshot.negotiatedCurrent = validated(
                number("Current", in: adapter).map { $0 / 1000.0 },
                range: 0...15
            )
            if let profiles = adapter["UsbHvcMenu"] as? [[String: Any]] {
                snapshot.pdProfiles = profiles.compactMap { profile in
                    guard let voltage = validated(
                              number("MaxVoltage", in: profile),
                              range: 0...60_000
                          ),
                          let current = validated(
                              number("MaxCurrent", in: profile),
                              range: 0...15_000
                          )
                    else {
                        return nil
                    }
                    return String(
                        format: "%.0fV × %.2fA (%.0fW)",
                        voltage / 1000.0,
                        current / 1000.0,
                        voltage * current / 1_000_000.0
                    )
                }
            }
        }

        snapshot.liveInputPower = nil
        snapshot.liveInputVoltage = nil
        snapshot.liveInputCurrent = nil
        if let telemetry = dictionary("PowerTelemetryData", in: properties) {
            snapshot.liveInputPower = validated(
                number("SystemPowerIn", in: telemetry).map {
                    $0 / 1000.0
                },
                range: 0...1_000
            )
            snapshot.liveInputVoltage = validated(
                number("SystemVoltageIn", in: telemetry).map {
                    $0 / 1000.0
                },
                range: 0...60
            )
            snapshot.liveInputCurrent = validated(
                signedNumber("SystemCurrentIn", in: telemetry).map {
                    abs($0) / 1000.0
                },
                range: 0...30
            )
        }

        return snapshot
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        let bytes = buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func modelDisplayName(for identifier: String) -> String {
        if identifier == "Mac17,5" {
            return "MacBook Neo"
        }
        if identifier.hasPrefix("MacBookAir") {
            return "MacBook Air"
        }
        if identifier.hasPrefix("MacBookPro") {
            return "MacBook Pro"
        }
        if identifier.hasPrefix("Macmini") {
            return "Mac mini"
        }
        if identifier.hasPrefix("iMac") {
            return "iMac"
        }
        if identifier.hasPrefix("MacStudio") {
            return "Mac Studio"
        }
        return "Mac"
    }

    private static func normalizedCurrentBatteryTemperature(
        _ rawValue: Double?
    ) -> Double? {
        guard let rawValue, rawValue.isFinite else {
            return nil
        }
        let candidate: Double
        if (1_800...4_000).contains(rawValue) {
            candidate = rawValue / 10.0 - 273.15
        } else if (-40...100).contains(rawValue) {
            candidate = rawValue
        } else if (-400...1_000).contains(rawValue) {
            candidate = rawValue / 10.0
        } else {
            return nil
        }
        return (-30...100).contains(candidate) ? candidate : nil
    }

    private static func batteryCapacity(
        _ key: String,
        in dictionary: [String: Any]
    ) -> Double? {
        validated(number(key, in: dictionary), range: 0...30_000)
    }

    private static func validated(
        _ value: Double?,
        range: ClosedRange<Double>
    ) -> Double? {
        guard let value, value.isFinite, range.contains(value) else {
            return nil
        }
        return value
    }

    private static func normalizedHistoricalBatteryTemperatures(
        minimum: Double?,
        maximum: Double?
    ) -> (Double?, Double?) {
        guard let minimum, let maximum,
              minimum.isFinite, maximum.isFinite else {
            return (nil, nil)
        }
        for scale in [1.0, 0.1] {
            let scaledMinimum = minimum * scale
            let scaledMaximum = maximum * scale
            if (-40...80).contains(scaledMinimum),
               (-20...100).contains(scaledMaximum),
               scaledMinimum <= scaledMaximum {
                return (scaledMinimum, scaledMaximum)
            }
        }
        return (nil, nil)
    }

    private static func memoryUsed(total: Double) -> Double {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size
                / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) {
                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else {
            return 0
        }
        let freePages = UInt64(statistics.free_count + statistics.speculative_count)
        var pageSize: UInt64 = 0
        var pageSizeLength = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.pagesize", &pageSize, &pageSizeLength, nil, 0) != 0 {
            pageSize = 16_384
        }
        let freeBytes = Double(freePages) * Double(pageSize)
        return max(0, total - freeBytes)
    }

    private static func dictionary(
        _ key: String,
        in dictionary: [String: Any]
    ) -> [String: Any]? {
        if let value = dictionary[key] as? [String: Any] {
            return value
        }
        if let value = dictionary[key] as? NSDictionary {
            return value as? [String: Any]
        }
        return nil
    }

    private static func number(
        _ key: String,
        in dictionary: [String: Any]
    ) -> Double? {
        (dictionary[key] as? NSNumber)?.doubleValue
    }

    private static func signedNumber(
        _ key: String,
        in dictionary: [String: Any]
    ) -> Double? {
        guard let value = dictionary[key] as? NSNumber else {
            return nil
        }
        return Double(value.int64Value)
    }

    private static func integer(
        _ key: String,
        in dictionary: [String: Any]
    ) -> Int? {
        (dictionary[key] as? NSNumber)?.intValue
    }

    private static func bool(
        _ key: String,
        in dictionary: [String: Any]
    ) -> Bool {
        (dictionary[key] as? NSNumber)?.boolValue ?? false
    }

    private static func numberArray(
        _ key: String,
        in dictionary: [String: Any]
    ) -> [Double] {
        if let values = dictionary[key] as? [NSNumber] {
            return values.map(\.doubleValue)
        }
        if let values = dictionary[key] as? NSArray {
            return values.compactMap { ($0 as? NSNumber)?.doubleValue }
        }
        return []
    }
}
