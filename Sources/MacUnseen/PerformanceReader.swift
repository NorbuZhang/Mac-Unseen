import Darwin
import Foundation
import IOKit
import SystemMonitorBridge

/// Serialized, off the UI actor. Each page session owns a reader so returning
/// from another page, sleep or background never reuses an old rate baseline.
actor PerformanceReader {
    private var previousCPU: [CPUCounters]?
    private var previousDisk: [String: ByteCounters]?
    private var previousNetwork: [String: ByteCounters]?
    private var previousTime: TimeInterval?
    private var previousProcesses: [ProcessIdentity: UInt64] = [:]
    private var previousProcessTime: TimeInterval?
    private var appMetadata: [String: ProcessApplication] = [:]

    func sample() -> PerformanceReading {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = previousTime.map { now - $0 } ?? 0
        let counters = Self.cpuCounters()
        var value = PerformanceReading()
        if let counters, let old = previousCPU, old.count == counters.count,
           elapsed > 0, elapsed <= 10 {
            value.cores = zip(counters, old).map { $0.usage(since: $1) }
            func total(_ values: [CPUCounters]) -> CPUCounters {
                values.reduce(CPUCounters(user: 0, system: 0, idle: 0, nice: 0)) {
                    CPUCounters(user: $0.user + $1.user, system: $0.system + $1.system,
                                idle: $0.idle + $1.idle, nice: $0.nice + $1.nice)
                }
            }
            value.cpu = total(counters).usage(since: total(old))
        }
        value.memory = Self.memory()
        value.gpus = Self.gpus()
        let disk = Self.diskCounters()
        let network = Self.networkCounters()
        (value.diskRead, value.diskWrite) = SampleDelta.rates(current: disk, previous: previousDisk, elapsed: elapsed)
        (value.networkReceive, value.networkSend) = SampleDelta.rates(current: network, previous: previousNetwork, elapsed: elapsed)
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 { value.loadAverages = loads }
        previousCPU = counters; previousDisk = disk; previousNetwork = network; previousTime = now
        value.sampledAt = Date()
        return value
    }

    func sampleProcesses() -> ProcessSnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = previousProcessTime.map { now - $0 } ?? 0
        var pointer: UnsafeMutablePointer<MUProcessSample>?
        let count = MUCopyProcessSamples(&pointer)
        guard count >= 0, let pointer else {
            previousProcesses = [:]; previousProcessTime = nil
            return ProcessSnapshot(sampledAt: Date(), failed: true)
        }
        defer { MUFreeProcessSamples(pointer) }
        var next: [ProcessIdentity: UInt64] = [:]
        // The native bridge always terminates the path; reuse one scratch buffer.
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        var liveApplications: Set<String> = []
        var rows = UnsafeBufferPointer(start: pointer, count: Int(count)).map { item in
            let id = ProcessIdentity(pid: item.pid, startSeconds: item.start_seconds, startMicroseconds: item.start_microseconds)
            let cpuTime: UInt64? = item.has_usage != 0 ? item.cpu_nanoseconds : nil
            if let cpuTime { next[id] = cpuTime }
            var name = item.name
            let label = withUnsafeBytes(of: &name) { raw in
                String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            let metadata: (String?, ProcessApplication?)
            do {
                let path = MUProcessPath(item.pid, id.startSeconds, id.startMicroseconds, &pathBuffer, UInt32(pathBuffer.count)) > 0
                    ? pathBuffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) } : nil
                var application: ProcessApplication?
                if let path, let bundlePath = ProcessApplication.bundlePath(for: path) {
                    liveApplications.insert(bundlePath)
                    if let cached = appMetadata[bundlePath] { application = cached }
                    else if let bundle = Bundle(path: bundlePath), bundle.infoDictionary?["CFBundlePackageType"] as? String == "APPL" {
                        let name = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                            ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                            ?? (bundle.localizedInfoDictionary?["CFBundleName"] as? String)
                            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                            ?? URL(fileURLWithPath: bundlePath).deletingPathExtension().lastPathComponent
                        let app = ProcessApplication(bundlePath: bundlePath, name: name)
                        appMetadata[bundlePath] = app; application = app
                    }
                }
                metadata = (path, application)
            }
            return ProcessReading(
                id: id, name: label.isEmpty ? "PID \(item.pid)" : label, uid: item.uid,
                cpu: SampleDelta.processCPU(current: cpuTime, previous: previousProcesses[id], elapsed: elapsed),
                memory: item.has_usage == 0 ? nil : Double(item.has_footprint != 0 ? item.footprint_bytes : item.resident_bytes),
                usesFootprint: item.has_footprint != 0, parentPID: item.parent_pid,
                executablePath: metadata.0, application: metadata.1
            )
        }
        // Resolve parent ownership only against this sample, never a stale/reused PID.
        rows = ProcessApplication.inheritingOwners(rows)
        appMetadata = appMetadata.filter { liveApplications.contains($0.key) }
        previousProcesses = next; previousProcessTime = now
        return ProcessSnapshot(rows: rows, sampledAt: Date())
    }

    func sampleSystemRuntime() -> SystemRuntime {
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) != 3 { loads = [] }
        let count = MUProcessCount()
        return SystemRuntime(uptime: ProcessInfo.processInfo.systemUptime, loads: loads,
                             processCount: count >= 0 ? Int(count) : nil, sampledAt: Date())
    }

    nonisolated static func cpuCounters() -> [CPUCounters]? {
        var processors: natural_t = 0
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &processors, &info, &count) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        guard count >= processors * UInt32(CPU_STATE_MAX) else { return nil }
        return (0..<Int(processors)).map { core in
            let offset = core * Int(CPU_STATE_MAX)
            func tick(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[offset + Int(state)])) }
            return CPUCounters(user: tick(CPU_STATE_USER), system: tick(CPU_STATE_SYSTEM), idle: tick(CPU_STATE_IDLE), nice: tick(CPU_STATE_NICE))
        }
    }

    nonisolated static func memory() -> MemoryReading {
        var value = MemoryReading(total: Double(ProcessInfo.processInfo.physicalMemory))
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        if result == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS {
            let page = Double(pageSize)
            let wired = Double(stats.wire_count) * page
            let compressed = Double(stats.compressor_page_count) * page
            let cached = (Double(stats.purgeable_count) + Double(stats.external_page_count)) * page
            let pageable = (Double(stats.active_count) + Double(stats.inactive_count) + Double(stats.speculative_count)) * page
            let app = max(0, pageable - cached)
            value.app = app; value.wired = wired; value.compressed = compressed; value.cached = cached
            value.used = min(value.total, app + wired + compressed)
        }
        var swap = xsw_usage()
        var length = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &length, nil, 0) == 0 { value.swapUsed = Double(swap.xsu_used) }
        value.pressure = SystemIdentityReader.integer("kern.memorystatus_vm_pressure_level")
        return value
    }

    nonisolated static func gpus() -> [GPUReading] {
        var rows: [GPUReading] = []
        visit("IOAccelerator") { service in
            guard let stats = property("PerformanceStatistics", service) as? [String: Any] else { return }
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &id)
            func percentage(_ key: String) -> Double? {
                guard let n = (stats[key] as? NSNumber)?.doubleValue, n.isFinite, (0...100).contains(n) else { return nil }
                return n
            }
            let model = property("model", service)
            let name = (model as? String) ?? (model as? Data).flatMap { String(data: $0, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) } ?? "GPU"
            rows.append(GPUReading(id: String(id), name: name,
                cores: (property("gpu-core-count", service) as? NSNumber)?.intValue,
                utilization: percentage("Device Utilization %"), renderer: percentage("Renderer Utilization %"),
                tiler: percentage("Tiler Utilization %"), allocatedMemory: (stats["Alloc system memory"] as? NSNumber)?.doubleValue))
        }
        return rows.sorted { $0.id < $1.id }
    }

    nonisolated private static func diskCounters() -> [String: ByteCounters]? {
        var counters: [String: ByteCounters] = [:]
        let success = visit("IOBlockStorageDriver") { service in
            guard let stats = property("Statistics", service) as? [String: Any],
                  let read = stats["Bytes (Read)"] as? NSNumber, let written = stats["Bytes (Write)"] as? NSNumber else { return }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else { return }
            counters[String(id)] = ByteCounters(input: read.uint64Value, output: written.uint64Value)
        }
        return success && !counters.isEmpty ? counters : nil
    }

    nonisolated private static func networkCounters() -> [String: ByteCounters]? {
        var pointer: UnsafeMutablePointer<MUNetworkSample>?
        let count = MUCopyNetworkSamples(&pointer)
        guard count >= 0, let pointer else { return nil }
        defer { MUFreeNetworkSamples(pointer) }
        var counters: [String: ByteCounters] = [:]
        for item in UnsafeBufferPointer(start: pointer, count: Int(count)) {
            var name = item.name
            let label = withUnsafeBytes(of: &name) { String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self)) }
            counters["\(item.index):\(label)"] = ByteCounters(input: item.received_bytes, output: item.sent_bytes)
        }
        return counters
    }

    @discardableResult nonisolated private static func visit(_ className: String, body: (io_service_t) -> Void) -> Bool {
        guard let matching = IOServiceMatching(className) else { return false }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            body(service); IOObjectRelease(service)
        }
        return true
    }
    nonisolated private static func property(_ name: String, _ service: io_service_t) -> Any? {
        IORegistryEntryCreateCFProperty(service, name as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

enum SystemIdentityReader {
    static func read() -> SystemIdentity {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        let bootTime = sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 ? Date(timeIntervalSince1970: Double(boot.tv_sec)) : nil
        var coreGroups: [CPUCoreGroup] = []
        for index in 0..<(integer("hw.nperflevels") ?? 0) {
            if let name = string("hw.perflevel\(index).name"),
               let count = integer("hw.perflevel\(index).physicalcpu"), count > 0 {
                coreGroups.append(CPUCoreGroup(name: name, count: count,
                    l1InstructionBytes: unsignedInteger("hw.perflevel\(index).l1icachesize"),
                    l1DataBytes: unsignedInteger("hw.perflevel\(index).l1dcachesize"),
                    l2Bytes: unsignedInteger("hw.perflevel\(index).l2cachesize"),
                    coresPerL2: integer("hw.perflevel\(index).cpusperl2")))
            }
        }
        return SystemIdentity(osVersion: string("kern.osproductversion") ?? ProcessInfo.processInfo.operatingSystemVersionString,
            osBuild: string("kern.osversion") ?? "", kernel: string("kern.osrelease") ?? "",
            architecture: string("hw.machine") ?? "", physicalCores: integer("hw.physicalcpu"), logicalCores: integer("hw.logicalcpu"),
            coreGroups: coreGroups, bootTime: bootTime,
            gpuNames: PerformanceReader.gpus().map { gpu in gpu.cores.map { "\(gpu.name) · \($0) cores" } ?? gpu.name },
            hostName: ProcessInfo.processInfo.hostName, packages: integer("hw.packages"),
            pageBytes: unsignedInteger("hw.pagesize"), reportedFrequencyHz: unsignedInteger("hw.cpufrequency"),
            l3Bytes: unsignedInteger("hw.l3cachesize"), virtualization: integer("kern.hv_support").map { $0 != 0 })
    }
    static func integer(_ key: String) -> Int? {
        var value: Int32 = 0, size = MemoryLayout<Int32>.size
        guard sysctlbyname(key, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
    static func string(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
    }
    static func unsignedInteger(_ key: String) -> UInt64? {
        var value: UInt64 = 0, size = MemoryLayout<UInt64>.size
        guard sysctlbyname(key, &value, &size, nil, 0) == 0, size == 4 || size == 8 else { return nil }
        return value > 0 ? value : nil
    }
}
