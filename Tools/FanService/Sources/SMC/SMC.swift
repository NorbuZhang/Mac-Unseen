import Foundation
import IOKit

// MARK: - Errors

public enum SMCError: Error, CustomStringConvertible {
    case driverNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t)
    case notPrivileged
    case keyNotFound(String)
    case smcResult(UInt8, key: String)
    case unsupportedType(String, key: String)

    public var description: String {
        switch self {
        case .driverNotFound: return "AppleSMC service not found"
        case .openFailed(let kr): return "IOServiceOpen failed (kern_return \(kr))"
        case .callFailed(let kr): return "SMC call failed (kern_return \(kr))"
        case .notPrivileged: return "SMC write requires root privileges"
        case .keyNotFound(let key): return "SMC key not found: \(key)"
        case .smcResult(let code, let key): return "SMC returned result \(code) for key \(key)"
        case .unsupportedType(let type, let key): return "Unsupported SMC data type \(type) for key \(key)"
        }
    }
}

// MARK: - Param struct (must match the AppleSMC kernel ABI, 80 bytes)

typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    // Explicit padding so the Swift layout matches the C struct layout.
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

private enum SMCSelector {
    static let handleYPCEvent: UInt32 = 2
}

private enum SMCCommand {
    static let readKey: UInt8 = 5
    static let writeKey: UInt8 = 6
    static let getKeyFromIndex: UInt8 = 8
    static let getKeyInfo: UInt8 = 9
}

private enum SMCResult {
    static let success: UInt8 = 0
    static let keyNotFound: UInt8 = 0x84
}

// MARK: - FourCC helpers

func fourCC(_ string: String) -> UInt32 {
    var result: UInt32 = 0
    for scalar in string.utf8.prefix(4) {
        result = (result << 8) | UInt32(scalar)
    }
    return result
}

func fourCCString(_ value: UInt32) -> String {
    let bytes: [UInt8] = [
        UInt8((value >> 24) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8(value & 0xFF),
    ]
    return String(bytes: bytes, encoding: .ascii) ?? "????"
}

// MARK: - Key info

public struct SMCKeyInfo {
    public let key: String
    public let dataType: String
    public let dataSize: Int
}

// MARK: - Connection

/// A connection to the AppleSMC kernel service. Reads work as a normal user;
/// writes (fan control) require root.
public final class SMCConnection {
    private var connection: io_connect_t = 0
    private let lock = NSLock()
    private var keyInfoCache: [UInt32: SMCKeyInfoData] = [:]

    public init() throws {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.driverNotFound }
        defer { IOObjectRelease(service) }

        let kr = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard kr == kIOReturnSuccess else { throw SMCError.openFailed(kr) }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    // MARK: Raw call

    private func call(_ input: inout SMCParamStruct, keyForError: String) throws -> SMCParamStruct {
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let kr = IOConnectCallStructMethod(
            connection,
            SMCSelector.handleYPCEvent,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize)

        if kr == kIOReturnNotPrivileged { throw SMCError.notPrivileged }
        guard kr == kIOReturnSuccess else { throw SMCError.callFailed(kr) }

        switch output.result {
        case SMCResult.success:
            return output
        case SMCResult.keyNotFound:
            throw SMCError.keyNotFound(keyForError)
        default:
            throw SMCError.smcResult(output.result, key: keyForError)
        }
    }

    // MARK: Key info / enumeration

    private func rawKeyInfo(_ keyCode: UInt32, name: String) throws -> SMCKeyInfoData {
        lock.lock()
        if let cached = keyInfoCache[keyCode] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var input = SMCParamStruct()
        input.key = keyCode
        input.data8 = SMCCommand.getKeyInfo
        let output = try call(&input, keyForError: name)

        lock.lock()
        keyInfoCache[keyCode] = output.keyInfo
        lock.unlock()
        return output.keyInfo
    }

    public func keyInfo(_ key: String) throws -> SMCKeyInfo {
        let info = try rawKeyInfo(fourCC(key), name: key)
        return SMCKeyInfo(
            key: key,
            dataType: fourCCString(info.dataType),
            dataSize: Int(info.dataSize))
    }

    public func hasKey(_ key: String) -> Bool {
        (try? keyInfo(key)) != nil
    }

    public func keyCount() throws -> Int {
        Int(try readInteger("#KEY"))
    }

    public func key(atIndex index: Int) throws -> String {
        var input = SMCParamStruct()
        input.data8 = SMCCommand.getKeyFromIndex
        input.data32 = UInt32(index)
        let output = try call(&input, keyForError: "#\(index)")
        return fourCCString(output.key)
    }

    // MARK: Reading

    public func readBytes(_ key: String) throws -> (type: String, bytes: [UInt8]) {
        let keyCode = fourCC(key)
        let info = try rawKeyInfo(keyCode, name: key)

        var input = SMCParamStruct()
        input.key = keyCode
        input.keyInfo.dataSize = info.dataSize
        input.data8 = SMCCommand.readKey
        let output = try call(&input, keyForError: key)

        let size = min(Int(info.dataSize), 32)
        var bytes = [UInt8](repeating: 0, count: size)
        withUnsafeBytes(of: output.bytes) { raw in
            for i in 0..<size { bytes[i] = raw[i] }
        }
        return (fourCCString(info.dataType), bytes)
    }

    /// Reads any numeric SMC key and decodes it to a Double.
    public func readNumeric(_ key: String) throws -> Double {
        let (type, bytes) = try readBytes(key)
        guard let value = SMCConnection.decodeNumeric(type: type, bytes: bytes) else {
            throw SMCError.unsupportedType(type, key: key)
        }
        return value
    }

    public func readInteger(_ key: String) throws -> Int {
        Int(try readNumeric(key).rounded())
    }

    static func decodeNumeric(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt " where bytes.count >= 4:
            let bits = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            return Double(Float(bitPattern: bits))
        case "ui8 ", "ui16", "ui32", "ui64":
            var value: UInt64 = 0
            for byte in bytes { value = (value << 8) | UInt64(byte) }
            return Double(value)
        case "si8 ", "si16", "si32", "si64":
            var value: UInt64 = 0
            for byte in bytes { value = (value << 8) | UInt64(byte) }
            let bits = bytes.count * 8
            if bits < 64, value >= (1 << (bits - 1)) {
                return Double(Int64(value) - (1 << bits))
            }
            return Double(value)
        case "ioft" where bytes.count >= 8:
            // 48.16 fixed point, big-endian.
            var value: UInt64 = 0
            for byte in bytes.prefix(8) { value = (value << 8) | UInt64(byte) }
            return Double(value) / 65536.0
        default:
            // fpXY (unsigned) / spXY (signed) fixed-point, big-endian 16-bit.
            let chars = Array(type)
            if bytes.count >= 2, chars.count == 4, chars[0] == "f" || chars[0] == "s",
               chars[1] == "p",
               let fractionBits = Int(String(chars[3]), radix: 16) {
                let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
                let divisor = Double(1 << fractionBits)
                if chars[0] == "s" {
                    return Double(Int16(bitPattern: raw)) / divisor
                }
                return Double(raw) / divisor
            }
            return nil
        }
    }

    static func encodeNumeric(type: String, size: Int, value: Double) -> [UInt8]? {
        switch type {
        case "flt ":
            let bits = Float(value).bitPattern
            return [
                UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF),
                UInt8((bits >> 16) & 0xFF), UInt8((bits >> 24) & 0xFF),
            ]
        case "ui8 ":
            return [UInt8(max(0, min(255, value.rounded())))]
        case "ui16":
            let v = UInt16(max(0, min(65535, value.rounded())))
            return [UInt8(v >> 8), UInt8(v & 0xFF)]
        case "ui32":
            let v = UInt32(max(0, min(Double(UInt32.max), value.rounded())))
            return [
                UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF),
                UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF),
            ]
        default:
            let chars = Array(type)
            if chars.count == 4, chars[0] == "f", chars[1] == "p",
               let fractionBits = Int(String(chars[3]), radix: 16) {
                let raw = UInt16(max(0, min(65535, (value * Double(1 << fractionBits)).rounded())))
                return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
            }
            return nil
        }
    }

    // MARK: Writing

    public func writeBytes(_ key: String, bytes: [UInt8]) throws {
        let keyCode = fourCC(key)
        let info = try rawKeyInfo(keyCode, name: key)
        guard bytes.count == Int(info.dataSize) else {
            throw SMCError.unsupportedType(
                "size mismatch (\(bytes.count) vs \(info.dataSize))", key: key)
        }

        var input = SMCParamStruct()
        input.key = keyCode
        input.keyInfo.dataSize = info.dataSize
        input.data8 = SMCCommand.writeKey
        withUnsafeMutableBytes(of: &input.bytes) { raw in
            for (i, byte) in bytes.enumerated() where i < 32 { raw[i] = byte }
        }
        _ = try call(&input, keyForError: key)
    }

    public func writeNumeric(_ key: String, value: Double) throws {
        let keyCode = fourCC(key)
        let info = try rawKeyInfo(keyCode, name: key)
        let type = fourCCString(info.dataType)
        guard let bytes = SMCConnection.encodeNumeric(
            type: type, size: Int(info.dataSize), value: value) else {
            throw SMCError.unsupportedType(type, key: key)
        }
        try writeBytes(key, bytes: bytes)
    }
}
