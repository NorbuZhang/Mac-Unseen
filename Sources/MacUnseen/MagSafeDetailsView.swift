import SwiftUI

struct MagSafeDetailsView: View {
    let connection: MagSafeSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(connection.connector).font(.headline)
                Spacer()
                Label(tr("已连接"), systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            SpecificationGrid(rows: rows)
            Text(tr("线缆固件来自系统诊断中的 bcdDevice 版本标识；已确认的版本显示为易读版本号，其他版本保留原始值。接口控制器固件属于 Mac，充电器固件属于电源适配器。"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rows: [(String, String)] {
        var rows = [
            ("线缆固件", connection.cableFirmware?.displayVersion ?? tr("未能读取")),
            ("接口控制器固件", connection.controllerFirmware ?? "—"),
        ]
        if let firmware = connection.cableFirmware {
            rows.append(("线缆版本标识", firmware.rawVersion + " · bcdDevice"))
        }
        if let vendor = connection.cableVendorID {
            rows.append(("线缆厂商 ID", vendor == 0x05AC ? "Apple · 0x05AC" : String(format: "0x%04X", vendor)))
        }
        if let product = connection.cableProductID {
            rows.append(("线缆产品 ID", String(format: "0x%04X", product)))
        }
        return rows
    }
}
