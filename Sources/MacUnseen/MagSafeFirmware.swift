import Foundation

struct MagSafeFirmwareRequest: Equatable, Sendable {
    let connectionID: String
    let rid: Int
    let address: Int
    let vendorID: Int
    let productID: Int
}

struct MagSafeCableFirmware: Equatable, Sendable {
    let bcdDevice: UInt16

    var rawVersion: String { String(format: "0x%04X", bcdDevice) }

    /// These Apple cable mappings have been independently observed. Do not apply
    /// Apple's dotted-version convention to unknown revisions or other vendors.
    var knownVersion: String? {
        switch bcdDevice {
        case 0x3112: "3.1.12"
        case 0x3200: "3.2.0"
        default: nil
        }
    }

    var displayVersion: String { knownVersion ?? rawVersion }
}

enum MagSafeFirmwareParser {
    /// hpmdiagnose register 0x49 holds the SOP' cable identity response.
    /// Match the built-in HPM controller as well as the cable VID/PID: the same
    /// diagnostic also includes USB-C cables, adapters and disconnected ports.
    static func parse(_ text: String, for request: MagSafeFirmwareRequest) -> MagSafeCableFirmware? {
        guard let header = try? NSRegularExpression(
            pattern: #"^HPM at RID 0x([0-9a-f]+) Route 0x([0-9a-f]+) Address 0x([0-9a-f]+)\s*:$"#,
            options: .caseInsensitive
        ) else { return nil }
        var matchesController = false
        var results: [MagSafeCableFirmware] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("HPM at") {
                matchesController = false
                let range = NSRange(line.startIndex..., in: line)
                if let match = header.firstMatch(in: line, range: range) {
                    let values = (1...3).compactMap { index -> Int? in
                        guard let range = Range(match.range(at: index), in: line) else { return nil }
                        return Int(line[range], radix: 16)
                    }
                    matchesController = values == [request.rid, 0, request.address]
                }
                continue
            }
            guard matchesController else { continue }
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 3, fields[0].lowercased() == "0x49",
                  fields[1].hasPrefix("0x"), fields[2].hasPrefix("0x"),
                  let length = Int(fields[1].dropFirst(2), radix: 16),
                  (13...64).contains(length) else { continue }
            let hex = Array(fields[2].dropFirst(2))
            guard hex.count == length * 2 else { continue }
            let bytes = stride(from: 0, to: hex.count, by: 2).compactMap {
                UInt8(String(hex[$0...($0 + 1)]), radix: 16)
            }
            guard bytes.count == length, bytes[0] != 0 else { continue }
            let vendor = Int(bytes[1]) | Int(bytes[2]) << 8
            let product = Int(bytes[11]) | Int(bytes[12]) << 8
            let version = UInt16(bytes[9]) | UInt16(bytes[10]) << 8
            guard vendor == request.vendorID, product == request.productID,
                  version != 0, version != .max else { continue }
            results.append(MagSafeCableFirmware(bcdDevice: version))
        }
        // Ambiguous/changed diagnostic output should produce no version, not a guess.
        return results.count == 1 ? results[0] : nil
    }
}

/// Runs off the main actor, without a shell, privilege prompt or persistent log.
/// The page owner cancels on backgrounding/leaving; the hard timeout bounds failure.
final class MagSafeFirmwareJob: @unchecked Sendable {
    private let command = SystemCommand()
    func cancel() { command.cancel() }

    func run(for request: MagSafeFirmwareRequest) -> MagSafeCableFirmware? {
        guard let data = command.run(executable: "/usr/bin/hpmdiagnose", arguments: [], timeout: 4),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return MagSafeFirmwareParser.parse(text, for: request)
    }
}
