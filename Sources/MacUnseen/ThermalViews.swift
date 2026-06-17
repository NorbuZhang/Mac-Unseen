// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct TemperatureView: View {
    @EnvironmentObject private var store: SensorStore

    var body: some View {
        Page(
            title: "温度",
            subtitle: "来自 SMC 与 HID Sensor Hub 的温度传感器"
        ) {
            if store.advancedSensorsActive {
                let temperatureMetrics =
                    store.advanced.telemetry["Temperature"] ?? []
                let capability =
                    store.advanced.capabilities["temperature"]
                if temperatureMetrics.isEmpty
                    && (capability == "unsupported"
                        || capability == "unreadable") {
                    Card(
                        title: "温度传感器",
                        symbol: "thermometer.medium",
                        tint: .orange
                    ) {
                        CapabilityNotice(
                            capability: capability,
                            unsupported: "此机型没有返回可访问的温度传感器",
                            unreadable: "检测到温度传感器，但当前无法读取"
                        )
                    }
                } else {
                    let groups = temperatureGroups(temperatureMetrics)
                    ForEach(groups) { group in
                        CollapsibleTemperatureGroup(
                            group: group,
                            error: store.advanced.collectorErrors["temperature"]
                        )
                    }
                    AdvancedErrorsCard(errors: store.advanced.errors)
                }
            } else {
                AdvancedAccessCard()
            }
        }
    }
}

struct FansView: View {
    @EnvironmentObject private var store: SensorStore

    var body: some View {
        Page(
            title: "风扇",
            subtitle: "当前转速、目标转速与硬件限制"
        ) {
            if store.advancedSensorsActive {
                let fanCapability = store.advanced.capabilities["fans"]
                let fanMetrics = store.advanced.telemetry["Fans"] ?? []
                let fanCount = fanMetrics.first {
                    $0.name == "Fan Count"
                }.flatMap {
                    Int(Double($0.value) ?? -1)
                }
                let currentSpeeds = fanMetrics.filter {
                    $0.detail?.hasSuffix("Ac") == true
                        || $0.name.localizedCaseInsensitiveContains("Current Speed")
                }
                if fanCapability == "unsupported" {
                    Card(
                        title: "风扇",
                        symbol: "fan",
                        tint: .cyan
                    ) {
                        CapabilityNotice(
                            capability: fanCapability,
                            unsupported: "此机型采用无风扇设计，没有风扇硬件",
                            unreadable: "检测到风扇硬件，但当前无法访问"
                        )
                    }
                } else {
                    Card(
                        title: "实时转速",
                        symbol: "fan.fill",
                        tint: .cyan,
                        info: "这是风扇此刻真正的转速，单位为 RPM（每分钟转数）。0 RPM 表示风扇当前停转，属于 Apple Silicon Mac 在温度较低时的正常状态；负载或温度升高后，转速会自动上升。"
                    ) {
                        if currentSpeeds.isEmpty {
                            MetricGrid(
                                metrics: unavailableMetrics(
                                    (1...max(fanCount ?? 1, 1)).map {
                                        "风扇 \($0)"
                                    },
                                    capability: fanCapability
                                ),
                                tint: .cyan
                            )
                            if let error = store.advanced.collectorErrors["fans"] {
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        } else {
                            MetricGrid(metrics: currentSpeeds, tint: .cyan)
                        }
                    }
                    TelemetrySection(
                        title: "转速范围",
                        symbol: "fan",
                        metrics: fanMetrics.filter {
                            $0.detail?.hasSuffix("Ac") != true
                                && !$0.name.localizedCaseInsensitiveContains("Current Speed")
                                && $0.name != "Fan Count"
                        },
                        tint: .cyan,
                        limit: 20
                    )
                }
                AdvancedErrorsCard(errors: store.advanced.errors)
            } else {
                AdvancedAccessCard()
            }
        }
    }
}

private struct TemperatureGroup: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
    let explanation: String
    let metrics: [Metric]
}

private struct CollapsibleTemperatureGroup: View {
    @EnvironmentObject private var store: SensorStore
    let group: TemperatureGroup
    let error: String?

    private var isExpanded: Bool {
        store.isTemperatureGroupExpanded(group.id)
    }

    private var maximum: String {
        let values = group.metrics.compactMap { Double($0.value) }
        guard let value = values.max() else {
            return "-"
        }
        return "\(format(value, digits: 1)) °C"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    toggleExpanded()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: group.symbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(
                                LinearGradient(
                                    colors: [
                                        group.tint.opacity(0.95),
                                        group.tint.opacity(0.65),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                            .shadow(
                                color: group.tint.opacity(0.18),
                                radius: 5,
                                y: 2
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr(group.title))
                                .font(.headline)
                            Text(
                                group.metrics.isEmpty
                                    ? tr("等待首次读取")
                                    : (
                                        AppLocalization.language == .english
                                            ? "\(group.metrics.count) sensors"
                                            : "\(group.metrics.count) 个传感器"
                                    )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 48,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                InfoButton(text: group.explanation)

                Button {
                    toggleExpanded()
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(maximum)
                                .font(.headline.monospacedDigit())
                            Text(tr("组内最高"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 32, height: 48)
                    }
                    .frame(minWidth: 112, minHeight: 48, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                Group {
                    if group.metrics.isEmpty {
                        MetricGrid(
                            metrics: waitingMetrics([
                                "传感器 1",
                                "传感器 2",
                                "传感器 3",
                            ]),
                            tint: group.tint
                        )
                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        MetricGrid(metrics: group.metrics, tint: group.tint)
                    }
                }
                .padding(.top, 14)
            }
        }
        .padding(19)
        .cardSurface(tint: group.tint)
    }

    private func toggleExpanded() {
        store.setTemperatureGroup(group.id, expanded: !isExpanded)
    }
}

private func temperatureGroups(_ metrics: [Metric]) -> [TemperatureGroup] {
    let definitions: [(String, String, String, Color, String)] = [
        (
            "cpu",
            "处理器",
            "cpu",
            .red,
            "这一组主要来自 CPU 核心、CPU 集群、封装和热管附近。短时间高温通常是高负载的正常结果；更值得关注的是温度是否长期维持很高，以及系统是否同时出现风扇高速或性能下降。"
        ),
        (
            "gpu",
            "图形处理器",
            "square.stack.3d.up.fill",
            .purple,
            "这一组反映 GPU 核心、图形互连和散热部件附近的温度。运行游戏、视频处理、三维渲染或机器学习任务时通常会明显升高。"
        ),
        (
            "memory",
            "内存",
            "memorychip",
            .indigo,
            "这一组反映统一内存、内存附近区域和供电调节器的温度。大量读写、图形任务或持续高负载时可能升高。"
        ),
        (
            "storage",
            "存储",
            "internaldrive",
            .blue,
            "这一组来自 SSD、NAND 闪存和存储控制器。复制大文件、安装软件或进行大量磁盘读写时，温度通常会上升。"
        ),
        (
            "power",
            "电池与供电",
            "bolt.fill",
            .orange,
            "这一组来自电池、电源管理和 USB-C 供电芯片。充电、连接高功率适配器或整机负载较高时，部分传感器会升温。"
        ),
        (
            "environment",
            "机身与环境",
            "laptopcomputer",
            .teal,
            "这一组位于机身边缘、进出风区域、接口和环境附近，更接近你可能触摸到的外壳或周围空气温度。"
        ),
        (
            "soc",
            "主板与 SoC",
            "point.3.connected.trianglepath.dotted",
            AppPalette.accent,
            "这一组包含 SoC 内部、PMU、主板二极管和虚拟汇总传感器。名称较底层，主要用于观察整体热分布，不建议只凭单个编号判断硬件状态。"
        ),
    ]

    var grouped = Dictionary(uniqueKeysWithValues: definitions.map { ($0.0, [Metric]()) })
    for metric in metrics {
        grouped[temperatureCategory(for: metric.name), default: []].append(metric)
    }

    return definitions.map { id, title, symbol, tint, explanation in
        return TemperatureGroup(
            id: id,
            title: title,
            symbol: symbol,
            tint: tint,
            explanation: explanation,
            metrics: grouped[id] ?? []
        )
    }
}

func temperatureCategory(for name: String) -> String {
    let value = name.lowercased()
    if value.contains("gpu") {
        return "gpu"
    }
    if value.contains("cpu") || value.contains("heatpipe") {
        return "cpu"
    }
    if value.contains("memory") {
        return "memory"
    }
    if value.contains("ssd") || value.contains("nand") || value.contains("nvme") {
        return "storage"
    }
    if value.contains("battery")
        || value.contains("power")
        || value.contains("voltage")
        || value.contains("delivery")
        || value.contains("rf ") {
        return "power"
    }
    if value.contains("airflow")
        || value.contains("ambient")
        || value.contains("thunderbolt")
        || value.contains("airport")
        || value.contains("board diode") {
        return "environment"
    }
    return "soc"
}

private struct AdvancedErrorsCard: View {
    let errors: [String]

    @ViewBuilder
    var body: some View {
        if !errors.isEmpty {
            Card(title: "采集提示", symbol: "exclamationmark.circle", tint: .orange) {
                ForEach(errors, id: \.self) { error in
                    Text(error)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct TelemetrySection: View {
    let title: String
    let symbol: String
    let metrics: [Metric]
    let tint: Color
    let limit: Int

    var body: some View {
        Card(title: title, symbol: symbol, tint: tint) {
            if metrics.isEmpty {
                MetricGrid(
                    metrics: waitingMetrics([
                        "最低转速",
                        "目标转速",
                        "最高转速",
                    ]),
                    tint: tint
                )
            } else {
                MetricGrid(metrics: Array(metrics.prefix(limit)), tint: tint)
                if metrics.count > limit {
                    Text(
                        AppLocalization.language == .english
                            ? "Showing \(limit) of \(metrics.count) readings."
                            : "显示前 \(limit) 项，共 \(metrics.count) 项。"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
