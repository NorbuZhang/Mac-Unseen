// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct StorageView: View {
    @EnvironmentObject private var store: SensorStore

    var body: some View {
        Page(
            title: "存储",
            subtitle: "SSD 寿命、终身总读写量与本次开机的底层 I/O",
            headerAccessory: store.advancedSensorsActive ? nil : AnyView(
                Button {
                    store.startAdvancedSensors()
                } label: {
                    HStack(spacing: 7) {
                        if store.advancedAccessPending {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(tr(
                            store.advancedAccessPending
                                ? store.advancedAccessButtonTitle
                                : "读取终身 SMART 数据 🤫"
                        ))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.advancedAccessPending)
                .help(tr("需要管理员权限读取 NVMe SMART 寿命和终身读写计数"))
            )
        ) {
            if store.storage.disks.isEmpty {
                Card(
                    title: "正在读取存储设备",
                    symbol: "internaldrive",
                    tint: .blue
                ) {
                    MetricGrid(
                        metrics: waitingMetrics([
                            "磁盘健康度",
                            "终身总 I/O",
                            "终身总读取",
                            "终身总写入",
                            "本次已读取",
                            "本次已写入",
                        ]),
                        tint: .blue
                    )
                    Text(tr("首次读取通常需要几秒。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(store.storage.disks) { disk in
                    DiskStatusCard(
                        disk: disk,
                        smart: disk.isInternal
                            ? store.advanced.storageSMART
                            : StorageSMARTSnapshot()
                    )
                }
            }

            Card(
                title: "数据说明",
                symbol: "info.circle",
                tint: .secondary
            ) {
                Text(tr(
                    "健康度按 NVMe SMART 的 Percentage Used 计算：健康度 = 100% − 已用寿命。"
                    + "它反映 SSD 额定写入寿命的消耗程度，不是故障概率，也不能保证磁盘不会突然损坏。"
                    + "终身读写量来自 SSD 自身累计计数，本次开机 I/O 来自 macOS 驱动层，两者统计口径不同。"
                ))
                .foregroundStyle(.secondary)
            }

            HardwareUpdatedLabel(date: store.storage.updatedAt)
        }
    }
}

private struct DiskStatusCard: View {
    let disk: DiskSnapshot
    let smart: StorageSMARTSnapshot

    var body: some View {
        Card(
            title: disk.name,
            symbol: disk.isInternal ? "internaldrive.fill" : "externaldrive.fill",
            tint: disk.readErrors + disk.writeErrors == 0 ? .blue : .orange,
            info: disk.bsdName.isEmpty
                ? nil
                : (
                    AppLocalization.language == .english
                        ? "System device name: \(disk.bsdName). The app never displays the drive serial number."
                        : "系统设备名：\(disk.bsdName)。应用不会显示磁盘序列号。"
                )
        ) {
            HStack(spacing: 5) {
                Text(tr("终身 SMART 统计"))
                    .font(.headline)
                InfoButton(
                    text: "这些计数由 SSD 控制器保存，不会在普通重启后归零。读取 Apple 内置 NVMe SSD 的完整 SMART 数据需要管理员授权。"
                )
            }
            if disk.isInternal && !smart.available {
                Text(tr("启用隐藏传感器后显示健康度和终身总读写量。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            MetricGrid(
                metrics: [
                    Metric(
                        name: "磁盘健康度",
                        value: optional(smart.healthPercentage, digits: 0),
                        unit: smart.healthPercentage == nil ? "" : "%",
                        info: "按 NVMe 标准的已用寿命字段计算：100% 减去 Percentage Used。它代表额定耐久度余量，不是故障概率。"
                    ),
                    Metric(
                        name: "已用寿命",
                        value: optional(smart.percentageUsed, digits: 0),
                        unit: smart.percentageUsed == nil ? "" : "%"
                    ),
                    Metric(
                        name: "终身总 I/O",
                        value: formatBytes(
                            (smart.totalBytesRead ?? 0)
                                + (smart.totalBytesWritten ?? 0)
                        ),
                        info: "SSD 从投入使用以来累计的数据读取量与写入量之和。NVMe 以 512,000 字节为一个 Data Unit 进行统计。"
                    ),
                    Metric(
                        name: "终身总读取",
                        value: formatOptionalBytes(smart.totalBytesRead)
                    ),
                    Metric(
                        name: "终身总写入",
                        value: formatOptionalBytes(smart.totalBytesWritten)
                    ),
                    Metric(
                        name: "通电时间",
                        value: optionalHours(smart.powerOnHours)
                    ),
                    Metric(
                        name: "通电次数",
                        value: optionalInteger(smart.powerCycles),
                        unit: smart.powerCycles == nil ? "" : "次"
                    ),
                    Metric(
                        name: "异常断电",
                        value: optionalInteger(smart.unsafeShutdowns),
                        unit: smart.unsafeShutdowns == nil ? "" : "次",
                        info: "SSD 记录的非正常断电或未完成标准关机流程的次数。系统崩溃、强制断电等情况都可能增加该值。"
                    ),
                    Metric(
                        name: "介质错误",
                        value: optionalInteger(smart.mediaErrors),
                        unit: smart.mediaErrors == nil ? "" : "次"
                    ),
                    Metric(
                        name: "可用备用空间",
                        value: optional(smart.availableSpare, digits: 0),
                        unit: smart.availableSpare == nil ? "" : "%"
                    ),
                ],
                tint: smart.healthPercentage.map { $0 >= 90 ? .green : .orange }
                    ?? .blue
            )

            SoftDivider()

            HStack(spacing: 5) {
                Text(tr("本次开机以来的 I/O"))
                    .font(.headline)
                InfoButton(
                    text: "这些数值从本次 macOS 启动后开始累计，重启会归零；它们不是硬盘出厂以来的终身写入量。"
                )
            }
            MetricGrid(
                metrics: [
                    Metric(name: "已读取", value: formatBytes(disk.bytesRead)),
                    Metric(name: "已写入", value: formatBytes(disk.bytesWritten)),
                    Metric(
                        name: "读取操作",
                        value: formattedInteger(disk.readOperations),
                        unit: "次"
                    ),
                    Metric(
                        name: "写入操作",
                        value: formattedInteger(disk.writeOperations),
                        unit: "次"
                    ),
                    Metric(
                        name: "读取错误",
                        value: formattedInteger(disk.readErrors),
                        unit: "次"
                    ),
                    Metric(
                        name: "写入错误",
                        value: formattedInteger(disk.writeErrors),
                        unit: "次"
                    ),
                ],
                tint: disk.readErrors + disk.writeErrors == 0 ? .teal : .orange
            )
        }
    }
}
