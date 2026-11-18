// Adapted from jbforge/mac-fan-control (MIT), commit ae14180d.
import Foundation


enum DaemonClientError: Error, CustomStringConvertible {
    case notRunning
    case connectionFailed(String)
    case badResponse(String)
    case daemonError(String)

    var description: String {
        switch self {
        case .notRunning:
            return tr("风扇服务未运行。")
        case .connectionFailed(let msg): return "Could not talk to fanctld: \(msg)"
        case .badResponse(let msg): return "Bad response from fanctld: \(msg)"
        case .daemonError(let msg): return msg
        }
    }
}

/// Blocking one-shot client for the fanctld Unix socket.
enum DaemonClient {

    static func status() throws -> DaemonStatus {
        let response = try send(DaemonRequest(cmd: "status"))
        guard response.ok, let status = response.status else {
            throw DaemonClientError.daemonError(response.error ?? "no status returned")
        }
        return status
    }

    @discardableResult
    static func apply(_ config: DaemonConfig) throws -> DaemonStatus {
        let response = try send(DaemonRequest(cmd: "set", config: config))
        guard response.ok else {
            throw DaemonClientError.daemonError(response.error ?? "set failed")
        }
        guard let status = response.status else {
            throw DaemonClientError.badResponse("set returned no status")
        }
        return status
    }

    static func send(_ request: DaemonRequest) throws -> DaemonResponse {
        let path = "/var/run/fanctld.sock"
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw DaemonClientError.connectionFailed("socket() failed: \(String(cString: strerror(errno)))")
        }
        defer { close(fd) }

        var noSigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))

        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            path.utf8CString.withUnsafeBytes { src in
                raw.copyMemory(from: UnsafeRawBufferPointer(rebasing: src.prefix(raw.count - 1)))
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            if errno == ENOENT || errno == ECONNREFUSED {
                throw DaemonClientError.notRunning
            }
            throw DaemonClientError.connectionFailed(String(cString: strerror(errno)))
        }

        var payload = try JSONEncoder().encode(request)
        payload.append(0x0A)
        let sent = payload.withUnsafeBytes { raw in
            write(fd, raw.baseAddress, raw.count)
        }
        guard sent == payload.count else {
            throw DaemonClientError.connectionFailed("short write")
        }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while buffer.count < 1_048_576 {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
            if chunk[0..<n].contains(0x0A) { break }
        }
        guard let newline = buffer.firstIndex(of: 0x0A) else {
            throw DaemonClientError.badResponse("no reply")
        }

        do {
            return try JSONDecoder().decode(DaemonResponse.self, from: buffer[..<newline])
        } catch {
            throw DaemonClientError.badResponse("\(error)")
        }
    }
}

enum FanMode: String, Codable, CaseIterable, Sendable {
    /// The SMC's built-in fan curve — Apple's default behavior.
    case auto
    /// Fixed RPM per fan, chosen by the user.
    case manual
    /// Fans ramp between min and max to hold temperature below a target.
    case curve
}

struct DaemonConfig: Codable, Equatable, Sendable {
    var mode: FanMode
    /// Desired RPM per fan id; used in `.manual` mode.
    var manualRPM: [Double]
    /// Temperature ceiling in °C; used in `.curve` mode.
    var targetTemp: Double

    init(mode: FanMode = .auto, manualRPM: [Double] = [], targetTemp: Double = 75) {
        self.mode = mode
        self.manualRPM = manualRPM
        self.targetTemp = targetTemp
    }
}

struct FanStatus: Codable, Identifiable, Sendable {
    var id: Int
    var name: String
    var actualRPM: Double
    var targetRPM: Double
    var minRPM: Double
    var maxRPM: Double
    var forced: Bool
    /// macOS/SMC has locked this fan (parked); writes are rejected until it releases.
    var systemOverride: Bool

    /// Speed as a percentage of the fan's controllable range (min→0%, max→100%),
    /// matching how percentage inputs like `fanctl manual 60%` are interpreted.
    var percent: Double? {
        guard maxRPM > minRPM else { return nil }
        let fraction = (actualRPM - minRPM) / (maxRPM - minRPM)
        return min(max(fraction, 0), 1) * 100
    }

    init(id: Int, name: String, actualRPM: Double, targetRPM: Double,
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

struct DaemonStatus: Codable, Sendable {
    var fans: [FanStatus]
    var cpuTemp: Double?
    var gpuTemp: Double?
    var maxTemp: Double?
    /// The temperature the curve controller is regulating on.
    var controlTemp: Double?
    var config: DaemonConfig
    /// True while the 100 °C failsafe has taken over and forced max fans.
    var failsafeActive: Bool
    /// False when the daemon is running without root and cannot write to the SMC.
    var canControl: Bool
    var version: String

    init(fans: [FanStatus], cpuTemp: Double?, gpuTemp: Double?, maxTemp: Double?,
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

struct DaemonRequest: Codable, Sendable {
    var cmd: String  // "status" | "set" | "sensors"
    var config: DaemonConfig?

    init(cmd: String, config: DaemonConfig? = nil) {
        self.cmd = cmd
        self.config = config
    }
}

struct DaemonResponse: Codable, Sendable {
    var ok: Bool
    var error: String?
    var status: DaemonStatus?
}
