// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct MotionView: View {
    @EnvironmentObject private var store: SensorStore

    private var orientationMetrics: [Metric] {
        guard let orientation = store.advanced.motion.orientation else {
            let statuses = [
                store.advanced.capabilities["accelerometer"],
                store.advanced.capabilities["gyroscope"],
            ]
            let capability = statuses.contains("unsupported")
                ? "unsupported"
                : statuses.contains("unreadable") ? "unreadable" : nil
            return unavailableMetrics(
                ["横滚 Roll", "俯仰 Pitch", "相对偏航 Yaw"],
                capability: capability
            )
        }
        return [
            Metric(
                name: "横滚 Roll",
                value: format(orientation.roll, digits: 1),
                unit: "°",
                info: "表示机身向左或向右倾斜的角度。可以把它想象成飞机左右压低机翼：水平放置时通常接近 0°，左侧或右侧抬高时会向正值或负值变化。"
            ),
            Metric(
                name: "俯仰 Pitch",
                value: format(orientation.pitch, digits: 1),
                unit: "°",
                info: "表示机身前端或后端抬起的角度。可以把它想象成飞机抬头或低头：水平放置时通常接近 0°，垫高掌托或转轴一侧时会变化。"
            ),
            Metric(
                name: "相对偏航 Yaw",
                value: format(orientation.yaw, digits: 1),
                unit: "°",
                info: "表示 Mac 在桌面上向左或向右转了多少度。它把本次启动高级传感器时的朝向当作 0°，之后通过陀螺仪不断累加旋转量。这里没有磁力计帮助校正方向，所以它不是指南针；即使电脑不动，误差也会慢慢累积，数值可能随时间轻微漂移。"
            ),
        ]
    }

    var body: some View {
        Page(
            title: "运动与震动",
            subtitle: "读取机身内部 BMI286 IMU，采样频率可在 25–200 Hz 间调整"
        ) {
            if store.advancedSensorsActive {
                HStack(alignment: .top, spacing: 16) {
                    VectorCard(
                        title: "三轴加速度",
                        symbol: "move.3d",
                        reading: store.advanced.motion.accelerometer,
                        capability: store.advanced.capabilities["accelerometer"],
                        unit: "g",
                        tint: .blue,
                        info: "它可以理解为 Mac 感受到的“推、拉和震动”。X、Y、Z 分别代表机身三个方向；即使电脑静止，传感器也会读到地球重力，所以其中一个方向通常接近 1 g，三个方向合起来也大约是 1 g。移动电脑、敲击桌面或扬声器振动时，数字会立即变化。"
                    )
                    VectorCard(
                        title: "三轴角速度",
                        symbol: "gyroscope",
                        reading: store.advanced.motion.gyroscope,
                        capability: store.advanced.capabilities["gyroscope"],
                        unit: "°/s",
                        tint: .purple,
                        info: "它测量 Mac 正在“转得多快”，而不是已经转到了多少度。X、Y、Z 对应绕机身三个方向旋转，单位 °/s 表示每秒旋转多少度。电脑静止时应接近 0；抬起、转动或晃动电脑时，数值会增大。"
                    )
                }

                Card(title: "机身姿态估算", symbol: "rotate.3d", tint: .indigo) {
                    MetricGrid(metrics: orientationMetrics, tint: .indigo)
                }

                Card(title: "机身震动", symbol: "waveform.path", tint: .orange) {
                    let accelerationCapability =
                        store.advanced.capabilities["accelerometer"]
                    HStack {
                        HStack(spacing: 5) {
                            Text(tr("动态加速度趋势"))
                                .font(.subheadline.weight(.medium))
                            InfoButton(
                                text: "这条曲线把三个方向的动态加速度合成一个容易观察的震动强度。程序会尽量扣除静止时约 1 g 的重力影响；曲线越高，表示机身在最近一刻震动得越明显。敲击桌面、移动电脑、扬声器播放低频声音或附近设备运转都可能让曲线上升。"
                            )
                        }
                        Spacer()
                        Picker(tr("目标采样频率"), selection: $store.targetIMUSampleRate) {
                            Text("25 Hz").tag(25)
                            Text("50 Hz").tag(50)
                            Text("100 Hz").tag(100)
                            Text("200 Hz").tag(200)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 100)
                        .help(tr("设置加速度计和陀螺仪的目标采样频率"))
                    }
                    if accelerationCapability == "unsupported"
                        || accelerationCapability == "unreadable" {
                        CapabilityNotice(
                            capability: accelerationCapability,
                            unsupported: "此机型没有可访问的机身运动传感器",
                            unreadable: "检测到机身运动传感器，但当前无法访问"
                        )
                    } else {
                        Sparkline(
                            values: store.vibrationHistory,
                            tint: .orange
                        )
                        .frame(height: 110)
                    }
                    MetricGrid(
                        metrics: accelerationCapability == "unsupported"
                            || accelerationCapability == "unreadable"
                            ? unavailableMetrics(
                                ["动态 RMS", "近期峰值", "实际采样频率"],
                                capability: accelerationCapability
                            )
                            : [
                                Metric(
                                    name: "动态 RMS",
                                    value: format(store.advanced.motion.vibrationRMS, digits: 5),
                                    unit: "g"
                                ),
                                Metric(
                                    name: "近期峰值",
                                    value: format(store.advanced.motion.vibrationPeak, digits: 4),
                                    unit: "g"
                                ),
                                Metric(
                                    name: "实际采样频率",
                                    value: format(store.advanced.motion.sampleRate, digits: 0),
                                    unit: "Hz",
                                    info: "表示程序每秒实际收到多少次传感器读数。比如 100 Hz 大约等于每秒读取 100 次。频率越高，越容易捕捉短促震动，但会产生更多数据和少量额外开销。由于系统调度和硬件节奏，实际值与所选目标相差一两次属于正常现象。"
                                ),
                            ],
                        tint: .orange
                    )
                }
            } else {
                AdvancedAccessCard()
            }
        }
    }
}

private struct VectorCard: View {
    let title: String
    let symbol: String
    let reading: VectorReading?
    let capability: String?
    let unit: String
    let tint: Color
    let info: String

    var body: some View {
        Card(title: title, symbol: symbol, tint: tint, info: info) {
            if let reading {
                MetricGrid(
                    metrics: [
                        Metric(name: "X", value: format(reading.x, digits: 3), unit: unit),
                        Metric(name: "Y", value: format(reading.y, digits: 3), unit: unit),
                        Metric(name: "Z", value: format(reading.z, digits: 3), unit: unit),
                    ],
                    tint: tint
                )
            } else {
                MetricGrid(
                    metrics: unavailableMetrics(
                        ["X", "Y", "Z"],
                        capability: capability
                    ),
                    tint: tint
                )
            }
            Text(
                reading?.magnitude.map {
                    AppLocalization.language == .english
                        ? "Magnitude \(format($0, digits: 3)) \(unit)"
                        : "合向量 \(format($0, digits: 3)) \(unit)"
                } ?? " "
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: 16, alignment: .leading)
            .accessibilityHidden(reading?.magnitude == nil)
        }
    }
}
