import XCTest
@testable import MacUnseen

final class NetworkTopologyTests: XCTestCase {
    func testUSBHubFunctionsDoNotOccupyExtraPortsBesideUSB4Display() {
        let snapshot = HardwareStatusReader.networkSnapshot(
            profiler: usb4DisplayProfiler,
            preserving: NetworkSnapshot(),
            includePorts: true
        )

        let connected = snapshot.ports.filter(\.connected)
        XCTAssertEqual(connected.count, 1)
        XCTAssertEqual(connected.first?.id, "tb-1")
        XCTAssertEqual(connected.first?.deviceName, "Series 7 Pro 732pk")
        XCTAssertEqual(connected.first?.speed, "20 Gb/s")
    }

    func testThunderboltPeripheralInheritsNestedUpstreamSpeed() {
        let snapshot = HardwareStatusReader.networkSnapshot(
            profiler: usb4DisplayProfiler,
            preserving: NetworkSnapshot(),
            includePorts: true
        )

        let display = snapshot.peripherals.first {
            $0.name == "Series 7 Pro 732pk"
        }
        XCTAssertEqual(display?.protocolName, "Thunderbolt / USB4")
        XCTAssertEqual(display?.speed, "20 Gb/s")
    }

    func testSeparateUSBDeviceStillOccupiesItsOwnPort() {
        let snapshot = HardwareStatusReader.networkSnapshot(
            profiler: usb4DisplayAndSeparateDeviceProfiler,
            preserving: NetworkSnapshot(),
            includePorts: true
        )

        let connected = snapshot.ports.filter(\.connected)
        XCTAssertEqual(connected.count, 2)
        XCTAssertTrue(connected.contains { $0.id == "tb-1" })
        XCTAssertTrue(connected.contains {
            $0.id == "tb-2" && $0.deviceName == "External SSD"
        })
    }

    private var usb4DisplayProfiler: [String: Any] {
        [
            "SPThunderboltDataType": [
                [
                    "_name": "thunderboltusb4_bus_0",
                    "receptacle_1_tag": [
                        "receptacle_id_key": "1",
                        "receptacle_status_key": "receptacle_device_connected",
                        "current_speed_key": "20 Gb/s",
                    ],
                    "_items": [
                        [
                            "_name": "Series 7 Pro 732pk",
                            "device_name_key": "Series 7 Pro 732pk",
                            "route_string_key": "1",
                            "vendor_name_key": "HP",
                            "port_upstream": [
                                "current_speed_key": "20 Gb/s",
                            ],
                        ],
                    ],
                ],
                [
                    "_name": "thunderboltusb4_bus_1",
                    "receptacle_1_tag": [
                        "receptacle_id_key": "2",
                        "receptacle_status_key": "receptacle_no_devices_connected",
                        "current_speed_key": "Up to 120 Gb/s",
                    ],
                ],
            ],
            "SPUSBHostDataType": [
                [
                    "_name": "USB 2.0 Bus",
                    "_items": [[
                        "_name": "USB2.0 Hub",
                        "USBKeyLocationID": "0x01100000",
                        "USBDeviceKeyLinkSpeed": "480 Mb/s",
                    ]],
                ],
                [
                    "_name": "USB 3.1 Bus",
                    "_items": [[
                        "_name": "USB3.0 Hub",
                        "USBKeyLocationID": "0x02200000",
                        "USBDeviceKeyLinkSpeed": "10 Gb/s",
                    ]],
                ],
            ],
        ]
    }

    private var usb4DisplayAndSeparateDeviceProfiler: [String: Any] {
        var profiler = usb4DisplayProfiler
        var buses = profiler["SPUSBHostDataType"] as? [[String: Any]] ?? []
        buses.append([
            "_name": "USB 3.1 Bus",
            "_items": [[
                "_name": "External SSD",
                "USBKeyLocationID": "0x02200000",
                "USBDeviceKeyLinkSpeed": "10 Gb/s",
            ]],
        ])
        profiler["SPUSBHostDataType"] = buses
        return profiler
    }
}
