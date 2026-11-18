import SwiftUI

struct FanSpeedReading: Decodable, Sendable {
    struct Speed: Decodable, Identifiable, Sendable {
        var index: Int
        var rpm: Double
        var id: Int { index }
    }
    var fanCount: Int
    var speeds: [Speed]

    static func read() -> Self? {
        guard let probe = Bundle.main.url(forResource: "FanSpeedProbe", withExtension: nil),
              let data = SystemCommand().run(executable: probe.path, arguments: [], timeout: 1.5),
              let reading = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        return reading
    }
}

extension DaemonStatus {
    var fullSpeedTargets: [Double]? {
        guard canControl, !fans.isEmpty else { return nil }
        // The service indexes manualRPM by hardware fan ID. A partial reading
        // with missing IDs must not shift one fan's limit into another slot.
        let ordered = fans.sorted { $0.id < $1.id }
        for (index, fan) in ordered.enumerated() {
            guard fan.id == index, fan.minRPM.isFinite, fan.minRPM >= 0,
                  fan.maxRPM.isFinite, fan.maxRPM > fan.minRPM else { return nil }
        }
        return ordered.map(\.maxRPM)
    }
}

/// Both the menu and the window edit the same draft and serialize requests to the service.
@MainActor
final class FanControlSession: ObservableObject {
    @Published private(set) var status: DaemonStatus?
    @Published private(set) var didRead = false
    @Published private(set) var busy = false
    @Published private(set) var errorText: String?
    @Published private(set) var installMessage: String?
    @Published var mode = FanMode.auto
    @Published var fraction = 50.0
    @Published var ceiling = 75.0
    private var revision = 0
    @Published private(set) var readOnlySpeeds: FanSpeedReading?
    private var nextProbe = Date.distantPast
    private var refreshing = false
    private var lastRead = Date.distantPast
    private let readStatus: @Sendable () throws -> DaemonStatus
    private let writeConfig: @Sendable (DaemonConfig) throws -> DaemonStatus

    init(readStatus: @escaping @Sendable () throws -> DaemonStatus = DaemonClient.status,
         writeConfig: @escaping @Sendable (DaemonConfig) throws -> DaemonStatus = DaemonClient.apply) {
        self.readStatus = readStatus
        self.writeConfig = writeConfig
    }

    func refresh(readSpeeds: Bool = true) async {
        guard !busy, !refreshing, Date().timeIntervalSince(lastRead) >= 1 else { return }
        refreshing = true
        defer { refreshing = false }
        let atStart = revision
        let result = await Task.detached(priority: .utility) { [readStatus] in Result { try readStatus() } }.value
        guard atStart == revision else { return }
        if !didRead { didRead = true }
        lastRead = Date()
        switch result {
        case .success(let value):
            if status == nil { errorText = nil }
            receive(value)
        case .failure(let error):
            status = nil
            if case DaemonClientError.notRunning = error { errorText = nil }
            else { errorText = String(describing: error) }
            if readSpeeds, Date() >= nextProbe {
                let speeds = await Task.detached(priority: .utility) { FanSpeedReading.read() }.value
                guard atStart == revision else { return }
                readOnlySpeeds = speeds
                if speeds?.fanCount == 0 { nextProbe = .distantFuture }
                else { nextProbe = Date().addingTimeInterval(speeds == nil ? 30 : 4) }
            }
        }
    }

    private func receive(_ value: DaemonStatus, applied: Bool = false) {
        if applied || status?.config != value.config {
            mode = value.config.mode
            ceiling = value.config.targetTemp
            if let fan = value.fans.first, fan.maxRPM > fan.minRPM,
               value.config.manualRPM.indices.contains(fan.id) {
                fraction = min(100, max(0, 100 * (value.config.manualRPM[fan.id] - fan.minRPM) / (fan.maxRPM - fan.minRPM)))
            }
        }
        if readOnlySpeeds != nil { readOnlySpeeds = nil }
        nextProbe = .distantPast
        installMessage = nil
        status = value
    }

    func enableService() {
        guard !busy else { return }
        busy = true
        revision += 1
        installMessage = nil
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { try FanServiceInstaller.install() }.value
                installMessage = FanServiceInstallError.starting.localizedDescription
            } catch {
                installMessage = error.localizedDescription
            }
            busy = false
            lastRead = .distantPast
            await refresh()
        }
    }

    func rpm(for fan: FanStatus) -> Double {
        (fan.minRPM + fraction / 100 * (fan.maxRPM - fan.minRPM)).rounded()
    }

    func apply(_ requested: FanMode) {
        guard !busy, let status, status.canControl, !status.fans.isEmpty else { return }
        var draft = status.config
        draft.mode = requested
        if requested == .manual { draft.manualRPM = status.fans.sorted { $0.id < $1.id }.map(rpm(for:)) }
        if requested == .curve { draft.targetTemp = ceiling }
        submit(draft)
    }

    func applyFullSpeed() {
        guard !busy, let status, let targets = status.fullSpeedTargets else { return }
        var config = status.config
        config.mode = .manual
        config.manualRPM = targets
        submit(config)
    }

    private func submit(_ config: DaemonConfig) {
        busy = true
        revision += 1
        Task {
            defer { busy = false }
            do {
                let value = try await Task.detached(priority: .userInitiated) { [writeConfig] in try writeConfig(config) }.value
                receive(value, applied: true)
                errorText = nil
            } catch {
                errorText = String(describing: error)
            }
        }
    }
}
