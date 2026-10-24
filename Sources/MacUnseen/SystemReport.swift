import Foundation

struct SystemReportCategory: Identifiable, Equatable {
    let id: String
    let title: String
    let section: DashboardSection
    var profilerType: String? { id == "cpu" ? nil : id }
    var startsExpanded: Bool { !Self.largeDirectories.contains(id) }
    static let largeDirectories: Set<String> = [
        "SPApplicationsDataType", "SPExtensionsDataType", "SPFrameworksDataType", "SPFontsDataType",
        "SPInstallHistoryDataType", "SPPrefPaneDataType", "SPLegacySoftwareDataType", "SPLogsDataType",
        "SPPrintersSoftwareDataType", "SPNetworkLocationDataType",
    ]

    static func categories(for section: DashboardSection) -> [Self] {
        all.filter { $0.section == section }
    }

    // Every report has exactly one home, alongside the same hardware's live data.
    static let all: [Self] = {
        func group(_ section: DashboardSection, _ items: [(String, String)]) -> [Self] {
            items.map { Self(id: $0.0, title: $0.1, section: section) }
        }
        return group(.performance, [
            ("cpu", "处理器与缓存"), ("SPMemoryDataType", "内存"),
            ("SPDisplaysDataType", "图形与显示器"),
        ]) + group(.battery, [
            ("SPPowerDataType", "电源"),
        ]) + group(.storage, [
            ("SPNVMeDataType", "NVMExpress"), ("SPStorageDataType", "存储卷"),
            ("SPSerialATADataType", "SATA"), ("SPNetworkVolumeDataType", "网络卷"),
        ]) + group(.network, [
            ("SPNetworkDataType", "网络配置"), ("SPAirPortDataType", "Wi-Fi"),
            ("SPEthernetDataType", "以太网"), ("SPNetworkLocationDataType", "网络位置"),
            ("SPFirewallDataType", "防火墙"),
        ]) + group(.ports, [
            ("SPThunderboltDataType", "雷雳与 USB4"), ("SPUSBHostDataType", "USB"),
            ("SPBluetoothDataType", "蓝牙"), ("SPAudioDataType", "音频"),
            ("SPCameraDataType", "相机"), ("SPCardReaderDataType", "读卡器"),
            ("SPPCIDataType", "PCI"), ("SPSPIDataType", "SPI"),
            ("SPSmartCardsDataType", "智能卡"), ("SPPrintersDataType", "打印机"),
            ("SPPrintersSoftwareDataType", "打印机软件"),
        ]) + group(.systemInfo, [
            ("SPHardwareDataType", "整机信息"), ("SPiBridgeDataType", "系统控制器"),
            ("SPSecureElementDataType", "安全元件"), ("SPSoftwareDataType", "软件概览"),
            ("SPApplicationsDataType", "应用程序"), ("SPExtensionsDataType", "系统扩展"),
            ("SPFrameworksDataType", "框架"), ("SPFontsDataType", "字体"),
            ("SPInstallHistoryDataType", "安装记录"), ("SPPrefPaneDataType", "偏好设置面板"),
            ("SPLegacySoftwareDataType", "旧版软件"), ("SPDeveloperToolsDataType", "开发者工具"),
            ("SPInternationalDataType", "语言与地区"), ("SPLogsDataType", "日志"),
            ("SPUniversalAccessDataType", "辅助功能"),
        ])
    }()
}

struct SystemReportNode: Identifiable, Equatable, Sendable {
    var id: Int
    var label: String
    var value: String?
    var children: [SystemReportNode]?

    func matching(_ query: String) -> Self? {
        if query.isEmpty || label.localizedCaseInsensitiveContains(query)
            || value?.localizedCaseInsensitiveContains(query) == true
            || SystemReportLabels.localized(label, value: value).localizedCaseInsensitiveContains(query)
            || value.map({ SystemReportLabels.localizedValue($0, label: label).localizedCaseInsensitiveContains(query) }) == true { return self }
        let matches = children?.compactMap { $0.matching(query) } ?? []
        return matches.isEmpty ? nil : Self(id: id, label: label, value: value, children: matches)
    }
}

struct SystemReportOutlineRow: Identifiable {
    let node: SystemReportNode
    let depth: Int
    var id: Int { node.id }
}

enum SystemReportOutline {
    static func rows(_ nodes: [SystemReportNode], collapsed: Set<Int> = [], depth: Int = 0) -> [SystemReportOutlineRow] {
        nodes.flatMap { node in
            [SystemReportOutlineRow(node: node, depth: depth)] + (collapsed.contains(node.id) ? []
                : rows(node.children ?? [], collapsed: collapsed, depth: depth + 1))
        }
    }
}

struct SystemReport: Equatable, Sendable {
    var nodes: [SystemReportNode]
    var sampledAt: Date

    var batteryHealthPercentage: Double? {
        func find(_ label: String, in nodes: [SystemReportNode]) -> [SystemReportNode] {
            nodes.flatMap { $0.label == label ? [$0] : find(label, in: $0.children ?? []) }
        }
        for battery in find("Battery Information", in: nodes) {
            for health in find("Health Information", in: battery.children ?? []) {
                for field in health.children ?? [] where field.label == "Maximum Capacity" {
                    guard let value = field.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                          value.hasSuffix("%"),
                          let percentage = Double(value.dropLast().trimmingCharacters(in: .whitespaces)),
                          percentage.isFinite, (0...100).contains(percentage) else { continue }
                    return percentage
                }
            }
        }
        return nil
    }
}

enum SystemReportParser {
    /// Native text reports supply human-readable field names and decoded values,
    /// unlike JSON tokens such as spdisplays_mtlgpufamilysupport.
    static func parse(_ text: String) -> [SystemReportNode] {
        struct Line { var indent: Int; var label: String; var value: String? }
        let lines: [Line] = text.components(separatedBy: .newlines).compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let indent = raw.prefix { $0 == " " || $0 == "\t" }.count
            if let separator = trimmed.range(of: ": ") {
                return Line(indent: indent, label: String(trimmed[..<separator.lowerBound]),
                            value: String(trimmed[separator.upperBound...]))
            }
            return Line(indent: indent, label: trimmed.hasSuffix(":") ? String(trimmed.dropLast()) : trimmed, value: nil)
        }
        var index = 0
        func block(at indent: Int) -> [SystemReportNode] {
            var nodes: [SystemReportNode] = []
            while index < lines.count, lines[index].indent >= indent {
                let line = lines[index]
                let id = index
                index += 1
                let children = index < lines.count && lines[index].indent > line.indent
                    ? block(at: lines[index].indent) : []
                nodes.append(SystemReportNode(id: id, label: line.label, value: line.value,
                                              children: children.isEmpty ? nil : children))
            }
            return nodes
        }
        let result = lines.first.map { block(at: $0.indent) } ?? []
        // The first heading repeats the category shown above the report.
        if result.count == 1, result[0].value == nil {
            if let children = result[0].children { return children }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(":") { return [] }
        }
        return result
    }
}

/// Each job owns a single bounded subprocess; switching categories or leaving
/// the page terminates it. Cancellation and launch are serialized by the lock.
final class SystemReportJob: @unchecked Sendable {
    private let command = SystemCommand()
    private let type: String
    init(type: String) { self.type = type }

    func cancel() { command.cancel() }

    func run() -> SystemReport? {
        guard let data = command.run(executable: "/usr/sbin/system_profiler",
                arguments: [type, "-detailLevel", "full", "-timeout", "25"], timeout: 28),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return SystemReport(nodes: SystemReportParser.parse(text), sampledAt: Date())
    }
}

@MainActor final class SystemReportStore: ObservableObject {
    @Published private(set) var section: DashboardSection = .systemInfo
    @Published private(set) var reports: [String: SystemReport] = [:]
    @Published private(set) var loading: String?
    @Published private(set) var failed: Set<String> = []
    private(set) var requested: Set<String> = []
    private var inlineRequests: Set<String> = []
    private var active = false
    private var job: SystemReportJob?
    private var task: Task<Void, Never>?

    init(reports: [String: SystemReport] = [:]) { self.reports = reports }

    func show(section: DashboardSection, active: Bool) {
        if self.section != section {
            cancel(); requested = []; inlineRequests = []
            // Large optional directories belong to their page session. Keep small
            // hardware specifications cached so revisiting does not re-query them.
            for id in SystemReportCategory.largeDirectories { discardDirectory(id) }
        }
        self.section = section
        setActive(active)
    }
    func request(_ id: String, persistent: Bool = false) {
        guard SystemReportCategory.all.contains(where: { $0.id == id && $0.section == section && $0.profilerType != nil }) else { return }
        if persistent { inlineRequests.insert(id) }
        requested.insert(id)
        pump()
    }
    func release(_ id: String) {
        // Optional disclosures can share the hardware card's report source.
        guard !inlineRequests.contains(id) else { return }
        requested.remove(id)
        discardDirectory(id)
        if loading == id { cancel(); pump() }
    }
    private func discardDirectory(_ id: String) {
        guard SystemReportCategory.largeDirectories.contains(id) else { return }
        if reports[id] != nil { reports.removeValue(forKey: id) }
        failed.remove(id)
    }
    func setActive(_ active: Bool) {
        self.active = active
        if active { pump() } else { cancel() }
    }
    func cancel() {
        job?.cancel(); job = nil
        task?.cancel(); task = nil
        loading = nil
    }
    func refresh(_ id: String) {
        guard requested.contains(id) else { return }
        if loading == id { cancel() }
        reports.removeValue(forKey: id)
        failed.remove(id)
        pump()
    }
    func refreshRequested() {
        cancel()
        for id in requested { reports.removeValue(forKey: id); failed.remove(id) }
        pump()
    }
    private func pump() {
        guard active, loading == nil,
              let category = SystemReportCategory.categories(for: section).first(where: {
                  requested.contains($0.id) && reports[$0.id] == nil && !failed.contains($0.id)
              }), let type = category.profilerType else { return }
        let job = SystemReportJob(type: type)
        self.job = job
        loading = category.id
        task = Task { [weak self] in
            let value = await Task.detached(priority: .utility) { job.run() }.value
            guard let self, !Task.isCancelled, self.job === job else { return }
            if let value { self.reports[category.id] = value } else { self.failed.insert(category.id) }
            self.loading = nil
            self.job = nil
            self.task = nil
            self.pump()
        }
    }
}
