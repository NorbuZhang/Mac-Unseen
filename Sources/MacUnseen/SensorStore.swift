// SPDX-License-Identifier: MPL-2.0

import AppKit
@preconcurrency import CoreLocation
import Foundation
import TrackpadBridge

@MainActor
final class SensorStore:
    NSObject,
    ObservableObject,
    @preconcurrency CLLocationManagerDelegate
{
    @Published var selectedSection: DashboardSection? = .overview {
        didSet {
            if selectedSection == .network {
                if oldValue != .network {
                    forceNetworkPortRefresh = true
                }
                requestNetworkLocationAccessIfNeeded()
            }
            configureTrackpadForSelectedSection()
            if selectedSection == .temperature {
                temperatureDiscoveryStartedAt = Date()
            } else {
                expandedTemperatureGroups.removeAll()
            }
            writeAdvancedConfiguration()
            restartHardwareStatusRefreshing()
            if appIsActive {
                refreshSelectedSection(force: true)
            }
        }
    }
    @Published var system = SystemSnapshot()
    @Published var battery = BatterySnapshot()
    @Published var storage = StorageSnapshot()
    @Published var network = NetworkSnapshot()
    @Published var advanced = AdvancedSnapshot()
    @Published var trackpadTouches: [TrackpadTouch] = []
    @Published var trackpadDetails = TrackpadDetails()
    @Published var trackpadAvailable = false
    @Published var trackpadPressureHistory: [Double] = []
    @Published private(set) var expandedTemperatureGroups = Set<String>()
    @Published var vibrationHistory: [Double] = []
    @Published var targetIMUSampleRate = 100 {
        didSet {
            writeAdvancedConfiguration()
        }
    }
    @Published var isAuthorizing = false
    @Published private(set) var isConnectingAdvancedSensors = false
    @Published var authorizationMessage: String?
    @Published var isMagicAnglePresented = false
    @Published private(set) var advancedSensorsActive = false
    let launchMottoIndex = ComputerMottos.randomIndex()

    var launchMotto: String {
        ComputerMottos.motto(
            at: launchMottoIndex,
            language: AppLocalization.language
        )
    }

    var advancedAccessPending: Bool {
        isAuthorizing || isConnectingAdvancedSensors
    }

    var advancedAccessButtonTitle: String {
        if isAuthorizing {
            return "等待系统授权…"
        }
        if isConnectingAdvancedSensors {
            return "正在连接传感器…"
        }
        return "启用隐藏传感器 🤫"
    }

    var displayedTrackpadTouches: [TrackpadTouch] {
        trackpadTouches
    }

    private var refreshTask: Task<Void, Never>?
    private var hardwareStatusTask: Task<Void, Never>?
    private var magicAngleCandidateStartedAt: Date?
    private var magicAngleArmed = true
    private var appIsActive = true
    private let locationManager = CLLocationManager()
    private var pageIsScrolling = false
    private var temperatureDiscoveryStartedAt: Date?
    private var advancedSnapshotStaleSince: Date?
    private var advancedConnectionStartedAt: Date?
    private var lastAdvancedSnapshotModificationDate: Date?
    private var lastAdvancedSnapshotTimestamp: Date?
    private var lastAdvancedSnapshotStatus: String?
    private var lastSystemRefresh = Date.distantPast
    private var lastDiskUsageRefresh = Date.distantPast
    private var lastBatteryRefresh = Date.distantPast
    private var lastBatterySlowRefresh = Date.distantPast
    private var lastAdvancedStatusRefresh = Date.distantPast
    private var storageMetadataLoaded = false
    private var lastNetworkPortRefresh = Date.distantPast
    private var forceNetworkPortRefresh = false
    private let advancedDirectory: URL
    private let advancedOutputURL: URL
    private let advancedStopURL: URL
    private let advancedLogURL: URL
    private let advancedConfigURL: URL

    override init() {
        let directory = URL(
            fileURLWithPath: "/tmp/MacUnseen-\(getuid())",
            isDirectory: true
        )
        advancedDirectory = directory
        advancedOutputURL = directory.appendingPathComponent("advanced.json")
        advancedStopURL = directory.appendingPathComponent("stop")
        advancedLogURL = directory.appendingPathComponent("helper.log")
        advancedConfigURL = directory.appendingPathComponent("config.json")
        super.init()
        locationManager.delegate = self

        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        writeAdvancedConfiguration()
        system = SystemReader.readSystem()
        lastSystemRefresh = Date()
        lastDiskUsageRefresh = Date()
        battery = SystemReader.readBattery()
        lastBatterySlowRefresh = Date()
        readAdvancedSnapshot(publishData: true)
        startRefreshing()
    }

    func startAdvancedSensors() {
        guard !advancedAccessPending else {
            return
        }
        guard let helper = Bundle.main.url(
            forResource: "advanced_sensor_helper",
            withExtension: "py"
        ),
        let ismc = Bundle.main.url(forResource: "iSMC", withExtension: nil),
        let fanProbe = Bundle.main.url(
            forResource: "FanSpeedProbe",
            withExtension: nil
        ),
        let smartctl = Bundle.main.url(forResource: "smartctl", withExtension: nil)
        else {
            authorizationMessage = "应用资源不完整，请重新构建应用。"
            return
        }

        try? FileManager.default.removeItem(at: advancedStopURL)
        if !advancedSensorsActive {
            try? FileManager.default.removeItem(at: advancedOutputURL)
        }
        lastAdvancedSnapshotModificationDate = nil
        lastAdvancedSnapshotTimestamp = nil
        lastAdvancedSnapshotStatus = nil
        isAuthorizing = true
        isConnectingAdvancedSensors = false
        advancedConnectionStartedAt = nil
        authorizationMessage = "等待管理员授权…"

        let outputPath = advancedOutputURL.path
        let stopPath = advancedStopURL.path
        let logPath = advancedLogURL.path
        let configPath = advancedConfigURL.path
        let helperPath = helper.path
        let ismcPath = ismc.path
        let fanProbePath = fanProbe.path
        let smartctlPath = smartctl.path

        Task {
            let launchResult = await Task.detached(priority: .userInitiated) {
                Self.launchPrivilegedHelper(
                    helperPath: helperPath,
                    ismcPath: ismcPath,
                    fanProbePath: fanProbePath,
                    smartctlPath: smartctlPath,
                    outputPath: outputPath,
                    stopPath: stopPath,
                    logPath: logPath,
                    configPath: configPath
                )
            }.value
            isAuthorizing = false
            authorizationMessage = launchResult.message
            if launchResult.success {
                isConnectingAdvancedSensors = true
                advancedConnectionStartedAt = Date()
                advanced.status = "正在连接"
                readAdvancedSnapshot(publishData: true)
            } else {
                isConnectingAdvancedSensors = false
                advancedConnectionStartedAt = nil
            }
        }
    }

    func stopAdvancedSensors() {
        let data = Data("stop".utf8)
        FileManager.default.createFile(
            atPath: advancedStopURL.path,
            contents: data
        )
        authorizationMessage = "已请求停止高级传感器。"
        isAuthorizing = false
        isConnectingAdvancedSensors = false
        advancedConnectionStartedAt = nil
        advancedSensorsActive = false
    }

    func dismissMagicAngle() {
        isMagicAnglePresented = false
    }

    func setAppActive(_ active: Bool) {
        guard appIsActive != active else {
            return
        }
        appIsActive = active
        advancedSnapshotStaleSince = nil
        writeAdvancedConfiguration()
        if active {
            configureTrackpadForSelectedSection()
            restartHardwareStatusRefreshing()
            refreshSelectedSection(force: true)
        } else {
            hardwareStatusTask?.cancel()
            hardwareStatusTask = nil
            stopTrackpad()
        }
    }

    func setTemperatureGroup(_ id: String, expanded: Bool) {
        if expanded {
            expandedTemperatureGroups.insert(id)
        } else {
            expandedTemperatureGroups.remove(id)
        }
        writeAdvancedConfiguration()
    }

    func isTemperatureGroupExpanded(_ id: String) -> Bool {
        expandedTemperatureGroups.contains(id)
    }

    func setPageScrolling(_ scrolling: Bool) {
        guard pageIsScrolling != scrolling else {
            return
        }
        pageIsScrolling = scrolling
        if scrolling, selectedSection == .trackpad {
            trackpadTouches = []
        }
    }

    private func requestNetworkLocationAccessIfNeeded() {
        guard CLLocationManager.locationServicesEnabled(),
              locationManager.authorizationStatus == .notDetermined else {
            return
        }
        locationManager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        guard selectedSection == .network else {
            return
        }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            restartHardwareStatusRefreshing()
        default:
            break
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        hardwareStatusTask?.cancel()
        hardwareStatusTask = nil
        stopTrackpad()
        stopAdvancedSensors()
    }

    private func configureTrackpadForSelectedSection() {
        guard appIsActive, selectedSection == .trackpad else {
            stopTrackpad()
            return
        }
        startTrackpad()
    }

    private func startTrackpad() {
        trackpadAvailable = SLTrackpadIsAvailable() != 0
        if trackpadAvailable {
            _ = SLTrackpadStart()
            updateTrackpadInfo()
        }
    }

    private func stopTrackpad() {
        guard trackpadDetails.running || !trackpadTouches.isEmpty else {
            return
        }
        SLTrackpadStop()
        trackpadTouches = []
        trackpadDetails.running = false
    }

    private func startRefreshing() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                if appIsActive {
                    refreshSelectedSection()
                } else if Date().timeIntervalSince(lastAdvancedStatusRefresh) >= 2 {
                    readAdvancedSnapshot(publishData: false)
                }
                try? await Task.sleep(
                    for: refreshInterval
                )
            }
        }
    }

    private func restartHardwareStatusRefreshing() {
        hardwareStatusTask?.cancel()
        hardwareStatusTask = nil
        guard appIsActive,
              selectedSection == .storage || selectedSection == .network else {
            return
        }
        let section = selectedSection
        let includeStorageMetadata = !storageMetadataLoaded
        hardwareStatusTask = Task { [weak self] in
            var shouldIncludeStorageMetadata = includeStorageMetadata
            while !Task.isCancelled {
                if section == .storage {
                    let includeMetadata = shouldIncludeStorageMetadata
                    let value = await Task.detached(priority: .utility) {
                        HardwareStatusReader.readStorage(
                            includeDeviceMetadata: includeMetadata
                        )
                    }.value
                    guard let self, !Task.isCancelled,
                          self.selectedSection == .storage else {
                        return
                    }
                    storage = Self.mergingStorageMetadata(
                        from: storage,
                        into: value
                    )
                    storageMetadataLoaded = true
                    shouldIncludeStorageMetadata = false
                } else {
                    guard let self else {
                        return
                    }
                    let includePorts = forceNetworkPortRefresh
                        || Date().timeIntervalSince(lastNetworkPortRefresh) >= 30
                    let previous = network
                    let value = await Task.detached(priority: .utility) {
                        HardwareStatusReader.readNetwork(
                            preserving: previous,
                            includePorts: includePorts
                        )
                    }.value
                    guard !Task.isCancelled,
                          selectedSection == .network else {
                        return
                    }
                    network = value
                    if includePorts {
                        lastNetworkPortRefresh = Date()
                        forceNetworkPortRefresh = false
                    }
                }
                guard !Task.isCancelled else {
                    return
                }
                try? await Task.sleep(
                    for: .seconds(section == .network ? 5 : 60)
                )
            }
        }
    }

    private var refreshInterval: Duration {
        guard appIsActive else {
            return .seconds(1)
        }
        switch selectedSection ?? .overview {
        case .motion, .environment, .trackpad:
            return .milliseconds(100)
        case .temperature, .fans:
            return .seconds(1)
        case .storage:
            return .seconds(2)
        default:
            return .seconds(1)
        }
    }

    private func refreshSelectedSection(force: Bool = false) {
        let section = selectedSection ?? .overview
        let now = Date()
        if pageIsScrolling {
            if now.timeIntervalSince(lastAdvancedStatusRefresh) >= 2 {
                readAdvancedSnapshot(publishData: false)
            }
            return
        }
        var readAdvanced = false
        switch section {
        case .overview:
            if force || now.timeIntervalSince(lastSystemRefresh) >= 2 {
                let includeDiskUsage = now.timeIntervalSince(
                    lastDiskUsageRefresh
                ) >= 300
                system = SystemReader.readSystem(
                    preserving: system,
                    includeStatic: false,
                    includeDiskUsage: includeDiskUsage
                )
                lastSystemRefresh = now
                if includeDiskUsage {
                    lastDiskUsageRefresh = now
                }
            }
            readAdvancedSnapshot(publishData: true)
            readAdvanced = true
        case .motion:
            readAdvancedSnapshot(publishData: true)
            readAdvanced = true
            Self.appendHistory(
                advanced.motion.vibrationRMS,
                to: &vibrationHistory
            )
        case .environment:
            readAdvancedSnapshot(publishData: true)
            readAdvanced = true
        case .trackpad:
            readTrackpadTouches()
            if let pressure = trackpadTouches.map(\.pressure).max() {
                Self.appendHistory(pressure, to: &trackpadPressureHistory)
            }
        case .temperature, .fans, .storage:
            readAdvancedSnapshot(publishData: true)
            readAdvanced = true
        case .battery:
            if force || now.timeIntervalSince(lastBatteryRefresh) >= 2 {
                let includeSlow = now.timeIntervalSince(
                    lastBatterySlowRefresh
                ) >= 300
                battery = SystemReader.readBattery(
                    preserving: battery,
                    includeStatic: false,
                    includeSlow: includeSlow
                )
                lastBatteryRefresh = now
                if includeSlow {
                    lastBatterySlowRefresh = now
                }
            }
        case .network, .about:
            break
        }
        if !readAdvanced,
           now.timeIntervalSince(lastAdvancedStatusRefresh) >= 2 {
            readAdvancedSnapshot(publishData: false)
        }
    }

    private static func mergingStorageMetadata(
        from previous: StorageSnapshot,
        into current: StorageSnapshot
    ) -> StorageSnapshot {
        var merged = current
        merged.disks = current.disks.map { disk in
            guard disk.trimEnabled == nil,
                  let old = previous.disks.first(where: {
                      $0.bsdName == disk.bsdName
                  }) else {
                return disk
            }
            var updated = disk
            updated.trimEnabled = old.trimEnabled
            return updated
        }
        return merged
    }

    private static func appendHistory(
        _ value: Double,
        to history: inout [Double]
    ) {
        history.append(value)
        if history.count > 180 {
            history.removeFirst(history.count - 180)
        }
    }

    private func readAdvancedSnapshot(publishData: Bool) {
        let modificationDate = try? advancedOutputURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
        if modificationDate == lastAdvancedSnapshotModificationDate {
            lastAdvancedStatusRefresh = Date()
            updateAdvancedAvailability(
                timestamp: lastAdvancedSnapshotTimestamp,
                status: lastAdvancedSnapshotStatus
            )
            return
        }
        guard let data = try? Data(contentsOf: advancedOutputURL),
              let snapshot = AdvancedSnapshotParser.parse(data)
        else {
            updateAdvancedAvailability(timestamp: nil, status: nil)
            return
        }
        lastAdvancedSnapshotModificationDate = modificationDate
        lastAdvancedSnapshotTimestamp = snapshot.timestamp
        lastAdvancedSnapshotStatus = snapshot.status
        lastAdvancedStatusRefresh = Date()
        updateAdvancedAvailability(
            timestamp: snapshot.timestamp,
            status: snapshot.status
        )
        guard publishData else {
            return
        }

        var updated = advanced
        updated.status = snapshot.status
        updated.timestamp = snapshot.timestamp
        updated.collectorTimestamps = snapshot.collectorTimestamps
        updated.collectorErrors = snapshot.collectorErrors
        updated.capabilities = snapshot.capabilities
        updated.errors = snapshot.errors
        switch selectedSection ?? .overview {
        case .overview:
            updated.telemetry["Power"] = snapshot.telemetry["Power"]
        case .motion:
            updated.motion = snapshot.motion
        case .environment:
            updated.environment = snapshot.environment
            updateMagicAngle(snapshot.environment.lidAngle)
        case .temperature:
            updateTemperatureTelemetry(from: snapshot, in: &updated)
        case .fans:
            updated.telemetry["Fans"] = snapshot.telemetry["Fans"]
        case .storage:
            updated.storageSMART = snapshot.storageSMART
        case .trackpad, .battery, .network, .about:
            break
        }
        if updated != advanced {
            advanced = updated
        }
    }

    private func updateAdvancedAvailability(
        timestamp: Date?,
        status: String?
    ) {
        guard let timestamp, status == "running" else {
            if status == "stopped" || status == "error" {
                advancedSensorsActive = false
                isConnectingAdvancedSensors = false
                advancedConnectionStartedAt = nil
                advancedSnapshotStaleSince = nil
            }
            updateAdvancedConnectionTimeout()
            return
        }
        let timeout = appIsActive ? 6.0 : 20.0
        if Date().timeIntervalSince(timestamp) < timeout {
            advancedSensorsActive = true
            isConnectingAdvancedSensors = false
            advancedConnectionStartedAt = nil
            authorizationMessage = nil
            advancedSnapshotStaleSince = nil
            return
        }
        guard advancedSensorsActive else {
            return
        }
        let now = Date()
        guard let staleSince = advancedSnapshotStaleSince else {
            advancedSnapshotStaleSince = now
            return
        }
        if now.timeIntervalSince(staleSince) >= timeout {
            advancedSensorsActive = false
        }
        updateAdvancedConnectionTimeout(now: now)
    }

    private func updateAdvancedConnectionTimeout(now: Date = Date()) {
        guard isConnectingAdvancedSensors,
              let startedAt = advancedConnectionStartedAt,
              now.timeIntervalSince(startedAt) >= 20 else {
            return
        }
        isConnectingAdvancedSensors = false
        advancedConnectionStartedAt = nil
        authorizationMessage = advancedHelperFailureMessage()
            ?? "传感器连接超时，请重试。"
    }

    private func advancedHelperFailureMessage() -> String? {
        guard let data = try? Data(contentsOf: advancedLogURL),
              let log = String(data: data, encoding: .utf8) else {
            return nil
        }
        let lines = log.split(whereSeparator: \.isNewline)
        guard let lastLine = lines.last?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !lastLine.isEmpty else {
            return nil
        }
        return "高级传感器启动失败：\(lastLine)"
    }

    private func updateTemperatureTelemetry(
        from snapshot: AdvancedSnapshot,
        in updated: inout AdvancedSnapshot
    ) {
        let metrics = snapshot.telemetry["Temperature"] ?? []
        if let discoveryStartedAt = temperatureDiscoveryStartedAt {
            guard snapshot.collectorTimestamps["temperature"].map({
                $0 >= discoveryStartedAt
            }) == true else {
                return
            }
            if !metrics.isEmpty {
                updated.telemetry["Temperature"] = metrics
                temperatureDiscoveryStartedAt = nil
            }
            return
        }
        guard !expandedTemperatureGroups.isEmpty else {
            return
        }
        var merged = Dictionary(
            uniqueKeysWithValues: (
                updated.telemetry["Temperature"] ?? []
            ).map { ($0.id, $0) }
        )
        for metric in metrics
        where expandedTemperatureGroups.contains(
            temperatureCategory(for: metric.name)
        ) {
            merged[metric.id] = metric
        }
        updated.telemetry["Temperature"] = merged.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func updateMagicAngle(_ angle: Double?, now: Date = Date()) {
        guard selectedSection == .environment else {
            magicAngleCandidateStartedAt = nil
            return
        }
        guard let angle else {
            magicAngleCandidateStartedAt = nil
            return
        }

        let isAtMagicAngle = Int(angle.rounded()) == 104
        guard isAtMagicAngle else {
            magicAngleCandidateStartedAt = nil
            magicAngleArmed = true
            return
        }

        guard magicAngleArmed, !isMagicAnglePresented else {
            return
        }
        guard let startedAt = magicAngleCandidateStartedAt else {
            magicAngleCandidateStartedAt = now
            return
        }
        guard now.timeIntervalSince(startedAt) >= 2 else {
            return
        }

        magicAngleCandidateStartedAt = nil
        magicAngleArmed = false
        isMagicAnglePresented = true
    }

    private func readTrackpadTouches() {
        guard trackpadAvailable else {
            return
        }
        var rawTouches = [SLTouchPoint](
            repeating: SLTouchPoint(),
            count: Int(SL_MAX_TOUCHES)
        )
        let count = rawTouches.withUnsafeMutableBufferPointer { buffer in
            SLTrackpadCopyTouches(buffer.baseAddress, Int32(buffer.count))
        }
        let touches = rawTouches.prefix(Int(count)).map { touch in
            TrackpadTouch(
                id: touch.identifier,
                state: touch.state,
                x: Double(touch.x),
                y: Double(touch.y),
                velocityX: Double(touch.velocity_x),
                velocityY: Double(touch.velocity_y),
                total: Double(touch.total),
                pressure: Double(touch.pressure),
                angle: Double(touch.angle),
                majorAxis: Double(touch.major_axis),
                minorAxis: Double(touch.minor_axis),
                density: Double(touch.density)
            )
        }
        trackpadTouches = touches
    }

    private func updateTrackpadInfo() {
        let info = SLTrackpadGetInfo()
        trackpadDetails = TrackpadDetails(
            surfaceWidth: Int(info.surface_width),
            surfaceHeight: Int(info.surface_height),
            sensorRows: Int(info.sensor_rows),
            sensorColumns: Int(info.sensor_columns),
            familyID: Int(info.family_id),
            deviceID: info.device_id,
            builtIn: info.built_in != 0,
            running: info.running != 0
        )
    }

    private struct LaunchResult: Sendable {
        let success: Bool
        let message: String
    }

    nonisolated private static func launchPrivilegedHelper(
        helperPath: String,
        ismcPath: String,
        fanProbePath: String,
        smartctlPath: String,
        outputPath: String,
        stopPath: String,
        logPath: String,
        configPath: String
    ) -> LaunchResult {
        let command = [
            "/usr/bin/python3", "-u",
            shellQuote(helperPath),
            "--output", shellQuote(outputPath),
            "--stop", shellQuote(stopPath),
            "--ismc", shellQuote(ismcPath),
            "--fan-probe", shellQuote(fanProbePath),
            "--smartctl", shellQuote(smartctlPath),
            "--config", shellQuote(configPath),
            ">", shellQuote(logPath),
            "2>&1",
            "< /dev/null",
            "&",
        ].joined(separator: " ")

        let script = "do shell script \(appleScriptLiteral(command)) with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return LaunchResult(
                success: false,
                message: "无法启动授权流程：\(error.localizedDescription)"
            )
        }

        if process.terminationStatus == 0 {
            return LaunchResult(
                success: true,
                message: "高级传感器正在启动，通常需要 1–3 秒。"
            )
        }
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return LaunchResult(
            success: false,
            message: text?.isEmpty == false ? text! : "管理员授权已取消。"
        )
    }

    private func writeAdvancedConfiguration() {
        let allowedRates = [25, 50, 100, 200]
        let sampleRate = allowedRates.contains(targetIMUSampleRate)
            ? targetIMUSampleRate
            : 100
        let payload: [String: Any] = [
            "imuSampleRate": sampleRate,
            "appActive": appIsActive,
            "highRateActive": appIsActive
                && (selectedSection == .motion || selectedSection == .environment),
            "activeSection": appIsActive
                ? (selectedSection ?? .overview).rawValue
                : "inactive",
            "expandedTemperatureGroups": expandedTemperatureGroups.sorted(),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }
        try? data.write(to: advancedConfigURL, options: .atomic)
    }

    nonisolated private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated private static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
