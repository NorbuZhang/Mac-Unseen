import Foundation

struct ProcessApplication: Equatable, Sendable {
    let bundlePath: String
    let name: String

    static func bundlePath(for executable: String) -> String? {
        guard executable.hasPrefix("/") else { return nil }
        let parts = (executable as NSString).standardizingPath.components(separatedBy: "/")
        guard let index = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        // Use the outer application, not its nested Helper.app bundles.
        return parts[...index].joined(separator: "/")
    }

    static func inheritingOwners(_ rows: [ProcessReading]) -> [ProcessReading] {
        let byPID = Dictionary(rows.map { ($0.id.pid, $0) }, uniquingKeysWith: { first, _ in first })
        return rows.map { original in
            var row = original
            guard row.application == nil else { return row }
            var current = row
            var visited: Set<Int32> = [row.id.pid]
            for _ in 0..<32 {
                guard current.parentPID > 1, let parent = byPID[current.parentPID],
                      parent.uid == row.uid, visited.insert(parent.id.pid).inserted,
                      (parent.id.startSeconds < current.id.startSeconds ||
                       (parent.id.startSeconds == current.id.startSeconds && parent.id.startMicroseconds <= current.id.startMicroseconds)) else { break }
                if let app = parent.application { row.application = app; break }
                current = parent
            }
            return row
        }
    }
}

struct ApplicationProcessGroup: Identifiable {
    let id: String
    let name: String
    let processes: [ProcessReading]
    var cpu: Double? { sum(\.cpu) }
    var memory: Double? { sum(\.memory) }
    var partialCPU: Bool { processes.contains { $0.cpu == nil } }
    var partialMemory: Bool { processes.contains { $0.memory == nil } }
    var usesResidentFallback: Bool { processes.contains { $0.memory != nil && !$0.usesFootprint } }
    private func sum(_ field: KeyPath<ProcessReading, Double?>) -> Double? {
        let values = processes.compactMap { $0[keyPath: field] }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    func matches(_ query: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query) || processes.contains {
            $0.name.localizedCaseInsensitiveContains(query) || String($0.id.pid).contains(query)
        }
    }
    static func group(_ rows: [ProcessReading]) -> [Self] {
        let buckets = Dictionary(grouping: rows) { row -> String in
            let owner = row.application.map { "app:" + $0.bundlePath }
                ?? row.executablePath.map { "executable:" + $0 }
                ?? "pid:\(row.id.pid):\(row.id.startSeconds):\(row.id.startMicroseconds)"
            return "\(row.uid):" + owner
        }
        return buckets.map { key, members in
            let members = members.sorted { $0.id.pid < $1.id.pid }
            return Self(id: key, name: members[0].application?.name ?? members[0].name, processes: members)
        }
    }
}

extension ProcessSort {
    func precedes(_ lhs: ApplicationProcessGroup, _ rhs: ApplicationProcessGroup) -> Bool {
        let comparison: ComparisonResult
        switch column {
        case .name: comparison = lhs.name.localizedStandardCompare(rhs.name)
        case .pid:
            comparison = lhs.processes.count == rhs.processes.count ? .orderedSame :
                lhs.processes.count < rhs.processes.count ? .orderedAscending : .orderedDescending
        case .cpu, .memory:
            let a = column == .cpu ? lhs.cpu : lhs.memory
            let b = column == .cpu ? rhs.cpu : rhs.memory
            if a == nil && b != nil { return false }
            if a != nil && b == nil { return true }
            comparison = a == b ? .orderedSame : (a ?? 0) < (b ?? 0) ? .orderedAscending : .orderedDescending
        }
        if comparison == .orderedSame { return lhs.id < rhs.id }
        return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
    }
}
