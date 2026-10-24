import XCTest
@testable import MacUnseen

final class SystemReportTests: XCTestCase {
    func testBatteryHealthUsesScopedPowerReportPercentageOnly() {
        func report(_ maximum: String) -> SystemReport {
            SystemReport(nodes: SystemReportParser.parse("""
            Power:
                Battery Information:
                    Charge Information:
                        Maximum Capacity: 100%
                    Health Information:
                        Maximum Capacity: \(maximum)
                AC Charger Information:
                    Maximum Capacity: 65%
            """), sampledAt: Date())
        }
        XCTAssertEqual(report("97%").batteryHealthPercentage, 97)
        XCTAssertEqual(report("97 %").batteryHealthPercentage, 97)
        for invalid in ["6587 mAh", "100", "105%", "-1%", "Unknown"] {
            XCTAssertNil(report(invalid).batteryHealthPercentage)
        }
        XCTAssertNil(SystemReport(nodes: [], sampledAt: Date()).batteryHealthPercentage)
    }

    func testDiskTypeDoesNotTreatMissingInformationAsHardDisk() {
        XCTAssertEqual(DiskSnapshot(solidState: true).mediaKind, "SSD")
        XCTAssertEqual(DiskSnapshot(mediumType: "Rotational").mediaKind, "HDD")
        XCTAssertEqual(DiskSnapshot(mediumType: "Non-Rotational").mediaKind, "SSD")
        XCTAssertEqual(DiskSnapshot().mediaKind, "未知")
    }

    func testCacheSizesUseNumericConversionAndBinaryUnits() {
        XCTAssertEqual(formatHardwareBytes(196_608), "192 KiB")
        XCTAssertEqual(formatHardwareBytes(131_072), "128 KiB")
        XCTAssertEqual(formatHardwareBytes(65_536), "64 KiB")
        XCTAssertEqual(formatHardwareBytes(16_777_216), "16 MiB")
        XCTAssertEqual(formatHardwareBytes(8_388_608), "8 MiB")
        XCTAssertEqual(formatHardwareBytes(16_384), "16 KiB")
        XCTAssertEqual(formatHardwareBytes(nil), "—")
        XCTAssertEqual(formatHardwareBytes(0), "—")
    }

    func testReportParserPreservesNestingRepeatedDevicesAndColonValues() throws {
        let nodes = SystemReportParser.parse("""
        USB:

            USB 3.1 Bus:
              Driver: AppleUSB
                Hub:
                  Location: bus: port 1
            USB 3.1 Bus:
              Location ID: 0x02000000
        """)
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0].label, "USB 3.1 Bus")
        XCTAssertNotEqual(nodes[0].id, nodes[1].id)
        XCTAssertEqual(nodes[0].children?.first?.value, "AppleUSB")
        XCTAssertEqual(nodes[0].children?.first?.children?.first?.label, "Hub")
        XCTAssertEqual(nodes[0].children?.first?.children?.first?.children?.first?.value, "bus: port 1")
        XCTAssertEqual(nodes[1].children?.first?.value, "0x02000000")
        XCTAssertTrue(SystemReportParser.parse("").isEmpty)
        XCTAssertTrue(SystemReportParser.parse("PCI:\n").isEmpty)
    }

    func testSearchRetainsAncestorsAndDoesNotMatchUnrelatedDevices() throws {
        let nodes = SystemReportParser.parse("""
        Audio:
            Speaker:
              Manufacturer: Apple
            Microphone:
              Manufacturer: Other
        """)
        let filtered = nodes.compactMap { $0.matching("apple") }
        XCTAssertEqual(filtered.map(\.label), ["Speaker"])
        XCTAssertEqual(filtered.first?.children?.first?.value, "Apple")
        XCTAssertEqual(nodes.compactMap { $0.matching("") }, nodes)
    }

    func testCatalogCoversTMOGHardwareNetworkAndSoftwareWithoutDuplicateIDs() {
        let ids = SystemReportCategory.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        for id in ["SPAudioDataType", "SPBluetoothDataType", "SPCameraDataType", "SPCardReaderDataType", "SPiBridgeDataType",
                   "SPNVMeDataType", "SPSPIDataType", "SPSecureElementDataType", "SPSmartCardsDataType", "SPThunderboltDataType",
                   "SPUSBHostDataType", "SPPowerDataType", "SPNetworkLocationDataType", "SPNetworkVolumeDataType", "SPFirewallDataType",
                   "SPApplicationsDataType", "SPExtensionsDataType", "SPFrameworksDataType", "SPFontsDataType", "SPInstallHistoryDataType",
                   "SPPrefPaneDataType", "SPLegacySoftwareDataType", "SPDeveloperToolsDataType", "SPInternationalDataType", "SPLogsDataType",
                   "SPPrintersDataType", "SPPrintersSoftwareDataType", "SPUniversalAccessDataType"] {
            XCTAssertTrue(ids.contains(id), id)
        }
    }

    @MainActor func testInactiveRequestsDoNotStartAndPageSwitchDropsOldRequests() {
        let store = SystemReportStore()
        store.show(section: .systemInfo, active: false)
        store.request("SPApplicationsDataType")
        store.request("SPFontsDataType")
        XCTAssertEqual(store.requested, ["SPApplicationsDataType", "SPFontsDataType"])
        XCTAssertNil(store.loading)
        XCTAssertTrue(store.reports.isEmpty)
        store.show(section: .network, active: false)
        XCTAssertTrue(store.requested.isEmpty)
        store.request("SPFirewallDataType")
        store.release("SPFirewallDataType")
        XCTAssertTrue(store.requested.isEmpty)
    }


    @MainActor func testFoldingSupplementDoesNotReleaseInlineHardwareReport() {
        let store = SystemReportStore()
        store.show(section: .battery, active: false)
        store.request("SPPowerDataType", persistent: true)
        store.request("SPPowerDataType")
        store.release("SPPowerDataType")
        XCTAssertTrue(store.requested.contains("SPPowerDataType"))
        store.show(section: .systemInfo, active: false)
        XCTAssertTrue(store.requested.isEmpty)
        store.show(section: .battery, active: false)
        store.request("SPPowerDataType")
        store.release("SPPowerDataType")
        XCTAssertTrue(store.requested.isEmpty)
    }

    func testEachReportHasOneHomeBesideItsHardware() {
        let expected: [DashboardSection: Set<String>] = [
            .performance: ["cpu", "SPMemoryDataType", "SPDisplaysDataType"],
            .battery: ["SPPowerDataType"],
            .storage: ["SPNVMeDataType", "SPStorageDataType", "SPSerialATADataType", "SPNetworkVolumeDataType"],
            .network: ["SPNetworkDataType", "SPAirPortDataType", "SPEthernetDataType", "SPNetworkLocationDataType", "SPFirewallDataType"],
            .ports: ["SPThunderboltDataType", "SPUSBHostDataType", "SPBluetoothDataType", "SPAudioDataType", "SPCameraDataType", "SPCardReaderDataType", "SPPCIDataType", "SPSPIDataType", "SPSmartCardsDataType", "SPPrintersDataType", "SPPrintersSoftwareDataType"],
        ]
        for (section, ids) in expected {
            XCTAssertEqual(Set(SystemReportCategory.categories(for: section).map(\.id)), ids)
        }
        let movedIDs = Set(expected.values.flatMap { $0 })
        let remainingIDs = Set(SystemReportCategory.categories(for: .systemInfo).map(\.id))
        XCTAssertTrue(movedIDs.isDisjoint(with: remainingIDs))
        XCTAssertEqual(movedIDs.union(remainingIDs).count, 39)
        XCTAssertTrue(remainingIDs.isSuperset(of: ["SPHardwareDataType", "SPiBridgeDataType", "SPSoftwareDataType", "SPApplicationsDataType"]))
    }

    @MainActor func testReportRequestsCannotCrossPageOwnership() {
        let store = SystemReportStore()
        store.show(section: .network, active: false)
        store.request("SPFirewallDataType")
        store.request("SPSerialATADataType")
        XCTAssertEqual(store.requested, ["SPFirewallDataType"])
        store.show(section: .fans, active: true)
        XCTAssertNil(store.loading)
        XCTAssertTrue(store.requested.isEmpty)
    }

    func testLargeDirectoriesAreCollapsedByDefault() {
        for id in ["SPFontsDataType", "SPLegacySoftwareDataType", "SPApplicationsDataType", "SPFrameworksDataType"] {
            XCTAssertFalse(SystemReportCategory.all.first { $0.id == id }!.startsExpanded)
        }
        XCTAssertTrue(SystemReportCategory.all.first { $0.id == "SPMemoryDataType" }!.startsExpanded)
    }

    func testProjectionDoesNotMixDevicesOrRemoveNearbyNetworkFields() {
        let nodes = SystemReportParser.parse("""
        Wi-Fi:
            en0:
                BSD Device Name: en0
                Current Network Information:
                    Home:
                        Channel: 36
                        MCS Index: 8
                Other Local Wi-Fi Networks:
                    Nearby:
                        Channel: 1
            en1:
                BSD Device Name: en1
                Channel: 44
        """)
        let selected = SystemReportProjection.nodes(nodes, selection: .device(field: "BSD Device Name", value: "en0"),
            excluding: ["BSD Device Name"], scopedExcluding: ["Current Network Information": ["Channel"]])
        let flattened = SystemReportOutline.rows(selected).map(\.node)
        XCTAssertEqual(flattened.filter { $0.label == "Channel" }.map(\.value), ["1"])
        XCTAssertTrue(flattened.contains { $0.label == "MCS Index" })
        XCTAssertTrue(SystemReportProjection.nodes(nodes, selection: .device(field: "BSD Device Name", value: "en9")).isEmpty)
        let remaining = SystemReportProjection.nodes(nodes, selection: .omittingDevices(field: "BSD Device Name", values: ["en0"]))
        XCTAssertEqual(remaining.map(\.label), ["en1"])
    }

    func testDiskDeduplicationPreservesNestedVolumeCapacityAndIdentifiers() {
        let nodes = SystemReportParser.parse("""
        NVMExpress:
            Disk:
                BSD Name: disk0
                Capacity: 2 TB
                Volumes:
                    Data:
                        BSD Name: disk0s2
                        Capacity: 1.9 TB
        """)
        let selected = SystemReportProjection.nodes(nodes, selection: .device(field: "BSD Name", value: "disk0"),
                                                    excludingDirect: ["BSD Name", "Capacity"])
        let leaves = SystemReportOutline.rows(selected).map(\.node)
        XCTAssertEqual(leaves.filter { $0.label == "BSD Name" }.map(\.value), ["disk0s2"])
        XCTAssertEqual(leaves.filter { $0.label == "Capacity" }.map(\.value), ["1.9 TB"])
    }

    func testReportLocalizationPreservesNamesAndDistinguishesBatteryCapacityUnits() {
        let previous = AppLocalization.language
        AppLocalization.language = .simplifiedChinese
        defer { AppLocalization.language = previous }
        XCTAssertEqual(SystemReportLabels.localized("Maximum Capacity", value: "95%"), "最大容量（健康度）")
        XCTAssertEqual(SystemReportLabels.localized("Maximum Capacity", value: "5000 mAh"), "最大容量")
        XCTAssertEqual(SystemReportLabels.localized("Vendor Name"), "厂商名称")
        XCTAssertEqual(SystemReportLabels.localized("Thunderbolt/USB4 Bus 2"), "雷雳 / USB4 总线 2")
        XCTAssertEqual(SystemReportLabels.localizedValue("Up to 120 Gb/s", label: "Speed"), "最高 120 Gb/s")
        XCTAssertEqual(SystemReportLabels.localizedValue("Normal", label: "Condition"), "正常")
        XCTAssertEqual(SystemReportLabels.localizedValue("Normal", label: "Name"), "Normal")
        XCTAssertEqual(SystemReportLabels.localized("com.apple.example"), "com.apple.example")
    }

    func testReportsDefaultToFullyExpandedAndCollapseOnlyTheirSubtree() {
        let nodes = SystemReportParser.parse("""
        USB:
            Bus:
                Hub:
                    Product ID: 123
                Other device:
                    Product ID: 456
        """)
        let expanded = SystemReportOutline.rows(nodes)
        XCTAssertEqual(expanded.map { $0.node.label }, ["Bus", "Hub", "Product ID", "Other device", "Product ID"])
        XCTAssertEqual(expanded.map(\.depth), [0, 1, 2, 1, 2])
        let collapsed = SystemReportOutline.rows(nodes, collapsed: [expanded[1].id])
        XCTAssertEqual(collapsed.map { $0.node.label }, ["Bus", "Hub", "Other device", "Product ID"])
        XCTAssertEqual(SystemReportOutline.rows(nodes, collapsed: [expanded[0].id]).count, 1)
        XCTAssertEqual(SystemReportOutline.rows(nodes).map(\.id), expanded.map(\.id))
    }

    func testCancelledReportJobCannotStartAProcess() {
        let job = SystemReportJob(type: "SPMemoryDataType")
        job.cancel()
        XCTAssertNil(job.run())
    }
}
