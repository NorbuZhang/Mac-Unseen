import SwiftUI

private extension FanMode {
    var title: String {
        switch self {
        case .auto: tr("系统自动")
        case .manual: tr("固定转速")
        case .curve: tr("目标温度")
        }
    }
}

struct FanControlCard: View {
    var body: some View {
        Card(title: "风扇控制", symbol: "slider.horizontal.3", tint: .cyan) {
            FanControls()
        }
    }
}

struct FanControls: View {
    @EnvironmentObject private var control: FanControlSession
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let status = control.status {
                Text(tr("当前模式") + " · " + status.config.mode.title).font(.headline)
                ForEach(status.fans) { fan in
                    HStack {
                        Text(fan.name)
                        Spacer()
                        Text("\(Int(fan.actualRPM)) RPM")
                        Text(fan.systemOverride ? tr("系统接管") : fan.forced ? "→ \(Int(fan.targetRPM)) RPM" : tr("系统自动"))
                            .foregroundStyle(.secondary)
                    }.monospacedDigit()
                }
                if status.failsafeActive { Text(tr("温度保护已启用，风扇由服务接管。")).foregroundStyle(.orange) }
                if status.fans.isEmpty {
                    Text(tr("这台 Mac 未报告可控制的风扇。")).foregroundStyle(.secondary)
                } else if !status.canControl {
                    Text(tr("当前风扇服务只提供读数。")).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button(tr("一键满转")) { control.applyFullSpeed() }
                            .disabled(status.fullSpeedTargets == nil)
                        if status.config.mode != .auto {
                            Button(tr("恢复系统自动")) { control.apply(.auto) }
                        }
                    }.disabled(control.busy)
                    Picker(tr("控制模式"), selection: $control.mode) {
                        ForEach(FanMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    if control.mode == .manual {
                        Slider(value: $control.fraction, in: 0...100, step: 1)
                            .accessibilityLabel(tr("目标转速"))
                        ForEach(status.fans) { fan in
                            Text("\(fan.name) · \(Int(control.rpm(for: fan))) RPM")
                        }.font(.caption).monospacedDigit()
                    } else if control.mode == .curve {
                        Slider(value: $control.ceiling, in: 60...95, step: 1)
                            .accessibilityLabel(tr("目标温度"))
                        Text("\(Int(control.ceiling)) °C").monospacedDigit()
                    }
                    Button(tr("应用设置")) { control.apply(control.mode) }
                        .disabled(control.busy)
                    Text(tr("设置由风扇服务保存，退出 Mac Unseen 后仍会生效。")).font(.caption).foregroundStyle(.secondary)
                }
            } else if !control.didRead {
                ProgressView().controlSize(.small)
            } else if control.readOnlySpeeds?.fanCount == 0 {
                Text(tr("这台 Mac 未报告可控制的风扇。")).foregroundStyle(.secondary)
            } else {
                ForEach(control.readOnlySpeeds?.speeds ?? []) { fan in
                    LabeledContent(tr("风扇") + " \(fan.index)", value: "\(Int(fan.rpm)) RPM").monospacedDigit()
                }
                Text(tr("首次启用需要管理员授权，在本机安装随应用提供的风扇服务。")).foregroundStyle(.secondary)
                Button(tr(control.busy ? "正在启用…" : "启用风扇控制")) { control.enableService() }
                    .disabled(control.busy)
                if let installMessage = control.installMessage { Text(installMessage).font(.caption) }
            }
            if let errorText = control.errorText { Text(errorText).font(.caption).foregroundStyle(.secondary) }
        }
        .task {
            while !Task.isCancelled {
                await control.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}
