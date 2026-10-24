import AppKit
import Combine
@preconcurrency import CoreLocation
import Foundation
import TrackpadBridge

@MainActor
final class SensorStore:
    NSObject,
    ObservableObject,
    @preconcurrency CLLocationManagerDelegate
{
    let navigation = DashboardNavigation()
    @Published var selectedSection: DashboardSection? = .overview {
        didSet {
            if oldValue != selectedSection {
                navigation.selectedSection = selectedSection
                if oldValue == .processes { processSnapshot = ProcessSnapshot() }
            }
            // A disappearing ScrollView may never deliver its final idle phase.
            // Do not let that stale state suspend refreshes on the next page.
            pageIsScrolling = false
            if selectedSection == .ports { forceNetworkPortRefresh = true }
            if selectedSection == .network {
                if oldValue != .network {
                    forceNetworkPortRefresh = true
                }
                requestNetworkLocationAccessIfNeeded()
            }
            restartMonitoring()
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
            startRefreshing()
        }
    }
    @Published var performance = PerformanceReading()
    @Published var processSnapshot = ProcessSnapshot()
    @Published var cpuHistory: [Double] = []
    @Published var memoryPressureHistory = MemoryPressureHistory()
    @Published var systemIdentity = SystemIdentity()
    @Published private(set) var systemRuntime = SystemRuntime()
    let systemReports = SystemReportStore()
    private var reportSubscription: AnyCancellable?
    @Published private(set) var systemDetails = SystemDetails()
    @Published private(set) var systemDetailsLoading = false
    @Published private(set) var displays: [DisplayDetails] = []
    private var systemDetailsTask: Task<Void, Never>?
    private var systemDetailsJob: SystemCommand?
    @Published private(set) var monitoringActive = false
    private var monitoringTask: Task<Void, Never>?
    @Published var system = SystemSnapshot()
    @Published var battery = BatterySnapshot()
    @Published var storage = StorageSnapshot()
    @Published var network = NetworkSnapshot()
    @Published var advanced = AdvancedSnapshot()
    @Published var trackpadTouches: [TrackpadTouch] = []
    @Published var trackpadDetails = TrackpadDetails()
    @Published var trackpadAvailable = false {
        didSet { if oldValue != trackpadAvailable { startRefreshing() } }
    }
    @Published var trackpadPressureHistory: [Double] = []
    @Published private(set) var expandedTemperatureGroups = Set<String>()
    @Published var vibrationHistory: [Double] = []
    @Published var targetIMUSampleRate = 100 {
        didSet {
            writeAdvancedConfiguration()
        }
    }
    @Published var isAuthorizing = false {
        didSet { if oldValue != isAuthorizing { startRefreshing() } }
    }
    @Published private(set) var isConnectingAdvancedSensors = false {
        didSet { if oldValue != isConnectingAdvancedSensors { startRefreshing() } }
    }
    @Published var authorizationMessage: String?
    @Published var isMagicAnglePresented = false {
        didSet {
            if oldValue != isMagicAnglePresented { navigation.isMagicAnglePresented = isMagicAnglePresented }
        }
    }
    @Published private(set) var advancedSensorsActive = false {
        didSet {
            if oldValue != advancedSensorsActive {
                navigation.advancedSensorsActive = advancedSensorsActive
                startRefreshing()
            }
        }
    }
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
    private var stopped = false
    private var hardwareStatusTask: Task<Void, Never>?
    private var hardwareStatusJob: SystemCommand?
    private var magicAngleCandidateStartedAt: Date?
    private var magicAngleArmed = true
    private var applicationIsActive = true
    private var windowIsVisible = true
    private var appIsActive: Bool { applicationIsActive && windowIsVisible }
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
    private var lastBatteryMediumRefresh = Date.distantPast
    private var lastBatterySlowRefresh = Date.distantPast
    private var magSafeFirmwareTask: Task<Void, Never>?
    private var magSafeFirmwareJob: MagSafeFirmwareJob?
    private var magSafeFirmwareRequest: MagSafeFirmwareRequest?
    private var lastMagSafeFirmwareAttempt = Date.distantPast
    private var lastAdvancedStatusRefresh = Date.distantPast
    private var storageMetadataLoaded = false
    private var lastNetworkPortRefresh = Date.distantPast
    private var forceNetworkPortRefresh = false
    private let batteryLiveRefreshInterval: TimeInterval = 0.5
    private let batteryMediumRefreshInterval: TimeInterval = 2
    private let batterySlowRefreshInterval: TimeInterval = 300
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
        systemIdentity = SystemIdentityReader.read()
        system = SystemReader.readSystem()
        lastSystemRefresh = Date()
        lastDiskUsageRefresh = Date()
        battery = SystemReader.readBattery()
        reportSubscription = systemReports.$reports.sink { [weak self] reports in
            guard let self else { return }
            let health = reports["SPPowerDataType"]?.batteryHealthPercentage
            if self.battery.healthPercentage != health { self.battery.healthPercentage = health }
        }
        lastBatteryMediumRefresh = Date()
        lastBatterySlowRefresh = Date()
        readAdvancedSnapshot(publishData: true)
        startRefreshing()
        restartMonitoring()
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
        let powerProbe = Bundle.main.url(
            forResource: "LivePowerProbe",
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
        let powerProbePath = powerProbe.path
        let smartctlPath = smartctl.path
        guard let pythonPath = Self.resolvePythonInterpreter() else {
            isAuthorizing = false
            authorizationMessage = "未找到可运行的 Python 3。请安装 python.org 或 Homebrew Python；系统 /usr/bin/python3 在未安装开发工具时不能运行高级传感器。"
            return
        }

        Task {
            let launchResult = await Task.detached(priority: .userInitiated) {
                Self.launchPrivilegedHelper(
                    pythonPath: pythonPath,
                    helperPath: helperPath,
                    ismcPath: ismcPath,
                    fanProbePath: fanProbePath,
                    powerProbePath: powerProbePath,
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
        guard applicationIsActive != active else { return }
        applicationIsActive = active
        updateActivity()
    }

    func setWindowVisible(_ visible: Bool) {
        guard windowIsVisible != visible else { return }
        windowIsVisible = visible
        updateActivity()
    }

    private func updateActivity() {
        restartMonitoring()
        advancedSnapshotStaleSince = nil
        writeAdvancedConfiguration()
        if appIsActive {
            configureTrackpadForSelectedSection()
            restartHardwareStatusRefreshing()
            refreshSelectedSection(force: true)
        } else {
            cancelHardwareStatus()
            stopTrackpad()
        }
        startRefreshing()
    }

    func setTemperatureGroup(_ id: String, expanded: Bool) {
        if expanded {
            expandedTemperatureGroups.insert(id)
        } else {
            expandedTemperatureGroups.remove(id)
        }
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
        stopped = true
        cancelMagSafeFirmware()
        systemReports.setActive(false)
        cancelSystemDetails()
        monitoringTask?.cancel()
        monitoringTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        cancelHardwareStatus()
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

    func refreshSystemInformation() {
        systemIdentity = SystemIdentityReader.read()
        system = SystemReader.readSystem()
        lastSystemRefresh = Date()
        lastDiskUsageRefresh = Date()
        if selectedSection == .battery {
            battery = SystemReader.readBattery(preserving: battery)
            refreshMagSafeFirmware(force: true)
            let refreshedAt = Date()
            lastBatteryRefresh = refreshedAt
            lastBatteryMediumRefresh = refreshedAt
            lastBatterySlowRefresh = refreshedAt
        }
        if selectedSection == .systemInfo { loadSystemDetails(force: true) }
        systemReports.refreshRequested()
    }

    func refreshDisplays() {
        guard selectedSection == .performance, appIsActive else { return }
        displays = DisplayDetailsReader.read()
    }

    private func cancelMagSafeFirmware() {
        // An interrupted attempt can be retried when the page becomes active.
        if magSafeFirmwareJob != nil { lastMagSafeFirmwareAttempt = .distantPast }
        magSafeFirmwareJob?.cancel()
        magSafeFirmwareJob = nil
        magSafeFirmwareTask?.cancel()
        magSafeFirmwareTask = nil
    }

    private func refreshMagSafeFirmware(force: Bool = false) {
        guard appIsActive, selectedSection == .battery,
              let request = battery.magSafe?.firmwareRequest else {
            cancelMagSafeFirmware()
            magSafeFirmwareRequest = nil
            return
        }
        if force || request != magSafeFirmwareRequest {
            cancelMagSafeFirmware()
            magSafeFirmwareRequest = request
            lastMagSafeFirmwareAttempt = .distantPast
        }
        guard magSafeFirmwareJob == nil,
              Date().timeIntervalSince(lastMagSafeFirmwareAttempt) >= batterySlowRefreshInterval else { return }
        lastMagSafeFirmwareAttempt = Date()
        let job = MagSafeFirmwareJob()
        magSafeFirmwareJob = job
        magSafeFirmwareTask = Task { [weak self] in
            let firmware = await Task.detached(priority: .utility) { job.run(for: request) }.value
            guard let self, !Task.isCancelled, self.magSafeFirmwareJob === job else { return }
            self.magSafeFirmwareJob = nil
            self.magSafeFirmwareTask = nil
            guard self.appIsActive, self.selectedSection == .battery,
                  self.battery.magSafe?.firmwareRequest == request else { return }
            // Recheck the physical connection after the diagnostic, so a cable
            // swapped while it ran cannot receive the old cable's version.
            var current = MagSafeReader.read(preserving: nil, refreshMetadata: true)
            if current?.firmwareRequest == request { current?.cableFirmware = firmware }
            self.battery.magSafe = current
        }
    }

    private func cancelSystemDetails() {
        systemDetailsJob?.cancel()
        systemDetailsJob = nil
        systemDetailsTask?.cancel()
        systemDetailsTask = nil
        if systemDetailsLoading { systemDetailsLoading = false }
    }

    private func loadSystemDetails(force: Bool = false) {
        guard !systemDetailsLoading, force || systemDetails.sampledAt == nil else { return }
        systemDetailsLoading = true
        let job = SystemCommand()
        systemDetailsJob = job
        systemDetailsTask = Task { [weak self] in
            let details = await Task.detached(priority: .utility) { SystemDetailsReader.read(using: job) }.value
            guard let self, !Task.isCancelled, self.systemDetailsJob === job else { return }
            self.systemDetails = details
            self.systemDetailsLoading = false
            self.systemDetailsTask = nil
            self.systemDetailsJob = nil
            if let name = details.modelName { self.system.modelName = name }
        }
    }

    private func restartMonitoring() {
        if !appIsActive || selectedSection != .battery { cancelMagSafeFirmware() }
        if !appIsActive || selectedSection != .systemInfo { cancelSystemDetails() }
        monitoringTask?.cancel()
        monitoringTask = nil
        monitoringActive = false
        memoryPressureHistory.pause()
        let section = selectedSection ?? .overview
        systemReports.show(section: section, active: appIsActive)
        if section == .battery, appIsActive { systemReports.request("SPPowerDataType", persistent: true) }
        if section == .systemInfo, appIsActive { loadSystemDetails() }
        guard let interval = MonitoringRefreshPolicy.interval(for: section, active: appIsActive) else { return }
        monitoringActive = true
        if section == .processes {
            processSnapshot = ProcessSnapshot()
        } else if section != .systemInfo {
            cpuHistory = []
            performance = PerformanceReading()
        }
        // New instance intentionally discards every cumulative-counter baseline.
        let reader = PerformanceReader()
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                if section == .systemInfo {
                    let value = await reader.sampleSystemRuntime()
                    guard let self, !Task.isCancelled, self.appIsActive,
                          self.selectedSection == section else { return }
                    self.systemRuntime = value
                } else if section == .processes {
                    let value = await reader.sampleProcesses()
                    guard let self, !Task.isCancelled, self.appIsActive,
                          self.selectedSection == section else { return }
                    self.processSnapshot = value
                } else {
                    let value = await reader.sample()
                    guard let self, !Task.isCancelled, self.appIsActive,
                          self.selectedSection == section else { return }
                    self.performance = value
                    if let date = value.sampledAt {
                        self.memoryPressureHistory.append(rawLevel: value.memory.pressure, at: date)
                    }
                    if let cpu = value.cpu {
                        self.cpuHistory.append(cpu)
                        if self.cpuHistory.count > 60 { self.cpuHistory.removeFirst(self.cpuHistory.count - 60) }
                    }
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
        guard !stopped,
              let interval = MonitoringRefreshPolicy.sensorInterval(
                for: selectedSection ?? .overview, active: appIsActive,
                advancedActive: advancedSensorsActive, advancedPending: advancedAccessPending,
                trackpadAvailable: trackpadAvailable
              ) else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                // Page and activity changes already perform an immediate read.
                // Sleep first so status transitions can safely reschedule this loop.
                do { try await Task.sleep(for: .seconds(interval)) }
                catch { return }
                guard let self, !Task.isCancelled else { return }
                if appIsActive {
                    refreshSelectedSection()
                } else if Date().timeIntervalSince(lastAdvancedStatusRefresh) >= 2 {
                    readAdvancedSnapshot(publishData: false)
                }
            }
        }
    }

    private func cancelHardwareStatus() {
        hardwareStatusJob?.cancel()
        hardwareStatusJob = nil
        hardwareStatusTask?.cancel()
        hardwareStatusTask = nil
    }

    private func restartHardwareStatusRefreshing() {
        cancelHardwareStatus()
        guard appIsActive,
              selectedSection == .storage || selectedSection == .network || selectedSection == .ports else {
            return
        }
        let section = selectedSection
        let includeStorageMetadata = !storageMetadataLoaded
        hardwareStatusTask = Task { [weak self] in
            var shouldIncludeStorageMetadata = includeStorageMetadata
            while !Task.isCancelled {
                guard let self else { return }
                let job = SystemCommand()
                self.hardwareStatusJob = job
                if section == .storage {
                    let includeMetadata = shouldIncludeStorageMetadata
                    let value = await Task.detached(priority: .utility) {
                        HardwareStatusReader.readStorage(
                            includeDeviceMetadata: includeMetadata, command: job
                        )
                    }.value
                    guard !Task.isCancelled, self.hardwareStatusJob === job,
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
                    let includePorts = section == .ports && (forceNetworkPortRefresh
                        || Date().timeIntervalSince(lastNetworkPortRefresh) >= 30)
                    let previous = network
                    let value = await Task.detached(priority: .utility) {
                        HardwareStatusReader.readNetwork(
                            preserving: previous,
                            includePorts: includePorts, command: job
                        )
                    }.value
                    guard !Task.isCancelled, self.hardwareStatusJob === job,
                          selectedSection == section else {
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
                self.hardwareStatusJob = nil
                try? await Task.sleep(
                    for: .seconds(section == .network ? 5 : section == .ports ? 30 : 60)
                )
            }
        }
    }

    private func refreshSelectedSection(force: Bool = false) {
        let section = selectedSection ?? .overview
        let now = Date()
        if pageIsScrolling && section != .battery {
            if now.timeIntervalSince(lastAdvancedStatusRefresh) >= 2 {
                readAdvancedSnapshot(publishData: false)
            }
            return
        }
        var readAdvanced = false
        switch section {
        case .overview, .performance:
            if force || now.timeIntervalSince(lastSystemRefresh) >= MonitoringRefreshPolicy.systemSummary {
                let includeDiskUsage = now.timeIntervalSince(
                    lastDiskUsageRefresh
                ) >= MonitoringRefreshPolicy.systemSummary
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
            if let report = systemReports.reports["SPPowerDataType"],
               now.timeIntervalSince(report.sampledAt) >= batterySlowRefreshInterval {
                systemReports.refresh("SPPowerDataType")
            }
            if force
                || now.timeIntervalSince(lastBatteryRefresh)
                    >= batteryLiveRefreshInterval {
                let includeSlow = now.timeIntervalSince(
                    lastBatterySlowRefresh
                ) >= batterySlowRefreshInterval
                let includeMedium = includeSlow || now.timeIntervalSince(
                    lastBatteryMediumRefresh
                ) >= batteryMediumRefreshInterval
                battery = SystemReader.readBattery(
                    preserving: battery,
                    includeStatic: false,
                    includeMedium: includeMedium,
                    includeSlow: includeSlow
                )
                lastBatteryRefresh = now
                if includeMedium {
                    lastBatteryMediumRefresh = now
                }
                if includeSlow {
                    lastBatterySlowRefresh = now
                }
            }
            refreshMagSafeFirmware()
            readAdvancedSnapshot(publishData: true)
            readAdvanced = true
        case .network, .ports, .processes, .systemInfo, .about, .support:
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
        case .battery:
            updated.telemetry["Power"] = snapshot.telemetry["Power"]
            updated.livePower = snapshot.livePower
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
        case .trackpad, .network, .ports, .performance, .processes, .systemInfo, .about, .support:
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
                if advancedSensorsActive { advancedSensorsActive = false }
                if isConnectingAdvancedSensors { isConnectingAdvancedSensors = false }
                advancedConnectionStartedAt = nil
                advancedSnapshotStaleSince = nil
            }
            updateAdvancedConnectionTimeout()
            return
        }
        let timeout = appIsActive ? 6.0 : 20.0
        if Date().timeIntervalSince(timestamp) < timeout {
            if !advancedSensorsActive { advancedSensorsActive = true }
            if isConnectingAdvancedSensors { isConnectingAdvancedSensors = false }
            advancedConnectionStartedAt = nil
            if authorizationMessage != nil { authorizationMessage = nil }
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
        if Self.isXcodeSelectPythonFailure(log) {
            return "高级传感器启动失败：系统 /usr/bin/python3 需要 Xcode Command Line Tools。请安装 python.org 或 Homebrew Python 后重试。"
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
        }
        guard !metrics.isEmpty else {
            return
        }
        updated.telemetry["Temperature"] = metrics
        temperatureDiscoveryStartedAt = nil
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
        pythonPath: String,
        helperPath: String,
        ismcPath: String,
        fanProbePath: String,
        powerProbePath: String,
        smartctlPath: String,
        outputPath: String,
        stopPath: String,
        logPath: String,
        configPath: String
    ) -> LaunchResult {
        let command = [
            shellQuote(pythonPath), "-u",
            shellQuote(helperPath),
            "--output", shellQuote(outputPath),
            "--stop", shellQuote(stopPath),
            "--ismc", shellQuote(ismcPath),
            "--fan-probe", shellQuote(fanProbePath),
            "--power-probe", shellQuote(powerProbePath),
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

    nonisolated private static func resolvePythonInterpreter() -> String? {
        var candidates: [String] = []
        if let bundled = Bundle.main.url(
            forResource: "python3",
            withExtension: nil
        )?.path {
            candidates.append(bundled)
        }
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.10/bin/python3",
            "/Library/Developer/CommandLineTools/usr/bin/python3",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/python3",
        ])
        if developerToolsAvailable() {
            candidates.append("/usr/bin/python3")
        }

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate).inserted {
            if isUsablePython(candidate) {
                return candidate
            }
        }
        return nil
    }

    nonisolated private static func developerToolsAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    nonisolated private static func isUsablePython(_ path: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [
            "-c",
            "import ctypes,json,subprocess,sys,threading; raise SystemExit(0 if sys.version_info[0] == 3 else 1)",
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    nonisolated private static func isXcodeSelectPythonFailure(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("xcode-select")
            || text.localizedCaseInsensitiveContains("man xcode-select")
            || text.localizedCaseInsensitiveContains("command line developer tools")
    }
}
