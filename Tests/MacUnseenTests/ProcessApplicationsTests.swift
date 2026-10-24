import XCTest
@testable import MacUnseen

final class ProcessApplicationsTests: XCTestCase {
    private func row(_ pid: Int32, _ path: String? = nil, uid: UInt32 = 501,
                     cpu: Double? = 10, memory: Double? = 100, app: ProcessApplication? = nil,
                     parent: Int32 = 1, started: UInt64 = 100) -> ProcessReading {
        ProcessReading(id: ProcessIdentity(pid: pid, startSeconds: started, startMicroseconds: 0),
                       name: "Same Name", uid: uid, cpu: cpu, memory: memory, usesFootprint: true,
                       parentPID: parent, executablePath: path, application: app)
    }
    func testNestedHelpersUseOuterApplicationAndOtherPathsStayUnbundled() {
        XCTAssertEqual(ProcessApplication.bundlePath(for: "/Applications/Browser.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"), "/Applications/Browser.app")
        XCTAssertNil(ProcessApplication.bundlePath(for: "/usr/bin/python3"))
        XCTAssertNil(ProcessApplication.bundlePath(for: "relative.app/tool"))
    }
    func testApplicationTotalsIncludeHelpersWithoutMergingNamesOrUsers() {
        let app = ProcessApplication(bundlePath: "/Applications/Test.app", name: "Test")
        let rows = [row(10, app: app), row(11, cpu: 25, memory: 200, app: app),
                    row(12, "/usr/bin/first"), row(13, "/usr/bin/second"), row(14, uid: 502, app: app)]
        let groups = ApplicationProcessGroup.group(rows)
        XCTAssertEqual(groups.count, 4)
        let merged = groups.first { $0.processes.count == 2 }!
        XCTAssertEqual(merged.cpu, 35)
        XCTAssertEqual(merged.memory, 300)
        XCTAssertTrue(merged.matches("11"))
        XCTAssertEqual(merged.processes.count, 2)
    }
    func testUnknownMetricsArePartialOrUnavailableRatherThanZero() {
        let rows = [row(10, "/bin/tool"), row(11, "/bin/tool", cpu: nil, memory: nil)]
        let group = ApplicationProcessGroup.group(rows)[0]
        XCTAssertEqual(group.cpu, 10)
        XCTAssertTrue(group.partialCPU)
        XCTAssertTrue(group.partialMemory)
        let unknown = ApplicationProcessGroup.group([rows[1]])[0]
        XCTAssertNil(unknown.cpu)
        XCTAssertNil(unknown.memory)
        XCTAssertEqual(ApplicationProcessGroup.group([row(1), row(2)]).count, 2)
    }
    func testParentInheritanceUsesCurrentSampleAndRejectsReusedParentsOrDifferentUsers() {
        let app = ProcessApplication(bundlePath: "/Applications/Test.app", name: "Test")
        let rows = [row(10, app: app), row(11, parent: 10, started: 101),
                    row(12, uid: 502, parent: 10, started: 101), row(13, parent: 10, started: 99)]
        let resolved = ProcessApplication.inheritingOwners(rows)
        XCTAssertEqual(resolved[1].application, app)
        XCTAssertNil(resolved[2].application)
        XCTAssertNil(resolved[3].application)
    }
    func testApplicationSortingUsesMemberCountAndKeepsUnknownMetricsLast() {
        let groups = ApplicationProcessGroup.group([row(1, "/a"), row(2, "/a"), row(3, "/b", cpu: nil)])
        var sort = ProcessSort(column: .pid, ascending: false)
        XCTAssertEqual(groups.sorted(by: sort.precedes).first?.processes.count, 2)
        sort.column = .cpu
        for ascending in [true, false] {
            sort.ascending = ascending
            XCTAssertNil(groups.sorted(by: sort.precedes).last?.cpu)
        }
    }
}
