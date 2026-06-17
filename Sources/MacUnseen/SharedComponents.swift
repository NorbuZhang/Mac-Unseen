// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct Page<Content: View>: View {
    @EnvironmentObject private var store: SensorStore
    let title: String
    let subtitle: String
    let headerAccessory: AnyView?
    let content: Content

    init(
        title: String,
        subtitle: String,
        headerAccessory: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.headerAccessory = headerAccessory
        self.content = content()
    }

    var body: some View {
        ZStack {
            DashboardBackground()

            GeometryReader { viewport in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .center, spacing: 14) {
                                Text(tr(title))
                                    .font(
                                        .system(
                                            size: 31,
                                            weight: .bold,
                                            design: .rounded
                                        )
                                    )
                                    .tracking(-0.45)
                                if let headerAccessory {
                                    headerAccessory
                                }
                            }
                            Text(tr(subtitle))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 2)
                        content
                    }
                    .frame(
                        width: max(viewport.size.width - 60, 0),
                        alignment: .leading
                    )
                    .padding(.horizontal, 30)
                    .padding(.top, 27)
                    .padding(.bottom, 36)
                }
                .onScrollPhaseChange { _, phase in
                    store.setPageScrolling(phase != .idle)
                }
            }
        }
    }
}

struct DashboardBackground: View {
    var body: some View {
        ZStack {
            AppPalette.canvas
            LinearGradient(
                colors: [
                    AppPalette.blue.opacity(0.045),
                    AppPalette.accent.opacity(0.02),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct CardSurface: View {
    let tint: Color
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                colorScheme == .light
                    ? Color.white.opacity(0.72)
                    : Color.white.opacity(0.055)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.105),
                                tint.opacity(0.035),
                                colorScheme == .light
                                    ? Color.white.opacity(0.10)
                                    : AppPalette.blue.opacity(0.025),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.18),
                                AppPalette.cardBorder,
                                Color.primary.opacity(0.045),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
    }
}

struct TileSurface: View {
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        tint.opacity(0.105),
                        AppPalette.tileFill,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.16),
                                AppPalette.tileBorder,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
    }
}

extension View {
    func cardSurface(tint: Color, cornerRadius: CGFloat = 20) -> some View {
        background {
            CardSurface(tint: tint, cornerRadius: cornerRadius)
        }
    }
}

struct SoftDivider: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.clear,
                AppPalette.hairline,
                Color.clear,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
    }
}

struct HeaderAccent: View {
    let tint: Color

    var body: some View {
        LinearGradient(
            colors: [tint.opacity(0.7), tint.opacity(0)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 56, height: 2)
        .clipShape(Capsule())
    }
}

struct Card<Content: View>: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor
    var info: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        LinearGradient(
                            colors: [tint.opacity(0.95), tint.opacity(0.68)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                    .shadow(color: tint.opacity(0.18), radius: 5, y: 2)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(tr(title))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let info {
                            InfoButton(text: info)
                        }
                    }
                    HeaderAccent(tint: tint)
                }
            }
            content
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(tint: tint)
    }
}

struct InfoButton: View {
    let text: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            ZStack {
                Color.clear
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
            .padding(-10)
        }
        .buttonStyle(.plain)
        .help(tr(text))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            Text(tr(text))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 330, alignment: .leading)
                .padding(18)
                .background(.regularMaterial)
        }
    }
}

struct MetricTile: View {
    let name: String
    let value: String
    var unit = ""
    var detail: String?
    var info: String?
    var tint: Color = .accentColor
    var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 5 : 3) {
            HStack(spacing: 4) {
                Text(tr(name))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let info {
                    InfoButton(text: info)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(tr(value))
                    .font(
                        .system(
                            size: expanded ? 24 : 21,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(tr(unit))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let detail {
                Text(tr(detail))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(expanded ? 15 : 11)
        .frame(
            maxWidth: .infinity,
            minHeight: expanded ? 106 : 78,
            maxHeight: expanded ? 106 : 78,
            alignment: .topLeading
        )
        .background {
            TileSurface(tint: tint)
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.95), tint.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3, height: 31)
                .padding(.leading, 1.5)
        }
    }
}

struct MetricGrid: View {
    let metrics: [Metric]
    var tint: Color = .accentColor
    var minimumWidth: CGFloat = 145

    private var needsExpandedTiles: Bool {
        metrics.contains { metric in
            (metric.detail?.count ?? 0) > 30
                || metric.value.count > 18
        }
    }

    var body: some View {
        AdaptiveMetricLayout(minimumWidth: minimumWidth) {
            ForEach(metrics) { metric in
                MetricTile(
                    name: metric.name,
                    value: metric.value,
                    unit: metric.unit,
                    detail: metric.detail,
                    info: metric.info,
                    tint: tint,
                    expanded: needsExpandedTiles
                )
            }
        }
    }
}

struct AdaptiveMetricLayout: Layout {
    let minimumWidth: CGFloat
    var maximumWidth: CGFloat = 220
    var spacing: CGFloat = 12

    private func dimensions(
        proposal: ProposedViewSize,
        count: Int
    ) -> (width: CGFloat, columns: Int, itemWidth: CGFloat) {
        let proposedWidth = proposal.width ?? minimumWidth
        let fallbackWidth = max(minimumWidth, 1)
        let available = proposedWidth.isFinite && proposedWidth > 0
            ? max(proposedWidth, minimumWidth)
            : fallbackWidth
        let maximumColumns = max(count, 1)
        let rawColumns = (available + spacing) / (minimumWidth + spacing)
        let possibleColumns: Int
        if !rawColumns.isFinite || rawColumns >= CGFloat(maximumColumns) {
            possibleColumns = maximumColumns
        } else {
            possibleColumns = max(1, Int(rawColumns.rounded(.down)))
        }
        let columns = min(max(count, 1), possibleColumns)
        let itemWidth = min(
            maximumWidth,
            (available - spacing * CGFloat(columns - 1))
                / CGFloat(columns)
        )
        return (available, columns, itemWidth)
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard !subviews.isEmpty else {
            return .zero
        }
        let layout = dimensions(proposal: proposal, count: subviews.count)
        var rowHeights = [CGFloat](
            repeating: 0,
            count: Int(ceil(Double(subviews.count) / Double(layout.columns)))
        )
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(
                ProposedViewSize(width: layout.itemWidth, height: nil)
            )
            rowHeights[index / layout.columns] = max(
                rowHeights[index / layout.columns],
                size.height
            )
        }
        return CGSize(
            width: layout.width,
            height: rowHeights.reduce(0, +)
                + spacing * CGFloat(max(rowHeights.count - 1, 0))
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty else {
            return
        }
        let layout = dimensions(
            proposal: ProposedViewSize(width: bounds.width, height: proposal.height),
            count: subviews.count
        )
        var rowHeights = [CGFloat](
            repeating: 0,
            count: Int(ceil(Double(subviews.count) / Double(layout.columns)))
        )
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(
                ProposedViewSize(width: layout.itemWidth, height: nil)
            )
            rowHeights[index / layout.columns] = max(
                rowHeights[index / layout.columns],
                size.height
            )
        }
        var rowOrigins = [CGFloat]()
        var nextY = bounds.minY
        for height in rowHeights {
            rowOrigins.append(nextY)
            nextY += height + spacing
        }
        for (index, subview) in subviews.enumerated() {
            let row = index / layout.columns
            let column = index % layout.columns
            subview.place(
                at: CGPoint(
                    x: bounds.minX
                        + CGFloat(column) * (layout.itemWidth + spacing),
                    y: rowOrigins[row]
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(
                    width: layout.itemWidth,
                    height: rowHeights[row]
                )
            )
        }
    }
}

struct AdvancedAccessCard: View {
    @EnvironmentObject private var store: SensorStore

    var body: some View {
        Card(title: "需要启用高级传感器", symbol: "lock.shield", tint: .orange) {
            Text(tr(
                "加速度计、陀螺仪、屏幕角度和部分 SMC 数据没有公开接口。"
                + "应用会通过 macOS 管理员授权启动只读采集进程，不修改风扇、功耗或系统设置。"
            ))
            .foregroundStyle(.secondary)

            HStack {
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
                                : "启用并授权"
                        ))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.advancedAccessPending)

                if let message = store.authorizationMessage {
                    Text(tr(message))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct CapabilityNotice: View {
    let capability: String?
    let unsupported: String
    let unreadable: String

    var body: some View {
        Label(
            tr(capability == "unsupported" ? unsupported : unreadable),
            systemImage: capability == "unsupported"
                ? "minus.circle"
                : "exclamationmark.triangle"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }
}

struct HardwareUpdatedLabel: View {
    let date: Date?

    var body: some View {
        if let date {
            Text(
                AppLocalization.language == .english
                    ? "Hardware status updated \(date.formatted(date: .omitted, time: .standard))"
                    : "硬件状态更新于 \(date.formatted(date: .omitted, time: .standard))"
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }
}
