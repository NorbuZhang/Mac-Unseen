// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct EnvironmentView: View {
    @EnvironmentObject private var store: SensorStore

    private var ambientIsWarm: Bool {
        let channels = store.advanced.environment.spectralChannels
        guard channels.count >= 4 else {
            return true
        }
        let coolResponse = max(channels[0] + channels[1], 1)
        let warmResponse = channels[2] + channels[3]
        return warmResponse / coolResponse >= 1.35
    }

    private var ambientTint: Color {
        ambientIsWarm
            ? .yellow
            : Color(red: 0.30, green: 0.52, blue: 0.82)
    }

    var body: some View {
        Page(
            title: "屏幕角度与环境光",
            subtitle: "屏幕铰链、环境照度和颜色通道"
        ) {
            if store.advancedSensorsActive {
                GeometryReader { geometry in
                    let environmentWidth = max(
                        380,
                        min(geometry.size.width * 0.34, 500)
                    )
                    HStack(alignment: .top, spacing: 16) {
                        Card(
                            title: "屏幕角度",
                            symbol: "laptopcomputer",
                            tint: .cyan,
                            info: "它表示屏幕与键盘底座之间大约张开了多少度。屏幕合上时接近 0°，正常使用时通常在 90° 到 130° 左右。这个隐藏传感器的原始报告只提供整数度，所以界面不显示小数；轻微晃动或铰链结构也可能让读数在相邻两度之间跳动。"
                        ) {
                            let capability =
                                store.advanced.capabilities["lidAngle"]
                            if capability == "unsupported"
                                || capability == "unreadable" {
                                CapabilityNotice(
                                    capability: "unsupported",
                                    unsupported: "此机型没有可访问的屏幕角度传感器",
                                    unreadable: "此机型没有可访问的屏幕角度传感器"
                                )
                            } else {
                                HStack(spacing: 6) {
                                    Text(
                                        store.advanced.environment.lidAngle.map {
                                            "\(format($0, digits: 0))°"
                                        } ?? tr("等待数据")
                                    )
                                    .font(.system(size: 38, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .fixedSize()
                                    Spacer(minLength: 4)
                                    LidAngleDiagram(
                                        angle: store.advanced.environment.lidAngle
                                            ?? 90
                                    )
                                    .frame(width: 200, height: 78)
                                    .fixedSize()
                                    .offset(x: 8)
                                }
                            }
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 180,
                            maxHeight: 180,
                            alignment: .top
                        )

                        Card(
                            title: "环境光",
                            symbol: "sun.max.fill",
                            tint: ambientTint,
                            info: "环境光传感器位于屏幕附近，用来判断周围环境是明亮还是昏暗。macOS 通常利用它调节自动亮度和键盘背光。遮住传感器、靠近窗户或打开台灯时，读数会明显变化。"
                        ) {
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(environmentMetrics) { metric in
                                    MetricTile(
                                        name: metric.name,
                                        value: metric.value,
                                        unit: metric.unit,
                                        detail: metric.detail,
                                        info: metric.info,
                                        tint: ambientTint
                                    )
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .frame(
                            width: environmentWidth,
                            height: 180,
                            alignment: .top
                        )
                    }
                }
                .frame(height: 180)
                .animation(.easeInOut(duration: 0.35), value: ambientIsWarm)

                Card(
                    title: "四路原始光谱通道",
                    symbol: "slider.horizontal.3",
                    tint: AppPalette.accent,
                    info: "Mac 的环境光传感器会同时返回四组原始计数，不同光源会形成不同的四路比例。Apple 没有公开 CH1–CH4 分别对应哪段波长，所以它们不能直接叫作红、绿、蓝，也不能准确还原颜色。它们更适合用来比较窗外日光、暖色台灯和冷色屏幕等光源之间的相对差异。"
                ) {
                    let capability = store.advanced.capabilities["spectral"]
                    if capability == "unsupported"
                        || capability == "unreadable" {
                        CapabilityNotice(
                            capability: "unsupported",
                            unsupported: "此机型不提供可访问的原始光谱通道",
                            unreadable: "此机型不提供可访问的原始光谱通道"
                        )
                        .frame(height: 80)
                    } else {
                        SpectralBars(
                            values: store.advanced.environment.spectralChannels
                        )
                        .frame(height: 190)
                    }
                }
            } else {
                AdvancedAccessCard()
            }
        }
    }

    private var environmentMetrics: [Metric] {
        [
            Metric(
                name: "实际照度",
                value: store.advanced.environment.lux.map {
                    format($0, digits: 0)
                } ?? "-",
                unit: "lux",
                detail: isUnavailable(
                    store.advanced.capabilities["ambientLux"]
                )
                    ? "此机型没有返回可访问的照度数据"
                    : nil,
                info: "lux 是照度单位，描述落在一个表面上的可见光有多强。数值越高代表环境越亮：昏暗房间可能只有几十 lux，普通室内通常是几百 lux，阳光下会高得多。这里的数值来自 Mac 自己的环境光传感器，不是专业校准仪器。"
            ),
            Metric(
                name: "ALS 归一化强度",
                value: store.advanced.environment.alsIntensity.map {
                    format($0, digits: 3)
                } ?? "-",
                detail: isUnavailable(
                    store.advanced.capabilities["spectral"]
                )
                    ? "此机型不提供原始光谱通道"
                    : nil,
                info: "这是环境光传感器内部使用的原始强度数值，可以用来比较“现在比刚才更亮还是更暗”。它没有公开、稳定的物理单位，因此不能当作 lux，也不适合拿来和专业照度计直接比较。"
            ),
        ]
    }

    private func isUnavailable(_ capability: String?) -> Bool {
        capability == "unsupported" || capability == "unreadable"
    }
}

private struct LidAngleDiagram: View {
    let angle: Double

    var body: some View {
        GeometryReader { geometry in
            let safeAngle = max(0, min(180, angle))
            let vertex = CGPoint(
                x: 145,
                y: geometry.size.height * 0.80
            )
            let radians = safeAngle * .pi / 180
            let directionX = -cos(radians)
            let directionY = -sin(radians)
            let horizontalLimit = directionX > 0
                ? (geometry.size.width - vertex.x - 8) / directionX
                : (vertex.x - 8) / max(-directionX, 0.001)
            let verticalLimit = directionY < 0
                ? (vertex.y - 8) / -directionY
                : (geometry.size.height - vertex.y - 8)
                    / max(directionY, 0.001)
            let length = max(
                20,
                min(
                    108,
                    geometry.size.height * 0.78,
                    horizontalLimit,
                    verticalLimit
                )
            )
            let screenEnd = CGPoint(
                x: vertex.x + directionX * length,
                y: vertex.y + directionY * length
            )
            let arcRadius = min(42, length * 0.32)
            ZStack {
                Path { path in
                    path.move(to: vertex)
                    path.addLine(
                        to: CGPoint(x: vertex.x - length, y: vertex.y)
                    )
                }
                .stroke(.secondary, style: StrokeStyle(lineWidth: 8, lineCap: .round))

                Path { path in
                    path.move(to: vertex)
                    path.addLine(to: screenEnd)
                }
                .stroke(.cyan, style: StrokeStyle(lineWidth: 7, lineCap: .round))

                Path { path in
                    let segments = max(8, Int(safeAngle / 4))
                    for index in 0...segments {
                        let progress = Double(index) / Double(segments)
                        let theta = radians * progress
                        let point = CGPoint(
                            x: vertex.x - cos(theta) * arcRadius,
                            y: vertex.y - sin(theta) * arcRadius
                        )
                        if index == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                }
                .stroke(
                    .cyan.opacity(0.72),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )

                Circle()
                    .fill(.cyan)
                    .frame(width: 13, height: 13)
                    .position(vertex)
            }
        }
    }
}

private struct SpectralBars: View {
    let values: [Double]
    private let colors = AppPalette.spectral

    var body: some View {
        GeometryReader { geometry in
            let maximum = max(values.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(0..<4, id: \.self) { index in
                    let value = index < values.count ? values[index] : 0
                    VStack(spacing: 8) {
                        Text(format(value, digits: 0))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        colors[index].opacity(0.72),
                                        colors[index].opacity(0.9),
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(
                                height: max(
                                    4,
                                    (geometry.size.height - 45) * value / maximum
                                )
                            )
                        Text("CH\(index + 1)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(colors[index])
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
