import AppKit
import SwiftUI

struct MenuMonitorPanel: View {
    @ObservedObject var monitor: MenuBarMonitor
    @EnvironmentObject private var fanControl: FanControlSession
    let maxHeight: CGFloat
    private var data: MenuReading { monitor.reading }
    private var performance: PerformanceReading { data.performance }
    private var overview: Bool { monitor.metric == .overview }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Mac Unseen").font(.title3.bold())
                Spacer()
                if let date = data.sampledAt {
                    Text(date, format: .dateTime.hour().minute().second()).font(.caption).foregroundStyle(.secondary)
                }
                Button { monitor.sample() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help(tr("立即刷新")).accessibilityLabel(tr("立即刷新"))
            }
            Picker(tr("监测项目"), selection: Binding(get: { monitor.metric }, set: monitor.selectMetric)) {
                ForEach(MenuMetric.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.menu)
            if overview {
                Picker(tr("菜单栏读数"), selection: Binding(get: { monitor.overviewMetric }, set: monitor.selectOverviewMetric)) {
                    Text(tr("仅显示图标")).tag(MenuMetric.overview)
                    ForEach(MenuMetric.allCases.filter { $0 != .overview }, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.menu)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if overview || monitor.metric == .cpu {
                        rows(.cpu, [
                            ("CPU 占用", MenuReading.value(performance.cpu, unit: "%", digits: 1)),
                            ("1 / 5 / 15 分钟负载", performance.loadAverages.isEmpty ? "—" :
                                performance.loadAverages.map { String(format: "%.2f", $0) }.joined(separator: " / "))
                        ])
                    }
                    if overview || monitor.metric.performanceMetrics == [.gpu] {
                        group(.gpu) {
                            if performance.gpus.isEmpty {
                                Text(tr("当前驱动未提供 GPU 占用数据。")).font(.callout).foregroundStyle(.secondary)
                            }
                            ForEach(performance.gpus) { gpu in
                                Text(gpu.name).font(.callout.weight(.medium))
                                fields([("GPU 核心数", gpu.cores.map(String.init) ?? "—")])
                                metricRow(.gpu, label: "GPU 占用", value: MenuReading.value(gpu.utilization, unit: "%", digits: 1))
                                metricRow(.renderer, value: MenuReading.value(gpu.renderer, unit: "%", digits: 1))
                                metricRow(.tiler, value: MenuReading.value(gpu.tiler, unit: "%", digits: 1))
                                fields([("GPU 分配内存", formatMonitoredBytes(gpu.allocatedMemory))])
                            }
                        }
                    }
                    if overview || monitor.metric == .memory {
                        rows(.memory, [
                            ("内存压力", data.title(for: .memory, fans: nil) + " · " +
                                tr(performance.memory.pressure.flatMap(MemoryPressureLevel.init)?.title ?? "不可用")),
                            ("已用 / 总内存", formatMonitoredBytes(performance.memory.used) + " / " +
                                formatMonitoredBytes(performance.memory.total > 0 ? performance.memory.total : nil)),
                            ("压缩内存", formatMonitoredBytes(performance.memory.compressed)),
                            ("已用交换空间", formatMonitoredBytes(performance.memory.swapUsed))
                        ])
                    }
                    if overview || monitor.metric.section == .battery {
                        group(.battery) {
                            metricRow(.battery, label: "电量")
                            fields([("供电状态", powerState)])
                            metricRow(.power)
                            fields([
                                ("实时输入电压", MenuReading.value(data.battery?.liveInputVoltage, unit: " V", digits: 2)),
                                ("实时输入电流", MenuReading.value(data.battery?.liveInputCurrent, unit: " A", digits: 2)),
                                ("电池温度", MenuReading.value(data.battery?.temperature, unit: " °C", digits: 1))
                            ])
                        }
                    }
                    if overview || monitor.metric.section == .network {
                        group(.network, title: DashboardSection.network.title) {
                            metricRow(.network)
                            metricRow(.upload)
                        }
                    }
                    if overview || monitor.metric.section == .storage {
                        group(.storage, title: DashboardSection.storage.title) {
                            metricRow(.storage)
                            metricRow(.diskWrite)
                            fields([("已用 / 总容量", data.system.flatMap { $0.diskTotal > 0 ?
                                formatMonitoredBytes($0.diskUsed) + " / " + formatMonitoredBytes($0.diskTotal) : nil } ?? "—")])
                        }
                    }
                    if overview || monitor.metric == .temperature {
                        rows(.temperature, thermalRows)
                    }
                    if overview || monitor.metric == .fans { group(.fans) { FanControls() } }
                    if overview || monitor.metric == .lidAngle {
                        group(.lidAngle) {
                            metricRow(.lidAngle, label: "当前角度")
                            if !overview, let angle = data.lidAngle {
                                LidAngleDiagram(angle: Double(angle))
                                    .frame(width: 200, height: 78)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    if overview || monitor.metric == .systemInfo {
                        rows(.systemInfo, [("芯片", data.system?.chipName ?? "—"),
                                           ("运行时间", data.uptime.map(formatDuration) ?? "—")],
                             title: DashboardSection.systemInfo.title)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }.id(monitor.metric)
            Divider()
            HStack {
                Button(tr("打开主窗口")) { monitor.showSection(monitor.metric.section) }
                Spacer()
                MenuMonitorToggle(monitor: monitor).toggleStyle(.switch)
                Button(tr("退出 Mac Unseen")) { NSApp.terminate(nil) }
            }.controlSize(.small)
        }
        .padding(14)
        .frame(width: 382, height: min(maxHeight, preferredHeight))
    }

    private var preferredHeight: CGFloat {
        switch monitor.metric {
        case .overview: 570
        case .fans: fanControl.status?.fans.isEmpty == false ? 525 : 290
        case .gpu, .renderer, .tiler: performance.gpus.count > 1 ? 530 : 342
        case .lidAngle: 305
        case .battery, .power: 354
        case .memory: 312
        default: 280
        }
    }

    private var thermalRows: [(String, String)] {
        var rows = [("热状态", data.system.map { tr($0.thermalState) } ?? "—")]
        if let status = fanControl.status {
            rows += [("CPU", MenuReading.value(status.cpuTemp, unit: " °C", digits: 1)),
                     ("GPU", MenuReading.value(status.gpuTemp, unit: " °C", digits: 1))]
        }
        return rows
    }

    private func metricRow(_ choice: MenuMetric, label: String? = nil, value: String? = nil) -> some View {
        let name = label.map(tr) ?? choice.title
        let current = choice == monitor.statusMetric
        return Button {
            if overview { monitor.selectOverviewMetric(choice) }
            else { monitor.selectMetric(choice) }
        } label: {
            HStack {
                Text(name)
                Spacer()
                Text(value ?? data.title(for: choice, fans: fanControl.status)).monospacedDigit()
                Image(systemName: current ? "pin.fill" : "pin")
                    .font(.caption2).foregroundStyle(current ? Color.accentColor : Color.secondary)
            }.contentShape(Rectangle())
        }
        .font(.callout).buttonStyle(.plain)
        .help(tr("在菜单栏显示") + " · " + name)
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private var powerState: String {
        guard let battery = data.battery, battery.percentage != nil || battery.externalConnected else { return "—" }
        return tr(battery.charging ? "正在充电" : battery.externalConnected ? "外接电源" : "电池供电")
    }

    private func fields(_ pairs: [(String, String)]) -> some View {
        ForEach(pairs.indices, id: \.self) { index in
            LabeledContent(tr(pairs[index].0)) {
                Text(pairs[index].1).monospacedDigit().multilineTextAlignment(.trailing).textSelection(.enabled)
            }.font(.callout)
        }
    }

    private func rows(_ choice: MenuMetric, _ pairs: [(String, String)], title: String? = nil) -> some View {
        group(choice, title: title) { fields(pairs) }
    }

    private func group<Content: View>(_ choice: MenuMetric, title: String? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if overview {
                Button { monitor.selectMetric(choice) } label: {
                    HStack {
                        Label(title ?? choice.title, systemImage: choice.symbol)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).font(.headline)
            } else {
                Label(title ?? choice.title, systemImage: choice.symbol).font(.headline)
            }
            content()
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}
