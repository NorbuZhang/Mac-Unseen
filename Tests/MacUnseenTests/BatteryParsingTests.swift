import Foundation
import XCTest
@testable import MacUnseen

final class BatteryParsingTests: XCTestCase {
    func testFullChargeRatioIsUncappedAndIndependentOfQmaxAndSystemHealth() throws {
        var battery = BatterySnapshot(designCapacity: 6000, qmaxCapacity: 7000,
                                      healthPercentage: 97, fullChargeCapacity: 6300)
        XCTAssertEqual(try XCTUnwrap(battery.fullChargeCapacityRatio), 105, accuracy: 0.001)
        XCTAssertEqual(batteryHealth(battery), "97")
        battery.designCapacity = 6249
        battery.fullChargeCapacity = 6089
        XCTAssertEqual(try XCTUnwrap(battery.fullChargeCapacityRatio), 97.43959, accuracy: 0.0001)
        battery.qmaxCapacity = nil
        XCTAssertEqual(try XCTUnwrap(battery.fullChargeCapacityRatio), 97.43959, accuracy: 0.0001)
    }

    func testFullChargeRatioDoesNotInventMissingCapacityOrAcceptInvalidInputs() {
        var battery = BatterySnapshot(designCapacity: 6000, nominalCapacity: 6200,
                                      qmaxCapacity: 6500, healthPercentage: 100)
        XCTAssertNil(battery.fullChargeCapacityRatio)
        for invalid in [0, -1, Double.nan, Double.infinity] {
            battery.fullChargeCapacity = invalid
            XCTAssertNil(battery.fullChargeCapacityRatio)
            battery.fullChargeCapacity = 6300
            battery.designCapacity = invalid
            XCTAssertNil(battery.fullChargeCapacityRatio)
            battery.designCapacity = 6000
        }
        battery.designCapacity = nil
        XCTAssertNil(battery.fullChargeCapacityRatio)
    }

    func testFullChargeAliasDoesNotPopulateQmaxOrSystemHealth() throws {
        var battery = BatterySnapshot()
        SystemReader.applyPackBatteryData(["DesignCapacity": 6000, "FullChargeCapacity": 6300,
                                           "NominalChargeCapacity": 6500, "MaxCapacity": 100],
                                          to: &battery, includeStatic: true, includeMedium: false, includeSlow: true)
        XCTAssertEqual(try XCTUnwrap(battery.fullChargeCapacityRatio), 105, accuracy: 0.001)
        XCTAssertNil(battery.qmaxCapacity)
        XCTAssertNil(battery.healthPercentage)
    }

    func testPackLayoutDecodesTemperatureCapacitiesAndLifetime() throws {
        let lifetime: [String: Any] = [
            "AverageTemperature": 218,
            "MinimumTemperature": 15,
            "MaximumTemperature": 40,
            "MaximumChargeCurrent": 6658,
            "MaximumDischargeCurrent": NSNumber(
                value: UInt64.max - 9_244
            ),
        ]
        let pack: [String: Any] = [
            "Temperature": 3359,
            "DesignCapacity": 6249,
            "MaxCapacity": 100,
            "NominalChargeCapacity": 6390,
            "AppleRawMaxCapacity": 6238,
            "AppleRawCurrentCapacity": 5961,
            "LifetimeData": lifetime,
        ]
        var snapshot = BatterySnapshot()

        SystemReader.applyPackBatteryData(
            pack,
            to: &snapshot,
            includeStatic: true,
            includeMedium: true,
            includeSlow: true
        )
        snapshot.temperature = SystemReader.normalizedCurrentBatteryTemperature(
            3359,
            preferCentiDegrees: true,
            historicalMinimum: snapshot.historicalMinTemperature,
            historicalMaximum: snapshot.historicalMaxTemperature,
            averageTemperature: 21.8
        )

        XCTAssertEqual(try XCTUnwrap(snapshot.temperature), 33.59, accuracy: 0.001)
        XCTAssertEqual(snapshot.designCapacity, 6249)
        XCTAssertEqual(snapshot.nominalCapacity, 6390)

        XCTAssertNil(snapshot.healthPercentage)
        XCTAssertEqual(batteryHealth(snapshot), "—")
        XCTAssertEqual(snapshot.fullChargeCapacity, 6238)
        XCTAssertEqual(snapshot.rawCurrentCapacity, 5961)
        XCTAssertEqual(snapshot.historicalMinTemperature, 15)
        XCTAssertEqual(snapshot.historicalMaxTemperature, 40)
        XCTAssertEqual(
            try XCTUnwrap(snapshot.historicalMaxChargeCurrent),
            6.658,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(snapshot.historicalMaxDischargeCurrent),
            9.245,
            accuracy: 0.001
        )
    }

    func testFullChargeCapacityIsUsedWhenRawAliasIsAbsent() {
        let pack: [String: Any] = [
            "DesignCapacity": 6249,
            "NominalChargeCapacity": 5971,
            "FullChargeCapacity": 5819,
        ]
        var snapshot = BatterySnapshot()

        SystemReader.applyPackBatteryData(
            pack,
            to: &snapshot,
            includeStatic: true,
            includeMedium: false,
            includeSlow: false
        )

        XCTAssertEqual(snapshot.designCapacity, 6249)
        XCTAssertEqual(snapshot.nominalCapacity, 5971)

        XCTAssertEqual(snapshot.fullChargeCapacity, 5819)
        XCTAssertEqual(batteryHealth(snapshot), "—")
    }

    func testSystemHealthPercentageTakesPriorityOverCapacityRatio() {
        let battery = BatterySnapshot(
            designCapacity: 6249,
            healthPercentage: 100,
            fullChargeCapacity: 5829
        )

        XCTAssertEqual(batteryHealth(battery), "100")
    }

    func testQmaxNeverOverridesSystemHealthBelowOneHundred() {
        let battery = BatterySnapshot(
            designCapacity: 6249,
            qmaxCapacity: 6587,
            healthPercentage: 97
        )

        XCTAssertEqual(batteryHealth(battery), "97")
    }

    func testLowestCellQmaxLimitsPackCapacity() {
        let records: [[String: Any]] = [
            bank(pack: 0, id: 0, voltage: 4385, resistance: 53, qmax: 6235),
            bank(pack: 0, id: 1, voltage: 4386, resistance: 39, qmax: 6227),
            bank(pack: 0, id: 2, voltage: 4386, resistance: 41, qmax: 6228),
        ]

        XCTAssertEqual(SystemReader.representativeQmax(records), 6227)
    }

    func testSlowPackRefreshPreservesQmaxWhenBankReadIsUnavailable() {
        var snapshot = BatterySnapshot(
            designCapacity: 6249,
            qmaxCapacity: 6587,
            healthPercentage: 97,
            fullChargeCapacity: 6095
        )
        SystemReader.applyPackBatteryData(
            ["MaxCapacity": 100, "AppleRawMaxCapacity": 6080, "NominalChargeCapacity": 6247],
            to: &snapshot,
            includeStatic: false,
            includeMedium: true,
            includeSlow: true
        )

        XCTAssertNil(SystemReader.representativeQmax([]))

        XCTAssertEqual(snapshot.qmaxCapacity, 6587)
        XCTAssertEqual(snapshot.fullChargeCapacity, 6080)
        XCTAssertEqual(snapshot.healthPercentage, 97)
    }

    func testBankLayoutIsStableByPackAndBankID() {
        let records: [[String: Any]] = [
            bank(pack: 0, id: 2, voltage: 4426, resistance: 56),
            bank(pack: 0, id: 0, voltage: 4428, resistance: 54),
            bank(pack: 0, id: 1, voltage: 4427, resistance: 55),
        ]

        let result = SystemReader.decodedCellMeasurements(
            legacyBatteryData: nil,
            bankRecords: records
        )

        XCTAssertEqual(result.voltages, [4.428, 4.427, 4.426])
        XCTAssertEqual(result.resistance, [54, 55, 56])
    }

    func testLegacyArraysRemainPreferred() {
        let legacy: [String: Any] = [
            "CellVoltage": [4201, 4202, 4203],
            "WeightedRa": [41, 42, 43],
        ]
        let result = SystemReader.decodedCellMeasurements(
            legacyBatteryData: legacy,
            bankRecords: [bank(pack: 0, id: 0, voltage: 4400, resistance: 90)]
        )

        XCTAssertEqual(result.voltages, [4.201, 4.202, 4.203])
        XCTAssertEqual(result.resistance, [41, 42, 43])
    }

    func testMediumAndSlowFieldsRemainGated() {
        let pack: [String: Any] = [
            "AppleRawCurrentCapacity": 6000,
            "AppleRawMaxCapacity": 6500,
            "LifetimeData": [
                "MinimumTemperature": 10,
                "MaximumTemperature": 50,
            ],
        ]
        var snapshot = BatterySnapshot(
            fullChargeCapacity: 6200,
            rawCurrentCapacity: 5800,
            historicalMinTemperature: 15,
            historicalMaxTemperature: 40
        )

        SystemReader.applyPackBatteryData(
            pack,
            to: &snapshot,
            includeStatic: false,
            includeMedium: false,
            includeSlow: false
        )

        XCTAssertEqual(snapshot.rawCurrentCapacity, 5800)
        XCTAssertEqual(snapshot.fullChargeCapacity, 6200)
        XCTAssertEqual(snapshot.historicalMinTemperature, 15)
        XCTAssertEqual(snapshot.historicalMaxTemperature, 40)
    }

    func testAdvancedSnapshotParsesStructuredLivePower() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "status": "running",
            "livePower": [
                "inputPower": 31.25,
                "inputVoltage": 20.0,
                "inputCurrent": 1.5625,
                "batteryPower": -4.5,
                "systemPower": 26.75,
                "timestamp": 1_750_000_000.0,
            ],
        ])

        let snapshot = try XCTUnwrap(AdvancedSnapshotParser.parse(data))
        XCTAssertEqual(snapshot.livePower.inputPower, 31.25)
        XCTAssertEqual(snapshot.livePower.inputVoltage, 20.0)
        XCTAssertEqual(snapshot.livePower.inputCurrent, 1.5625)
        XCTAssertEqual(snapshot.livePower.batteryPower, -4.5)
        XCTAssertEqual(snapshot.livePower.systemPower, 26.75)
        XCTAssertEqual(
            snapshot.livePower.timestamp,
            Date(timeIntervalSince1970: 1_750_000_000)
        )
    }

    private func bank(
        pack: Int,
        id: Int,
        voltage: Int,
        resistance: Int,
        qmax: Int? = nil
    ) -> [String: Any] {
        var data: [String: Any] = [
            "CellVoltage": voltage,
            "WeightedRa": resistance,
        ]
        if let qmax {
            data["Qmax"] = qmax
        }
        return [
            "PackID": pack,
            "BankID": id,
            "BatteryData": data,
        ]
    }
}
