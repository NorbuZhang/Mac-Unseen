// SPDX-License-Identifier: MPL-2.0

import Foundation

enum AdvancedSnapshotParser {
    static func parse(_ data: Data) -> AdvancedSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var snapshot = AdvancedSnapshot()
        snapshot.status = root["status"] as? String ?? "未知"
        if let timestamp = number(root["timestamp"]) {
            snapshot.timestamp = Date(timeIntervalSince1970: timestamp)
        }
        if let timestamps = root["collectorTimestamps"] as? [String: Any] {
            snapshot.collectorTimestamps = timestamps.reduce(into: [:]) {
                result, entry in
                if let value = number(entry.value) {
                    result[entry.key] = Date(timeIntervalSince1970: value)
                }
            }
        }
        snapshot.collectorErrors = root["collectorErrors"]
            as? [String: String] ?? [:]
        snapshot.capabilities = root["capabilities"]
            as? [String: String] ?? [:]
        snapshot.errors = root["errors"] as? [String] ?? []

        if let motion = root["motion"] as? [String: Any] {
            if let accelerometer = motion["accelerometer"] as? [String: Any] {
                snapshot.motion.accelerometer = VectorReading(
                    x: number(accelerometer["x"]) ?? 0,
                    y: number(accelerometer["y"]) ?? 0,
                    z: number(accelerometer["z"]) ?? 0,
                    magnitude: number(accelerometer["magnitude"])
                )
            }
            if let gyroscope = motion["gyroscope"] as? [String: Any] {
                snapshot.motion.gyroscope = VectorReading(
                    x: number(gyroscope["x"]) ?? 0,
                    y: number(gyroscope["y"]) ?? 0,
                    z: number(gyroscope["z"]) ?? 0,
                    magnitude: number(gyroscope["magnitude"])
                )
            }
            if let orientation = motion["orientation"] as? [String: Any] {
                snapshot.motion.orientation = OrientationReading(
                    roll: number(orientation["roll"]) ?? 0,
                    pitch: number(orientation["pitch"]) ?? 0,
                    yaw: number(orientation["yaw"]) ?? 0
                )
            }
            if let vibration = motion["vibration"] as? [String: Any] {
                snapshot.motion.vibrationRMS = number(vibration["rms"]) ?? 0
                snapshot.motion.vibrationPeak = number(vibration["peak"]) ?? 0
                snapshot.motion.sampleRate = number(vibration["sampleRate"]) ?? 0
            }
        }

        if let environment = root["environment"] as? [String: Any] {
            snapshot.environment.lidAngle = number(environment["lidAngle"])
            snapshot.environment.alsIntensity = number(environment["alsIntensity"])
            snapshot.environment.lux = number(environment["lux"])
            if let channels = environment["spectralChannels"] as? [Any] {
                snapshot.environment.spectralChannels = channels.compactMap(number)
            }
        }

        if let smart = root["storageSmart"] as? [String: Any] {
            snapshot.storageSMART.available = smart["available"] as? Bool ?? false
            snapshot.storageSMART.healthPercentage = number(
                smart["healthPercentage"]
            )
            snapshot.storageSMART.percentageUsed = number(
                smart["percentageUsed"]
            )
            snapshot.storageSMART.totalBytesRead = number(
                smart["totalBytesRead"]
            )
            snapshot.storageSMART.totalBytesWritten = number(
                smart["totalBytesWritten"]
            )
            snapshot.storageSMART.powerOnHours = integer(
                smart["powerOnHours"]
            )
            snapshot.storageSMART.powerCycles = integer(
                smart["powerCycles"]
            )
            snapshot.storageSMART.unsafeShutdowns = integer(
                smart["unsafeShutdowns"]
            )
            snapshot.storageSMART.mediaErrors = integer(
                smart["mediaErrors"]
            )
            snapshot.storageSMART.availableSpare = number(
                smart["availableSpare"]
            )
            snapshot.storageSMART.temperature = number(smart["temperature"])
            snapshot.storageSMART.passed = smart["passed"] as? Bool
        }

        if let ismc = root["ismc"] as? [String: Any] {
            snapshot.telemetry = parseTelemetry(ismc)
        }
        return snapshot
    }

    private static func parseTelemetry(
        _ dictionary: [String: Any]
    ) -> [String: [Metric]] {
        var result: [String: [Metric]] = [:]

        for (sectionName, rawSection) in dictionary {
            guard let section = rawSection as? [String: Any] else {
                continue
            }
            var metrics: [Metric] = []
            for (name, rawEntry) in section {
                guard let entry = rawEntry as? [String: Any] else {
                    continue
                }
                let key = entry["key"] as? String
                let unit = entry["unit"] as? String ?? ""
                let quantity = number(entry["quantity"])
                if let quantity,
                   !isPlausibleTelemetry(
                       quantity,
                       section: sectionName,
                       name: name
                   ) {
                    continue
                }
                let value: String
                if let quantity {
                    value = formattedNumber(quantity)
                } else {
                    value = displayValue(entry["value"])
                }
                metrics.append(
                    Metric(
                        id: "\(sectionName)-\(name)-\(key ?? "")",
                        name: name,
                        value: value,
                        unit: unit,
                        detail: key,
                        info: telemetryInfo(section: sectionName, name: name)
                    )
                )
            }

            result[sectionName] = metrics.sorted {
                telemetrySortKey(section: sectionName, metric: $0)
                    < telemetrySortKey(section: sectionName, metric: $1)
            }
        }
        return result
    }

    private static func telemetrySortKey(
        section: String,
        metric: Metric
    ) -> TelemetrySortKey {
        let priority: Int
        switch section {
        case "Power":
            priority = powerPriority(metric)
        case "Fans":
            priority = metric.name == "Fan Count" ? 0 : 1
        default:
            priority = 0
        }
        return TelemetrySortKey(
            priority: priority,
            name: metric.name,
            id: metric.id
        )
    }

    private static func powerPriority(_ metric: Metric) -> Int {
        let keyPriority = [
            "PDTR": 0,
            "PSTR": 1,
            "PHPC": 2,
            "PDBR": 3,
            "PPBR": 4,
        ]
        if let key = metric.detail, let priority = keyPriority[key] {
            return priority
        }

        let namePriority = [
            "DC In": 0,
            "System Total": 1,
            "Heatpipe": 2,
            "Power Delivery Brightness": 3,
            "Battery": 4,
        ]
        return namePriority[metric.name] ?? 100
    }

    private struct TelemetrySortKey: Comparable {
        let priority: Int
        let name: String
        let id: String

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    private static func isPlausibleTelemetry(
        _ value: Double,
        section: String,
        name: String
    ) -> Bool {
        guard value.isFinite else {
            return false
        }
        switch section {
        case "Temperature":
            return (-40...180).contains(value)
        case "Power":
            return (-1_000...1_000).contains(value)
        case "Fans":
            if name == "Fan Count" {
                return (0...32).contains(value)
            }
            return (0...30_000).contains(value)
        default:
            return abs(value) < 1e15
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private static func integer(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber {
            return number.uint64Value
        }
        if let string = value as? String {
            return UInt64(string)
        }
        return nil
    }

    private static func displayValue(_ value: Any?) -> String {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return value.boolValue ? tr("是") : tr("否")
            }
            return formattedNumber(value.doubleValue)
        case nil:
            return "-"
        default:
            return String(describing: value!)
        }
    }

    private static func formattedNumber(_ value: Double) -> String {
        if abs(value) >= 100 {
            return String(format: "%.0f", value)
        }
        if abs(value) >= 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.3f", value)
    }

    private static func telemetryInfo(section: String, name: String) -> String? {
        switch section {
        case "Temperature":
            if AppLocalization.language == .english {
                return "The Mac reports this internal temperature sensor as “\(name)”. It may sit near the chip, battery, memory, storage, power circuitry, or chassis. A short spike rarely means failure; sustained temperature, neighboring sensors, fan speed, and thermal throttling provide better context."
            }
            return "这是 Mac 内部名为“\(name)”的温度传感器。它可能位于芯片、电池、内存、存储、供电芯片或机身附近。单个读数短暂升高通常不代表故障，更有参考价值的是持续温度、同一组传感器的整体趋势，以及系统是否出现降频或风扇加速。"
        case "Power":
            if AppLocalization.language == .english {
                return "The current measured or estimated power for “\(name)”, in watts. It represents how quickly this component is consuming or transferring energy and can change rapidly with workload, display brightness, charging, and peripherals."
            }
            return "这是“\(name)”当前测得或估算的功率，单位为瓦（W）。它表示这一部分此刻传输或消耗能量的速度，会随着应用负载、屏幕亮度、充电和外设使用快速变化。"
        case "Fans":
            let lower = name.lowercased()
            if lower.contains("target") {
                if AppLocalization.language == .english {
                    return "The speed requested by macOS. The target normally rises first as temperatures increase, then the physical fan catches up."
                }
                return "这是系统希望风扇达到的目标转速。温度升高时目标值通常会先上升，实际转速随后逐渐追上。"
            }
            if lower.contains("min") {
                if AppLocalization.language == .english {
                    return "The minimum speed in this fan's control range, not necessarily its current speed."
                }
                return "这是该风扇控制范围中的最低转速，不代表风扇此刻一定正在以这个速度运行。"
            }
            if lower.contains("max") {
                if AppLocalization.language == .english {
                    return "The maximum speed supported by this fan. It is a hardware limit, not a normal operating target."
                }
                return "这是该风扇控制范围中的最高转速，是硬件上限，不代表正常使用时会一直达到。"
            }
            if AppLocalization.language == .english {
                return "The fan's current speed, normally measured in RPM. macOS raises it automatically as sustained load and temperature increase."
            }
            return "这是风扇当前的实际转速，单位通常为 RPM，也就是每分钟转数。温度和持续负载升高时，系统会自动提高转速。"
        default:
            return nil
        }
    }
}
