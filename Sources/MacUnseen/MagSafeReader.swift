import Foundation
import IOKit

struct MagSafeSnapshot: Equatable, Sendable {
    var connectionID: String
    var connector: String
    var controllerFirmware: String?
    var cableVendorID: Int?
    var cableProductID: Int?
    var controllerRID: Int?
    var controllerAddress: Int?
    var cableFirmware: MagSafeCableFirmware?

    var firmwareRequest: MagSafeFirmwareRequest? {
        guard cableVendorID == 0x05AC, cableProductID == 0x7800,
              let controllerRID, let controllerAddress else { return nil }
        return MagSafeFirmwareRequest(connectionID: connectionID, rid: controllerRID,
                                      address: controllerAddress, vendorID: 0x05AC, productID: 0x7800)
    }
}

enum MagSafeReader {
    /// Poll only the small connection properties. Re-read identity on reconnect or manual/slow refresh.
    static func read(preserving previous: MagSafeSnapshot?, refreshMetadata: Bool) -> MagSafeSnapshot? {
        guard let matching = IOServiceMatching("IOPort") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let port = IOIteratorNext(iterator), port != IO_OBJECT_NULL {
            defer { IOObjectRelease(port) }
            guard let name = property("PortTypeDescription", on: port) as? String,
                  name.localizedCaseInsensitiveContains("MagSafe"),
                  (property("ConnectionActive", on: port) as? NSNumber)?.boolValue == true else { continue }
            let connectionID = property("ConnectionUUID", on: port) as? String ?? name
            if !refreshMetadata, let previous, previous.connectionID == connectionID { return previous }
            var transport: [String: Any] = [:]
            var children: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(port, kIOServicePlane, &children) == KERN_SUCCESS {
                defer { IOObjectRelease(children) }
                while case let child = IOIteratorNext(children), child != IO_OBJECT_NULL {
                    defer { IOObjectRelease(child) }
                    if IOObjectConformsTo(child, "IOPortTransportStateCC") != 0 {
                        transport = properties(child)
                        break
                    }
                }
            }
            var controller: [String: Any] = [:]
            var parent: io_registry_entry_t = 0
            if IORegistryEntryGetParentEntry(port, kIOServicePlane, &parent) == KERN_SUCCESS {
                controller = properties(parent)
                IOObjectRelease(parent)
            }
            var result = snapshot(port: properties(port), transport: transport, controller: controller)
            // A metadata refresh must not erase the independently sampled cable firmware.
            // A new connection must never inherit the previous cable's version.
            if let previous, result?.firmwareRequest == previous.firmwareRequest,
               result?.connectionID == previous.connectionID {
                result?.cableFirmware = previous.cableFirmware
            }
            return result
        }
        return nil
    }

    static func snapshot(port: [String: Any], transport: [String: Any], controller: [String: Any] = [:]) -> MagSafeSnapshot? {
        guard let description = port["PortTypeDescription"] as? String,
              description.localizedCaseInsensitiveContains("MagSafe"),
              (port["ConnectionActive"] as? NSNumber)?.boolValue == true else { return nil }
        return MagSafeSnapshot(
            connectionID: port["ConnectionUUID"] as? String ?? description,
            connector: description.trimmingCharacters(in: .whitespacesAndNewlines),
            controllerFirmware: firmwareText(port["FW Version"]),
            cableVendorID: identifier(transport["Vendor ID (SOP1)"]),
            cableProductID: identifier(transport["Product ID (SOP1)"]),
            controllerRID: identifier(controller["RID"]),
            controllerAddress: identifier(controller["Address"])
        )
    }

    /// Preserve registry bytes; no undocumented version-number decoding or cable-firmware fallback.
    static func firmwareText(_ value: Any?) -> String? {
        if let data = value as? Data, !data.isEmpty {
            return data.map { String(format: "%02X", $0) }.joined(separator: " ")
        }
        if let string = value as? String {
            let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func identifier(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              (0...65535).contains(number.intValue) else { return nil }
        return number.intValue
    }

    private static func property(_ key: String, on service: io_registry_entry_t) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func properties(_ service: io_registry_entry_t) -> [String: Any] {
        var result: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &result, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return [:] }
        return result?.takeRetainedValue() as? [String: Any] ?? [:]
    }
}
