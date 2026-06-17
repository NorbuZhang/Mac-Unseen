// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct BatteryView: View {
    @EnvironmentObject private var store: SensorStore

    private var overviewTint: Color {
        guard let percentage = store.battery.percentage else {
            return .green
        }
        if percentage < 10 {
            return .red
        }
        if percentage < 20 {
            return .orange
        }
        return .green
    }

    var body: some View {
        Page(
            title: "电池与电源",
            subtitle: "电池状态、寿命记录、供电来源和 USB-C PD 信息"
        ) {
            Card(
                title: "总览",
                symbol: "gauge.with.dots.needle.67percent",
                tint: overviewTint
            ) {
                MetricGrid(
                    metrics: [
                        Metric(
                            name: "电量",
                            value: optional(store.battery.percentage, digits: 0),
                            unit: "%",
                            info: "电池管理系统估算的剩余电量百分比。它是根据电池电压、电流和历史状态计算的估计值，短时间内不一定线性变化。"
                        ),
                        Metric(
                            name: "循环次数",
                            value: store.battery.cycleCount.map(String.init) ?? "-",
                            info: "累计使用相当于 100% 电池容量算一个循环，不要求一次从满电用到没电。例如两次各使用 50%，大约合计一个循环。"
                        ),
                        Metric(
                            name: "当前温度",
                            value: optional(store.battery.temperature, digits: 1),
                            unit: "°C",
                            info: "电池组当前温度。充电、持续高负载和较高环境温度都会让它升高。与单次峰值相比，长时间处在高温环境对电池寿命更值得关注。"
                        ),
                        Metric(
                            name: "实时功率",
                            value: optional(batteryPower(store.battery), digits: 2),
                            unit: "W",
                            info: "这是用电池实时电压乘以电流估算出的功率，并取绝对值方便阅读。它可以粗略理解为电池此刻充入或输出能量的速度：数值越大，通常代表充电更快，或电脑正在消耗更多电量。"
                        ),
                        Metric(
                            name: "供电来源",
                            value: store.battery.externalConnected
                                ? "外接电源"
                                : "电池供电",
                            info: "显示 Mac 当前是否检测到充电器或其他外接供电。接入电源不一定代表正在给电池充电，系统也可能只使用外部电源维持运行。"
                        ),
                        Metric(
                            name: "充电状态",
                            value: store.battery.charging ? "正在充电" : "未充电",
                            info: "显示电池此刻是否正在接收充电电流。即使接着充电器，电量已满、电池温度较高或系统启用优化充电时，也可能显示未充电。"
                        ),
                    ],
                    tint: overviewTint
                )
            }
            .animation(.easeInOut(duration: 0.6), value: overviewTint)

            Card(title: "历史极值", symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90", tint: .orange) {
                MetricGrid(
                    metrics: [
                        Metric(
                            name: "最低温度",
                            value: optional(store.battery.historicalMinTemperature, digits: 0),
                            unit: "°C"
                        ),
                        Metric(
                            name: "最高温度",
                            value: optional(store.battery.historicalMaxTemperature, digits: 0),
                            unit: "°C"
                        ),
                        Metric(
                            name: "最大充电电流",
                            value: optional(store.battery.historicalMaxChargeCurrent, digits: 2),
                            unit: "A"
                        ),
                        Metric(
                            name: "最大放电电流",
                            value: optional(store.battery.historicalMaxDischargeCurrent, digits: 2),
                            unit: "A"
                        ),
                    ],
                    tint: .orange
                )
            }

            Card(title: "容量", symbol: "chart.bar.fill", tint: .teal) {
                MetricGrid(
                    metrics: [
                        Metric(
                            name: "设计容量",
                            value: optional(store.battery.designCapacity, digits: 0),
                            unit: "mAh"
                        ),
                        Metric(
                            name: "最大容量",
                            value: optional(store.battery.maximumCapacity, digits: 0),
                            unit: "mAh",
                            info: "电池管理系统提供的 NominalChargeCapacity。它经过平滑处理，用于表示电池当前预计充满时可容纳的电量。新电池可能略高于标称设计容量。"
                        ),
                        Metric(
                            name: "补偿容量",
                            value: optional(
                                store.battery.rawMaximumCapacity,
                                digits: 0
                            ),
                            unit: "mAh",
                            info: "底层 AppleRawMaxCapacity，也称补偿后的满充容量。它会随温度、荷电状态和电池模型校准发生短期波动，因此不再直接用于计算系统健康度。"
                        ),
                        Metric(
                            name: "当前原始电量",
                            value: optional(store.battery.rawCurrentCapacity, digits: 0),
                            unit: "mAh"
                        ),
                        Metric(
                            name: "健康度",
                            value: batteryHealth(store.battery),
                            unit: "%",
                            info: "使用最大容量除以设计容量得到的实际比例，不再封顶为 100%。新电池实际容量高于标称设计容量时，健康度可能显示为 100% 以上。"
                        ),
                    ],
                    tint: .teal
                )
            }

            Card(title: "电芯状态", symbol: "batteryblock", tint: .green) {
                if store.battery.cellVoltages.isEmpty {
                    Text(tr("未读取到电芯数据。"))
                        .foregroundStyle(.secondary)
                } else {
                    MetricGrid(
                        metrics: store.battery.cellVoltages.enumerated().map {
                            Metric(
                                name: AppLocalization.language == .english
                                    ? "Cell \($0.offset + 1)"
                                    : "电芯 \($0.offset + 1)",
                                value: format($0.element, digits: 3),
                                unit: "V",
                                detail: store.battery.cellResistance.indices.contains($0.offset)
                                    ? (
                                        AppLocalization.language == .english
                                            ? "Resistance index \(format(store.battery.cellResistance[$0.offset], digits: 0))"
                                            : "阻抗指标 \(format(store.battery.cellResistance[$0.offset], digits: 0))"
                                    )
                                    : nil
                            )
                        },
                        tint: .green
                    )
                    let spread = (store.battery.cellVoltages.max() ?? 0)
                        - (store.battery.cellVoltages.min() ?? 0)
                    Text(
                        AppLocalization.language == .english
                            ? "Cell spread: \(format(spread * 1000, digits: 0)) mV"
                            : "电芯压差：\(format(spread * 1000, digits: 0)) mV"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Card(title: "充电器与实时输入", symbol: "powerplug.fill", tint: .blue) {
                Text(tr(store.battery.adapterName ?? "未连接充电器"))
                    .font(.headline)
                MetricGrid(
                    metrics: [
                        Metric(
                            name: "额定功率",
                            value: optional(store.battery.adapterRatedWatts, digits: 0),
                            unit: "W"
                        ),
                        Metric(
                            name: "协商电压",
                            value: optional(store.battery.negotiatedVoltage, digits: 1),
                            unit: "V"
                        ),
                        Metric(
                            name: "协商上限电流",
                            value: optional(store.battery.negotiatedCurrent, digits: 2),
                            unit: "A"
                        ),
                        Metric(
                            name: "实时输入功率",
                            value: optional(store.battery.liveInputPower, digits: 2),
                            unit: "W"
                        ),
                        Metric(
                            name: "实时输入电压",
                            value: optional(store.battery.liveInputVoltage, digits: 2),
                            unit: "V"
                        ),
                        Metric(
                            name: "实时输入电流",
                            value: optional(store.battery.liveInputCurrent, digits: 3),
                            unit: "A"
                        ),
                    ],
                    tint: .blue
                )
            }

            Card(title: "充电器公布的 USB-C PD 档位", symbol: "list.number", tint: .blue) {
                if store.battery.pdProfiles.isEmpty {
                    Text(tr("当前没有可显示的 PD 档位。"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(store.battery.pdProfiles.enumerated()), id: \.offset) { index, profile in
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            Text(profile)
                            Spacer()
                            if store.battery.negotiatedVoltage.map({
                                profile.hasPrefix(String(format: "%.0fV", $0))
                            }) == true {
                                Text(tr("当前"))
                                    .font(.caption.bold())
                                    .foregroundStyle(.blue)
                            }
                        }
                        SoftDivider()
                    }
                }
            }
        }
    }
}
