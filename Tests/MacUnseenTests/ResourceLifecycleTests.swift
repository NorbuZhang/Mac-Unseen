import XCTest
@testable import MacUnseen

final class ResourceLifecycleTests: XCTestCase {
    func testCancelledCommandDoesNotLaunch() {
        let command = SystemCommand()
        command.cancel()
        XCTAssertNil(command.run(executable: "/bin/sleep", arguments: ["10"], timeout: 20))
        XCTAssertFalse(command.isRunning)
    }

    func testCancellationStopsRunningChildPromptly() async throws {
        let command = SystemCommand()
        let task = Task.detached { command.run(executable: "/bin/sleep", arguments: ["10"], timeout: 20) }
        let launchDeadline = Date().addingTimeInterval(3)
        while !command.isRunning, Date() < launchDeadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(command.isRunning)
        let start = Date()
        command.cancel()
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertFalse(command.isRunning)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testTimeoutBoundsUnresponsiveCommand() {
        let command = SystemCommand()
        let start = Date()
        // Ignored signals survive exec: this child needs the SIGKILL fallback.
        XCTAssertNil(command.run(executable: "/bin/sh",
            arguments: ["-c", "trap '' TERM; exec /bin/sleep 10"], timeout: 0.2))
        XCTAssertFalse(command.isRunning)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 1)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testCommandDrainsLargeOutputAndRejectsFailure() {
        let data = SystemCommand().run(executable: "/bin/dd",
            arguments: ["if=/dev/zero", "bs=65536", "count=8"], timeout: 5)
        XCTAssertEqual(data?.count, 524_288)
        XCTAssertNil(SystemCommand().run(executable: "/usr/bin/false", arguments: [], timeout: 5))
    }

    func testFinishedCommandIsNotRetainedByDeadline() {
        weak var weakCommand: SystemCommand?
        autoreleasepool {
            let command = SystemCommand()
            weakCommand = command
            XCTAssertNotNil(command.run(executable: "/usr/bin/true", arguments: [], timeout: 60))
        }
        XCTAssertNil(weakCommand)
    }

    @MainActor func testLargeReportCacheSurvivesBackgroundButNotPageExit() {
        let value = SystemReport(nodes: [SystemReportNode(id: 0, label: "Test", value: "Value")], sampledAt: Date())
        let store = SystemReportStore(reports: ["SPFontsDataType": value, "SPApplicationsDataType": value,
                                               "SPMemoryDataType": value, "SPPowerDataType": value])
        store.show(section: .systemInfo, active: false)
        store.request("SPFontsDataType")
        store.setActive(false)
        XCTAssertNotNil(store.reports["SPFontsDataType"])
        store.show(section: .support, active: false)
        XCTAssertNil(store.reports["SPFontsDataType"])
        XCTAssertNil(store.reports["SPApplicationsDataType"])
        XCTAssertNotNil(store.reports["SPMemoryDataType"])
        XCTAssertNotNil(store.reports["SPPowerDataType"])
        XCTAssertTrue(store.requested.isEmpty)
    }

    @MainActor func testFoldingLargeDirectoryFreesOnlyItsOwnReport() {
        let value = SystemReport(nodes: [], sampledAt: Date())
        let store = SystemReportStore(reports: ["SPFontsDataType": value, "SPApplicationsDataType": value,
                                               "SPHardwareDataType": value])
        store.show(section: .systemInfo, active: false)
        store.request("SPFontsDataType")
        store.release("SPFontsDataType")
        XCTAssertNil(store.reports["SPFontsDataType"])
        XCTAssertNotNil(store.reports["SPApplicationsDataType"])
        store.request("SPHardwareDataType")
        store.release("SPHardwareDataType")
        XCTAssertNotNil(store.reports["SPHardwareDataType"])
    }
}
