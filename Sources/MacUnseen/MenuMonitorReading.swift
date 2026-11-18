import Foundation
import IOKit.ps
import IOKit.hid

enum MenuMetric: String, CaseIterable, Sendable {
    case overview, cpu, gpu, renderer, tiler, memory, fans, temperature, battery, power, network, upload, storage, diskWrite, lidAngle, systemInfo

    var title: String {
        switch self {
        case .overview: tr("总览")
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .renderer: tr("渲染器占用")
        case .tiler: tr("分块器占用")
        case .memory: tr("内存压力")
        case .fans: tr("风扇")
        case .temperature: tr("温度")
        case .battery: tr("电池与电源")
        case .power: tr("实时输入功率")
        case .network: tr("网络接收")
        case .upload: tr("网络发送")
        case .storage: tr("磁盘读取")
        case .diskWrite: tr("磁盘写入")
        case .lidAngle: tr("屏幕角度")
        case .systemInfo: tr("运行时间")
        }
    }

    var section: DashboardSection {
        switch self {
        case .overview: .overview
        case .cpu, .gpu, .renderer, .tiler, .memory: .performance
        case .fans: .fans
        case .temperature: .temperature
        case .battery, .power: .battery
        case .network, .upload: .network
        case .storage, .diskWrite: .storage
        case .lidAngle: .environment
        case .systemInfo: .systemInfo
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu, .renderer, .tiler: "square.3.layers.3d"
        case .memory: "memorychip"
        case .power: "bolt.fill"
        case .network: "arrow.down"
        case .upload: "arrow.up"
        case .lidAngle: "angle"
        default: section.symbol
        }
    }

    var performanceMetrics: Set<PerformanceMetric> {
        switch self {
        case .overview: Set(PerformanceMetric.allCases)
        case .cpu: [.cpu]
        case .gpu, .renderer, .tiler: [.gpu]
        case .memory: [.memory]
        case .network, .upload: [.network]
        case .storage, .diskWrite: [.disk]
        default: []
        }
    }

    var usesFanService: Bool { self == .overview || self == .fans || self == .temperature }

    static func saved(in settings: UserDefaults) -> Self {
        if let raw = settings.string(forKey: "menuMonitorMetric"), let metric = Self(rawValue: raw) { return metric }
        let legacy = settings.string(forKey: "menuMonitorPanelCategory") ?? ""
        return legacy == "performance" ? .cpu : Self(rawValue: legacy) ?? .overview
    }
}

struct MenuReading: Sendable {
    var performance = PerformanceReading()
    var system: SystemSnapshot?
    var battery: BatterySnapshot?
    var lidAngle: Int?
    var uptime: TimeInterval?
    var sampledAt: Date?

    func title(for metric: MenuMetric, fans: DaemonStatus?, readOnlyRPM: Double? = nil) -> String {
        switch metric {
        case .overview: ""
        case .cpu: Self.value(performance.cpu, unit: "%")
        case .gpu: Self.value(performance.gpus.compactMap(\.utilization).max(), unit: "%")
        case .renderer: Self.value(performance.gpus.compactMap(\.renderer).max(), unit: "%")
        case .tiler: Self.value(performance.gpus.compactMap(\.tiler).max(), unit: "%")
        case .memory: performance.memory.pressurePercent.map { "\($0)%" } ?? "—"
        case .fans: Self.value(fans?.fans.map(\.actualRPM).max() ?? readOnlyRPM, unit: " RPM")
        case .temperature: fans?.cpuTemp.map { Self.value($0, unit: "°C") } ?? system.map { tr($0.thermalState) } ?? "—"
        case .battery: Self.value(battery?.percentage, unit: "%")
        case .power: Self.value(battery?.liveInputPower, unit: " W", digits: 1)
        case .network: Self.rate(performance.networkReceive)
        case .upload: Self.rate(performance.networkSend)
        case .storage: Self.rate(performance.diskRead)
        case .diskWrite: Self.rate(performance.diskWrite)
        case .lidAngle: lidAngle.map { "\($0)°" } ?? "—"
        case .systemInfo: uptime.map(formatDuration) ?? "—"
        }
    }

    static func value(_ number: Double?, unit: String, digits: Int = 0) -> String {
        number.map { String(format: "%.*f", digits, $0) + unit } ?? "—"
    }

    static func rate(_ number: Double?) -> String {
        number.map { formatMonitoredBytes($0) + "/s" } ?? "—"
    }
}

actor MenuSampler {
    private let performance = PerformanceReader()
    private var system: SystemSnapshot?
    private var lastInventory = Date.distantPast

    func sample(_ metric: MenuMetric, expanded: Bool) async -> MenuReading {
        let all = metric == .overview
        var reading = MenuReading()
        let now = Date()
        if !metric.performanceMetrics.isEmpty {
            reading.performance = await performance.sample(including: metric.performanceMetrics)
        }
        if all || metric == .battery || metric == .power {
            if expanded || metric == .power {
                reading.battery = SystemReader.readBattery(includeStatic: false, includeMedium: true, includeSlow: false)
            } else {
                reading.battery = BatterySnapshot(percentage: Self.batteryPercent())
            }
        }
        let inventory = now.timeIntervalSince(lastInventory) >= 30
        if all || metric == .temperature || (expanded && (metric.section == .storage || metric == .systemInfo)) {
            let disk = expanded && (all || metric.section == .storage) && inventory
            system = SystemReader.readSystem(preserving: system ?? SystemSnapshot(), includeStatic: system == nil, includeDiskUsage: disk)
            if disk { lastInventory = now }
            reading.system = system
        }
        if all || metric == .lidAngle { reading.lidAngle = Self.readLidAngle() }
        reading.uptime = ProcessInfo.processInfo.systemUptime
        reading.sampledAt = now
        return reading
    }

    /// The hinge exposes the angle in degrees in bytes 1–2 of HID feature report 1.
    private static func readLidAngle() -> Int? {
        guard let matching = IOServiceMatching("AppleSPUHIDDevice") as NSMutableDictionary? else { return nil }
        matching[kIOPropertyMatchKey] = [kIOHIDPrimaryUsagePageKey: 0x20, kIOHIDPrimaryUsageKey: 138]
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching as CFDictionary)
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service),
              IOHIDDeviceOpen(device, 0) == kIOReturnSuccess else { return nil }
        defer { IOHIDDeviceClose(device, 0) }
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length) == kIOReturnSuccess,
              length >= 3, report[0] == 1 else { return nil }
        let angle = Int(report[1]) | (Int(report[2]) << 8)
        return angle <= 360 ? angle : nil
    }

    private static func batteryPercent() -> Double? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Double,
                  let capacity = info[kIOPSMaxCapacityKey] as? Double, capacity > 0 else { continue }
            return 100 * current / capacity
        }
        return nil
    }
}
