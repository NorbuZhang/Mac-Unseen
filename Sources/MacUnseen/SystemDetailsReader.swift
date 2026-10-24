import AppKit
import Darwin
import Foundation

struct MemoryModuleDetails: Equatable, Sendable, Identifiable {
    var id: Int
    var name: String?
    var capacity: String?
    var type: String?
    var manufacturer: String?
    var speed: String?
}

struct GPUDetails: Equatable, Sendable, Identifiable {
    var id: Int
    var name: String
    var cores: Int?
    var metal: String?
    var vram: String?
    var unifiedMemory: Bool?
}

struct SystemDetails: Equatable, Sendable {
    var modelName: String?
    var modelNumber: String?
    var firmware: String?
    var bootLoader: String?
    var memory: [MemoryModuleDetails] = []
    var gpus: [GPUDetails] = []
    var disks: [DiskSnapshot] = []
    var volumeName: String?
    var fileSystem: String?
    var profilerAvailable = false
    var sampledAt: Date?
}

enum SystemDetailsReader {
    /// This snapshot is read on first visit or manual refresh, never by the live sampler.
    static func read(using command: SystemCommand = SystemCommand()) -> SystemDetails {
        var details = profilerData(using: command).flatMap(parse) ?? SystemDetails()
        // Memory, GPU and disk details now belong to their hardware pages.
        // Do not query them (or initialize Metal) for this system summary.
        details.sampledAt = Date()
        return details
    }

    /// Select only hardware fields. Serial numbers and device UUIDs are not retained.
    static func parse(_ data: Data) -> SystemDetails? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var result = SystemDetails()
        let hardware = (root["SPHardwareDataType"] as? [[String: Any]])?.first
        result.profilerAvailable = hardware != nil
        result.modelName = text(hardware?["machine_name"])
        result.modelNumber = text(hardware?["model_number"])
        result.firmware = text(hardware?["boot_rom_version"])
        result.bootLoader = text(hardware?["os_loader_version"])
        for bank in root["SPMemoryDataType"] as? [[String: Any]] ?? [] {
            // Apple Silicon reports one unified bank; Intel reports individual DIMMs.
            let modules = bank["_items"] as? [[String: Any]] ?? [bank]
            for module in modules {
                let capacity = text(module["dimm_size"]) ?? text(module["SPMemoryDataType"])
                let type = text(module["dimm_type"])
                let manufacturer = text(module["dimm_manufacturer"])
                let speed = text(module["dimm_speed"])
                guard capacity != nil || type != nil || manufacturer != nil || speed != nil else { continue }
                result.memory.append(MemoryModuleDetails(id: result.memory.count,
                    name: text(module["_name"]), capacity: capacity, type: type,
                    manufacturer: manufacturer, speed: speed))
            }
        }
        for gpu in root["SPDisplaysDataType"] as? [[String: Any]] ?? [] {
            guard let name = text(gpu["sppci_model"]) ?? text(gpu["_name"]) else { continue }
            let metalValue = text(gpu["spdisplays_mtlgpufamilysupport"])
            let metal = ["spdisplays_metal3": "Metal 3", "spdisplays_metal4": "Metal 4"][metalValue ?? ""]
            result.gpus.append(GPUDetails(id: result.gpus.count, name: name,
                cores: text(gpu["sppci_cores"]).flatMap(Int.init), metal: metal,
                vram: text(gpu["spdisplays_vram"]) ?? text(gpu["spdisplays_vram_shared"])))
        }
        return result
    }

    private static func text(_ value: Any?) -> String? {
        let string = (value as? String) ?? (value as? NSNumber)?.stringValue
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }
        return string
    }

    private static func profilerData(using command: SystemCommand) -> Data? {
        command.run(executable: "/usr/sbin/system_profiler",
                    arguments: ["SPHardwareDataType", "-json", "-timeout", "8"], timeout: 10)
    }
}

struct DisplayDetails: Equatable, Sendable, Identifiable {
    var id: UInt32
    var name: String
    var pixelWidth: Int?
    var pixelHeight: Int?
    var logicalWidth: Int
    var logicalHeight: Int
    var scale: Double
    var refreshHz: Double?
    var builtIn: Bool
    var main: Bool
}

enum DisplayDetailsReader {
    @MainActor static func read() -> [DisplayDetails] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = number.uint32Value
            let mode = CGDisplayCopyDisplayMode(id)
            let rate = mode?.refreshRate ?? 0
            return DisplayDetails(id: id, name: screen.localizedName,
                pixelWidth: mode?.pixelWidth, pixelHeight: mode?.pixelHeight,
                logicalWidth: Int(screen.frame.width), logicalHeight: Int(screen.frame.height),
                scale: screen.backingScaleFactor, refreshHz: rate > 0 ? rate : nil,
                builtIn: CGDisplayIsBuiltin(id) != 0, main: CGDisplayIsMain(id) != 0)
        }
    }
}
