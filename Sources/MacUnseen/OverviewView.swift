import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: SensorStore

    var body: some View {
        Page(
            title: "Mac Unseen",
            subtitle: store.launchMotto,
            headerAccessory: store.advancedSensorsActive ? nil : AnyView(
                Button {
                    store.startAdvancedSensors()
                } label: {
                    HStack(spacing: 7) {
                        if store.advancedAccessPending {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(tr(store.advancedAccessButtonTitle))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.advancedAccessPending)
                .help(tr("向 macOS 请求管理员权限，只读访问屏幕角度、运动、温度、风扇和功耗数据"))
            )
        ) {
            Card(title: store.system.modelName, symbol: "laptopcomputer", tint: .blue) {
                Text(store.system.chipName)
                    .font(.title3.weight(.semibold))
                Text(store.system.modelIdentifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                SoftDivider()
                PerformanceSummary()
                HStack(spacing: 18) {
                    Button(tr("查看实时性能")) { store.selectedSection = .performance }
                    Button(tr("查看进程")) { store.selectedSection = .processes }
                    Button(tr("查看系统信息")) { store.selectedSection = .systemInfo }
                }.buttonStyle(.link).font(.callout)
            }

            if store.advancedSensorsActive {
                let powerMetrics = store.advanced.telemetry["Power"] ?? []
                let powerCapability =
                    store.advanced.capabilities["power"]
                Card(
                    title: "实时功耗",
                    symbol: "bolt.fill",
                    tint: .orange,
                    info: "这里显示 Mac 当前各部分消耗或传输的电功率，单位是瓦（W）。数值越高，通常表示芯片负载、屏幕亮度、充电活动或外设供电越多。它是即时读数，会随着使用状态快速变化。"
                ) {
                    if powerMetrics.isEmpty
                        && (powerCapability == "unsupported"
                            || powerCapability == "unreadable") {
                        CapabilityNotice(
                            capability: powerCapability,
                            unsupported: "此机型没有返回可访问的功耗传感器",
                            unreadable: "检测到功耗传感器，但当前无法读取"
                        )
                    } else {
                        MetricGrid(
                            metrics: powerMetrics.isEmpty
                                ? waitingMetrics([
                                    "DC In",
                                    "System Total",
                                    "Heatpipe",
                                    "Power Delivery Brightness",
                                ])
                                : powerMetrics,
                            tint: .orange
                        )
                    }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                Card(
                    title: "隐藏传感器",
                    symbol: "sensor",
                    tint: .purple
                ) {
                    FeatureRow(symbol: "move.3d", title: "Bosch BMI286", detail: "加速度计 + 陀螺仪")
                    FeatureRow(symbol: "laptopcomputer", title: "MagAlpha ma981", detail: "屏幕铰链角度")
                    FeatureRow(symbol: "sun.max", title: "Redbird ALS", detail: "照度 + 四路光谱")
                    FeatureRow(symbol: "thermometer", title: "TI TMP114", detail: "独立温度传感器")
                }
                Card(
                    title: "当前状态",
                    symbol: "checklist",
                    tint: .green
                ) {
                    FeatureRow(
                        symbol: store.advancedSensorsActive ? "checkmark.circle.fill" : "circle",
                        title: "高级采集",
                        detail: store.advancedSensorsActive ? "实时运行" : "尚未启用"
                    )
                    FeatureRow(
                        symbol: store.trackpadDetails.running ? "checkmark.circle.fill" : "circle",
                        title: "触控板原始数据",
                        detail: store.trackpadDetails.running ? "实时运行" : "不可用"
                    )
                    FeatureRow(
                        symbol: "battery.75percent",
                        title: "电池内部数据",
                        detail: "无需管理员权限"
                    )
                    FeatureRow(
                        symbol: "desktopcomputer",
                        title: "基础系统数据",
                        detail: "实时运行"
                    )
                }
            }
            if !store.advancedSensorsActive, let message = store.authorizationMessage {
                Text(tr(message))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(tr(title))
                    .fontWeight(.medium)
                Text(tr(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
