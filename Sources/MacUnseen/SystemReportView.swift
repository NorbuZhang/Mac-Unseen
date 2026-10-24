import SwiftUI

enum ReportSelection: Equatable {
    case all
    case branch(String)
    case device(field: String, value: String)
    case omittingDevices(field: String, values: Set<String>)
}

enum SystemReportProjection {
    static func nodes(_ source: [SystemReportNode], selection: ReportSelection = .all,
                      excluding: Set<String> = [], omitting: Set<String> = [], scopedExcluding: [String: Set<String>] = [:],
                      excludingDirect: Set<String> = []) -> [SystemReportNode] {
        func find(_ nodes: [SystemReportNode], match: (SystemReportNode) -> Bool) -> [SystemReportNode] {
            nodes.flatMap { node in match(node) ? [node] : find(node.children ?? [], match: match) }
        }
        var nodes: [SystemReportNode]
        switch selection {
        case .all: nodes = source
        case .branch(let label): nodes = find(source) { $0.label == label }.flatMap { $0.children ?? [$0] }
        case .omittingDevices(let field, let values):
            nodes = source.filter { node in !(node.children?.contains { $0.label == field && values.contains($0.value ?? "") } ?? false) }
        case .device(let field, let value):
            nodes = value.isEmpty ? [] : find(source) { node in
                node.children?.contains { $0.label == field && $0.value == value } == true
            }.flatMap { $0.children ?? [$0] }
        }
        if nodes.count == 1, ["Hardware Overview", "System Software Overview"].contains(nodes[0].label) {
            nodes = nodes[0].children ?? nodes
        }
        func prune(_ node: SystemReportNode, inherited: Set<String>) -> SystemReportNode? {
            guard !omitting.contains(node.label) else { return nil }
            let excluded = inherited.union(scopedExcluding[node.label] ?? [])
            var node = node
            if let children = node.children {
                let kept = children.compactMap { prune($0, inherited: excluded) }
                if kept.isEmpty && node.value == nil { return nil }
                node.children = kept.isEmpty ? nil : kept
            }
            if node.children == nil && excluded.contains(node.label) { return nil }
            return node
        }
        return nodes.filter { !excludingDirect.contains($0.label) || $0.children != nil }
            .compactMap { prune($0, inherited: excluding) }
    }
}

/// Appears inside the same hardware card as its live data, with duplicate
/// fields removed by the owner of that card. No second navigation surface.
struct InlineSystemReport: View {
    @ObservedObject var reports: SystemReportStore
    let id: String
    var selection: ReportSelection = .all
    var excluding: Set<String> = []
    var omitting: Set<String> = []
    var scopedExcluding: [String: Set<String>] = [:]
    var compact = false
    var excludingDirect: Set<String> = []
    var report: SystemReport? { reports.reports[id] }
    var body: some View {
        Group {
            if let report {
                let nodes = SystemReportProjection.nodes(report.nodes, selection: selection, excluding: excluding, omitting: omitting, scopedExcluding: scopedExcluding, excludingDirect: excludingDirect)
                if !nodes.isEmpty {
                    if nodes.count <= 12 && nodes.allSatisfy({ $0.children == nil && $0.value != nil }) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 12) {
                            ForEach(nodes) { node in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(SystemReportLabels.localized(node.label, value: node.value))
                                        .font(.caption).foregroundStyle(.secondary).help(node.label)
                                    Text(SystemReportLabels.localizedValue(node.value ?? "", label: node.label))
                                        .font(.callout).textSelection(.enabled).help(node.value ?? "")
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        ReportFields(nodes: nodes, collapseItems: compact)
                            .id(id + String(report.sampledAt.timeIntervalSince1970))
                    }
                    Text(tr("系统资料读取于") + " " + report.sampledAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else if reports.failed.contains(id) {
                HStack {
                    Text(tr("部分资料暂时无法读取"))
                    Button(tr("重试")) { reports.refresh(id) }.buttonStyle(.link).tint(AppPalette.accentText)
                }.font(.caption).foregroundStyle(.secondary)
            } else {
                Text(tr("正在读取硬件资料…")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { reports.request(id, persistent: true) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            if id == "SPDisplaysDataType" { reports.refresh(id) }
        }
    }
}

/// Named categories are visible on the page. Large directories remain folded
/// until requested; opening one never replaces the rest of the page.
struct SystemReportCard: View {
    @ObservedObject var reports: SystemReportStore
    let category: SystemReportCategory
    var excluding: Set<String> = []
    var omitting: Set<String> = []
    var title: String?
    var selection: ReportSelection = .all
    @State private var expanded: Bool
    @State private var query = ""

    init(reports: SystemReportStore, id: String, title: String? = nil,
         excluding: Set<String> = [], omitting: Set<String> = [], expanded: Bool? = nil, selection: ReportSelection = .all) {
        self.reports = reports
        self.category = SystemReportCategory.all.first { $0.id == id }!
        self.title = title; self.excluding = excluding; self.omitting = omitting; self.selection = selection
        _expanded = State(initialValue: expanded ?? category.startsExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 9) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption.weight(.semibold))
                        Text(tr(title ?? category.title)).font(.headline)
                        Spacer()
                        if let report = reports.reports[category.id] {
                            Text("\(report.nodes.count) \(tr("项"))").font(.caption).foregroundStyle(.secondary)
                        } else if !expanded { Text(tr("按需读取")).font(.caption).foregroundStyle(.secondary) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityValue(tr(expanded ? "已展开" : "已折叠"))
                if expanded {
                    Button { reports.refresh(category.id) } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).help(tr("更新资料")).accessibilityLabel(tr("更新资料"))
                }
            }
            if expanded {
                if let report = reports.reports[category.id] {
                    let source = SystemReportProjection.nodes(report.nodes, selection: selection, excluding: excluding, omitting: omitting)
                    if !category.startsExpanded || source.count > 12 {
                        TextField(tr("筛选当前报告"), text: $query).textFieldStyle(.roundedBorder)
                    }
                    let nodes = source.compactMap { $0.matching(query.trimmingCharacters(in: .whitespaces)) }
                    if source.isEmpty { Text(tr("没有可报告的项目")).foregroundStyle(.secondary).font(.callout) }
                    else if nodes.isEmpty { Text(tr("没有匹配的项目")).foregroundStyle(.secondary).font(.callout) }
                    else {
                        ReportFields(nodes: nodes, collapseItems: !category.startsExpanded || source.count > 12,
                                     searching: !query.isEmpty).id(category.id + String(report.sampledAt.timeIntervalSince1970))
                    }
                    Text(tr("资料读取于") + " " + report.sampledAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                } else if reports.failed.contains(category.id) {
                    Text(tr("此类别未能读取。可能是系统限制或读取超时，请重新读取。"))
                        .foregroundStyle(.secondary).font(.caption)
                } else {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(tr(reports.loading == category.id ? "正在读取…" : "等待读取…"))
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18).background(CardSurface(tint: category.tint, cornerRadius: 16))
        .onAppear { if expanded { reports.request(category.id) } }
        .onChange(of: expanded) { _, open in
            if open { reports.request(category.id) } else { reports.release(category.id) }
        }
    }
}

struct ReportFields: View {
    let nodes: [SystemReportNode]
    var collapseItems = false
    var searching = false
    @State private var collapsed: Set<Int> = []
    @State private var initialized = false
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(SystemReportOutline.rows(nodes, collapsed: searching ? [] : collapsed)) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if entry.node.children != nil {
                        Button {
                            if collapsed.contains(entry.id) { collapsed.remove(entry.id) } else { collapsed.insert(entry.id) }
                        } label: {
                            Image(systemName: collapsed.contains(entry.id) && !searching ? "chevron.right" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold)).frame(width: 20, height: 22)
                        }.buttonStyle(.plain).disabled(searching)
                            .accessibilityLabel(SystemReportLabels.localized(entry.node.label))
                            .accessibilityValue(tr(collapsed.contains(entry.id) && !searching ? "已折叠" : "已展开"))
                    }
                    Text(SystemReportLabels.localized(entry.node.label, value: entry.node.value))
                        .foregroundStyle(entry.node.value == nil ? .primary : .secondary)
                        .fontWeight(entry.node.children == nil ? .regular : .medium)
                        .help(entry.node.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let value = entry.node.value {
                        Text(SystemReportLabels.localizedValue(value, label: entry.node.label))
                            .textSelection(.enabled).help(value)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.callout).padding(.vertical, 5).padding(.leading, CGFloat(entry.depth) * 12)
                .accessibilityElement(children: .contain)
                if entry.node.children == nil { Divider().opacity(0.3) }
            }
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            if collapseItems { collapsed = Set(nodes.filter { $0.children != nil }.map(\.id)) }
        }
    }
}

extension SystemReportCategory {
    var tint: Color {
        switch id {
        case "SPMemoryDataType": return .purple
        case "SPDisplaysDataType": return .green
        case "SPSecureElementDataType", "SPFirewallDataType": return .orange
        default:
            switch section {
            case .battery: return .green
            case .network: return .teal
            case .ports: return .indigo
            case .systemInfo: return .purple
            default: return .blue
            }
        }
    }
}

struct SpecificationGrid: View {
    let rows: [(String, String)]
    var columns: Int? = nil
    private var gridColumns: [GridItem] {
        if let columns { return Array(repeating: GridItem(.flexible(minimum: 0), alignment: .leading), count: columns) }
        return [GridItem(.adaptive(minimum: 180), alignment: .leading)]
    }
    var body: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
            ForEach(rows.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr(rows[i].0)).font(.caption).foregroundStyle(.secondary)
                    Text(rows[i].1).font(.callout).textSelection(.enabled)
                        .lineLimit(columns == nil ? nil : 1).minimumScaleFactor(0.85).help(rows[i].1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
