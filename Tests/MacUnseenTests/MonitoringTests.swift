import XCTest
@testable import MacUnseen

final class MonitoringTests: XCTestCase {
    func testCPUUsesCounterDifferencesAndDoesNotTreatLoadAverageAsPercent() throws {
        let old = CPUCounters(user: 1_000, system: 400, idle: 2_000, nice: 0)
        let now = CPUCounters(user: 1_030, system: 410, idle: 2_060, nice: 0)
        XCTAssertEqual(try XCTUnwrap(now.usage(since: old)), 40, accuracy: 0.0001)
        XCTAssertNil(old.usage(since: old))
        XCTAssertNil(old.usage(since: now))
    }
    func testRatesUseActualTimeAndIgnoreNewRemovedOrResetDevices() throws {
        let old = ["old": ByteCounters(input: 8_000, output: 5_000), "removed": ByteCounters(input: 900_000, output: 900_000)]
        let new = ["old": ByteCounters(input: 8_600, output: 5_300), "new": ByteCounters(input: 8_000_000, output: 5_000_000)]
        let rates = SampleDelta.rates(current: new, previous: old, elapsed: 1.5)
        XCTAssertEqual(try XCTUnwrap(rates.0), 400, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(rates.1), 200, accuracy: 0.001)
        XCTAssertNil(SampleDelta.rates(current: old, previous: new, elapsed: 1).0)
        XCTAssertNil(SampleDelta.rates(current: new, previous: nil, elapsed: 1).0)
        XCTAssertNil(SampleDelta.rates(current: new, previous: old, elapsed: 60).0)
        XCTAssertNil(SampleDelta.rates(current: nil, previous: old, elapsed: 1).0)
    }
    func testProcessCPUCanExceed100AndNewOrReusedPIDNeedsBaseline() throws {
        XCTAssertEqual(try XCTUnwrap(SampleDelta.processCPU(current: 6_000_000_000, previous: 1_000_000_000, elapsed: 2)), 250, accuracy: 0.001)
        XCTAssertNil(SampleDelta.processCPU(current: 6_000_000_000, previous: nil, elapsed: 2))
        XCTAssertNil(SampleDelta.processCPU(current: 1, previous: 2, elapsed: 2))
        XCTAssertNotEqual(ProcessIdentity(pid: 42, startSeconds: 100, startMicroseconds: 0), ProcessIdentity(pid: 42, startSeconds: 101, startMicroseconds: 0))
    }
    func testRefreshPolicyStopsUnusedCollectorsAndDoesNotPollStaticIdentity() {
        for section in DashboardSection.allCases {
            XCTAssertNil(MonitoringRefreshPolicy.interval(for: section, active: false))
        }
        XCTAssertEqual(MonitoringRefreshPolicy.interval(for: .performance, active: true), 1)
        XCTAssertEqual(MonitoringRefreshPolicy.interval(for: .processes, active: true), 2)
        for section in [DashboardSection.systemInfo, .ports, .battery, .motion, .about] {
            XCTAssertNil(MonitoringRefreshPolicy.interval(for: section, active: true))
        }
    }
    func testNavigationGroupsIncludeEveryDestinationExactlyOnce() {
        let pages = DashboardGroup.all.flatMap(\.sections) + [.about]
        XCTAssertEqual(pages.count, Set(pages).count)
        XCTAssertEqual(Set(pages), Set(DashboardSection.allCases))
    }
}
