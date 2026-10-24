import SwiftUI

extension MemoryPressureLevel {
    var color: Color {
        switch self { case .normal: .green; case .warning: .yellow; case .critical: .red }
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
                Text(tr("曲线记录系统报告的压力等级，不是内存占用百分比。切换页面或进入后台时保留已有样本，返回后继续；暂停时间压缩为虚线，空白表示无数据。"))
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
                ForEach(MemoryPressureLevel.allCases, id: \.self) { level in
                    Text(tr(level.title)).font(.caption2).foregroundStyle(.secondary)
                        .frame(width: geometry.size.width, alignment: .trailing)
                        .position(x: geometry.size.width / 2,
                                  y: geometry.size.height - level.chartLevel / 3 * (geometry.size.height - 10))
                }
            }.frame(width: 46)
            Canvas { context, size in
                let plotHeight = size.height - 10
                for level in [1.0, 2.0, 3.0] {
                    var grid = Path()
                    let y = size.height - level / 3 * plotHeight
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(grid, with: .color(.secondary.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                let columns = history.plotColumns
                let count = max(MemoryPressureHistory.capacity, columns.count)
                let width = size.width / Double(count)
                let leading = count - columns.count
                var previousY: CGFloat?
                for (index, column) in columns.enumerated() {
                    let x = Double(leading + index) * width
                    guard case let .sample(sample) = column else {
                        var marker = Path()
                        marker.move(to: CGPoint(x: x + width / 2, y: 0))
                        marker.addLine(to: CGPoint(x: x + width / 2, y: size.height))
                        context.stroke(marker, with: .color(.secondary.opacity(0.65)),
                                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        previousY = nil
                        continue
                    }
                    guard let level = sample.level else { previousY = nil; continue }
                    let height = level.chartLevel / 3 * plotHeight
                    let rect = CGRect(x: x, y: size.height - height, width: width, height: height)
                    context.fill(Path(rect), with: .color(level.color.opacity(0.24)))
                    context.fill(Path(CGRect(x: x, y: rect.minY, width: width, height: 2)), with: .color(level.color))
                    if let previousY, previousY != rect.minY {
                        var edge = Path()
                        edge.move(to: CGPoint(x: x, y: previousY))
                        edge.addLine(to: CGPoint(x: x, y: rect.minY))
                        context.stroke(edge, with: .color(level.color), lineWidth: 1.5)
                    }
                    previousY = rect.minY
                }
            }
            .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel(tr("内存压力历史"))
            .accessibilityValue(tr(history.samples.last?.level?.title ?? "不可用") + "，" + tr("最近 60 次采样 · 暂停不计时"))
        }
    }
}
