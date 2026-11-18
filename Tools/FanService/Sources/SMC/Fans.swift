import Foundation

/// Snapshot of one fan's telemetry.
public struct SMCFan {
    public let id: Int
    public let name: String
    public let actualRPM: Double
    public let targetRPM: Double
    public let minRPM: Double
    public let maxRPM: Double
    /// Raw F*Md value: 0 = auto, 1 = forced, 3 = system override (observed on
    /// Apple Silicon when macOS parks the fans and locks out writes).
    public let modeRaw: Int
    /// True when the fan is under forced (manual) control rather than the SMC's own curve.
    public var forced: Bool { modeRaw == 1 }
    /// True when macOS/the SMC has locked the fan (writes are rejected until it releases).
    public var systemOverride: Bool { modeRaw > 1 }
}

extension SMCConnection {

    public func fanCount() -> Int {
        (try? readInteger("FNum")) ?? 0
    }

    private func fanName(id: Int, total: Int) -> String {
        if total == 2 {
            return id == 0 ? "Left Fan" : "Right Fan"
        }
        return "Fan \(id + 1)"
    }

    public func fan(_ id: Int, totalCount: Int) throws -> SMCFan {
        let actual = try readNumeric("F\(id)Ac")
        let target = (try? readNumeric("F\(id)Tg")) ?? actual
        let minRPM = (try? readNumeric("F\(id)Mn")) ?? 0
        let maxRPM = (try? readNumeric("F\(id)Mx")) ?? 0
        return SMCFan(
            id: id,
            name: fanName(id: id, total: totalCount),
            actualRPM: actual,
            targetRPM: target,
            minRPM: minRPM,
            maxRPM: maxRPM,
            modeRaw: fanMode(id))
    }

    public func allFans() -> [SMCFan] {
        let count = fanCount()
        return (0..<count).compactMap { try? fan($0, totalCount: count) }
    }

    public func fanMode(_ id: Int) -> Int {
        // Apple Silicon: per-fan mode key (0 = auto, 1 = forced, 3 = system lock).
        for key in ["F\(id)Md", "F\(id)md"] {
            if let mode = try? readInteger(key) { return mode }
        }
        // Intel: FS! is a bitmask of manually-controlled fans.
        if let mask = try? readInteger("FS! ") {
            return (mask & (1 << id)) != 0 ? 1 : 0
        }
        return 0
    }

    /// Puts a fan under forced control. Requires root.
    public func setFanForced(_ id: Int, forced: Bool) throws {
        if let key = ["F\(id)Md", "F\(id)md"].first(where: hasKey) {
            try writeNumeric(key, value: forced ? 1 : 0)
        } else if hasKey("FS! ") {
            let mask = try readInteger("FS! ")
            let newMask = forced ? (mask | (1 << id)) : (mask & ~(1 << id))
            try writeNumeric("FS! ", value: Double(newMask))
        } else {
            throw SMCError.keyNotFound("F\(id)Md")
        }
    }

    /// Sets a fan's target RPM. Only has an effect while the fan is forced. Requires root.
    public func setFanTarget(_ id: Int, rpm: Double) throws {
        try writeNumeric("F\(id)Tg", value: rpm)
    }
}
