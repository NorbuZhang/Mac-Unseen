// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct TrackpadView: View {
    @EnvironmentObject private var store: SensorStore

    private var sensingSurfaceValue: String {
        let width = store.trackpadDetails.surfaceWidth
        let height = store.trackpadDetails.surfaceHeight
        guard (1...100_000).contains(width),
              (1...100_000).contains(height) else {
            return "-"
        }
        let scale = max(width, height) >= 1_000 ? 100.0 : 1.0
        let widthMM = Double(width) / scale
        let heightMM = Double(height) / scale
        guard (30...300).contains(widthMM),
              (30...300).contains(heightMM) else {
            return "-"
        }
        return "\(format(widthMM, digits: 1)) × "
            + "\(format(heightMM, digits: 1))"
    }

    var body: some View {
        Page(
            title: "触控板原始数据",
            subtitle: "位置、压力和电容数据；压力单位为未经物理标定的相对值"
        ) {
            if store.trackpadAvailable {
                let displayedTouches = store.displayedTrackpadTouches
                Card(
                    title: "设备信息",
                    symbol: "cpu",
                    tint: .indigo
                ) {
                    let metrics = [
                            Metric(
                                name: "感应表面",
                                value: sensingSurfaceValue,
                                unit: sensingSurfaceValue == "-" ? "" : "mm",
                                info: "触控板私有接口返回的是百分之一毫米量级的整数，例如 12480 × 7680 对应约 124.8 × 76.8 mm。这里换算后显示感应区域的近似物理尺寸；它不是屏幕像素，也不是触点使用的 0–1 归一化坐标。"
                            ),
                            Metric(
                                name: "传感阵列",
                                value: "\(store.trackpadDetails.sensorRows) × \(store.trackpadDetails.sensorColumns)",
                                info: "触控板内部电容感应网格的行数与列数。系统结合多个感应单元的变化，估算手指位置、接触面积、移动方向和触摸强弱。"
                            ),
                            Metric(
                                name: "原始数据流",
                                value: store.trackpadDetails.running
                                    ? "可读取"
                                    : "不可用",
                                info: "表示应用是否已成功连接触控板的原始多点数据流。可读取时能获得触点位置、接触面积和内部相对压力。不同 MacBook 的触控板结构并不完全相同，例如 MacBook Neo 使用机械式多点触控板，因此这里不把数据流等同于 Force Touch。"
                            ),
                        ]
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(metrics) { metric in
                            MetricTile(
                                name: metric.name,
                                value: metric.value,
                                unit: metric.unit,
                                detail: metric.detail,
                                info: metric.info,
                                tint: .indigo
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                Card(
                    title: "当前读数",
                    symbol: "gauge.with.dots.needle.50percent",
                    tint: .cyan,
                    info: "这是触控板报告的内部相对压力，不是牛顿或克。它适合比较同一根手指按得更轻还是更重，但不同手指、接触面积和触点位置都会影响数值。只有经过已知重量校准后，实验性电子秤功能才可能换算成克。"
                ) {
                    MetricGrid(
                        metrics: [
                            Metric(
                                name: "触点数",
                                value: "\(displayedTouches.count)"
                            ),
                            Metric(
                                name: "最大压力",
                                value: format(
                                    displayedTouches.map(\.pressure).max() ?? 0,
                                    digits: 3
                                ),
                                unit: "相对值",
                                info: "当前所有触点中最大的原始压力值。它没有公开的物理单位，只能用于观察相对变化，不能直接解释为重量。"
                            ),
                            Metric(
                                name: "总电容",
                                value: format(
                                    displayedTouches.reduce(0) {
                                        $0 + $1.total
                                    },
                                    digits: 3
                                ),
                                info: "触控板对所有触点报告的电容总量。手指接触面积、皮肤状态和压力都会影响它，因此它常与压力一起用于判断接触强弱。"
                            ),
                        ],
                        tint: .cyan
                    )
                }

                HStack(alignment: .top, spacing: 16) {
                    Card(
                        title: "实时触摸面板",
                        symbol: "hand.draw",
                        tint: .blue
                    ) {
                        TrackpadCanvas(touches: displayedTouches)
                            .frame(height: 210)
                    }

                    Card(
                        title: "当前触点",
                        symbol: "list.bullet.rectangle",
                        tint: .purple,
                        info: "压力是触控板报告的相对按压强度；接触密度是驱动根据手指接触面积和电容分布计算的内部相对值。两者都没有公开的物理单位，适合观察同一次触摸中的相对变化，不能直接换算成重量或压强。"
                    ) {
                        if displayedTouches.isEmpty {
                            Text(tr("等待触控板输入"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: 210,
                                    alignment: .topLeading
                                )
                        } else {
                            let columns = displayedTouches.count >= 3
                                ? [
                                    GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10),
                                ]
                                : [GridItem(.flexible())]
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(displayedTouches) { touch in
                                    TrackpadTouchDetailTile(touch: touch)
                                }
                            }
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 210,
                                alignment: .top
                            )
                        }
                    }
                }

                Card(
                    title: "压力趋势（相对值）",
                    symbol: "chart.xyaxis.line",
                    tint: .pink
                ) {
                    Sparkline(
                        values: store.trackpadPressureHistory,
                        tint: .pink
                    )
                    .frame(height: 90)
                }

            } else {
                Card(title: "触控板不可用", symbol: "exclamationmark.triangle", tint: .orange) {
                    Text(tr("没有找到可由 MultitouchSupport 访问的内置触控板。"))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct TrackpadTouchDetailTile: View {
    let touch: TrackpadTouch

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("#\(touch.id)")
                    .font(.caption.monospaced().bold())
                Text(touch.stateName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    "(\(format(touch.x, digits: 2)), "
                    + "\(format(touch.y, digits: 2)))"
                )
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
            }
            HStack(spacing: 14) {
                Text(
                    "\(tr("压力")) "
                    + format(touch.pressure, digits: 3)
                )
                Text(
                    "\(tr("接触密度")) "
                    + format(touch.density, digits: 3)
                )
            }
            .font(.caption.monospacedDigit())
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background {
            TileSurface(tint: .purple)
        }
    }
}

private struct TrackpadCanvas: View {
    let touches: [TrackpadTouch]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppPalette.blue.opacity(0.12),
                                AppPalette.accent.opacity(0.06),
                                Color.primary.opacity(0.025),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        AppPalette.accent.opacity(0.2),
                                        AppPalette.cardBorder,
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.035), radius: 12, y: 5)

                if touches.isEmpty {
                    Text(tr("触摸触控板以查看原始压力数据"))
                        .foregroundStyle(.secondary)
                }

                ForEach(touches) { touch in
                    TrackpadTouchMarker(
                        touch: touch,
                        canvasSize: geometry.size
                    )
                }
            }
        }
    }
}

private struct TrackpadTouchMarker: View {
    let touch: TrackpadTouch
    let canvasSize: CGSize

    var body: some View {
        let pressure = CGFloat(touch.pressure)
        let majorAxis = CGFloat(touch.majorAxis)
        let diameter = max(24, min(90, 28 + majorAxis * 240 + pressure * 20))
        let x = max(
            14,
            min(canvasSize.width - 14, CGFloat(touch.x) * canvasSize.width)
        )
        let y = max(
            14,
            min(canvasSize.height - 14, (1 - CGFloat(touch.y)) * canvasSize.height)
        )

        Circle()
            .fill(
                RadialGradient(
                    colors: [.mint.opacity(0.95), .cyan.opacity(0.25)],
                    center: .center,
                    startRadius: 1,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
            .overlay {
                VStack(spacing: 0) {
                    Text(format(touch.pressure, digits: 2))
                        .font(.caption2.monospacedDigit().bold())
                    Text(tr("相对值"))
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .position(x: x, y: y)
    }
}
