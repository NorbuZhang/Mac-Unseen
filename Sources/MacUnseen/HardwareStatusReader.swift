// SPDX-License-Identifier: MPL-2.0

import Darwin
import CoreWLAN
import Foundation
import IOKit

enum HardwareStatusReader {
    static func readStorage(
        includeDeviceMetadata: Bool = true
    ) -> StorageSnapshot {
        let profiler = includeDeviceMetadata
            ? profilerJSON(types: ["SPNVMeDataType"])
            : [:]
        return storageSnapshot(profiler: profiler)
    }

    static func readNetwork(
        preserving previous: NetworkSnapshot = NetworkSnapshot(),
        includePorts: Bool = true
    ) -> NetworkSnapshot {
        let profiler = includePorts
            ? profilerJSON(
                types: ["SPUSBHostDataType", "SPThunderboltDataType"]
            )
            : [:]
        return networkSnapshot(
            profiler: profiler,
            preserving: previous,
            includePorts: includePorts
        )
    }

    private static func storageSnapshot(
        profiler: [String: Any]
    ) -> StorageSnapshot {
        let trimByModel = nvmeTrimValues(in: profiler)
        var disks: [DiskSnapshot] = []

        guard let matching = IOServiceMatching("IOBlockStorageDevice") else {
            return StorageSnapshot(disks: disks, updatedAt: Date())
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matching,
            &iterator
        ) == KERN_SUCCESS else {
            return StorageSnapshot(disks: disks, updatedAt: Date())
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator),
              service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            guard let properties = registryProperties(service) else {
                continue
            }
            let device = dictionary("Device Characteristics", in: properties)
            let protocolInfo = dictionary("Protocol Characteristics", in: properties)
            let name = string("Product Name", in: device) ?? "存储设备"
            let medium = string("Medium Type", in: device) ?? ""
            let firmware = string("Product Revision Level", in: device) ?? ""

            let driver = firstChild(of: service, conformingTo: "IOBlockStorageDriver")
            let driverProperties = driver.flatMap(registryProperties)
            let statistics = driverProperties.flatMap {
                dictionary("Statistics", in: $0)
            }
            let media = driver.flatMap {
                firstDescendant(of: $0, conformingTo: "IOMedia") { entry in
                    bool("Whole", in: entry)
                }
            }
            let mediaProperties = media.flatMap(registryProperties)
            guard media != nil else {
                if driver != nil {
                    IOObjectRelease(driver!)
                }
                continue
            }

            var disk = DiskSnapshot()
            disk.id = string("BSD Name", in: mediaProperties) ?? name
            disk.name = name
            disk.bsdName = string("BSD Name", in: mediaProperties) ?? ""
            disk.connection = string(
                "Physical Interconnect",
                in: protocolInfo
            ) ?? "未知"
            disk.location = string(
                "Physical Interconnect Location",
                in: protocolInfo
            ) ?? "未知"
            if disk.connection.localizedCaseInsensitiveContains("virtual")
                || disk.location.localizedCaseInsensitiveContains("file") {
                if driver != nil {
                    IOObjectRelease(driver!)
                }
                if media != nil {
                    IOObjectRelease(media!)
                }
                continue
            }
            disk.firmware = firmware
            disk.capacity = number("Size", in: mediaProperties)
            disk.solidState = medium.localizedCaseInsensitiveContains("solid")
                || disk.connection.localizedCaseInsensitiveContains("nvme")
                || disk.connection.localizedCaseInsensitiveContains("fabric")
            disk.removable = bool("Removable", in: mediaProperties)
            disk.smartCapable = bool("NVMe SMART Capable", in: properties)
            disk.trimEnabled = trimByModel[name]
            disk.encrypted = bool("Encryption", in: properties)
            disk.thermalThrottlingSupported = bool(
                "ThermalThrottlingSupported",
                in: properties
            )
            disk.bytesRead = number("Bytes (Read)", in: statistics)
            disk.bytesWritten = number("Bytes (Write)", in: statistics)
            disk.readOperations = integer("Operations (Read)", in: statistics)
            disk.writeOperations = integer("Operations (Write)", in: statistics)
            disk.readErrors = integer("Errors (Read)", in: statistics)
            disk.writeErrors = integer("Errors (Write)", in: statistics)

            if driver != nil {
                IOObjectRelease(driver!)
            }
            if media != nil {
                IOObjectRelease(media!)
            }
            disks.append(disk)
        }

        disks.sort {
            if $0.isInternal != $1.isInternal {
                return $0.isInternal
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return StorageSnapshot(disks: disks, updatedAt: Date())
    }

    private static func networkSnapshot(
        profiler: [String: Any],
        preserving previous: NetworkSnapshot,
        includePorts: Bool
    ) -> NetworkSnapshot {
        guard includePorts else {
            return NetworkSnapshot(
                interfaces: networkInterfaces(),
                wifi: wifiSnapshot(),
                ports: previous.ports,
                peripherals: previous.peripherals,
                vpnInterfaceCount: vpnCount(),
                updatedAt: Date()
            )
        }
        let usbConnections = connectedUSBDevices(in: profiler)
        return NetworkSnapshot(
            interfaces: networkInterfaces(),
            wifi: wifiSnapshot(),
            ports: mergedPorts(
                thunderboltPorts(in: profiler),
                usbConnections: usbConnections
            ),
            peripherals: peripherals(in: profiler),
            vpnInterfaceCount: vpnCount(),
            updatedAt: Date()
        )
    }

    private static func networkInterfaces() -> [NetworkInterfaceSnapshot] {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0,
              let firstAddress = addressPointer else {
            return []
        }
        defer { freeifaddrs(addressPointer) }

        var values: [String: NetworkInterfaceSnapshot] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let current = pointer {
            let entry = current.pointee
            pointer = entry.ifa_next
            let name = String(cString: entry.ifa_name)
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0,
                  flags & IFF_RUNNING != 0,
                  name != "lo0",
                  !name.hasPrefix("utun"),
                  !name.hasPrefix("awdl"),
                  !name.hasPrefix("llw"),
                  !name.hasPrefix("ap"),
                  !name.hasPrefix("anpi"),
                  let address = entry.ifa_addr else {
                continue
            }

            let family = Int32(address.pointee.sa_family)
            var value = values[name] ?? NetworkInterfaceSnapshot(
                name: name,
                displayName: interfaceDisplayName(name)
            )
            if family == AF_INET || family == AF_INET6,
               let host = numericHost(address) {
                if family == AF_INET {
                    if !value.ipv4.contains(host) {
                        value.ipv4.append(host)
                    }
                } else if !host.hasPrefix("fe80:"),
                          !value.ipv6.contains(host) {
                    value.ipv6.append(host)
                }
            } else if family == AF_LINK, let data = entry.ifa_data {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                value.receivedBytes = Double(stats.ifi_ibytes)
                value.sentBytes = Double(stats.ifi_obytes)
            }
            values[name] = value
        }

        return values.values
            .filter { !$0.ipv4.isEmpty || !$0.ipv6.isEmpty }
            .sorted { lhs, rhs in
                interfacePriority(lhs.name) < interfacePriority(rhs.name)
            }
    }

    private static func numericHost(_ address: UnsafePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(
            address,
            socklen_t(address.pointee.sa_len),
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        ) == 0 else {
            return nil
        }
        let bytes = host.prefix { $0 != 0 }.map {
            UInt8(bitPattern: $0)
        }
        return String(decoding: bytes, as: UTF8.self)
            .components(separatedBy: "%").first
    }

    private static func wifiSnapshot() -> WiFiSnapshot {
        var snapshot = WiFiSnapshot()
        guard let interface = CWWiFiClient.shared().interface() else {
            return snapshot
        }
        snapshot.interfaceName = interface.interfaceName ?? ""
        let channel = interface.wlanChannel()
        let signal = interface.rssiValue()
        let noise = interface.noiseMeasurement()
        snapshot.connected = interface.powerOn() && channel != nil && signal != 0
        snapshot.networkName = interface.ssid() ?? ""
        snapshot.protocolName = phyModeName(interface.activePHYMode().rawValue)
        if let channel {
            snapshot.channel = "\(channel.channelNumber) · "
                + bandName(channel.channelBand.rawValue)
        }
        let rate = interface.transmitRate()
        snapshot.transmitRate = rate > 0 ? String(format: "%.0f", rate) : ""
        if signal != 0 || noise != 0 {
            snapshot.signalNoise = "\(signal) / \(noise) dBm"
        }
        snapshot.security = securityName(interface.security().rawValue)
        return snapshot
    }

    private struct USBPortConnection {
        let portID: String?
        let location: String
        let deviceName: String
        let protocolName: String
        let speed: String
    }

    private static func connectedUSBDevices(
        in root: [String: Any]
    ) -> [USBPortConnection] {
        guard let buses = root["SPUSBHostDataType"] as? [[String: Any]] else {
            return []
        }
        var connections: [USBPortConnection] = []
        for bus in buses {
            guard let items = bus["_items"] as? [[String: Any]] else {
                continue
            }
            for item in items {
                let name = item["_name"] as? String ?? "USB 设备"
                let speed = item["USBDeviceKeyLinkSpeed"] as? String ?? ""
                let location = item["USBKeyLocationID"] as? String ?? ""
                connections.append(
                    USBPortConnection(
                        portID: usbRootPortID(from: location),
                        location: location,
                        deviceName: name,
                        protocolName: usbProtocol(for: speed),
                        speed: speed
                    )
                )
            }
        }
        return connections
    }

    private static func mergedPorts(
        _ thunderboltPorts: [PortSnapshot],
        usbConnections: [USBPortConnection]
    ) -> [PortSnapshot] {
        var ports = thunderboltPorts
        var unmatched: [USBPortConnection] = []

        for connection in usbConnections {
            guard let portID = connection.portID,
                  let index = ports.firstIndex(where: {
                      $0.id == "tb-\(portID)"
                  }) else {
                unmatched.append(connection)
                continue
            }
            ports[index].connected = true
            ports[index].protocolName = connection.protocolName
            ports[index].speed = connection.speed
            ports[index].deviceName = connection.deviceName
        }

        for connection in unmatched {
            var port = PortSnapshot()
            port.id = "usb-port-\(connection.location)-\(connection.deviceName)"
            port.name = "USB-C / 雷雳接口"
            port.connected = true
            port.protocolName = connection.protocolName
            port.speed = connection.speed
            port.deviceName = connection.deviceName
            ports.append(port)
        }
        return ports.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func usbRootPortID(from location: String) -> String? {
        let normalized = location
            .lowercased()
            .replacingOccurrences(of: "0x", with: "")
        guard let value = UInt32(normalized, radix: 16) else {
            return nil
        }
        let rootPort = (value >> 20) & 0xF
        return rootPort == 0 ? nil : String(rootPort)
    }

    private static func thunderboltPorts(
        in root: [String: Any]
    ) -> [PortSnapshot] {
        guard let buses = root["SPThunderboltDataType"] as? [[String: Any]] else {
            return []
        }
        var ports: [PortSnapshot] = []
        for bus in buses {
            for (key, value) in bus where key.hasPrefix("receptacle_") {
                guard let receptacle = value as? [String: Any] else {
                    continue
                }
                let portID = stringValue(receptacle["receptacle_id_key"])
                let status = receptacle["receptacle_status_key"] as? String ?? ""
                let connected = !status.contains("no_devices")
                var port = PortSnapshot()
                port.id = "tb-\(portID.isEmpty ? key : portID)"
                port.name = portID.isEmpty ? "USB-C / 雷雳接口" : "USB-C / 雷雳接口 \(portID)"
                port.connected = connected
                port.protocolName = "Thunderbolt / USB4"
                port.speed = receptacle["current_speed_key"] as? String ?? ""
                port.deviceName = connected
                    ? connectedThunderboltDeviceName(in: bus)
                    : ""
                ports.append(port)
            }
        }
        return ports.sorted { $0.name < $1.name }
    }

    private static func connectedThunderboltDeviceName(
        in dictionary: [String: Any]
    ) -> String {
        guard let items = dictionary["_items"] as? [[String: Any]],
              let first = items.first else {
            return ""
        }
        return first["_name"] as? String
            ?? first["device_name_key"] as? String
            ?? ""
    }

    private static func peripherals(
        in root: [String: Any]
    ) -> [PeripheralSnapshot] {
        var result: [PeripheralSnapshot] = []
        if let usb = root["SPUSBHostDataType"] {
            collectUSBDevices(in: usb, result: &result)
        }
        if let buses = root["SPThunderboltDataType"] as? [[String: Any]] {
            for bus in buses {
                collectThunderboltDevices(in: bus["_items"], result: &result)
            }
        }
        return result
    }

    private static func collectUSBDevices(
        in value: Any,
        result: inout [PeripheralSnapshot]
    ) {
        if let array = value as? [Any] {
            for child in array {
                collectUSBDevices(in: child, result: &result)
            }
            return
        }
        guard let dictionary = value as? [String: Any] else {
            return
        }
        let speed = dictionary["USBDeviceKeyLinkSpeed"] as? String
            ?? dictionary["device_speed"] as? String
            ?? dictionary["speed"] as? String
            ?? ""
        let isDevice = dictionary["USBDeviceKeyProductID"] != nil
            || dictionary["USBDeviceKeyVendorID"] != nil
            || dictionary["product_id"] != nil
            || dictionary["vendor_id"] != nil
            || !speed.isEmpty
        if isDevice, let name = dictionary["_name"] as? String {
            var device = PeripheralSnapshot()
            device.id = "usb-\(stringValue(dictionary["USBKeyLocationID"]))-\(name)"
            device.name = name
            device.protocolName = usbProtocol(for: speed)
            device.speed = speed
            device.vendor = dictionary["USBDeviceKeyVendorName"] as? String
                ?? dictionary["manufacturer"] as? String
                ?? ""
            device.power = dictionary["USBDeviceKeyPowerAllocation"] as? String
                ?? ""
            result.append(device)
        }
        for child in dictionary.values {
            collectUSBDevices(in: child, result: &result)
        }
    }

    private static func collectThunderboltDevices(
        in value: Any?,
        result: inout [PeripheralSnapshot]
    ) {
        guard let value else {
            return
        }
        if let array = value as? [Any] {
            for child in array {
                collectThunderboltDevices(in: child, result: &result)
            }
            return
        }
        guard let dictionary = value as? [String: Any] else {
            return
        }
        if let name = dictionary["_name"] as? String
            ?? dictionary["device_name_key"] as? String {
            var device = PeripheralSnapshot()
            device.id = "tb-\(stringValue(dictionary["route_string_key"]))-\(name)"
            device.name = name
            device.protocolName = "Thunderbolt / USB4"
            device.speed = dictionary["current_speed_key"] as? String
                ?? dictionary["link_speed_key"] as? String
                ?? ""
            device.vendor = dictionary["vendor_name_key"] as? String ?? ""
            result.append(device)
        }
        collectThunderboltDevices(in: dictionary["_items"], result: &result)
    }

    private static func nvmeTrimValues(
        in root: [String: Any]
    ) -> [String: Bool] {
        guard let controllers = root["SPNVMeDataType"] as? [[String: Any]] else {
            return [:]
        }
        var values: [String: Bool] = [:]
        for controller in controllers {
            guard let items = controller["_items"] as? [[String: Any]] else {
                continue
            }
            for item in items {
                let name = item["device_model"] as? String
                    ?? item["_name"] as? String
                    ?? ""
                let trim = item["spnvme_trim_support"] as? String
                if !name.isEmpty, let trim {
                    values[name] = trim.localizedCaseInsensitiveCompare("yes")
                        == .orderedSame
                }
            }
        }
        return values
    }

    private static func profilerJSON(types: [String]) -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = types + ["-json", "-detailLevel", "mini"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (try? JSONSerialization.jsonObject(with: data))
                as? [String: Any] ?? [:]
        } catch {
            return [:]
        }
    }

    private static func registryProperties(
        _ service: io_registry_entry_t
    ) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service,
            &unmanaged,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS else {
            return nil
        }
        return unmanaged?.takeRetainedValue() as? [String: Any]
    }

    private static func firstChild(
        of service: io_registry_entry_t,
        conformingTo className: String
    ) -> io_registry_entry_t? {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(
            service,
            kIOServicePlane,
            &iterator
        ) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        while case let child = IOIteratorNext(iterator),
              child != IO_OBJECT_NULL {
            if IOObjectConformsTo(child, className) != 0 {
                return child
            }
            IOObjectRelease(child)
        }
        return nil
    }

    private static func firstDescendant(
        of service: io_registry_entry_t,
        conformingTo className: String,
        where predicate: ([String: Any]) -> Bool
    ) -> io_registry_entry_t? {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(
            service,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        ) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        while case let child = IOIteratorNext(iterator),
              child != IO_OBJECT_NULL {
            if IOObjectConformsTo(child, className) != 0,
               let properties = registryProperties(child),
               predicate(properties) {
                return child
            }
            IOObjectRelease(child)
        }
        return nil
    }

    private static func dictionary(
        _ key: String,
        in dictionary: [String: Any]?
    ) -> [String: Any]? {
        dictionary?[key] as? [String: Any]
    }

    private static func string(
        _ key: String,
        in dictionary: [String: Any]?
    ) -> String? {
        dictionary?[key] as? String
    }

    private static func number(
        _ key: String,
        in dictionary: [String: Any]?
    ) -> Double {
        (dictionary?[key] as? NSNumber)?.doubleValue ?? 0
    }

    private static func integer(
        _ key: String,
        in dictionary: [String: Any]?
    ) -> UInt64 {
        (dictionary?[key] as? NSNumber)?.uint64Value ?? 0
    }

    private static func bool(
        _ key: String,
        in dictionary: [String: Any]?
    ) -> Bool {
        (dictionary?[key] as? NSNumber)?.boolValue ?? false
    }

    private static func stringValue(_ value: Any?) -> String {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return ""
    }

    private static func interfaceDisplayName(_ name: String) -> String {
        if name.hasPrefix("en") {
            return "物理网络接口"
        }
        if name.hasPrefix("bridge") {
            return "网络桥接"
        }
        return "网络接口"
    }

    private static func interfacePriority(_ name: String) -> Int {
        if name == "en0" {
            return 0
        }
        if name.hasPrefix("en") {
            return 1
        }
        return 2
    }

    private static func vpnCount() -> Int {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0,
              let firstAddress = addressPointer else {
            return 0
        }
        defer { freeifaddrs(addressPointer) }
        var names = Set<String>()
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let current = pointer {
            let entry = current.pointee
            pointer = entry.ifa_next
            let name = String(cString: entry.ifa_name)
            let flags = Int32(entry.ifa_flags)
            if name.hasPrefix("utun"),
               flags & IFF_UP != 0,
               flags & IFF_RUNNING != 0 {
                names.insert(name)
            }
        }
        return names.count
    }

    private static func usbProtocol(for speed: String) -> String {
        let value = speed.lowercased()
        if value.contains("40 gb") || value.contains("20 gb") {
            return "USB4"
        }
        if value.contains("10 gb") {
            return "USB 3.2"
        }
        if value.contains("5 gb") {
            return "USB 3.x"
        }
        if value.contains("480 mb") {
            return "USB 2.0"
        }
        if value.contains("12 mb") || value.contains("1.5 mb") {
            return "USB"
        }
        return "USB"
    }

    private static func phyModeName(_ rawValue: Int) -> String {
        switch rawValue {
        case 1: "802.11a"
        case 2: "802.11b"
        case 3: "802.11g"
        case 4: "802.11n"
        case 5: "802.11ac"
        case 6: "802.11ax"
        case 7: "802.11be"
        default: ""
        }
    }

    private static func bandName(_ rawValue: Int) -> String {
        switch rawValue {
        case 1: "2.4 GHz"
        case 2: "5 GHz"
        case 3: "6 GHz"
        default: "未知频段"
        }
    }

    private static func securityName(_ rawValue: Int) -> String {
        switch rawValue {
        case 0: "开放网络"
        case 1: "WEP"
        case 2, 3: "WPA 个人"
        case 4: "WPA2 个人"
        case 5: "WPA/WPA2 个人"
        case 6: "动态 WEP"
        case 7, 8: "WPA 企业"
        case 9: "WPA2 企业"
        case 10: "WPA/WPA2 企业"
        case 11: "WPA3 个人"
        case 12: "WPA3 企业"
        case 13: "WPA2/WPA3 过渡"
        case 14, 15: "增强开放网络"
        default: ""
        }
    }
}
