import Foundation
import SMC
import FanCore

/// Owns the SMC connection and applies the configured fan policy every tick.
final class FanController {
    private let smc: SMCConnection
    private let catalog: SensorCatalog
    private let lock = NSLock()

    private var config: DaemonConfig
    private let configURL: URL
    let canControl: Bool

    // Curve-mode state.
    private var lastCurveTarget: [Int: Double] = [:]
    /// Per-fan pause after the SMC refuses a control write (result 130/134).
    private var writeBackoffUntil: [Int: Date] = [:]
    /// Fans whose current refusal episode has already been logged.
    private var backoffLogged: Set<Int> = []
    /// Tracks which fans we have put into forced mode, so we can restore auto on exit.
    private var forcedByUs: Set<Int> = []
    private var failsafeActive = false
    private var lastAppliedManual: [Int: Double] = [:]
    /// Fans currently locked by macOS (F*Md == 3), so we log the transition once.
    private var systemOverridden: Set<Int> = []

    // Reading all ~330 temperature sensors is the expensive part of a tick, so
    // the tick caches its status snapshot and client polls are served from it —
    // total SMC traffic stays constant no matter how many clients poll.
    private var cachedStatus: DaemonStatus?
    private var cachedStatusAt = Date.distantPast

    /// How far below the target temp the fans start ramping (°C).
    private let curveBand = 8.0
    /// Max RPM decrease per 2 s tick. Ramp-up is deliberately unlimited —
    /// heating is urgent — while ramp-down is slewed so speeds decay quietly.
    private let slewDown = 150.0

    init() throws {
        smc = try SMCConnection()
        catalog = SensorCatalog(smc: smc)
        canControl = geteuid() == 0

        if geteuid() == 0 {
            configURL = URL(fileURLWithPath: "/Library/Preferences/com.norbu.MacUnseen.fans.json")
        } else {
            configURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/fanctld/config.json")
        }
        config = FanController.loadConfig(from: configURL) ?? DaemonConfig()

        log("fanctld \(FanControlConstants.version) starting: \(smc.fanCount()) fan(s), "
            + "\(catalog.temperatureKeys.count) temp sensors, "
            + (canControl ? "control enabled" : "READ-ONLY (not running as root)"))

        // Reconcile leftovers from a previous instance that died uncleanly: a
        // crash can strand fans forced (worst case with a zeroed target). Hand
        // everything back to the SMC; the policy re-engages on the first tick.
        if canControl {
            for fan in smc.allFans() where fan.forced {
                log("startup: \(fan.name) was left forced at \(Int(fan.targetRPM)) RPM — restoring auto")
                try? smc.setFanForced(fan.id, forced: false)
            }
        }
    }

    // MARK: Config persistence

    private static func loadConfig(from url: URL) -> DaemonConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DaemonConfig.self, from: data)
    }

    private func persistConfig() {
        do {
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: configURL, options: .atomic)
        } catch {
            log("warning: failed to persist config: \(error)")
        }
    }

    // MARK: Public API (called from the socket server threads)

    func currentStatus() -> DaemonStatus {
        lock.lock()
        defer { lock.unlock() }
        if let cachedStatus, Date().timeIntervalSince(cachedStatusAt) < 3 {
            return cachedStatus
        }
        refreshStatusCacheLocked(summary: catalog.summary())
        return cachedStatus!
    }

    private func refreshStatusCacheLocked(summary: SensorCatalog.Summary) {
        cachedStatus = buildStatusLocked(summary: summary)
        cachedStatusAt = Date()
    }

    func currentSensors() -> [SensorStatus] {
        catalog.readAll().map {
            SensorStatus(key: $0.key, group: $0.group.rawValue, value: $0.value)
        }
    }

    func applyConfig(_ newConfig: DaemonConfig) throws -> DaemonStatus {
        guard canControl else {
            throw SMCError.notPrivileged
        }
        lock.lock()
        defer { lock.unlock() }

        var sanitized = newConfig
        sanitized.targetTemp = min(max(newConfig.targetTemp, 60), 95)

        let fans = smc.allFans()
        // Ensure one manual RPM entry per fan, clamped to hardware limits.
        var manual = sanitized.manualRPM
        for fan in fans {
            let requested = fan.id < manual.count ? manual[fan.id] : fan.minRPM
            let clamped = min(max(requested, fan.minRPM), fan.maxRPM)
            if fan.id < manual.count {
                manual[fan.id] = clamped
            } else {
                manual.append(clamped)
            }
        }
        sanitized.manualRPM = Array(manual.prefix(fans.count))

        let modeChanged = sanitized.mode != config.mode
        config = sanitized
        persistConfig()

        if modeChanged {
            // Reset per-mode state so the new mode starts fresh.
            lastCurveTarget = [:]
            lastAppliedManual = [:]
        }
        log("config applied: mode=\(config.mode.rawValue) manual=\(config.manualRPM.map { Int($0) }) target=\(Int(config.targetTemp))°C")

        let summary = catalog.summary()
        applyPolicyLocked(summary: summary)
        refreshStatusCacheLocked(summary: summary)
        return cachedStatus!
    }

    // MARK: Control loop

    func tick() {
        lock.lock()
        defer { lock.unlock() }
        let summary = catalog.summary()
        applyPolicyLocked(summary: summary)
        refreshStatusCacheLocked(summary: summary)
    }

    /// Restore full SMC auto control. Called on shutdown and on unrecoverable errors.
    func restoreAuto() {
        lock.lock()
        defer { lock.unlock() }
        guard canControl else { return }
        for id in 0..<smc.fanCount() {
            try? smc.setFanForced(id, forced: false)
        }
        forcedByUs = []
        log("restored SMC automatic fan control")
    }

    // MARK: Internals (call with lock held)

    private func controlTemp(from summary: SensorCatalog.Summary) -> Double? {
        // Regulate on the hottest of CPU/GPU; fall back to the hottest anything.
        let candidates = [summary.cpuHot, summary.gpuHot].compactMap { $0 }
        return candidates.max() ?? summary.overallMax
    }

    private func buildStatusLocked(summary: SensorCatalog.Summary) -> DaemonStatus {
        let fans = smc.allFans().map { fan in
            FanStatus(
                id: fan.id, name: fan.name, actualRPM: fan.actualRPM,
                targetRPM: fan.targetRPM, minRPM: fan.minRPM, maxRPM: fan.maxRPM,
                forced: fan.forced, systemOverride: fan.systemOverride)
        }
        return DaemonStatus(
            fans: fans,
            cpuTemp: summary.cpuHot,
            gpuTemp: summary.gpuHot,
            maxTemp: summary.overallMax,
            controlTemp: controlTemp(from: summary),
            config: config,
            failsafeActive: failsafeActive,
            canControl: canControl,
            version: FanControlConstants.version)
    }

    private func applyPolicyLocked(summary: SensorCatalog.Summary) {
        guard canControl else { return }
        // Drop fans whose min/max limits failed to read this tick — controlling
        // them would clamp targets against garbage (e.g. 0 RPM).
        let allFans = smc.allFans().filter { $0.maxRPM > $0.minRPM && $0.maxRPM > 0 }
        guard !allFans.isEmpty else { return }

        // Fans macOS has locked (F*Md == 3, typically parked at 0 RPM after we
        // overcooled the machine): every write is rejected until the system
        // releases them, so stand down instead of fighting, and resume
        // automatically once the mode returns to auto/forced.
        for fan in allFans where fan.systemOverride && !systemOverridden.contains(fan.id) {
            log("\(fan.name): macOS took control (mode \(fan.modeRaw)) — standing down until released")
            systemOverridden.insert(fan.id)
            forcedByUs.remove(fan.id)
            lastCurveTarget[fan.id] = nil
            lastAppliedManual[fan.id] = nil
        }
        for fan in allFans where !fan.systemOverride && systemOverridden.contains(fan.id) {
            log("\(fan.name): macOS released control — resuming \(config.mode.rawValue) policy")
            systemOverridden.remove(fan.id)
        }

        let temp = controlTemp(from: summary)

        // Parked fans are normally left alone (fighting a cold-idle park is
        // futile and flappy). But once temps rise into territory where our
        // policy wants airflow, start knocking: the SMC accepts control writes
        // again at some point during warm-up, and every tick we reclaim early
        // is a tick of cooling Apple's lazier curve wouldn't have given us.
        let wantsAirflow: Bool
        switch config.mode {
        case .auto:
            wantsAirflow = false
        case .manual:
            wantsAirflow = true
        case .curve:
            wantsAirflow = temp.map { $0 > config.targetTemp - curveBand } ?? true
        }

        let fans = allFans.filter { !$0.systemOverride || wantsAirflow }
        guard !fans.isEmpty else { return }

        // Failsafe: regardless of mode, if we can't read temps or something is
        // critically hot while we are overriding Apple's curve, force max fans.
        if config.mode != .auto {
            if let t = temp {
                if t >= FanControlConstants.failsafeTemp { failsafeActive = true }
                if t < FanControlConstants.failsafeReleaseTemp { failsafeActive = false }
            } else {
                // Sensor readings vanished while we're in control: fail safe.
                failsafeActive = true
            }
        } else {
            failsafeActive = false
        }

        if failsafeActive {
            for fan in fans {
                forceLocked(fan, rpm: fan.maxRPM)
            }
            return
        }

        switch config.mode {
        case .auto:
            for fan in fans where forcedByUs.contains(fan.id) || fan.forced {
                try? smc.setFanForced(fan.id, forced: false)
                forcedByUs.remove(fan.id)
            }

        case .manual:
            for fan in fans {
                let requested = fan.id < config.manualRPM.count
                    ? config.manualRPM[fan.id] : fan.minRPM
                let rpm = min(max(requested, fan.minRPM), fan.maxRPM)
                // Skip identical writes, but verify the hardware readback so an
                // outside writer can't silently unpin the target.
                if lastAppliedManual[fan.id] != rpm || !fan.forced
                    || abs(fan.targetRPM - rpm) > 25 {
                    forceLocked(fan, rpm: rpm)
                    lastAppliedManual[fan.id] = rpm
                }
            }

        case .curve:
            applyCurveLocked(fans: fans, temp: temp)
        }
    }

    private func applyCurveLocked(fans: [SMCFan], temp: Double?) {
        guard let temp else { return }
        let target = config.targetTemp

        // 0 at (target - band) → 1 at target. Hitting the target temp means max fans,
        // which is what keeps the machine *below* the ceiling.
        let raw = (temp - (target - curveBand)) / curveBand
        let fraction = min(max(raw, 0), 1)

        // The fans stay forced the whole time we're in curve mode, idling at
        // their hardware minimum (near-silent) when cool. Handing them back to
        // auto sounds nicer but costs control authority: macOS parks idle fans
        // (mode 3) and locks the SMC keys, then tolerates 100 °C+ before it
        // spins them up — exactly when a spike needs an instant response.
        for fan in fans {
            // A forced fan targeting below its hardware minimum is never
            // legitimate (stranded by an interrupted write, or an outside
            // writer). Get it spinning again immediately; the normal path
            // below re-asserts the correct target this same tick.
            if fan.forced && fan.targetRPM < fan.minRPM {
                log("recovering \(fan.name): forced at \(Int(fan.targetRPM)) RPM (below min \(Int(fan.minRPM)))")
                try? smc.setFanTarget(fan.id, rpm: fan.minRPM)
                lastCurveTarget[fan.id] = nil
            }

            let desired = fan.minRPM + fraction * (fan.maxRPM - fan.minRPM)

            // Heating is urgent, cooling is not: follow increases immediately
            // (a spike reaches max fans in one tick), and slew-limit only the
            // ramp-down so speeds decay smoothly instead of pumping.
            let previous = lastCurveTarget[fan.id] ?? max(fan.actualRPM, fan.minRPM)
            let rpm = desired >= previous ? desired : max(desired, previous - slewDown)
            let clamped = min(max(rpm, fan.minRPM), fan.maxRPM)

            // Re-assert when our plan changed OR when the hardware readback
            // deviates from it — memory alone goes stale if an outside writer
            // (or an SMC reset) changes the target underneath us.
            if !fan.forced || abs((lastCurveTarget[fan.id] ?? 0) - clamped) > 25
                || abs(fan.targetRPM - clamped) > 25 {
                forceLocked(fan, rpm: clamped)
            }
            lastCurveTarget[fan.id] = clamped
        }
    }

    private func forceLocked(_ fan: SMCFan, rpm: Double) {
        // The SMC refuses control writes (results 130/134) while it holds the
        // fans (mode 3) and briefly around override transitions — keep
        // retrying on a short leash instead of spamming every tick.
        if let until = writeBackoffUntil[fan.id], until > Date() { return }

        do {
            if !fan.forced || !forcedByUs.contains(fan.id) {
                try smc.setFanForced(fan.id, forced: true)
                forcedByUs.insert(fan.id)
            }
            try smc.setFanTarget(fan.id, rpm: min(max(rpm, fan.minRPM), fan.maxRPM))
            writeBackoffUntil[fan.id] = nil
            if backoffLogged.remove(fan.id) != nil {
                log("\(fan.name): SMC accepted control again")
            }
        } catch {
            if case SMCError.smcResult(let code, _) = error, code == 130 || code == 134 {
                if !backoffLogged.contains(fan.id) {
                    log("\(fan.name): SMC refused control (result \(code)) — retrying every 4s")
                    backoffLogged.insert(fan.id)
                }
                writeBackoffUntil[fan.id] = Date().addingTimeInterval(4)
                forcedByUs.remove(fan.id)
            } else {
                log("error: failed to set \(fan.name) to \(Int(rpm)) RPM: \(error)")
            }
        }
    }
}

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    print("[\(stamp)] \(message)")
    fflush(stdout)
}
