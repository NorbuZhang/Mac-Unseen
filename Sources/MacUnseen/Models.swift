// SPDX-License-Identifier: MPL-2.0

import Foundation

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview
    case motion
    case environment
    case trackpad
    case temperature
    case fans
    case battery
    case storage
    case network
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: tr("总览")
        case .motion: tr("运动与震动")
        case .environment: tr("屏幕角度与环境光")
        case .trackpad: tr("触控板")
        case .temperature: tr("温度")
        case .fans: tr("风扇")
        case .battery: tr("电池与电源")
        case .storage: tr("存储")
        case .network: tr("网络与接口")
        case .about: tr("说明")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .motion: "waveform.path.ecg"
        case .environment: "sun.max"
        case .trackpad: "hand.point.up.left"
        case .temperature: "thermometer.medium"
        case .fans: "fan"
        case .battery: "battery.75percent"
        case .storage: "internaldrive"
        case .network: "network"
        case .about: "info.circle"
        }
    }
}

struct Metric: Identifiable, Hashable {
    let id: String
    let name: String
    let value: String
    let unit: String
    let detail: String?
    let info: String?

    init(
        id: String? = nil,
        name: String,
        value: String,
        unit: String = "",
        detail: String? = nil,
        info: String? = nil
    ) {
        self.id = id ?? name
        self.name = name
        self.value = value
        self.unit = unit
        self.detail = detail
        self.info = info
    }
}

struct VectorReading: Equatable {
    var x = 0.0
    var y = 0.0
    var z = 0.0
    var magnitude: Double?
}

struct OrientationReading: Equatable {
    var roll = 0.0
    var pitch = 0.0
    var yaw = 0.0
}

struct MotionReading: Equatable {
    var accelerometer: VectorReading?
    var gyroscope: VectorReading?
    var orientation: OrientationReading?
    var vibrationRMS = 0.0
    var vibrationPeak = 0.0
    var sampleRate = 0.0
}

struct EnvironmentReading: Equatable {
    var lidAngle: Double?
    var alsIntensity: Double?
    var lux: Double?
    var spectralChannels: [Double] = []
}

struct TrackpadTouch: Identifiable, Equatable {
    let id: Int32
    let state: Int32
    let x: Double
    let y: Double
    let velocityX: Double
    let velocityY: Double
    let total: Double
    let pressure: Double
    let angle: Double
    let majorAxis: Double
    let minorAxis: Double
    let density: Double

    var stateName: String {
        switch state {
        case 1: tr("进入感应区")
        case 2: tr("悬停")
        case 3: tr("开始触摸")
        case 4: tr("触摸中")
        case 5: tr("离开表面")
        case 6: tr("仍在感应区")
        case 7: tr("已离开")
        default: tr("未跟踪")
        }
    }
}

struct TrackpadDetails: Equatable {
    var surfaceWidth = 0
    var surfaceHeight = 0
    var sensorRows = 0
    var sensorColumns = 0
    var familyID = 0
    var deviceID: UInt64 = 0
    var builtIn = false
    var running = false
}

struct SystemSnapshot: Equatable {
    var modelName = "Mac"
    var modelIdentifier = ""
    var chipName = ""
    var memoryTotal = 0.0
    var memoryUsed = 0.0
    var diskTotal = 0.0
    var diskUsed = 0.0
    var loadAverages: [Double] = [0, 0, 0]
    var processorCount = 0
    var uptime = 0.0
    var thermalState = "正常"
}

struct BatterySnapshot: Equatable {
    var percentage: Double?
    var cycleCount: Int?
    var temperature: Double?
    var voltage: Double?
    var amperage: Double?
    var designCapacity: Double?
    var maximumCapacity: Double?
    var rawMaximumCapacity: Double?
    var rawCurrentCapacity: Double?
    var charging = false
    var externalConnected = false
    var cellVoltages: [Double] = []
    var cellResistance: [Double] = []
    var historicalMinTemperature: Double?
    var historicalMaxTemperature: Double?
    var historicalMaxChargeCurrent: Double?
    var historicalMaxDischargeCurrent: Double?
    var adapterName: String?
    var adapterRatedWatts: Double?
    var negotiatedVoltage: Double?
    var negotiatedCurrent: Double?
    var liveInputPower: Double?
    var liveInputVoltage: Double?
    var liveInputCurrent: Double?
    var pdProfiles: [String] = []
}

struct DiskSnapshot: Identifiable, Equatable, Sendable {
    var id = UUID().uuidString
    var name = "存储设备"
    var bsdName = ""
    var connection = "未知"
    var location = "未知"
    var firmware = ""
    var capacity = 0.0
    var solidState = false
    var removable = false
    var smartCapable = false
    var trimEnabled: Bool?
    var encrypted = false
    var thermalThrottlingSupported = false
    var bytesRead = 0.0
    var bytesWritten = 0.0
    var readOperations: UInt64 = 0
    var writeOperations: UInt64 = 0
    var readErrors: UInt64 = 0
    var writeErrors: UInt64 = 0

    var isInternal: Bool {
        location.localizedCaseInsensitiveContains("internal")
    }

    var healthText: String {
        if readErrors + writeErrors > 0 {
            return tr("发现 I/O 错误")
        }
        if smartCapable {
            return tr("正常")
        }
        return tr("未提供 SMART")
    }
}

struct StorageSnapshot: Equatable, Sendable {
    var disks: [DiskSnapshot] = []
    var updatedAt: Date?
}

struct StorageSMARTSnapshot: Equatable {
    var available = false
    var healthPercentage: Double?
    var percentageUsed: Double?
    var totalBytesRead: Double?
    var totalBytesWritten: Double?
    var powerOnHours: UInt64?
    var powerCycles: UInt64?
    var unsafeShutdowns: UInt64?
    var mediaErrors: UInt64?
    var availableSpare: Double?
    var temperature: Double?
    var passed: Bool?
}

struct NetworkInterfaceSnapshot: Identifiable, Equatable, Sendable {
    var id: String { name }
    var name = ""
    var displayName = "网络接口"
    var ipv4: [String] = []
    var ipv6: [String] = []
    var receivedBytes = 0.0
    var sentBytes = 0.0
}

struct WiFiSnapshot: Equatable, Sendable {
    var interfaceName = ""
    var connected = false
    var networkName = ""
    var protocolName = ""
    var channel = ""
    var transmitRate = ""
    var signalNoise = ""
    var security = ""
}

struct PortSnapshot: Identifiable, Equatable, Sendable {
    var id = UUID().uuidString
    var name = "接口"
    var connected = false
    var protocolName = ""
    var speed = ""
    var deviceName = ""
}

struct PeripheralSnapshot: Identifiable, Equatable, Sendable {
    var id = UUID().uuidString
    var name = "外接设备"
    var protocolName = ""
    var speed = ""
    var vendor = ""
    var power = ""
}

struct NetworkSnapshot: Equatable, Sendable {
    var interfaces: [NetworkInterfaceSnapshot] = []
    var wifi = WiFiSnapshot()
    var ports: [PortSnapshot] = []
    var peripherals: [PeripheralSnapshot] = []
    var vpnInterfaceCount = 0
    var updatedAt: Date?

    var connected: Bool {
        interfaces.contains { !$0.ipv4.isEmpty || !$0.ipv6.isEmpty }
    }
}

struct AdvancedSnapshot: Equatable {
    var status = "未启动"
    var timestamp: Date?
    var collectorTimestamps: [String: Date] = [:]
    var capabilities: [String: String] = [:]
    var motion = MotionReading()
    var environment = EnvironmentReading()
    var storageSMART = StorageSMARTSnapshot()
    var telemetry: [String: [Metric]] = [:]
    var collectorErrors: [String: String] = [:]
    var errors: [String] = []
}
