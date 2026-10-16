import SwiftUI

private func percentage(_ value: Double?) -> String { value.map { format($0, digits: 1) + "%" } ?? "—" }
private func bytes(_ value: Double?) -> String { value.map(formatBytes) ?? "—" }
private func rate(_ value: Double?) -> String { value.map { formatBytes($0) + "/s" } ?? "—" }

struct PerformanceSummary: View {
    @EnvironmentObject private var store: SensorStore
    var body: some View {
        MetricGrid(metrics: [
            Metric(name: "CPU 占用", value: percentage(store.performance.cpu)),
            Metric(name: "GPU 占用", value: percentage(store.performance.gpus.first?.utilization)),
            Metric(name: "已用内存", value: bytes(store.performance.memory.used), detail: "不含可回收缓存"),
            Metric(name: "网络接收", value: rate(store.performance.networkReceive)),
            Metric(name: "磁盘读取", value: rate(store.performance.diskRead)),
        ], tint: AppPalette.accent, minimumWidth: 135)
    }
}

struct PerformanceView: View {
    @EnvironmentObject private var store: SensorStore
    private var reading: PerformanceReading { store.performance }
    var body: some View {
        Page(title: "实时性能", subtitle: "CPU、GPU、内存与实时传输速率") {
            Text(tr("每秒更新；切换页面或进入后台后暂停。首个样本显示 —，取得下一次采样后计算占用率和速率。"))
                .font(.caption).foregroundStyle(.secondary)
            Card(title: "CPU", symbol: "cpu", tint: .blue,
                 info: "整机 CPU 占用以所有逻辑核心合计为 100%，由相邻两次计数差值计算。系统负载是等待或正在执行的任务数量，不是 CPU 百分比。") {
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
            }
            Card(title: "内存", symbol: "memorychip", tint: .purple,
                 info: "已用内存由应用、联动和压缩内存组成，可回收的文件缓存单独列出。数值根据系统内存页估算，可能与活动监视器略有差异。判断内存是否紧张应结合内存压力和交换空间，不能只看占用百分比。") {
                HStack {
                    Text("\(bytes(reading.memory.used)) / \(formatBytes(reading.memory.total))")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    Spacer()
                    Text(tr(pressureText)).foregroundStyle(pressureTint)
                }
                if let fraction = reading.memory.fraction { ProgressView(value: fraction).tint(pressureTint) }
                MetricGrid(metrics: [
                    Metric(name: "应用内存", value: bytes(reading.memory.app)),
                    Metric(name: "联动内存", value: bytes(reading.memory.wired)),
                    Metric(name: "压缩内存", value: bytes(reading.memory.compressed)),
                    Metric(name: "缓存文件", value: bytes(reading.memory.cached)),
                    Metric(name: "已用交换空间", value: bytes(reading.memory.swapUsed)),
                ], tint: .purple)
            }
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
    private var pressureText: String {
        switch reading.memory.pressure {
        case 1: "内存压力正常"
        case 2: "内存压力偏高"
        case 4: "内存压力很高"
        default: "内存压力不可用"
        }
    }
    private var pressureTint: Color {
        reading.memory.pressure == 4 ? .red : reading.memory.pressure == 2 ? .orange : .green
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
    @State private var order = "cpu"
    @State private var currentUserOnly = false
    private var rows: [ProcessReading] {
        store.processSnapshot.rows.filter {
            (!currentUserOnly || $0.uid == getuid()) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || String($0.id.pid).contains(query))
        }.sorted {
            if order == "name" {
                let compared = $0.name.localizedStandardCompare($1.name)
                if compared != .orderedSame { return compared == .orderedAscending }
            } else {
                let a = order == "cpu" ? $0.cpu : $0.memory
                let b = order == "cpu" ? $1.cpu : $1.memory
                if a != b { return (a ?? -1) > (b ?? -1) }
            }
            return $0.id.pid < $1.id.pid
        }
    }
    var body: some View {
        Page(title: "进程", subtitle: "按 CPU 或内存占用查看正在运行的进程") {
            HStack(spacing: 16) {
                TextField(tr("搜索名称或 PID"), text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Picker(tr("排序"), selection: $order) {
                    Text("CPU").tag("cpu")
                    Text(tr("内存")).tag("memory")
                    Text(tr("名称")).tag("name")
                }.frame(width: 170)
                Toggle(tr("仅当前用户"), isOn: $currentUserOnly)
                Spacer(minLength: 0)
            }
            Text(tr("每 2 秒更新，仅在此页采样。CPU 的 100% 表示占满一个逻辑核心，多核进程可超过 100%。内存优先显示物理占用；回退项标为“驻留”。— 表示采样中或无权限读取。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if store.processSnapshot.failed {
                Text(tr("无法读取进程列表；系统可能限制了访问。")) .foregroundStyle(.secondary)
            } else if store.processSnapshot.sampledAt == nil {
                ProgressView(tr("正在读取进程…"))
            } else {
                HStack {
                    Text("\(rows.count) \(tr("个进程"))").foregroundStyle(.secondary)
                    Spacer()
                    if let date = store.processSnapshot.sampledAt {
                        Text(date, style: .time).foregroundStyle(.secondary).monospacedDigit()
                    }
                }.font(.caption)
                HStack {
                    Text(tr("名称")).frame(maxWidth: .infinity, alignment: .leading)
                    Text("PID").frame(width: 65, alignment: .trailing)
                    Text("CPU").frame(width: 90, alignment: .trailing)
                    Text(tr("内存")).frame(width: 150, alignment: .trailing)
                }.font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 12)
                LazyVStack(spacing: 0) {
                    ForEach(rows) { process in
                        HStack(spacing: 10) {
                            Text(process.name).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(process.id.pid)).foregroundStyle(.secondary).frame(width: 65, alignment: .trailing)
                            Text(percentage(process.cpu)).frame(width: 90, alignment: .trailing)
                            Text(bytes(process.memory) + (!process.usesFootprint && process.memory != nil ? " (\(tr("驻留")))" : ""))
                                .frame(width: 150, alignment: .trailing)
                        }
                        .font(.system(size: 12)).monospacedDigit()
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        Divider().opacity(0.45)
                    }
                }.background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

struct SystemInformationView: View {
    @EnvironmentObject private var store: SensorStore
    private var identity: SystemIdentity { store.systemIdentity }
    private func count(_ value: Int?) -> String { value.map(String.init) ?? "—" }
    var body: some View {
        Page(title: "系统信息", subtitle: "机型、硬件规格与 macOS 信息",
             headerAccessory: AnyView(Button(tr("重新读取")) { store.refreshSystemInformation() }.buttonStyle(.bordered))) {
            Text(tr("硬件规格和系统版本在启动时读取，无需持续刷新。磁盘空间与运行时间每 60 秒更新，也可手动重新读取。"))
                .font(.caption).foregroundStyle(.secondary)
            Card(title: "硬件规格", symbol: "desktopcomputer", tint: .blue) {
                MetricGrid(metrics: [
                    Metric(name: "机型", value: store.system.modelName, detail: store.system.modelIdentifier),
                    Metric(name: "芯片", value: store.system.chipName),
                    Metric(name: "体系结构", value: identity.architecture),
                    Metric(name: "物理核心", value: count(identity.physicalCores)),
                    Metric(name: "逻辑核心", value: count(identity.logicalCores)),
                    Metric(name: "性能核心", value: count(identity.performanceCores)),
                    Metric(name: "能效核心", value: count(identity.efficiencyCores)),
                    Metric(name: "物理内存", value: formatBytes(store.system.memoryTotal)),
                ], tint: .blue)
                if !identity.gpuNames.isEmpty {
                    SoftDivider()
                    Text(identity.gpuNames.joined(separator: "\n")).font(.callout)
                }
            }
            Card(title: "操作系统", symbol: "macwindow", tint: .purple) {
                MetricGrid(metrics: [
                    Metric(name: "macOS 版本", value: identity.osVersion),
                    Metric(name: "系统构建号", value: identity.osBuild),
                    Metric(name: "内核版本", value: identity.kernel),
                    Metric(name: "运行时间", value: formatDuration(store.system.uptime)),
                ], tint: .purple)
                if let boot = identity.bootTime {
                    HStack { Text(tr("启动时间")); Spacer(); Text(boot.formatted(date: .abbreviated, time: .shortened)) }
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Card(title: "启动磁盘空间", symbol: "internaldrive", tint: .orange) {
                MetricGrid(metrics: [
                    Metric(name: "已用空间", value: formatBytes(store.system.diskUsed)),
                    Metric(name: "可用空间", value: formatBytes(max(0, store.system.diskTotal - store.system.diskUsed))),
                    Metric(name: "总容量", value: formatBytes(store.system.diskTotal)),
                ], tint: .orange)
            }
        }
    }
}
