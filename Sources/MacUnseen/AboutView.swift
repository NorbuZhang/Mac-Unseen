import SwiftUI

struct AboutView: View {
    var body: some View {
        Page(
            title: "关于",
            subtitle: "Mac Unseen " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        ) {
            Card(title: "数据边界", symbol: "shield.lefthalf.filled", tint: .green) {
                Text(tr(
                    "传感器读数在本机处理。首次启用风扇控制时，macOS 会请求管理员授权并安装本地服务。退出应用后，服务会继续执行已应用的风扇设置。"
                ))
                .foregroundStyle(.secondary)
            }
            Card(title: "开源组件", symbol: "chevron.left.forwardslash.chevron.right", tint: .blue) {
                Text(tr("Apple SPU 读取基于 olvvier/apple-silicon-accelerometer 的逆向研究。"))
                Text(tr("触控板结构与接口参考 Kyome22/OpenMultitouchSupport。"))
                Text(tr("SMC/HID 遥测由 dkorunic/iSMC 提供，按 GPL-3.0 分发。"))
                Text(tr("完整许可证位于应用包 Contents/Resources/Licenses。"))
                Link("Accordion: MAcordion by bruiselea", destination: URL(string: "https://github.com/bruiselea/MAcordion")!)
                Text(tr("这些接口未由 Apple 公开，系统更新后可能失效。"))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
