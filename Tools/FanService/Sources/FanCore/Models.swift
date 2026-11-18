import Foundation

public enum FanMode: String, Codable, CaseIterable, Sendable {
    /// The SMC's built-in fan curve — Apple's default behavior.
    case auto
    /// Fixed RPM per fan, chosen by the user.
    case manual
    /// Fans ramp between min and max to hold temperature below a target.
    case curve
}

public struct DaemonConfig: Codable, Equatable, Sendable {
    public var mode: FanMode
    /// Desired RPM per fan id; used in `.manual` mode.
    public var manualRPM: [Double]
    /// Temperature ceiling in °C; used in `.curve` mode.
    public var targetTemp: Double

    public init(mode: FanMode = .auto, manualRPM: [Double] = [], targetTemp: Double = 75) {
        self.mode = mode
        self.manualRPM = manualRPM
        self.targetTemp = targetTemp
    }
}

public struct FanStatus: Codable, Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var actualRPM: Double
    public var targetRPM: Double
    public var minRPM: Double
    public var maxRPM: Double
    public var forced: Bool
    /// macOS/SMC has locked this fan (parked); writes are rejected until it releases.
    public var systemOverride: Bool

    /// Speed as a percentage of the fan's controllable range (min→0%, max→100%),
    /// matching how percentage inputs like `fanctl manual 60%` are interpreted.
    public var percent: Double? {
        guard maxRPM > minRPM else { return nil }
        let fraction = (actualRPM - minRPM) / (maxRPM - minRPM)
        return min(max(fraction, 0), 1) * 100
    }

    public init(id: Int, name: String, actualRPM: Double, targetRPM: Double,
                minRPM: Double, maxRPM: Double, forced: Bool, systemOverride: Bool = false) {
        self.id = id
        self.name = name
        self.actualRPM = actualRPM
        self.targetRPM = targetRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.forced = forced
        self.systemOverride = systemOverride
    }
}

public struct SensorStatus: Codable, Identifiable, Sendable {
    public var key: String
    public var group: String
    public var value: Double
    public var id: String { key }

    public init(key: String, group: String, value: Double) {
        self.key = key
        self.group = group
        self.value = value
    }
}

public struct DaemonStatus: Codable, Sendable {
    public var fans: [FanStatus]
    public var cpuTemp: Double?
    public var gpuTemp: Double?
    public var maxTemp: Double?
    /// The temperature the curve controller is regulating on.
    public var controlTemp: Double?
    public var config: DaemonConfig
    /// True while the 100 °C failsafe has taken over and forced max fans.
    public var failsafeActive: Bool
    /// False when the daemon is running without root and cannot write to the SMC.
    public var canControl: Bool
    public var version: String

    public init(fans: [FanStatus], cpuTemp: Double?, gpuTemp: Double?, maxTemp: Double?,
                controlTemp: Double?, config: DaemonConfig, failsafeActive: Bool,
                canControl: Bool, version: String) {
        self.fans = fans
        self.cpuTemp = cpuTemp
        self.gpuTemp = gpuTemp
        self.maxTemp = maxTemp
        self.controlTemp = controlTemp
        self.config = config
        self.failsafeActive = failsafeActive
        self.canControl = canControl
        self.version = version
    }
}

// MARK: - Wire protocol (newline-delimited JSON over a Unix socket)

public struct DaemonRequest: Codable, Sendable {
    public var cmd: String  // "status" | "set" | "sensors"
    public var config: DaemonConfig?

    public init(cmd: String, config: DaemonConfig? = nil) {
        self.cmd = cmd
        self.config = config
    }
}

public struct DaemonResponse: Codable, Sendable {
    public var ok: Bool
    public var error: String?
    public var status: DaemonStatus?
    public var sensors: [SensorStatus]?

    public init(ok: Bool, error: String? = nil, status: DaemonStatus? = nil,
                sensors: [SensorStatus]? = nil) {
        self.ok = ok
        self.error = error
        self.status = status
        self.sensors = sensors
    }
}

public enum FanControlConstants {
    public static let socketPath = "/var/run/fanctld.sock"
    /// Used when the daemon runs unprivileged (dev/testing) and cannot bind in /var/run.
    public static let fallbackSocketPath = "/tmp/fanctld.sock"
    public static let version = "1.0.4"
    /// Above this temperature the daemon overrides manual/curve settings with max fans.
    public static let failsafeTemp = 100.0
    /// Failsafe releases once temperature drops below this.
    public static let failsafeReleaseTemp = 92.0
}
