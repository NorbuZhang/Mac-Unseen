// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct AboutView: View {
    var body: some View {
        Page(
            title: "关于",
            subtitle: "Mac Unseen 0.1"
        ) {
            Card(title: "数据边界", symbol: "shield.lefthalf.filled", tint: .green) {
                Text(tr(
                    "应用只读取传感器。首版不会设置风扇转速、修改屏幕或键盘亮度、"
                    + "运行快捷指令，也不会上传数据。管理员辅助进程退出后不会安装常驻服务。"
                ))
                .foregroundStyle(.secondary)
            }
            Card(title: "开源组件", symbol: "chevron.left.forwardslash.chevron.right", tint: .blue) {
                Text(tr("Apple SPU 读取基于 olvvier/apple-silicon-accelerometer 的逆向研究。"))
                Text(tr("触控板结构与接口参考 Kyome22/OpenMultitouchSupport。"))
                Text(tr("SMC/HID 遥测由 dkorunic/iSMC 提供，按 GPL-3.0 分发。"))
                Text(tr("完整许可证位于应用包 Contents/Resources/Licenses。"))
                Text(tr("这些接口未由 Apple 公开，系统更新后可能失效。"))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
