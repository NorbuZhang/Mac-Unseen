import SwiftUI

struct AccordionSettingsView: View {
    @ObservedObject var controller: AccordionController
    let sensorReady: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                    .frame(width: 46, height: 46)
                    .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("屏幕里的手风琴"))
                        .font(.title2.bold())
                    Text(tr("让屏幕成为风箱，让键盘奏出音符。"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Toggle(tr("启用手风琴彩蛋"), isOn: Binding(
                get: { controller.isEnabled }, set: { controller.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .disabled(!sensorReady && !controller.isEnabled)

            if !sensorReady {
                Text(tr("需要可用的屏幕角度数据。若刚更新应用，请重新启用隐藏传感器。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            if controller.failedToStart {
                Text(tr("无法启动音频，请检查声音输出设备后重试。"))
                    .font(.callout).foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(tr("按住音符键，再轻轻开合屏幕。停止移动后声音渐弱，松开按键停止发声。"))
                    .font(.callout)
                keyRow([
                    ("A", "C"), ("S", "D"), ("D", "E"), ("F", "F"), ("G", "G"),
                    ("H", "A"), ("J", "B"), ("K", "C"), ("L", "D"), (";", "E"),
                ])
                keyRow([
                    ("W", "C♯"), ("E", "D♯"), ("", ""), ("T", "F♯"), ("Y", "G♯"),
                    ("U", "A♯"), ("", ""), ("O", "C♯"), ("P", "D♯"), ("", ""),
                ])
                Text(tr("Z / X：降低 / 升高八度 · Esc：关闭彩蛋"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 14) {
                HStack {
                    Text(tr("音量")).frame(width: 80, alignment: .leading)
                    Slider(value: $controller.volume, in: 0...1)
                        .accessibilityLabel(tr("音量"))
                    Text("\(Int(controller.volume * 100))%")
                        .monospacedDigit().frame(width: 45, alignment: .trailing)
                }
                HStack {
                    Text(tr("灵敏度")).frame(width: 80, alignment: .leading)
                    Slider(value: $controller.sensitivity, in: 0.5...2)
                        .accessibilityLabel(tr("灵敏度"))
                    Text(String(format: "%.1f×", controller.sensitivity))
                        .monospacedDigit().frame(width: 45, alignment: .trailing)
                }
                Stepper(value: $controller.octave, in: 2...6) {
                    Text("\(tr("起始八度"))  C\(controller.octave)")
                }
            }

            Text(tr("频繁或用力开合屏幕可能增加铰链磨损、影响使用寿命。请小幅、轻柔操作，避免长时间反复开合或强行推至极限角度。"))
                .font(.caption)
                .foregroundStyle(AppPalette.accent)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Link("Inspired by MAcordion · bruiselea", destination: URL(string: "https://github.com/bruiselea/MAcordion")!)
                    .font(.caption)
                Spacer()
                Button(tr("完成")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 540)
        .background(AccordionWindowReader { controller.settingsWindow = $0 })
        .onDisappear { controller.settingsWindow = nil }
    }

    private func keyRow(_ pairs: [(key: String, note: String)]) -> some View {
        HStack(spacing: 0) {
            ForEach(pairs.indices, id: \.self) { index in
                let pair = pairs[index]
                VStack(spacing: 3) {
                    Text(pair.key).font(.system(.callout, design: .monospaced).bold())
                    Text(pair.note).font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityHidden(pair.key.isEmpty)
            }
        }
    }
}

struct AccordionWindowReader: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> WindowView { WindowView(onWindow: onWindow) }
    func updateNSView(_ nsView: WindowView, context: Context) { nsView.onWindow = onWindow }

    final class WindowView: NSView {
        var onWindow: (NSWindow?) -> Void
        init(onWindow: @escaping (NSWindow?) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() { onWindow(window) }
    }
}
