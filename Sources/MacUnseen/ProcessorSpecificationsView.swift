import SwiftUI

struct ProcessorSpecificationsView: View, Equatable {
    let identity: SystemIdentity
    private func count(_ value: Int?) -> String { value.map(String.init) ?? "—" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SpecificationGrid(rows: [
                ("物理核心 / 逻辑核心", count(identity.physicalCores) + " / " + count(identity.logicalCores)),
                ("处理器封装", count(identity.packages)),
                ("硬件虚拟化支持", identity.virtualization.map { tr($0 ? "是" : "否") } ?? "—"),
            ])
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow {
                    Text(tr("核心类型 / 数量"))
                    Text(tr("L1 指令 / 数据（每核心）"))
                    Text(tr("L2 缓存 / 共享组"))
                    Text(tr("每组共享 L2 的核心数"))
                }.font(.caption).foregroundStyle(.secondary)
                ForEach(identity.coreGroups.indices, id: \.self) { index in
                    let group = identity.coreGroups[index]
                    GridRow {
                        Text(tr(group.label) + " · " + String(group.count))
                        Text(formatHardwareBytes(group.l1InstructionBytes) + " / " + formatHardwareBytes(group.l1DataBytes))
                        Text(formatHardwareBytes(group.l2Bytes))
                        Text(count(group.coresPerL2))
                    }.font(.callout).textSelection(.enabled)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let l3 = identity.l3Bytes { SpecificationGrid(rows: [("L3 缓存", formatHardwareBytes(l3))]) }
        }
    }
}
