import Foundation

/// Read cadence is chosen before collection. Static identity has no polling timer.
enum MonitoringRefreshPolicy {
    static let performance: TimeInterval = 1
    static let processes: TimeInterval = 2
    static let systemSummary: TimeInterval = 60
    static func interval(for section: DashboardSection, active: Bool) -> TimeInterval? {
        guard active else { return nil }
        switch section {
        case .overview, .performance: return performance
        case .processes: return processes
        default: return nil
        }
    }
}

struct CPUCounters: Equatable, Sendable {
    var user: UInt64, system: UInt64, idle: UInt64, nice: UInt64
    func usage(since previous: Self) -> Double? {
        guard user >= previous.user, system >= previous.system,
              idle >= previous.idle, nice >= previous.nice else { return nil }
        let busy = Double(user - previous.user) + Double(system - previous.system) + Double(nice - previous.nice)
        let total = busy + Double(idle - previous.idle)
        return total > 0 ? busy / total * 100 : nil
    }
}

struct ByteCounters: Equatable, Sendable {
    var input: UInt64, output: UInt64
}

enum SampleDelta {
    static func rates(current: [String: ByteCounters]?, previous: [String: ByteCounters]?, elapsed: Double) -> (Double?, Double?) {
        guard let current, let previous, elapsed > 0, elapsed <= 10 else { return (nil, nil) }
        if current.isEmpty && previous.isEmpty { return (0, 0) }
        var input = 0.0, output = 0.0, valid = false
        for (id, now) in current {
            guard let old = previous[id], now.input >= old.input, now.output >= old.output else { continue }
            input += Double(now.input - old.input) / elapsed
            output += Double(now.output - old.output) / elapsed
            valid = true
        }
        return valid ? (input, output) : (nil, nil)
    }
    static func processCPU(current: UInt64?, previous: UInt64?, elapsed: Double) -> Double? {
        guard let current, let previous, current >= previous, elapsed > 0, elapsed <= 10 else { return nil }
        // 100% is one fully occupied logical CPU, matching Activity Monitor.
        return Double(current - previous) / (elapsed * 1_000_000_000) * 100
    }
}

struct MemoryReading: Equatable, Sendable {
    var total = 0.0
    var used: Double?
    var app: Double?
    var wired: Double?
    var compressed: Double?
    var cached: Double?
    var swapUsed: Double?
    var pressure: Int?
    var fraction: Double? { used.flatMap { total > 0 ? $0 / total : nil } }
}

struct GPUReading: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var cores: Int?
    var utilization: Double?
    var renderer: Double?
    var tiler: Double?
    var allocatedMemory: Double?
}

struct PerformanceReading: Equatable, Sendable {
    var cpu: Double?
    var cores: [Double?] = []
    var memory = MemoryReading()
    var gpus: [GPUReading] = []
    var diskRead: Double?
    var diskWrite: Double?
    var networkReceive: Double?
    var networkSend: Double?
    var loadAverages: [Double] = []
    var sampledAt: Date?
}

struct ProcessIdentity: Hashable, Sendable {
    var pid: Int32
    var startSeconds: UInt64
    var startMicroseconds: UInt64
}
struct ProcessReading: Identifiable, Equatable, Sendable {
    var id: ProcessIdentity
    var name: String
    var uid: UInt32
    var cpu: Double?
    var memory: Double?
    var usesFootprint: Bool
}
struct ProcessSnapshot: Equatable, Sendable {
    var rows: [ProcessReading] = []
    var sampledAt: Date?
    var failed = false
}

struct SystemIdentity: Equatable, Sendable {
    var osVersion = ""
    var osBuild = ""
    var kernel = ""
    var architecture = ""
    var physicalCores: Int?
    var logicalCores: Int?
    var performanceCores: Int?
    var efficiencyCores: Int?
    var bootTime: Date?
    var gpuNames: [String] = []
}
