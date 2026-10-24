import SwiftUI

private func percentage(_ value: Double?) -> String { value.map { format($0, digits: 1) + "%" } ?? "—" }
func formatMonitoredBytes(_ value: Double?) -> String {
    guard let value, value.isFinite, value >= 0 else { return "—" }
    return value == 0 ? "0 B" : formatBytes(value)
}
private func bytes(_ value: Double?) -> String { formatMonitoredBytes(value) }
private func rate(_ value: Double?) -> String { value.map { bytes($0) + "/s" } ?? "—" }

struct PerformanceSummary: View {
    @EnvironmentObject private var store: SensorStore
    var body: some View {
        MetricGrid(metrics: [
            Metric(name: "CPU 占用", value: percentage(store.performance.cpu)),
            Metric(name: "GPU 占用", value: percentage(store.performance.gpus.first?.utilization)),
            Metric(name: "已用内存", value: bytes(store.performance.memory.used), detail: "不含可回收缓存"),
            Metric(name: "网络接收", value: rate(store.performance.networkReceive)),
            Metric(name: "磁盘读取", value: rate(store.performance.diskRead)),
            Metric(name: "磁盘已用", value: store.system.diskTotal > 0 ? bytes(store.system.diskUsed) : "—",
                   detail: tr("总计") + " " + (store.system.diskTotal > 0 ? bytes(store.system.diskTotal) : "—")),
            Metric(name: "已开机时间", value: formatDuration(store.system.uptime)),
        ], tint: .blue, minimumWidth: 135)
    }
}

struct PerformanceView: View {
    @EnvironmentObject private var store: SensorStore
    private var reading: PerformanceReading { store.performance }
    var body: some View {
        Page(title: "实时性能", subtitle: "CPU、GPU、内存与实时传输速率", reportSection: .performance) {
            Text(tr("每秒更新；切换页面或进入后台后暂停。首个样本显示 —，取得下一次采样后计算占用率和速率。"))
                .font(.caption).foregroundStyle(.secondary)
            Card(title: "CPU", symbol: "cpu", tint: .blue,
                 info: "整机 CPU 占用以所有逻辑核心合计为 100%，由相邻两次计数差值计算。系统负载是等待或正在执行的任务数量，不是 CPU 百分比。") {
                Text(store.system.chipName).font(.headline).textSelection(.enabled)
                HStack(alignment: .firstTextBaseline) {
                    Text(percentage(reading.cpu)).font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                    Spacer()
                    Text(tr("最近 60 次采样 · 0–100%"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                CPUHistory(values: store.cpuHistory).frame(height: 90)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 10) {
                    ForEach(reading.cores.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("CPU \(index + 1)")
                                Spacer()
                                Text(percentage(reading.cores[index]))
                            }.font(.caption).monospacedDigit()
                            ProgressView(value: (reading.cores[index] ?? 0) / 100).tint(.blue)
                        }
                    }
                }
                MetricGrid(metrics: zip(["1 分钟负载", "5 分钟负载", "15 分钟负载"], reading.loadAverages).map {
                    Metric(name: $0, value: format($1, digits: 2))
                }, tint: .blue)
                SoftDivider()
                ProcessorSpecificationsView(identity: store.systemIdentity).equatable()
            }
            MemoryMonitoringCard(reading: reading.memory, history: store.memoryPressureHistory,
                                 pageBytes: store.systemIdentity.pageBytes, reports: store.systemReports)
            Card(title: "GPU", symbol: "square.3.layers.3d", tint: .green,
                 info: "GPU 占用来自驱动报告。不同机型和系统版本提供的项目可能不同；未提供的字段显示 —。GPU 分配内存属于系统内存的一部分，不应再次加到整机内存占用中。") {
                if reading.gpus.isEmpty {
                    Text(tr("当前驱动未提供 GPU 占用数据。")) .foregroundStyle(.secondary)
                }
                ForEach(reading.gpus) { gpu in
                    Text(gpu.name).font(.headline)
                    MetricGrid(metrics: [
                        Metric(name: "GPU 占用", value: percentage(gpu.utilization)),
                        Metric(name: "渲染器占用", value: percentage(gpu.renderer)),
                        Metric(name: "分块器占用", value: percentage(gpu.tiler)),
                        Metric(name: "GPU 分配内存", value: bytes(gpu.allocatedMemory)),
                    ], tint: .green)
                }
                InlineSystemReport(reports: store.systemReports, id: "SPDisplaysDataType",
                    excluding: reading.gpus.isEmpty ? [] : ["Chipset Model"])
            }
            Card(title: "实时读写与网络", symbol: "arrow.up.arrow.down", tint: .orange,
                 info: "速率由累计字节数的差值除以实际采样间隔得到。磁盘统计存储驱动的底层 I/O；网络统计活动的 en 系列物理接口，包括局域网流量，排除回环和 VPN 隧道以避免重复计数。它不是网速测试。") {
                MetricGrid(metrics: [
                    Metric(name: "磁盘读取", value: rate(reading.diskRead)),
                    Metric(name: "磁盘写入", value: rate(reading.diskWrite)),
                    Metric(name: "网络接收", value: rate(reading.networkReceive)),
                    Metric(name: "网络发送", value: rate(reading.networkSend)),
                ], tint: .orange)
            }
        }
    }
}

private struct CPUHistory: View {
    let values: [Double]
    var body: some View {
        Canvas { context, size in
            for fraction in [0.0, 0.5, 1.0] {
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: size.height * fraction))
                grid.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                context.stroke(grid, with: .color(.secondary.opacity(0.15)), lineWidth: 1)
            }
            var path = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: size.width * Double(index) / 59, y: size.height * (1 - min(100, max(0, value)) / 100))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(.blue), lineWidth: 2)
        }
        .accessibilityLabel(tr("CPU 占用历史"))
    }
}

struct ProcessesView: View {
    @EnvironmentObject private var store: SensorStore
    @State private var query = ""
    @State private var sort = ProcessSort()
    @State private var currentUserOnly = false
    @State private var byApplication = false
    @State private var expandedApps: Set<String> = []
    private var eligible: [ProcessReading] { store.processSnapshot.rows.filter { !currentUserOnly || $0.uid == getuid() } }
    private var rows: [ProcessReading] {
        eligible.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || String($0.id.pid).contains(query) }
            .sorted(by: sort.precedes)
    }
    private var apps: [ApplicationProcessGroup] {
        ApplicationProcessGroup.group(eligible).filter { $0.matches(query) }.sorted(by: sort.precedes)
    }
    var body: some View {
        // Filter/group/sort once for this update; the count and list share it.
        let rows = byApplication ? [] : self.rows
        let apps = byApplication ? self.apps : []
        Page(title: "进程", subtitle: "按 CPU 或内存占用查看正在运行的进程") {
            HStack {
                Picker(tr("列表方式"), selection: $byApplication) {
                    Text(tr("按进程")).tag(false)
                    Text(tr("按软件")).tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 220, alignment: .leading)
                Spacer()
                Text(tr("点击列标题排序")).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                TextField(tr("搜索名称或 PID"), text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                Toggle(tr("仅当前用户"), isOn: $currentUserOnly)
                Spacer(minLength: 0)
            }
            Text(tr(byApplication
                ? "每 2 秒更新。软件按应用包和同用户的父子进程归并；无法确认归属的后台服务单独显示。CPU 与内存为成员进程合计，内存可能重复计入共享页面；≥ 表示部分进程无法读取。搜索命中成员时仍显示整组总量。"
                : "每 2 秒更新，仅在此页采样。CPU 的 100% 表示占满一个逻辑核心，多核进程可超过 100%。内存优先显示物理占用；回退项标为“驻留”。— 表示采样中或无权限读取。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if store.processSnapshot.failed {
                Text(tr("无法读取进程列表；系统可能限制了访问。")).foregroundStyle(.secondary)
            } else if store.processSnapshot.sampledAt == nil {
                ProgressView(tr("正在读取进程…"))
            } else {
                HStack {
                    Text(byApplication ? "\(apps.count) \(tr("个软件／后台服务"))" : "\(rows.count) \(tr("个进程"))")
                    Spacer()
                    if let date = store.processSnapshot.sampledAt { Text(date, style: .time).monospacedDigit() }
                }.font(.caption).foregroundStyle(.secondary)
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        if byApplication {
                            ForEach(apps) { app in
                                HStack(spacing: 10) {
                                    Button {
                                        if expandedApps.contains(app.id) { expandedApps.remove(app.id) } else { expandedApps.insert(app.id) }
                                    } label: {
                                        HStack(spacing: 7) {
                                            Image(systemName: expandedApps.contains(app.id) ? "chevron.down" : "chevron.right").font(.caption2)
                                            Text(app.name).lineLimit(1).truncationMode(.middle)
                                            Spacer(minLength: 0)
                                        }.contentShape(Rectangle())
                                    }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
                                        .accessibilityValue(tr(expandedApps.contains(app.id) ? "已展开" : "已折叠"))
                                    Text(String(app.processes.count)).foregroundStyle(.secondary).frame(width: 65, alignment: .trailing)
                                    Text((app.partialCPU && app.cpu != nil ? "≥ " : "") + percentage(app.cpu)).frame(width: 90, alignment: .trailing)
                                    Text((app.partialMemory && app.memory != nil ? "≥ " : "") + bytes(app.memory)
                                         + (app.usesResidentFallback ? " *" : "")).frame(width: 150, alignment: .trailing)
                                        .help(tr("软件内存为各成员进程之和；* 表示部分成员使用驻留内存。"))
                                }
                                .font(.system(size: 12)).monospacedDigit().padding(.horizontal, 12).padding(.vertical, 9)
                                if expandedApps.contains(app.id) {
                                    ForEach(app.processes.sorted(by: sort.precedes)) { process in
                                        processRow(process).padding(.leading, 20).background(.quaternary.opacity(0.3))
                                    }
                                }
                                Divider().opacity(0.45)
                            }
                        } else {
                            ForEach(rows) { process in processRow(process); Divider().opacity(0.45) }
                        }
                    } header: {
                        HStack(spacing: 10) {
                            sortHeader(.name, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                            sortHeader(.pid).frame(width: 65)
                            sortHeader(.cpu).frame(width: 90)
                            sortHeader(.memory).frame(width: 150)
                        }.padding(.horizontal, 12).padding(.vertical, 4).background(.regularMaterial)
                    }
                }.background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    private func processRow(_ process: ProcessReading) -> some View {
        HStack(spacing: 10) {
            Text(process.name).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            Text((byApplication ? "PID " : "") + String(process.id.pid)).foregroundStyle(.secondary).frame(width: 65, alignment: .trailing)
            Text(percentage(process.cpu)).frame(width: 90, alignment: .trailing)
            Text(bytes(process.memory) + (!process.usesFootprint && process.memory != nil ? " (\(tr("驻留")))" : ""))
                .frame(width: 150, alignment: .trailing)
        }.font(.system(size: 12)).monospacedDigit().padding(.horizontal, 12).padding(.vertical, 9)
    }
    private func sortHeader(_ column: ProcessSortColumn, alignment: Alignment = .trailing) -> some View {
        let title = byApplication && column == .pid ? "进程数" : column.title
        return Button { sort.select(column) } label: {
            HStack(spacing: 5) {
                Text(tr(title))
                Image(systemName: sort.ascending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold)).opacity(sort.column == column ? 1 : 0)
                    .accessibilityHidden(true)
            }.font(.system(size: 12, weight: .semibold))
                .foregroundStyle(sort.column == column ? AppPalette.accentText : .secondary)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: alignment).contentShape(Rectangle())
        }.buttonStyle(SubtlePressButtonStyle()).accessibilityLabel(tr(title))
            .accessibilityValue(sort.column == column ? tr(sort.ascending ? "升序" : "降序") : tr("未排序"))
            .help(tr("点击排序，再次点击反转顺序"))
    }
}
