import Darwin
import Foundation
import IOKit

enum SystemReader {
    static func readSystem(
        preserving previous: SystemSnapshot = SystemSnapshot(),
        includeStatic: Bool = true,
        includeDiskUsage: Bool = true
    ) -> SystemSnapshot {
        var snapshot = previous
        if includeStatic {
            snapshot.modelIdentifier = sysctlString("hw.model") ?? ""
            snapshot.modelName = modelDisplayName(for: snapshot.modelIdentifier)
            snapshot.chipName = sysctlString("machdep.cpu.brand_string") ?? ""
            snapshot.serialNumber = platformSerialNumber()
            snapshot.processorCount = ProcessInfo.processInfo.processorCount
            snapshot.memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
        }
        snapshot.memoryUsed = PerformanceReader.memory().used ?? previous.memoryUsed
        snapshot.uptime = ProcessInfo.processInfo.systemUptime

        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 {
            snapshot.loadAverages = loads
        }

        if includeDiskUsage {
            if let values = try? URL(fileURLWithPath: "/").resourceValues(
                forKeys: [
                    .volumeTotalCapacityKey,
                    .volumeAvailableCapacityForImportantUsageKey,
                ]
            ) {
                let total = Double(values.volumeTotalCapacity ?? 0)
                let available = Double(
                    values.volumeAvailableCapacityForImportantUsage ?? 0
                )
                snapshot.diskTotal = total
                snapshot.diskUsed = max(0, total - available)
            }
        }

        snapshot.thermalState = switch ProcessInfo.processInfo.thermalState {
        case .nominal: "正常"
        case .fair: "轻度升温"
        case .serious: "较高"
        case .critical: "严重"
        @unknown default: "未知"
        }
        return snapshot
    }

    static func readBattery(
        preserving previous: BatterySnapshot = BatterySnapshot(),
        includeStatic: Bool = true,
        includeMedium: Bool = true,
        includeSlow: Bool = true
    ) -> BatterySnapshot {
        var snapshot = previous
        guard let matching = IOServiceMatching("AppleSmartBattery") else {
            return snapshot
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else {
            return snapshot
        }
        defer { IOObjectRelease(service) }

        let needsBatteryData = includeStatic || includeMedium || includeSlow
        let batteryData = needsBatteryData
            ? serviceDictionaryProperty("BatteryData", service: service)
            : nil

        var packData: [String: Any]?
        if let packMatching = IOServiceMatching("AppleSmartBatteryPack") {
            let packService = IOServiceGetMatchingService(
                kIOMainPortDefault,
                packMatching
            )
            if packService != IO_OBJECT_NULL {
                packData = serviceDictionaryProperty(
                    "BatteryData",
                    service: packService
                )
                IOObjectRelease(packService)
            }
        }

        if includeMedium {
            if let percentage = validated(
                serviceNumberProperty("CurrentCapacity", service: service)
                    ?? batteryData.flatMap { number("CurrentCapacity", in: $0) }
                    ?? packData.flatMap { number("StateOfCharge", in: $0) },
                range: 0...100
            ) {
                snapshot.percentage = percentage
            }
        }
        if let voltage = validated(
            serviceNumberProperty("Voltage", service: service).map {
                $0 / 1000.0
            },
            range: 5...30
        ) {
            snapshot.voltage = voltage
        }
        if let amperage = validated(
            serviceSignedNumberProperty("InstantAmperage", service: service)
                .map { $0 / 1000.0 },
            range: -30...30
        ) {
            snapshot.amperage = amperage
        }
        if includeSlow {
            snapshot.cycleCount = serviceIntegerProperty(
                "CycleCount",
                service: service
            ) ?? packData.flatMap { integer("CycleCount", in: $0) }
        }
        if includeStatic {
            snapshot.designCapacity = batteryCapacityValue(
                serviceNumberProperty("DesignCapacity", service: service)
                    ?? batteryData.flatMap { number("DesignCapacity", in: $0) }
                    ?? packData.flatMap { number("DesignCapacity", in: $0) }
            )
        }
        if includeStatic || includeSlow {
            // MaxCapacity may be the normalized charge scale (100), not battery
            // health. The authoritative percentage comes from the power report.
            snapshot.nominalCapacity = batteryCapacityValue(
                serviceNumberProperty("NominalChargeCapacity", service: service)
                    ?? batteryData.flatMap {
                        number("NominalChargeCapacity", in: $0)
                    }
                    ?? packData.flatMap {
                        number("NominalChargeCapacity", in: $0)
                    }
            )
            snapshot.fullChargeCapacity = batteryCapacityValue(
                serviceNumberProperty("AppleRawMaxCapacity", service: service)
                    ?? batteryData.flatMap {
                        number("AppleRawMaxCapacity", in: $0)
                            ?? number("FullChargeCapacity", in: $0)
                    }
                    ?? packData.flatMap {
                        number("AppleRawMaxCapacity", in: $0)
                            ?? number("FullChargeCapacity", in: $0)
                    }
            )
        }
        if includeMedium,
           let rawCurrentCapacity = batteryCapacityValue(
               serviceNumberProperty("AppleRawCurrentCapacity", service: service)
                   ?? batteryData.flatMap {
                       number("AppleRawCurrentCapacity", in: $0)
                   }
                   ?? packData.flatMap {
                       number("AppleRawCurrentCapacity", in: $0)
                   }
           ) {
            snapshot.rawCurrentCapacity = rawCurrentCapacity
        }
        if let packData {
            applyPackBatteryData(
                packData,
                to: &snapshot,
                includeStatic: includeStatic,
                includeMedium: includeMedium,
                includeSlow: includeSlow
            )
        }

        if let charging = serviceBoolProperty("IsCharging", service: service) {
            snapshot.charging = charging
        }
        let externalConnected = serviceBoolProperty(
            "ExternalConnected",
            service: service
        )
        let externalChargeCapable = serviceBoolProperty(
            "ExternalChargeCapable",
            service: service
        )
        if externalConnected != nil || externalChargeCapable != nil {
            snapshot.externalConnected = (externalConnected ?? false)
                || (externalChargeCapable ?? false)
        }

        if includeSlow {
            let lifetime = packData.flatMap { dictionary("LifetimeData", in: $0) }
                ?? batteryData.flatMap { dictionary("LifetimeData", in: $0) }
            if let lifetime {
                applyLifetimeData(lifetime, to: &snapshot)
            }
        }

        let rawPackTemperature = packData.flatMap { number("Temperature", in: $0) }
        let rawTopTemperature = serviceNumberProperty(
            "Temperature",
            service: service
        ) ?? batteryData.flatMap { number("Temperature", in: $0) }
        let rawTemperature = rawPackTemperature ?? rawTopTemperature
        let averageTemperature = packData
            .flatMap { dictionary("LifetimeData", in: $0) }
            .flatMap { signedNumber("AverageTemperature", in: $0) }
            .map { $0 / 10.0 }
        if let temperature = normalizedCurrentBatteryTemperature(
            rawTemperature,
            preferCentiDegrees: rawPackTemperature != nil,
            historicalMinimum: snapshot.historicalMinTemperature,
            historicalMaximum: snapshot.historicalMaxTemperature,
            averageTemperature: averageTemperature
        ) {
            snapshot.temperature = temperature
        }

        if includeStatic || includeMedium || includeSlow {
            let banks = batteryBankRecords()
            if let qmax = representativeQmax(banks) {
                snapshot.qmaxCapacity = qmax
            }
            let measurements = decodedCellMeasurements(
                legacyBatteryData: batteryData,
                bankRecords: banks
            )
            if includeMedium {
                let voltages = measurements.voltages
                if !voltages.isEmpty {
                    snapshot.cellVoltages = voltages
                }
            }
            if includeSlow {
                let resistance = measurements.resistance
                if !resistance.isEmpty {
                    snapshot.cellResistance = resistance
                }
            }
        }

        if includeStatic || includeMedium || includeSlow
            || previous.externalConnected != snapshot.externalConnected {
            snapshot.magSafe = MagSafeReader.read(
                preserving: previous.magSafe,
                refreshMetadata: includeStatic || includeSlow
            )
        }

        let shouldRefreshAdapterDetails = includeSlow
            || previous.magSafe?.connectionID != snapshot.magSafe?.connectionID
            || (!previous.externalConnected && snapshot.externalConnected)
            || previous.adapterName == nil
            || previous.adapterName == "外接电源"
        let adapter = shouldRefreshAdapterDetails
            ? serviceFirstDictionaryProperty("AdapterDetails", service: service)
                ?? serviceFirstDictionaryProperty(
                    "AppleRawAdapterDetails",
                    service: service
                )
            : nil
        let hasAdapterDetails = adapter.map(adapterIsPresent) == true
        if let adapter, snapshot.externalConnected || hasAdapterDetails {
            snapshot.externalConnected = true
            snapshot.adapterName = adapterDisplayName(adapter)
            snapshot.adapterRatedWatts = validated(
                number("Watts", in: adapter),
                range: 0...500
            )
            snapshot.negotiatedVoltage = validated(
                number("AdapterVoltage", in: adapter).map { $0 / 1000.0 },
                range: 0...60
            )
            snapshot.negotiatedCurrent = validated(
                number("Current", in: adapter).map { $0 / 1000.0 },
                range: 0...15
            )
            snapshot.pdProfiles = []
            if let profiles = dictionaryArray(adapter["UsbHvcMenu"]) {
                snapshot.pdProfiles = profiles.compactMap { profile in
                    guard let voltage = validated(
                              number("MaxVoltage", in: profile),
                              range: 0...60_000
                          ),
                          let current = validated(
                              number("MaxCurrent", in: profile),
                              range: 0...15_000
                          )
                    else {
                        return nil
                    }
                    return String(
                        format: "%.0fV × %.2fA (%.0fW)",
                        voltage / 1000.0,
                        current / 1000.0,
                        voltage * current / 1_000_000.0
                    )
                }
            }
        } else if !snapshot.externalConnected {
            snapshot.adapterName = nil
            snapshot.adapterRatedWatts = nil
            snapshot.negotiatedVoltage = nil
            snapshot.negotiatedCurrent = nil
            snapshot.pdProfiles = []
        }

        if let telemetry = serviceDictionaryProperty(
            "PowerTelemetryData",
            service: service
        ) {
            if let inputPower = validated(
                number("SystemPowerIn", in: telemetry).map {
                    $0 / 1000.0
                },
                range: 0...1_000
            ) {
                snapshot.liveInputPower = inputPower
            }
            if let inputVoltage = validated(
                number("SystemVoltageIn", in: telemetry).map {
                    $0 / 1000.0
                },
                range: 0...60
            ) {
                snapshot.liveInputVoltage = inputVoltage
            }
            if let inputCurrent = validated(
                signedNumber("SystemCurrentIn", in: telemetry).map {
                    abs($0) / 1000.0
                },
                range: 0...30
            ) {
                snapshot.liveInputCurrent = inputCurrent
            }
        }
        if let distribution = serviceDictionaryProperty(
            "PowerDistribution",
            service: service
        ) {
            if snapshot.liveInputPower == nil
                || snapshot.liveInputPower == 0 {
                snapshot.liveInputPower = validated(
                    number("IPDInputPower", in: distribution).map {
                        $0 / 1000.0
                    },
                    range: 0...1_000
                )
            }
            if snapshot.liveInputVoltage == nil
                || snapshot.liveInputVoltage == 0 {
                snapshot.liveInputVoltage = validated(
                    number("IPDInputVoltage", in: distribution).map {
                        $0 / 1000.0
                    },
                    range: 0...60
                )
            }
            if snapshot.liveInputCurrent == nil
                || snapshot.liveInputCurrent == 0 {
                snapshot.liveInputCurrent = validated(
                    signedNumber("IPDInputCurrent", in: distribution).map {
                        abs($0) / 1000.0
                    },
                    range: 0...30
                )
            }
        }
        // USB-C controllers may report a 5 V standby voltage while unplugged.
        // Require actual transferred power/current before inferring a charger.
        let hasLiveInput = snapshot.liveInputPower.map { $0 > 0.5 } == true
            || snapshot.liveInputCurrent.map { $0 > 0.05 } == true
        if snapshot.charging || hasLiveInput {
            snapshot.externalConnected = true
        }
        if !snapshot.externalConnected {
            snapshot.liveInputPower = nil
            snapshot.liveInputVoltage = nil
            snapshot.liveInputCurrent = nil
        }
        if snapshot.externalConnected, snapshot.adapterName == nil {
            snapshot.adapterName = "外接电源"
        }
        applyLiveBatteryExtremes(to: &snapshot)

        return snapshot
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        let bytes = buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func modelDisplayName(for identifier: String) -> String {
        if identifier == "Mac17,5" {
            return "MacBook Neo"
        }
        if identifier.hasPrefix("MacBookAir") {
            return "MacBook Air"
        }
        if identifier.hasPrefix("MacBookPro") {
            return "MacBook Pro"
        }
        if identifier.hasPrefix("Macmini") {
            return "Mac mini"
        }
        if identifier.hasPrefix("iMac") {
            return "iMac"
        }
        if identifier.hasPrefix("MacStudio") {
            return "Mac Studio"
        }
        return "Mac"
    }

    static func normalizedCurrentBatteryTemperature(
        _ rawValue: Double?,
        preferCentiDegrees: Bool = false,
        historicalMinimum: Double? = nil,
        historicalMaximum: Double? = nil,
        averageTemperature: Double? = nil
    ) -> Double? {
        guard let rawValue, rawValue.isFinite else {
            return nil
        }

        var candidates: [(value: Double, score: Double)] = []
        if (1_000...10_000).contains(rawValue) {
            candidates.append((rawValue / 100.0, preferCentiDegrees ? 0 : 1))
        }
        if (1_800...4_000).contains(rawValue) {
            candidates.append((rawValue / 10.0 - 273.15, preferCentiDegrees ? 2 : 0))
        }
        if (-400...1_000).contains(rawValue) {
            candidates.append((rawValue / 10.0, 3))
        }
        if (-40...100).contains(rawValue) {
            candidates.append((rawValue, 4))
        }

        let validCandidates = candidates.compactMap { candidate -> (Double, Double)? in
            guard (-30...100).contains(candidate.value) else {
                return nil
            }
            var score = candidate.score
            if let minimum = historicalMinimum,
               let maximum = historicalMaximum,
               minimum <= maximum {
                let permittedRange = (minimum - 5)...(maximum + 5)
                if !permittedRange.contains(candidate.value) {
                    score += 100 + min(
                        abs(candidate.value - minimum),
                        abs(candidate.value - maximum)
                    )
                }
            }
            if let averageTemperature,
               (-30...100).contains(averageTemperature) {
                score += abs(candidate.value - averageTemperature) * 0.05
            }
            return (candidate.value, score)
        }
        return validCandidates.min { $0.1 < $1.1 }?.0
    }

    private static func batteryCapacityValue(_ value: Double?) -> Double? {
        validated(value, range: 0...30_000)
    }

    static func applyPackBatteryData(
        _ data: [String: Any],
        to snapshot: inout BatterySnapshot,
        includeStatic: Bool,
        includeMedium: Bool,
        includeSlow: Bool
    ) {
        if includeStatic,
           let capacity = batteryCapacityValue(number("DesignCapacity", in: data)) {
            snapshot.designCapacity = capacity
        }
        if includeStatic || includeSlow {
            snapshot.nominalCapacity = batteryCapacityValue(
                number("NominalChargeCapacity", in: data)
            )
            snapshot.fullChargeCapacity = batteryCapacityValue(
                number("AppleRawMaxCapacity", in: data)
                    ?? number("FullChargeCapacity", in: data)
            )
            // Qmax stays separate, even when a bank reading is unavailable.
        }
        if includeMedium,
           let capacity = batteryCapacityValue(
               number("AppleRawCurrentCapacity", in: data)
           ) {
            snapshot.rawCurrentCapacity = capacity
        }
        if includeSlow,
           let lifetime = dictionary("LifetimeData", in: data) {
            applyLifetimeData(lifetime, to: &snapshot)
        }
    }

    static func applyLifetimeData(
        _ lifetime: [String: Any],
        to snapshot: inout BatterySnapshot
    ) {
        let temperatures = normalizedHistoricalBatteryTemperatures(
            minimum: signedNumber("MinimumTemperature", in: lifetime),
            maximum: signedNumber("MaximumTemperature", in: lifetime)
        )
        if let minimum = temperatures.0 {
            snapshot.historicalMinTemperature = minimum
        }
        if let maximum = temperatures.1 {
            snapshot.historicalMaxTemperature = maximum
        }
        if let current = validated(
            signedNumber("MaximumChargeCurrent", in: lifetime)
                .map { abs($0) / 1000.0 },
            range: 0...50
        ) {
            snapshot.historicalMaxChargeCurrent = current
        }
        if let current = validated(
            signedNumber("MaximumDischargeCurrent", in: lifetime)
                .map { abs($0) / 1000.0 },
            range: 0...50
        ) {
            snapshot.historicalMaxDischargeCurrent = current
        }
    }

    static func decodedBankMeasurements(
        _ records: [[String: Any]]
    ) -> (voltages: [Double], resistance: [Double]) {
        let ordered = records.sorted { lhs, rhs in
            let leftPack = integer("PackID", in: lhs) ?? 0
            let rightPack = integer("PackID", in: rhs) ?? 0
            if leftPack != rightPack {
                return leftPack < rightPack
            }
            return (integer("BankID", in: lhs) ?? 0)
                < (integer("BankID", in: rhs) ?? 0)
        }
        var voltages: [Double] = []
        var resistance: [Double] = []
        for record in ordered {
            guard let data = dictionary("BatteryData", in: record) else {
                continue
            }
            if let voltage = number("CellVoltage", in: data).map({ $0 / 1000.0 }),
               (2...5.5).contains(voltage) {
                voltages.append(voltage)
            }
            if let value = number("WeightedRa", in: data),
               (0...100_000).contains(value) {
                resistance.append(value)
            }
        }
        return (voltages, resistance)
    }

    private static func platformSerialNumber() -> String? {
        guard let matching = IOServiceMatching("IOPlatformExpertDevice") else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        let serial = (serviceProperty("IOPlatformSerialNumber", service: service) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return serial?.isEmpty == false ? serial : nil
    }

    static func representativeQmax(
        _ records: [[String: Any]]
    ) -> Double? {
        let values = records.compactMap { record -> Double? in
            guard let data = dictionary("BatteryData", in: record),
                  let qmax = number("Qmax", in: data),
                  (100...30_000).contains(qmax) else {
                return nil
            }
            return qmax
        }
        // Cells are connected in series, so the lowest learned cell capacity
        // is the conservative limit for the whole battery pack.
        return values.min()
    }

    static func decodedCellMeasurements(
        legacyBatteryData: [String: Any]?,
        bankRecords: [[String: Any]]
    ) -> (voltages: [Double], resistance: [Double]) {
        let legacyVoltages = legacyBatteryData
            .map { numberArray("CellVoltage", in: $0) } ?? []
        let legacyResistance = legacyBatteryData
            .map { numberArray("WeightedRa", in: $0) } ?? []
        let banks = decodedBankMeasurements(bankRecords)
        let voltages = (legacyVoltages.isEmpty
            ? banks.voltages
            : legacyVoltages.map { $0 / 1000.0 })
            .filter { (2...5.5).contains($0) }
        let resistance = (legacyResistance.isEmpty
            ? banks.resistance
            : legacyResistance)
            .filter { (0...100_000).contains($0) }
        return (voltages, resistance)
    }

    private static func batteryBankRecords() -> [[String: Any]] {
        guard let matching = IOServiceMatching("AppleSmartBatteryBank") else {
            return []
        }
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matching,
            &iterator
        ) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var records: [[String: Any]] = []
        while true {
            let bank = IOIteratorNext(iterator)
            guard bank != IO_OBJECT_NULL else {
                break
            }
            defer { IOObjectRelease(bank) }
            guard let data = serviceDictionaryProperty(
                "BatteryData",
                service: bank
            ) else {
                continue
            }
            var record: [String: Any] = ["BatteryData": data]
            if let packID = serviceIntegerProperty("PackID", service: bank) {
                record["PackID"] = packID
            }
            if let bankID = serviceIntegerProperty("BankID", service: bank) {
                record["BankID"] = bankID
            }
            records.append(record)
        }
        return records
    }

    private static func adapterDisplayName(
        _ adapter: [String: Any]
    ) -> String? {
        if let name = adapter["Name"] as? String,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        let description = (adapter["Description"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if description?.localizedCaseInsensitiveContains("pd charger") == true
            || number("FamilyCode", in: adapter).map({ $0 > 0 }) == true {
            return "第三方充电器"
        }
        return nil
    }

    private static func adapterIsPresent(_ adapter: [String: Any]) -> Bool {
        if let name = adapter["Name"] as? String,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let description = adapter["Description"] as? String,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return number("Watts", in: adapter).map { $0 > 0 } == true
            || number("AdapterVoltage", in: adapter).map { $0 > 0 } == true
            || number("Current", in: adapter).map { $0 > 0 } == true
    }

    private static func validated(
        _ value: Double?,
        range: ClosedRange<Double>
    ) -> Double? {
        guard let value, value.isFinite, range.contains(value) else {
            return nil
        }
        return value
    }

    static func normalizedHistoricalBatteryTemperatures(
        minimum: Double?,
        maximum: Double?
    ) -> (Double?, Double?) {
        guard let minimum, let maximum,
              minimum.isFinite, maximum.isFinite else {
            return (nil, nil)
        }
        for scale in [1.0, 0.1] {
            let scaledMinimum = minimum * scale
            let scaledMaximum = maximum * scale
            if (-40...80).contains(scaledMinimum),
               (-20...100).contains(scaledMaximum),
               scaledMinimum <= scaledMaximum {
                return (scaledMinimum, scaledMaximum)
            }
        }
        return (nil, nil)
    }

    private static func applyLiveBatteryExtremes(
        to snapshot: inout BatterySnapshot
    ) {
        if let temperature = snapshot.temperature {
            if snapshot.historicalMinTemperature.map({
                temperature < $0
            }) != false {
                snapshot.historicalMinTemperature = temperature
            }
            if snapshot.historicalMaxTemperature.map({
                temperature > $0
            }) != false {
                snapshot.historicalMaxTemperature = temperature
            }
        }

        guard let amperage = snapshot.amperage else {
            return
        }
        let absoluteAmperage = abs(amperage)
        if snapshot.charging || amperage > 0 {
            if snapshot.historicalMaxChargeCurrent.map({
                absoluteAmperage > $0
            }) != false {
                snapshot.historicalMaxChargeCurrent = absoluteAmperage
            }
        } else if amperage < 0,
                  snapshot.historicalMaxDischargeCurrent.map({
                      absoluteAmperage > $0
                  }) != false {
            snapshot.historicalMaxDischargeCurrent = absoluteAmperage
        }
    }

    private static func dictionary(
        _ key: String,
        in dictionary: [String: Any]
    ) -> [String: Any]? {
        if let value = dictionary[key] as? [String: Any] {
            return value
        }
        if let value = dictionary[key] as? NSDictionary {
            return value as? [String: Any]
        }
        return nil
    }

    private static func number(
        _ key: String,
        in dictionary: [String: Any]
    ) -> Double? {
        (dictionary[key] as? NSNumber)?.doubleValue
    }

    private static func signedNumber(
        _ key: String,
        in dictionary: [String: Any]
    ) -> Double? {
        guard let value = dictionary[key] as? NSNumber else {
            return nil
        }
        return Double(value.int64Value)
    }

    private static func integer(
        _ key: String,
        in dictionary: [String: Any]
    ) -> Int? {
        (dictionary[key] as? NSNumber)?.intValue
    }

    private static func bool(
        _ key: String,
        in dictionary: [String: Any]
    ) -> Bool {
        (dictionary[key] as? NSNumber)?.boolValue ?? false
    }

    private static func numberArray(
        _ key: String,
        in dictionary: [String: Any]
    ) -> [Double] {
        if let values = dictionary[key] as? [NSNumber] {
            return values.map(\.doubleValue)
        }
        if let values = dictionary[key] as? NSArray {
            return values.compactMap { ($0 as? NSNumber)?.doubleValue }
        }
        return []
    }

    private static func dictionaryArray(_ value: Any?) -> [[String: Any]]? {
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries
        }
        if let array = value as? NSArray {
            return array.compactMap { element in
                if let dictionary = element as? [String: Any] {
                    return dictionary
                }
                return (element as? NSDictionary) as? [String: Any]
            }
        }
        return nil
    }

    private static func serviceProperty(
        _ key: String,
        service: io_registry_entry_t
    ) -> Any? {
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return nil
        }
        return value.takeRetainedValue()
    }

    private static func serviceDictionaryProperty(
        _ key: String,
        service: io_registry_entry_t
    ) -> [String: Any]? {
        let value = serviceProperty(key, service: service)
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        return (value as? NSDictionary) as? [String: Any]
    }

    private static func serviceFirstDictionaryProperty(
        _ key: String,
        service: io_registry_entry_t
    ) -> [String: Any]? {
        guard let value = serviceProperty(key, service: service) else {
            return nil
        }
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        return dictionaryArray(value)?.first
    }

    private static func serviceNumberProperty(
        _ key: String,
        service: io_registry_entry_t
    ) -> Double? {
        (serviceProperty(key, service: service) as? NSNumber)?.doubleValue
    }

    private static func serviceSignedNumberProperty(
        _ key: String,
        service: io_registry_entry_t
    ) -> Double? {
        guard let value = serviceProperty(key, service: service) as? NSNumber else {
            return nil
        }
        return Double(value.int64Value)
    }

    private static func serviceIntegerProperty(
        _ key: String,
        service: io_registry_entry_t
    ) -> Int? {
        (serviceProperty(key, service: service) as? NSNumber)?.intValue
    }

    private static func serviceBoolProperty(
        _ key: String,
        service: io_registry_entry_t
    ) -> Bool? {
        (serviceProperty(key, service: service) as? NSNumber)?.boolValue
    }
}
