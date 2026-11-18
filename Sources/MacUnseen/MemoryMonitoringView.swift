import SwiftUI

extension MemoryPressureLevel {
    var color: Color {
        switch self { case .normal: .green; case .warning: .orange; case .critical: .red }
    }
}

struct MemoryMonitoringCard: View {
    let reading: MemoryReading
    let history: MemoryPressureHistory
    let pageBytes: UInt64?
    let reports: SystemReportStore
    private var level: MemoryPressureLevel? { reading.pressure.flatMap(MemoryPressureLevel.init(rawValue:)) }

    var body: some View {
        Card(title: "内存", symbol: "memorychip", tint: .purple,
             info: "已用内存由应用、联动和压缩内存组成，可回收的文件缓存单独列出。数值根据系统内存页估算，可能与活动监视器略有差异。判断内存是否紧张应结合内存压力和交换空间，不能只看占用百分比。") {
            SpecificationGrid(rows: [("内存页大小", formatHardwareBytes(pageBytes))])
            InlineSystemReport(reports: reports, id: "SPMemoryDataType",
                               excluding: reading.total > 0 ? ["Memory"] : [])
            SoftDivider()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tr("内存压力")) .font(.headline)
                    Spacer()
                    HStack(spacing: 5) {
                        Text(reading.pressurePercent.map { "\($0)%" } ?? "—").monospacedDigit()
                        Circle().fill(level?.color ?? .secondary).frame(width: 7, height: 7)
                        Text(tr(level?.title ?? "不可用")).font(.callout.weight(.medium))
                    }
                }
                MemoryPressureGraph(history: history).frame(height: 108)
                HStack {
                    Text(history.samples.first.map { $0.date.formatted(date: .omitted, time: .standard) } ?? "—")
                    Spacer()
                    Text(tr("最近 60 次采样 · 暂停不计时"))
                    Spacer()
                    Text(history.samples.last.map { $0.date.formatted(date: .omitted, time: .standard) } ?? "—")
                }.font(.caption2).foregroundStyle(.secondary).monospacedDigit().padding(.leading, 56)
                HStack(spacing: 16) {
                    ForEach(MemoryPressureLevel.allCases, id: \.self) { level in
                        HStack(spacing: 5) {
                            Circle().fill(level.color).frame(width: 7, height: 7)
                            Text(tr(level.title))
                        }
                    }
                    Spacer()
                    Text(tr("虚线：采样暂停"))
                }.font(.caption).foregroundStyle(.secondary)
                Text(tr("高度采用活动监视器的压力曲线读数（100 减去内核内存状态值）。绿色、橙色、红色分别表示系统报告的正常、偏高和很高压力。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            SoftDivider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tr("物理内存已用比例")) .font(.headline)
                    Spacer()
                    Text(reading.fraction.map { format($0 * 100, digits: 1) + "%" } ?? "—")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                }
                if let fraction = reading.fraction {
                    ProgressView(value: min(1, max(0, fraction))).tint(.purple)
                        .accessibilityLabel(tr("物理内存已用比例"))
                }
                HStack {
                    Text(tr("已用") + " " + formatMonitoredBytes(reading.used))
                    Spacer()
                    Text(tr("总计") + " " + formatMonitoredBytes(reading.total > 0 ? reading.total : nil))
                }.font(.callout).monospacedDigit()
                Text(tr("已用 = 应用 + 联动 + 压缩内存；可回收的文件缓存单独列出。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            MetricGrid(metrics: [
                Metric(name: "应用内存", value: formatMonitoredBytes(reading.app)),
                Metric(name: "联动内存", value: formatMonitoredBytes(reading.wired)),
                Metric(name: "压缩内存", value: formatMonitoredBytes(reading.compressed)),
                Metric(name: "缓存文件", value: formatMonitoredBytes(reading.cached)),
                Metric(name: "已用交换空间", value: formatMonitoredBytes(reading.swapUsed)),
            ], tint: .purple)
        }
    }
}

struct MemoryPressureGraph: View {
    let history: MemoryPressureHistory
    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geometry in
                ForEach([0, 50, 100], id: \.self) { percent in
                    Text("\(percent)%").font(.caption2).foregroundStyle(.secondary)
                        .frame(width: geometry.size.width, alignment: .trailing)
                        .position(x: geometry.size.width / 2,
                                  y: geometry.size.height - 5 - Double(percent) / 100 * (geometry.size.height - 10))
                }
            }.frame(width: 46)
            Canvas { context, size in
                let plotHeight = size.height - 10
                for fraction in [0.0, 0.5, 1.0] {
                    var grid = Path()
                    let y = size.height - 5 - fraction * plotHeight
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(grid, with: .color(.secondary.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                let capacity = MemoryPressureHistory.capacity
                let columns = history.plotColumns.suffix(capacity)
                var previous: CGPoint?
                for (index, column) in columns.enumerated() {
                    let x = HistoryAxis.x(index: index, count: columns.count, capacity: capacity, width: size.width)
                    guard case let .sample(sample) = column else {
                        var marker = Path()
                        marker.move(to: CGPoint(x: x, y: 0))
                        marker.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(marker, with: .color(.secondary.opacity(0.65)),
                                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        previous = nil
                        continue
                    }
                    guard let percent = sample.percent else { previous = nil; continue }
                    let color = sample.level?.color ?? .secondary
                    let baseline = size.height - 5
                    let point = CGPoint(x: x, y: baseline - Double(percent) / 100 * plotHeight)
                    if let previous {
                        var line = Path()
                        line.move(to: previous)
                        line.addLine(to: point)
                        var area = line
                        area.addLine(to: CGPoint(x: point.x, y: baseline))
                        area.addLine(to: CGPoint(x: previous.x, y: baseline))
                        area.closeSubpath()
                        context.fill(area, with: .linearGradient(
                            Gradient(colors: [color.opacity(0.48), color.opacity(0.12)]),
                            startPoint: CGPoint(x: 0, y: 5), endPoint: CGPoint(x: 0, y: baseline)))
                        context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    } else {
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5,
                                                            width: 3, height: 3)), with: .color(color))
                    }
                    previous = point
                }
            }
            .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel(tr("内存压力历史"))
            .accessibilityValue(tr(history.samples.last?.level?.title ?? "不可用") + "，" + tr("最近 60 次采样 · 暂停不计时"))
        }
    }
}
