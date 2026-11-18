import Foundation

public struct SMCSensor {
    public let key: String
    public let group: SensorGroup
    public let value: Double
}

public enum SensorGroup: String, Codable, CaseIterable {
    case cpu = "CPU"
    case gpu = "GPU"
    case memory = "Memory"
    case storage = "Storage"
    case battery = "Battery"
    case ambient = "Ambient"
    case other = "Other"
}

/// Discovers temperature sensors by enumerating every SMC key and keeping
/// plausible-looking temperature readings. Key names vary across Mac models,
/// so grouping is prefix-heuristic based.
public final class SensorCatalog {
    private let smc: SMCConnection
    /// Temperature keys discovered at init, with their group.
    public private(set) var temperatureKeys: [(key: String, group: SensorGroup)] = []

    public init(smc: SMCConnection) {
        self.smc = smc
        discover()
    }

    private static func group(for key: String) -> SensorGroup {
        // Apple Silicon prefixes (observed on M1–M4) and classic Intel keys.
        if key.hasPrefix("Tp") || key.hasPrefix("Tc") || key.hasPrefix("TC") || key.hasPrefix("Te") || key.hasPrefix("Tf") {
            return .cpu
        }
        if key.hasPrefix("Tg") || key.hasPrefix("TG") {
            return .gpu
        }
        if key.hasPrefix("Tm") || key.hasPrefix("TM") {
            return .memory
        }
        if key.hasPrefix("TH") || key.hasPrefix("TaN") || key.hasPrefix("TN") {
            return .storage
        }
        if key.hasPrefix("TB") || key.hasPrefix("Tb") {
            return .battery
        }
        if key.hasPrefix("TA") || key.hasPrefix("Ta") || key.hasPrefix("Ts") || key.hasPrefix("TW") {
            return .ambient
        }
        return .other
    }

    private func discover() {
        guard let count = try? smc.keyCount() else { return }
        var found: [(String, SensorGroup)] = []
        for index in 0..<count {
            guard let key = try? smc.key(atIndex: index), key.hasPrefix("T") else { continue }
            guard let info = try? smc.keyInfo(key) else { continue }
            // Temperature keys are floats or signed fixed-point.
            guard info.dataType == "flt " || info.dataType.hasPrefix("sp") else { continue }
            guard let value = try? smc.readNumeric(key), value > 1, value < 125 else { continue }
            found.append((key, SensorCatalog.group(for: key)))
        }
        temperatureKeys = found
    }

    /// Current readings for all discovered sensors.
    public func readAll() -> [SMCSensor] {
        temperatureKeys.compactMap { entry in
            guard let value = try? smc.readNumeric(entry.key), value > 1, value < 125 else {
                return nil
            }
            return SMCSensor(key: entry.key, group: entry.group, value: value)
        }
    }

    public struct Summary {
        /// "Hot average" per group: mean of the hottest quartile of sensors.
        /// Tracks real thermal pressure while staying robust to a single
        /// outlier/hotspot key (some dies report isolated sensors ~12 °C above
        /// the rest of the package).
        public let cpuHot: Double?
        public let gpuHot: Double?
        /// Raw single hottest sensor anywhere, for display.
        public let overallMax: Double?
        public let sensorCount: Int
    }

    private static func hotAverage(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted(by: >)
        let count = max(1, sorted.count / 4)
        let top = sorted.prefix(count)
        return top.reduce(0, +) / Double(top.count)
    }

    public func summary() -> Summary {
        let readings = readAll()
        let cpu = SensorCatalog.hotAverage(readings.filter { $0.group == .cpu }.map(\.value))
        let gpu = SensorCatalog.hotAverage(readings.filter { $0.group == .gpu }.map(\.value))
        let overall = readings.map(\.value).max()
        return Summary(
            cpuHot: cpu, gpuHot: gpu, overallMax: overall, sensorCount: readings.count)
    }
}
