import Foundation

/// Read cadence is chosen before collection. Static identity has no polling timer.
enum MonitoringRefreshPolicy {
    static let performance: TimeInterval = 1
    static let processes: TimeInterval = 2
    static let systemSummary: TimeInterval = 60
    static let systemRuntime: TimeInterval = 5
    static func interval(for section: DashboardSection, active: Bool) -> TimeInterval? {
        guard active else { return nil }
        switch section {
        case .overview, .performance: return performance
        case .processes: return processes
        case .systemInfo: return systemRuntime
        default: return nil
        }
    }

    /// The UI only checks the helper while it is running or being connected.
    /// Basic battery readings and the overview summary have independent needs.
    static func sensorInterval(for section: DashboardSection, active: Bool,
                               advancedActive: Bool, advancedPending: Bool,
                               trackpadAvailable: Bool) -> TimeInterval? {
        let needsStatus = advancedActive || advancedPending
        guard active else { return needsStatus ? 2 : nil }
        switch section {
        case .battery: return 0.5
        case .overview, .performance: return needsStatus ? 1 : systemSummary
        case .motion, .environment: return advancedActive ? 0.1 : (advancedPending ? 1 : nil)
        case .trackpad: return trackpadAvailable ? 0.1 : (needsStatus ? 2 : nil)
        case .temperature, .fans: return needsStatus ? 1 : nil
        default: return needsStatus ? 2 : nil
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

enum MemoryPressureLevel: Int, Equatable, Sendable, CaseIterable {
    case normal = 1, warning = 2, critical = 4
    var chartLevel: Double {
        switch self { case .normal: 1; case .warning: 2; case .critical: 3 }
    }
    var title: String {
        switch self { case .normal: "正常"; case .warning: "偏高"; case .critical: "很高" }
    }
}

struct MemoryPressureSample: Equatable, Sendable {
    var date: Date
    var level: MemoryPressureLevel?
    var startsNewSegment = false
}

enum MemoryPressureColumn: Equatable, Sendable {
    case sample(MemoryPressureSample)
    case pause
}

struct MemoryPressureHistory: Equatable, Sendable {
    static let capacity = 60
    private(set) var samples: [MemoryPressureSample] = []
    private var pendingBreak = false

    /// Preserve observations while collectors sleep. Never fabricate the missing interval.
    mutating func pause() {
        pendingBreak = !samples.isEmpty
    }

    mutating func append(rawLevel: Int?, at date: Date) {
        guard samples.last.map({ date > $0.date }) ?? true else { return }
        let delayed = samples.last.map { date.timeIntervalSince($0.date) > MonitoringRefreshPolicy.performance * 2.5 } ?? false
        samples.append(MemoryPressureSample(date: date, level: rawLevel.flatMap(MemoryPressureLevel.init),
                                            startsNewSegment: pendingBreak || delayed))
        pendingBreak = false
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    /// Sample-order axis keeps old observations visible after a long pause.
    /// An explicit gap marks omitted time, instead of pretending time was continuous.
    var plotColumns: [MemoryPressureColumn] {
        samples.enumerated().flatMap { index, sample in
            index > 0 && sample.startsNewSegment ? [.pause, .sample(sample)] : [.sample(sample)]
        }
    }
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
    var parentPID: Int32 = 0
    var executablePath: String? = nil
    var application: ProcessApplication? = nil
}
struct ProcessSnapshot: Equatable, Sendable {
    var rows: [ProcessReading] = []
    var sampledAt: Date?
    var failed = false
}

enum ProcessSortColumn: String, CaseIterable, Sendable {
    case name, pid, cpu, memory
    var title: String {
        switch self { case .name: "名称"; case .pid: "PID"; case .cpu: "CPU"; case .memory: "内存" }
    }
    var initiallyAscending: Bool { self == .name || self == .pid }
}

struct ProcessSort: Equatable, Sendable {
    var column: ProcessSortColumn = .cpu
    var ascending = false

    mutating func select(_ next: ProcessSortColumn) {
        if column == next { ascending.toggle() }
        else { column = next; ascending = next.initiallyAscending }
    }

    func precedes(_ lhs: ProcessReading, _ rhs: ProcessReading) -> Bool {
        let comparison: ComparisonResult
        switch column {
        case .name:
            comparison = lhs.name.localizedStandardCompare(rhs.name)
        case .pid:
            comparison = lhs.id.pid == rhs.id.pid ? .orderedSame : lhs.id.pid < rhs.id.pid ? .orderedAscending : .orderedDescending
        case .cpu, .memory:
            let a = column == .cpu ? lhs.cpu : lhs.memory
            let b = column == .cpu ? rhs.cpu : rhs.memory
            // Unavailable values stay at the bottom in either direction.
            if a == nil && b != nil { return false }
            if a != nil && b == nil { return true }
            if let a, let b, a != b { comparison = a < b ? .orderedAscending : .orderedDescending }
            else { comparison = .orderedSame }
        }
        if comparison == .orderedSame { return lhs.id.pid < rhs.id.pid }
        return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
    }
}

struct CPUCoreGroup: Equatable, Sendable {
    var name: String
    var count: Int
    var l1InstructionBytes: UInt64?
    var l1DataBytes: UInt64?
    var l2Bytes: UInt64?
    var coresPerL2: Int?
    var label: String {
        switch name.lowercased() {
        case "performance": "性能核心"
        case "efficiency": "能效核心"
        case "super": "超级核心"
        default: "CPU (\(name))"
        }
    }
}

struct SystemIdentity: Equatable, Sendable {
    var osVersion = ""
    var osBuild = ""
    var kernel = ""
    var architecture = ""
    var physicalCores: Int?
    var logicalCores: Int?
    var coreGroups: [CPUCoreGroup] = []
    var bootTime: Date?
    var gpuNames: [String] = []
    var hostName = ""
    var packages: Int?
    var pageBytes: UInt64?
    var reportedFrequencyHz: UInt64?
    var l3Bytes: UInt64?
    var virtualization: Bool?
}

struct SystemRuntime: Equatable, Sendable {
    var uptime: TimeInterval = 0
    var loads: [Double] = []
    var processCount: Int?
    var sampledAt: Date?
}
