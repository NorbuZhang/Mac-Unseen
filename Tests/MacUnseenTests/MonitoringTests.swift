import XCTest
import Darwin
import SystemMonitorBridge
@testable import MacUnseen

final class MonitoringTests: XCTestCase {
    func testNetworkEnumerationMatchesIndependentInterfaceList() throws {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        XCTAssertEqual(getifaddrs(&interfaces), 0)
        defer { freeifaddrs(interfaces) }
        var expected = Set<String>()
        var cursor = interfaces
        while let current = cursor {
            let entry = current.pointee
            cursor = entry.ifa_next
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  entry.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING) else { continue }
            let type = address.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { $0.pointee.sdl_type }
            let name = String(cString: entry.ifa_name)
            if type == IFT_ETHER && name.hasPrefix("en") { expected.insert(name) }
        }
        var samples: UnsafeMutablePointer<MUNetworkSample>?
        let count = MUCopyNetworkSamples(&samples)
        defer { MUFreeNetworkSamples(samples) }
        XCTAssertGreaterThanOrEqual(count, 0)
        let actual = UnsafeBufferPointer(start: samples, count: max(0, Int(count))).map { item in
            var name = item.name
            return withUnsafeBytes(of: &name) { String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self)) }
        }
        XCTAssertEqual(Set(actual), expected)
    }
    func testZeroBytesIsNotMissingAndCoreGroupsKeepSystemReportedTypes() {
        XCTAssertEqual(formatMonitoredBytes(0), "0 B")
        XCTAssertEqual(formatMonitoredBytes(nil), "—")
        XCTAssertEqual(formatMonitoredBytes(.nan), "—")
        XCTAssertEqual(CPUCoreGroup(name: "Super", count: 5).label, "超级核心")
        XCTAssertEqual(CPUCoreGroup(name: "Future", count: 2).label, "CPU (Future)")
    }
    func testNativeProcessTimeMatchesIndependentGetrusageClock() throws {
        func nativeTime() throws -> Double {
            var pointer: UnsafeMutablePointer<MUProcessSample>?
            let count = MUCopyProcessSamples(&pointer)
            defer { MUFreeProcessSamples(pointer) }
            let buffer = UnsafeBufferPointer(start: pointer, count: max(0, Int(count)))
            let sample = try XCTUnwrap(buffer.first { $0.pid == getpid() && $0.has_usage != 0 })
            return Double(sample.cpu_nanoseconds) / 1_000_000_000
        }
        func referenceTime() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        let nativeStart = try nativeTime()
        let referenceStart = referenceTime()
        // Measurable CPU work catches the Apple Silicon ticks-versus-nanoseconds error.
        let until = ProcessInfo.processInfo.systemUptime + 0.15
        while ProcessInfo.processInfo.systemUptime < until { _ = arc4random() }
        let nativeElapsed = try nativeTime() - nativeStart
        let referenceElapsed = referenceTime() - referenceStart
        XCTAssertGreaterThan(referenceElapsed, 0.03)
        XCTAssertEqual(nativeElapsed, referenceElapsed, accuracy: max(0.02, referenceElapsed * 0.2))
    }
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
        XCTAssertEqual(MonitoringRefreshPolicy.interval(for: .systemInfo, active: true), 5)
        for section in [DashboardSection.ports, .battery, .motion, .about, .support] {
            XCTAssertNil(MonitoringRefreshPolicy.interval(for: section, active: true))
        }
    }
    func testNavigationGroupsIncludeEveryDestinationExactlyOnce() {
        let pages = DashboardGroup.all.flatMap(\.sections)
        XCTAssertEqual(pages.count, Set(pages).count)
        XCTAssertEqual(Set(pages), Set(DashboardSection.allCases))
        XCTAssertTrue(pages.contains(.temperature))
        XCTAssertTrue(pages.contains(.fans))
        XCTAssertEqual(DashboardGroup.all.count, 4)
        XCTAssertEqual(DashboardGroup.all.last?.sections, [.about, .support])
    }

    func testSensorTimerStopsWithoutWorkButKeepsConnectionAndLiveReadings() {
        func interval(_ section: DashboardSection, active: Bool = true,
                      helper: Bool = false, pending: Bool = false, trackpad: Bool = false) -> TimeInterval? {
            MonitoringRefreshPolicy.sensorInterval(for: section, active: active,
                advancedActive: helper, advancedPending: pending, trackpadAvailable: trackpad)
        }
        for section in DashboardSection.allCases {
            XCTAssertNil(interval(section, active: false))
            XCTAssertEqual(interval(section, active: false, helper: true), 2)
            XCTAssertEqual(interval(section, active: false, pending: true), 2)
        }
        for section in [DashboardSection.about, .support, .systemInfo, .processes,
                        .storage, .network, .ports, .temperature, .fans, .environment, .motion, .trackpad] {
            XCTAssertNil(interval(section), "Unneeded timer on \(section)")
            XCTAssertNotNil(interval(section, pending: true), "Connection must still be observed")
        }
        XCTAssertEqual(interval(.battery), 0.5)
        XCTAssertEqual(interval(.overview), 60)
        XCTAssertEqual(interval(.performance), 60)
        XCTAssertEqual(interval(.overview, helper: true), 1)
        XCTAssertEqual(interval(.motion, helper: true), 0.1)
        XCTAssertEqual(interval(.environment, helper: true), 0.1)
        XCTAssertEqual(interval(.trackpad, trackpad: true), 0.1)
        XCTAssertNil(interval(.trackpad, active: false, trackpad: true))
    }

    func testPressureHistoryUsesSystemLevelsAndKeepsMissingSamplesAsGaps() {
        var history = MemoryPressureHistory()
        for (index, raw) in [1, 2, 4, 99, nil].enumerated() {
            history.append(rawLevel: raw, at: Date(timeIntervalSince1970: Double(index)))
        }
        XCTAssertEqual(history.samples.map(\.level), [.normal, .warning, .critical, nil, nil])
        XCTAssertEqual(history.samples[2].level?.chartLevel, 3)
        // The pressure enum is discrete and independent of physical-memory usage.
        XCTAssertNil(MemoryPressureLevel(rawValue: 75))
        history.append(rawLevel: 1, at: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(history.samples.count, 5)
        for index in 5..<80 { history.append(rawLevel: 1, at: Date(timeIntervalSince1970: Double(index))) }
        XCTAssertEqual(history.samples.count, 60)
        XCTAssertEqual(history.samples.first?.date, Date(timeIntervalSince1970: 20))
    }

    func testPressureHistorySurvivesLongPauseWithoutInventingSamples() {
        var history = MemoryPressureHistory()
        for index in 0..<30 { history.append(rawLevel: 1, at: Date(timeIntervalSince1970: Double(index))) }
        let before = history.samples
        history.pause()
        history.pause()
        XCTAssertEqual(history.samples, before)
        history.append(rawLevel: 2, at: Date(timeIntervalSince1970: 3600))
        XCTAssertEqual(Array(history.samples.dropLast()), before)
        XCTAssertEqual(history.samples.count, 31)
        XCTAssertTrue(history.samples.last!.startsNewSegment)
        XCTAssertEqual(history.plotColumns.filter { $0 == .pause }.count, 1)
        XCTAssertEqual(history.plotColumns.last, .sample(history.samples.last!))
        // No thousands of fabricated one-second samples, and no stale data aged out on resume.
        XCTAssertEqual(history.plotColumns.count, 32)
        history.append(rawLevel: 4, at: Date(timeIntervalSince1970: 3601))
        XCTAssertFalse(history.samples.last!.startsNewSegment)
    }

    func testPressureHistoryMarksDelayedSamplingAndBoundsStorageAcrossSessions() {
        var history = MemoryPressureHistory()
        history.pause() // Starting without a history must not insert a leading break.
        history.append(rawLevel: 1, at: Date(timeIntervalSince1970: 0))
        history.append(rawLevel: nil, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(history.plotColumns.filter { $0 == .pause }.count, 1)
        XCTAssertNil(history.samples.last?.level)
        history.pause()
        history.append(rawLevel: 1, at: Date(timeIntervalSince1970: 5)) // Ignore late sample.
        XCTAssertEqual(history.samples.count, 2)
        history.append(rawLevel: 2, at: Date(timeIntervalSince1970: 11))
        XCTAssertTrue(history.samples.last!.startsNewSegment)
        for index in 12..<100 {
            history.pause()
            history.append(rawLevel: 1, at: Date(timeIntervalSince1970: Double(index)))
        }
        XCTAssertEqual(history.samples.count, 60)
        XCTAssertEqual(history.plotColumns.count, 119)
        XCTAssertEqual(history.plotColumns.first, .sample(history.samples.first!))
    }

    func testColumnSortingTogglesAndKeepsUnavailableValuesLast() {
        func row(_ pid: Int32, _ name: String, _ cpu: Double?, _ memory: Double?) -> ProcessReading {
            ProcessReading(id: ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0),
                           name: name, uid: 0, cpu: cpu, memory: memory, usesFootprint: true)
        }
        let rows = [row(9, "App 10", 10, 100), row(5, "App 2", 0, 200), row(1, "Restricted", nil, nil), row(7, "App 1", 10, 50)]
        var sort = ProcessSort()
        func ordered() -> [Int32] { rows.sorted(by: sort.precedes).map(\.id.pid) }
        XCTAssertEqual(ordered(), [7, 9, 5, 1])
        sort.select(.cpu)
        XCTAssertEqual(ordered(), [5, 7, 9, 1])
        sort.select(.memory)
        XCTAssertFalse(sort.ascending)
        XCTAssertEqual(ordered(), [5, 9, 7, 1])
        sort.select(.memory)
        XCTAssertEqual(ordered(), [7, 9, 5, 1])
        sort.select(.name)
        XCTAssertEqual(ordered(), [7, 5, 9, 1])
        sort.select(.pid)
        XCTAssertEqual(ordered(), [1, 5, 7, 9])
        sort.select(.pid)
        XCTAssertEqual(ordered(), [9, 7, 5, 1])
    }

    func testSystemDetailsParseUnifiedMemoryAndGPUWithoutInventingMissingSpeed() throws {
        let data = Data(#"{"SPHardwareDataType":[{"machine_name":"MacBook Pro","model_number":"MODEL/A","boot_rom_version":"1.2","os_loader_version":"1.3"}],"SPMemoryDataType":[{"SPMemoryDataType":"48 GB","dimm_type":"LPDDR5","dimm_manufacturer":"Samsung"}],"SPDisplaysDataType":[{"sppci_model":"Apple Test GPU","sppci_cores":"16","spdisplays_mtlgpufamilysupport":"spdisplays_metal4"}]}"#.utf8)
        let result = try XCTUnwrap(SystemDetailsReader.parse(data))
        XCTAssertTrue(result.profilerAvailable)
        XCTAssertEqual(result.modelName, "MacBook Pro")
        XCTAssertEqual(result.firmware, "1.2")
        XCTAssertEqual(result.memory.count, 1)
        XCTAssertEqual(result.memory.first?.capacity, "48 GB")
        XCTAssertEqual(result.memory.first?.type, "LPDDR5")
        XCTAssertNil(result.memory.first?.speed)
        XCTAssertEqual(result.gpus.first?.cores, 16)
        XCTAssertEqual(result.gpus.first?.metal, "Metal 4")
        XCTAssertNil(result.gpus.first?.vram)
        // Unified memory is confirmed by Metal, not guessed from a GPU name.
        XCTAssertNil(result.gpus.first?.unifiedMemory)
    }

    func testSystemDetailsParseIntelDIMMsAndHandlePartialOrMalformedReports() throws {
        let data = Data(#"{"SPMemoryDataType":[{"_items":[{"_name":"BANK 0/DIMM0","dimm_size":"8 GB","dimm_type":"DDR4","dimm_speed":"2667 MHz"},{"_name":"BANK 1/DIMM0","dimm_size":"8 GB","dimm_manufacturer":"Vendor"}]}],"SPDisplaysDataType":[{"_name":"Intel GPU","spdisplays_mtlgpufamilysupport":"future_unknown","spdisplays_vram_shared":"1536 MB"}]}"#.utf8)
        let result = try XCTUnwrap(SystemDetailsReader.parse(data))
        XCTAssertFalse(result.profilerAvailable)
        XCTAssertNil(result.modelName)
        XCTAssertEqual(result.memory.map(\.id), [0, 1])
        XCTAssertEqual(result.memory.first?.speed, "2667 MHz")
        XCTAssertNil(result.memory.last?.speed)
        XCTAssertNil(result.gpus.first?.metal)
        XCTAssertEqual(result.gpus.first?.vram, "1536 MB")
        XCTAssertNil(SystemDetailsReader.parse(Data("invalid".utf8)))
        XCTAssertEqual(SystemDetailsReader.parse(Data("{}".utf8)), SystemDetails())
    }

    func testRuntimeSamplerReturnsNativeCountsAndLoads() async {
        let runtime = await PerformanceReader().sampleSystemRuntime()
        XCTAssertGreaterThan(runtime.processCount ?? 0, 0)
        XCTAssertEqual(runtime.loads.count, 3)
        XCTAssertTrue(runtime.loads.allSatisfy { $0 >= 0 && $0.isFinite })
        XCTAssertEqual(runtime.uptime, ProcessInfo.processInfo.systemUptime, accuracy: 2)
        XCTAssertNotNil(runtime.sampledAt)
    }
}
