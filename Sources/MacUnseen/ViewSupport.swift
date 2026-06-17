// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let maximum = max(values.max() ?? 0.001, 0.001)
            Path { path in
                guard values.count > 1 else {
                    return
                }
                for (index, value) in values.enumerated() {
                    let x = geometry.size.width
                        * Double(index) / Double(values.count - 1)
                    let y = geometry.size.height
                        * (1 - min(1, max(0, value / maximum)))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(
                tint.gradient,
                style: StrokeStyle(lineWidth: 2.5, lineJoin: .round)
            )
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.11),
                                Color.primary.opacity(0.025),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(tint.opacity(0.12), lineWidth: 1)
                    }
            }
        }
    }
}

func format(_ value: Double, digits: Int) -> String {
    String(format: "%.\(digits)f", value)
}

func optional(_ value: Double?, digits: Int) -> String {
    value.map { format($0, digits: digits) } ?? "-"
}

func formatBytes(_ bytes: Double) -> String {
    guard bytes > 0 else {
        return "-"
    }
    return ByteCountFormatter.string(
        fromByteCount: Int64(bytes),
        countStyle: .memory
    )
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let days = Int(seconds) / 86_400
    let hours = (Int(seconds) % 86_400) / 3_600
    if AppLocalization.language == .english {
        return days > 0
            ? "\(days)d \(hours)h"
            : "\(hours)h"
    }
    return days > 0 ? "\(days)天 \(hours)小时" : "\(hours)小时"
}

func batteryHealth(_ battery: BatterySnapshot) -> String {
    guard let design = battery.designCapacity,
          let maximum = battery.maximumCapacity,
          design > 0
    else {
        return "-"
    }
    return format(maximum / design * 100, digits: 1)
}

func batteryPower(_ battery: BatterySnapshot) -> Double? {
    guard let voltage = battery.voltage,
          let amperage = battery.amperage
    else {
        return nil
    }
    return abs(voltage * amperage)
}

func formattedInteger(_ value: UInt64) -> String {
    value.formatted(.number.grouping(.automatic))
}

func optionalInteger(_ value: UInt64?) -> String {
    value.map(formattedInteger) ?? "-"
}

func optionalHours(_ value: UInt64?) -> String {
    guard let value else {
        return "-"
    }
    let days = value / 24
    if AppLocalization.language == .english {
        return days > 0
            ? "\(formattedInteger(days)) days"
            : "\(value) hours"
    }
    return days > 0 ? "\(formattedInteger(days)) 天" : "\(value) 小时"
}

func formatOptionalBytes(_ value: Double?) -> String {
    guard let value else {
        return "-"
    }
    return formatBytes(value)
}

func emptyFallback(
    _ value: String,
    fallback: String = "-"
) -> String {
    value.isEmpty ? fallback : value
}

func wifiProtocolName(_ value: String) -> String {
    let normalized = value.lowercased()
    if normalized.contains("802.11be") {
        return "Wi-Fi 7 (802.11be)"
    }
    if normalized.contains("802.11ax") {
        return "Wi-Fi 6 / 6E (802.11ax)"
    }
    if normalized.contains("802.11ac") {
        return "Wi-Fi 5 (802.11ac)"
    }
    if normalized.contains("802.11n") {
        return "Wi-Fi 4 (802.11n)"
    }
    return value.isEmpty ? "-" : value
}

func waitingMetrics(_ names: [String]) -> [Metric] {
    names.map {
        Metric(
            id: "waiting-\($0)",
            name: $0,
            value: "…",
            detail: "正在读取"
        )
    }
}

func unavailableMetrics(
    _ names: [String],
    capability: String?
) -> [Metric] {
    guard capability == "unsupported" || capability == "unreadable" else {
        return waitingMetrics(names)
    }
    let detail = capability == "unsupported"
        ? "此机型没有对应硬件"
        : "检测到硬件，但无法访问"
    return names.map {
        Metric(
            id: "\(capability ?? "unknown")-\($0)",
            name: $0,
            value: "-",
            detail: detail
        )
    }
}
