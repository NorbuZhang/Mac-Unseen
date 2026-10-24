import Foundation
import XCTest
@testable import MacUnseen

final class MagSafeTests: XCTestCase {
    func testConnectedMagSafeUsesReportedGenerationAndSeparatesFirmwareSources() throws {
        let snapshot = try XCTUnwrap(MagSafeReader.snapshot(port: [
            "PortTypeDescription": "MagSafe 3", "ConnectionActive": true,
            "ConnectionUUID": "connection-1", "FW Version": Data([0x00, 0x15, 0x31, 0x00]),
            "FwVersion": "ADAPTER-VERSION-MUST-NOT-BE-USED",
        ], transport: ["Vendor ID (SOP1)": 0x05AC, "Product ID (SOP1)": 0x7800]))
        XCTAssertEqual(snapshot.connector, "MagSafe 3")
        XCTAssertEqual(snapshot.connectionID, "connection-1")
        XCTAssertEqual(snapshot.controllerFirmware, "00 15 31 00")
        XCTAssertEqual(snapshot.cableVendorID, 0x05AC)
        XCTAssertEqual(snapshot.cableProductID, 0x7800)
    }

    func testDisconnectedOrUSBCPortDoesNotShowMagSafe() {
        XCTAssertNil(MagSafeReader.snapshot(port: ["PortTypeDescription": "MagSafe 3", "ConnectionActive": false], transport: [:]))
        XCTAssertNil(MagSafeReader.snapshot(port: ["PortTypeDescription": "USB-C", "ConnectionActive": true, "PortType": 17], transport: [:]))
        XCTAssertNil(MagSafeReader.snapshot(port: ["PortTypeDescription": "MagSafe 3"], transport: [:]))
    }

    func testMissingIdentityRemainsUnknownAndGenerationIsNotGuessed() throws {
        let snapshot = try XCTUnwrap(MagSafeReader.snapshot(port: ["PortTypeDescription": "MagSafe", "ConnectionActive": true], transport: ["Vendor ID (SOP1)": -1]))
        XCTAssertEqual(snapshot.connector, "MagSafe")
        XCTAssertNil(snapshot.controllerFirmware)
        XCTAssertNil(snapshot.cableVendorID)
        XCTAssertNil(snapshot.cableProductID)
        XCTAssertNil(MagSafeReader.firmwareText(Data()))
        XCTAssertNil(MagSafeReader.firmwareText("  "))
    }

    private let request = MagSafeFirmwareRequest(connectionID: "connection-1", rid: 5,
                                                address: 8, vendorID: 0x05AC, productID: 0x7800)
    // Actual register layout: response status, ID Header VDO, Cert Stat VDO,
    // then little-endian Product VDO (bcdDevice followed by PID).
    private let response = "0x49\t0x3D\t0x54AC05001C000000000032007840060B6100000000000000000000AC050000000000000000000000000000000000000000000000000000000000000000"
    private let header = "HPM at RID 0x5 Route 0x0 Address 0x08 :"

    func testCableFirmwareUsesMatchingControllerAndSOP1Identity() throws {
        let text = "HPM at RID 0x1 Route 0x0 Address 0x0a :\n" + response.replacingOccurrences(of: "00320078", with: "12310078")
            + "\n" + header + "\n" + response
        let firmware = try XCTUnwrap(MagSafeFirmwareParser.parse(text, for: request))
        XCTAssertEqual(firmware.bcdDevice, 0x3200)
        XCTAssertEqual(firmware.knownVersion, "3.2.0")
        XCTAssertEqual(firmware.rawVersion, "0x3200")
        let old = try XCTUnwrap(MagSafeFirmwareParser.parse(header + "\n" + response.replacingOccurrences(of: "00320078", with: "12310078"), for: request))
        XCTAssertEqual(old.knownVersion, "3.1.12")
    }

    func testWrongCableOrControllerCannotSupplyFirmware() {
        for invalidHeader in [header.replacingOccurrences(of: "0x5", with: "0x1"),
                              header.replacingOccurrences(of: "0x08", with: "0x0c"),
                              header.replacingOccurrences(of: "Route 0x0", with: "Route 0x1")] {
            XCTAssertNil(MagSafeFirmwareParser.parse(invalidHeader + "\n" + response, for: request))
        }
        for invalidResponse in [response.replacingOccurrences(of: "54AC05", with: "54F003"),
                                response.replacingOccurrences(of: "00320078", with: "00320178"),
                                response.replacingOccurrences(of: "0x49", with: "0x48")] {
            XCTAssertNil(MagSafeFirmwareParser.parse(header + "\n" + invalidResponse, for: request))
        }
    }

    func testMalformedMissingAndAmbiguousResponsesRemainUnavailable() {
        for invalid in ["", response, header + "\n0x49 0x3D 0x54AC05",
                        header + "\n" + response.replacingOccurrences(of: "0x3D", with: "0x3E"),
                        header + "\n" + response.replacingOccurrences(of: "54AC05", with: "54ZZ05"),
                        header + "\n" + response.replacingOccurrences(of: "54AC05", with: "00AC05"),
                        header + "\n" + response.replacingOccurrences(of: "00320078", with: "00000078"),
                        header + "\n" + response.replacingOccurrences(of: "00320078", with: "FFFF0078"),
                        header + "\n" + response + "\n" + response] {
            XCTAssertNil(MagSafeFirmwareParser.parse(invalid, for: request))
        }
    }

    func testUnknownCableRevisionPreservesRawValue() throws {
        let firmware = try XCTUnwrap(MagSafeFirmwareParser.parse(header + "\n" + response.replacingOccurrences(of: "00320078", with: "10330078"), for: request))
        XCTAssertNil(firmware.knownVersion)
        XCTAssertEqual(firmware.displayVersion, "0x3310")
    }

    func testFirmwareRequestRequiresMatchingAppleCableAndController() throws {
        let port: [String: Any] = ["PortTypeDescription": "MagSafe 3", "ConnectionActive": true, "ConnectionUUID": "connection-1"]
        let transport: [String: Any] = ["Vendor ID (SOP1)": 0x05AC, "Product ID (SOP1)": 0x7800]
        XCTAssertEqual(MagSafeReader.snapshot(port: port, transport: transport, controller: ["RID": 5, "Address": 8])?.firmwareRequest, request)
        XCTAssertNil(MagSafeReader.snapshot(port: port, transport: transport)?.firmwareRequest)
        XCTAssertNil(MagSafeReader.snapshot(port: port, transport: ["Vendor ID (SOP1)": 0x1234, "Product ID (SOP1)": 0x7800], controller: ["RID": 5, "Address": 8])?.firmwareRequest)
        var reconnected = port
        reconnected["ConnectionUUID"] = "connection-2"
        XCTAssertNotEqual(MagSafeReader.snapshot(port: reconnected, transport: transport, controller: ["RID": 5, "Address": 8])?.firmwareRequest, request)
    }

    func testCancelledFirmwareJobDoesNotLaunch() {
        let job = MagSafeFirmwareJob()
        job.cancel()
        XCTAssertNil(job.run(for: request))
    }
}
