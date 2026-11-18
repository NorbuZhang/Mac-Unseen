import XCTest
@testable import MacUnseen

final class MenuMonitorTests: XCTestCase {
    @MainActor func testMenuIsOptInAndRemembersUnifiedSelection() {
        let suite = "macunseen.tests.\(UUID())"
        let settings = UserDefaults(suiteName: suite)!
        defer { settings.removePersistentDomain(forName: suite) }
        let fresh = MenuBarMonitor(settings: settings)
        XCTAssertFalse(fresh.enabled)
        XCTAssertEqual(fresh.metric, .overview)
        settings.set("fans", forKey: "menuMonitorPanelCategory")
        XCTAssertEqual(MenuMetric.saved(in: settings), .fans)
        fresh.enabled = true
        fresh.selectMetric(.gpu)
        let relaunched = MenuBarMonitor(settings: settings)
        XCTAssertTrue(relaunched.enabled)
        XCTAssertEqual(relaunched.metric, .gpu)
        relaunched.enabled = false
        XCTAssertFalse(MenuBarMonitor(settings: settings).enabled)
        XCTAssertEqual(MenuMetric.saved(in: settings), .gpu)
    }

    @MainActor func testOverviewCanPinAnAngleWithoutLeavingOverview() {
        let suite = "macunseen.tests.\(UUID())"
        let settings = UserDefaults(suiteName: suite)!
        defer { settings.removePersistentDomain(forName: suite) }
        let monitor = MenuBarMonitor(settings: settings)
        XCTAssertEqual(monitor.statusMetric, .overview)
        monitor.selectOverviewMetric(.lidAngle)
        XCTAssertEqual(monitor.metric, .overview)
        XCTAssertEqual(monitor.statusMetric, .lidAngle)
        monitor.selectMetric(.gpu)
        XCTAssertEqual(monitor.statusMetric, .gpu)
        monitor.selectMetric(.overview)
        XCTAssertEqual(MenuBarMonitor(settings: settings).statusMetric, .lidAngle)
        let missing = MenuReading()
        XCTAssertEqual(missing.title(for: .lidAngle, fans: nil), "—")
        XCTAssertEqual(MenuReading(lidAngle: 0).title(for: .lidAngle, fans: nil), "0°")
        monitor.selectOverviewMetric(.overview)
        XCTAssertEqual(MenuBarMonitor(settings: settings).statusMetric, .overview)
    }

    func testStatusTitlesDistinguishMissingReadingsAndStoppedFans() {
        var reading = MenuReading()
        XCTAssertEqual(reading.title(for: .overview, fans: nil), "")
        XCTAssertEqual(reading.title(for: .fans, fans: nil), "—")
        let fan = FanStatus(id: 0, name: "L", actualRPM: 0, targetRPM: 0, minRPM: 1700,
                            maxRPM: 6000, forced: false)
        let status = DaemonStatus(fans: [fan], cpuTemp: nil, gpuTemp: nil, maxTemp: nil,
                                  controlTemp: nil, config: DaemonConfig(), failsafeActive: false,
                                  canControl: true, version: "test")
        XCTAssertEqual(reading.title(for: .fans, fans: status), "0 RPM")
        reading.performance.gpus = [.init(id: "0", name: "GPU", utilization: 48)]
        XCTAssertEqual(reading.title(for: .gpu, fans: nil), "48%")
        XCTAssertNil(reading.performance.networkSend)
        reading.performance.networkReceive = 0
        XCTAssertEqual(reading.title(for: .network, fans: nil), "0 B/s")
        XCTAssertEqual(reading.title(for: .upload, fans: nil), "—")
    }

    @MainActor func testFullSpeedUsesEachHardwareMaximumAndCanReturnToAutomatic() async throws {
        let left = FanStatus(id: 0, name: "L", actualRPM: 0, targetRPM: 0, minRPM: 1700, maxRPM: 5800, forced: false)
        let right = FanStatus(id: 1, name: "R", actualRPM: 0, targetRPM: 0, minRPM: 1900, maxRPM: 6400, forced: false)
        let status: @Sendable (DaemonConfig) -> DaemonStatus = {
            DaemonStatus(fans: [right, left], cpuTemp: nil, gpuTemp: nil, maxTemp: nil, controlTemp: nil,
                         config: $0, failsafeActive: false, canControl: true, version: "test")
        }
        let original = DaemonConfig(mode: .curve, targetTemp: 81)
        let control = FanControlSession(readStatus: { status(original) }, writeConfig: status)
        await control.refresh()
        control.applyFullSpeed()
        for _ in 0..<100 where control.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(control.status?.config, DaemonConfig(mode: .manual, manualRPM: [5800, 6400], targetTemp: 81))
        XCTAssertEqual(control.fraction, 100)
        control.apply(.auto)
        for _ in 0..<100 where control.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(control.status?.config.mode, .auto)

        var unavailable = status(original)
        unavailable.canControl = false
        XCTAssertNil(unavailable.fullSpeedTargets)
        unavailable.canControl = true
        unavailable.fans = [right]
        XCTAssertNil(unavailable.fullSpeedTargets)
        unavailable.fans = [left]
        unavailable.fans[0].maxRPM = 0
        XCTAssertNil(unavailable.fullSpeedTargets)
    }

    @MainActor func testMenuAndWindowApplyTheSameFanDraft() async throws {
        let fan = FanStatus(id: 0, name: "L", actualRPM: 1800, targetRPM: 1800,
                            minRPM: 1800, maxRPM: 6200, forced: false)
        let status: @Sendable (DaemonConfig) -> DaemonStatus = {
            DaemonStatus(fans: [fan], cpuTemp: 48, gpuTemp: 46, maxTemp: 49, controlTemp: 48,
                         config: $0, failsafeActive: false, canControl: true, version: "test")
        }
        let control = FanControlSession(readStatus: { status(DaemonConfig()) }, writeConfig: status)
        await control.refresh()
        control.fraction = 50
        control.apply(.manual)
        for _ in 0..<100 where control.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(control.status?.config.manualRPM, [4000])
        XCTAssertEqual(control.mode, .manual)
        control.ceiling = 79
        control.apply(.curve)
        for _ in 0..<100 where control.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(control.status?.config.targetTemp, 79)
        control.apply(.auto)
        for _ in 0..<100 where control.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(control.status?.config.mode, .auto)
    }
}
