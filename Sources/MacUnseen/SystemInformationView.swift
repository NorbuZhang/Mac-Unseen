import SwiftUI

struct SystemInformationView: View {
    @EnvironmentObject private var store: SensorStore
    private var identity: SystemIdentity { store.systemIdentity }
    private var details: SystemDetails { store.systemDetails }
    private func count(_ value: Int?) -> String { value.map(String.init) ?? "—" }
    private func text(_ value: String?) -> String { value.flatMap { $0.isEmpty ? nil : $0 } ?? "—" }

    var body: some View {
        Page(title: "系统信息", subtitle: "整机、固件与软件资料", reportSection: .systemInfo) {
            Text(tr("运行状态每 5 秒更新；静态资料按需读取。大型软件目录默认折叠。"))
                .font(.caption).foregroundStyle(.secondary)
            runtimeCard
            systemCard
            ForEach(SystemReportCategory.categories(for: .systemInfo).filter { !["SPHardwareDataType", "SPSoftwareDataType"].contains($0.id) }) { category in
                SystemReportCard(reports: store.systemReports, id: category.id)
            }
        }
    }

    private var runtimeCard: some View {
        Card(title: "运行状态", symbol: "waveform.path.ecg", tint: .green,
             info: "进程数为系统当前可枚举的进程数量。负载表示正在运行或等待运行的任务数量，不是 CPU 占用百分比。") {
            MetricGrid(metrics: [
                Metric(name: "运行时间", value: store.systemRuntime.sampledAt == nil ? "—" : uptime(store.systemRuntime.uptime), detail: "天 : 时 : 分 : 秒"),
                Metric(name: "进程数", value: count(store.systemRuntime.processCount)),
            ] + zip(["1 分钟负载", "5 分钟负载", "15 分钟负载"], store.systemRuntime.loads).map {
                Metric(name: $0, value: format($1, digits: 2))
            }, tint: .green)
            informationRows([
                ("启动时间", identity.bootTime?.formatted(date: .abbreviated, time: .shortened) ?? "—"),
                ("采样时间", store.systemRuntime.sampledAt?.formatted(date: .omitted, time: .standard) ?? "—"),
            ])
        }
    }

    private var systemCard: some View {
        Card(title: "设备与系统", symbol: "desktopcomputer", tint: .blue) {
            informationRows([
                ("主机名", text(identity.hostName)),
                ("机型", text(details.modelName ?? store.system.modelName)),
                ("机型标识符", text(store.system.modelIdentifier)),
                ("型号编号", text(details.modelNumber)),
                ("macOS 版本", text(identity.osVersion)),
                ("系统构建号", text(identity.osBuild)),
                ("内核版本", "Darwin " + text(identity.kernel)),
                ("体系结构", text(identity.architecture)),
                ("系统固件", text(details.firmware)),
                ("启动加载器", text(details.bootLoader)),
            ])
            InlineSystemReport(reports: store.systemReports, id: "SPHardwareDataType", excluding: hardwareExclusions)
            InlineSystemReport(reports: store.systemReports, id: "SPSoftwareDataType", excluding: softwareExclusions)
        }
    }

    private var hardwareExclusions: Set<String> {
        var keys: Set<String> = ["Chip", "Memory", "Total Number of Cores"] // Owned by Performance.
        if details.modelName != nil || !store.system.modelName.isEmpty { keys.insert("Model Name") }
        if !store.system.modelIdentifier.isEmpty { keys.insert("Model Identifier") }
        if details.modelNumber != nil { keys.insert("Model Number") }
        if details.firmware != nil { keys.insert("System Firmware Version") }
        if details.bootLoader != nil { keys.insert("OS Loader Version") }
        return keys
    }

    private var softwareExclusions: Set<String> {
        var keys: Set<String> = []
        if !identity.osVersion.isEmpty { keys.insert("System Version") }
        if !identity.kernel.isEmpty { keys.insert("Kernel Version") }
        if !identity.hostName.isEmpty { keys.insert("Computer Name") }
        if store.systemRuntime.sampledAt != nil { keys.insert("Time since boot") }
        return keys
    }

    private func informationRows(_ rows: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
            ForEach(rows.indices, id: \.self) { index in
                GridRow(alignment: .firstTextBaseline) {
                    Text(tr(rows[index].0)).foregroundStyle(.secondary)
                    Text(rows[index].1).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.font(.callout)
    }

    private func uptime(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d:%02d", value / 86_400, value / 3_600 % 24, value / 60 % 60, value % 60)
    }
}
