// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: SensorStore
    @EnvironmentObject private var languageSettings: LanguageSettings

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                SidebarBrand()
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                List(DashboardSection.allCases) { section in
                    Button {
                        store.selectedSection = section
                    } label: {
                        Label {
                            Text(section.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: section.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(
                                    store.selectedSection == section
                                        ? Color.white
                                        : Color.secondary
                                )
                                .frame(width: 24, height: 24)
                                .background(
                                    store.selectedSection == section
                                        ? AnyShapeStyle(
                                            LinearGradient(
                                                colors: [
                                                    AppPalette.brandTeal,
                                                    AppPalette.brandLavender,
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        : AnyShapeStyle(Color.clear),
                                    in: RoundedRectangle(
                                        cornerRadius: 7,
                                        style: .continuous
                                    )
                                )
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 34,
                            alignment: .leading
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .listRowInsets(
                        EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
                    )
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(
                                store.selectedSection == section
                                    ? AppPalette.brandTeal.opacity(0.13)
                                    : Color.clear
                            )
                            .padding(.horizontal, 2)
                    )
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .background {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [
                            AppPalette.blue.opacity(0.09),
                            AppPalette.accent.opacity(0.055),
                            Color.clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .ignoresSafeArea()
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
            .safeAreaInset(edge: .bottom) {
                SensorStatusPanel()
                    .padding(12)
            }
        } detail: {
            Group {
                switch store.selectedSection ?? .overview {
                case .overview: OverviewView()
                case .motion: MotionView()
                case .environment: EnvironmentView()
                case .trackpad: TrackpadView()
                case .temperature: TemperatureView()
                case .fans: FansView()
                case .battery: BatteryView()
                case .storage: StorageView()
                case .network: NetworkView()
                case .about: AboutView()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    languageSettings.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "character.bubble.fill")
                        Text(
                            languageSettings.language == .simplifiedChinese
                                ? "中 → EN"
                                : "EN → 中"
                        )
                        .font(.system(size: 12, weight: .semibold))
                    }
                }
                .help(tr("切换界面语言"))
            }
            ToolbarItem(placement: .primaryAction) {
                if store.advancedSensorsActive {
                    Button(tr("停止高级传感器"), systemImage: "stop.circle") {
                        store.stopAdvancedSensors()
                    }
                }
            }
        }
        .tint(AppPalette.accent)
        .overlay {
            if store.isMagicAnglePresented {
                MagicAngleOverlay {
                    store.dismissMagicAngle()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .zIndex(100)
            }
        }
        .animation(
            .spring(response: 0.5, dampingFraction: 0.88),
            value: store.isMagicAnglePresented
        )
    }
}

private struct MagicAngleOverlay: View {
    let onClose: () -> Void
    @State private var showingStory = false

    private let deepGreen = Color(red: 0.035, green: 0.27, blue: 0.22)
    private let vividGreen = Color(red: 0.08, green: 0.58, blue: 0.39)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    deepGreen,
                    Color(red: 0.045, green: 0.43, blue: 0.31),
                    vividGreen,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 520, height: 520)
                .blur(radius: 4)
                .offset(x: 390, y: -310)
            Circle()
                .fill(Color.mint.opacity(0.18))
                .frame(width: 360, height: 360)
                .blur(radius: 25)
                .offset(x: -430, y: 330)

            VStack(spacing: 22) {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Label(tr("关闭"), systemImage: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 5)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundStyle(.white)
                    .keyboardShortcut(.cancelAction)
                }

                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Color.white.opacity(0.14), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    }

                Text(tr("隐藏彩蛋 · 104°"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.78))

                VStack(spacing: 12) {
                    Text(tr("你找到了展示桌上的秘密"))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .tracking(-0.55)
                    Text(tr("104°，一台 Mac 最像在等你伸手碰它的角度。"))
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.82))
                    Text(tr("路过不算，得真正停下来。毕竟你已经很熟悉那种只经过她的心，却没能被留下的感觉了。"))
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.95))
                }
                .multilineTextAlignment(.center)

                Button {
                    showingStory = true
                } label: {
                    Label(tr("背后的故事"), systemImage: "book.pages")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.white)
                .foregroundStyle(deepGreen)
            }
            .padding(44)
            .frame(maxWidth: 720)
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .sheet(isPresented: $showingStory) {
            MagicAngleStory()
        }
    }
}

private struct MagicAngleStory: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "laptopcomputer")
                    .font(.title2)
                    .foregroundStyle(AppPalette.accent)
                Text(tr("104° 背后的故事"))
                    .font(.title2.bold())
                Spacer()
                Button(tr("完成")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StorySection(
                        symbol: "angle",
                        title: "先认识这个角度",
                        text: "104° 常被 Mac 爱好者称作 Apple Store 式的展示角度：屏幕足够打开，让画面和机身轮廓都能被看见；又稍微保留一点克制，好像它正在安静地等你伸手。"
                    )

                    StorySection(
                        symbol: "hand.point.up.left.fill",
                        title: "为什么偏偏摆在这里？",
                        text: "一种流传很广的零售设计解释是：104° 看起来端正，却未必正好适合每个人的身高和站姿。顾客为了看得更舒服，往往会忍不住伸手调整屏幕。这个小动作会把“站在旁边看看”变成“我正在使用它”，接下来摸摸键盘、滑动触控板、打开几个页面，也就顺理成章了。至少你调整它时，它真的会回应你。"
                    )

                    StorySection(
                        symbol: "brain.head.profile",
                        title: "那半秒钟可能做了什么",
                        text: "这类说法常用“触摸效应”和“微承诺”来解释：一旦亲手调整设备，人会更容易继续探索，也可能产生一点“它正在按我的方式工作”的心理归属感。和单相思不同，这一次不是你独自在脑海里完成全部交互：Mac 至少真的动了。"
                    )

                    StorySection(
                        symbol: "checkmark.seal",
                        title: "传闻，不是官方定理",
                        text: "Apple 并没有公开把 104° 写成全球门店统一规范，也没有正式确认上述心理设计目的。门店、机型、桌高和陈列方式都可能不同。所以请把它当作一则很有 Apple 气质、也很值得玩味的零售设计传闻。"
                    )

                    Label(
                        tr("彩蛋要求屏幕连续停在 104° 约 2 秒。短暂经过不会触发，就像你在她心里仅仅路过，也不会自动拥有故事的后续。"),
                        systemImage: "timer"
                    )
                    .font(.callout)
                    .foregroundStyle(AppPalette.accent)
                    .padding(14)
                    .background(
                        AppPalette.accent.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                }
            }
            .frame(maxHeight: 510)
        }
        .padding(28)
        .frame(width: 590)
    }
}

private struct StorySection: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppPalette.accent)
                .frame(width: 30, height: 30)
                .background(
                    AppPalette.accent.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 5) {
                Text(tr(title))
                    .font(.headline)
                Text(tr(text))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SidebarBrand: View {
    var body: some View {
        HStack(spacing: 10) {
            SidebarBrandMark()
            VStack(alignment: .leading, spacing: 1) {
                Text("Mac Unseen")
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer()
        }
    }
}

private struct SidebarBrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppPalette.brandSlate,
                            AppPalette.brandSlate.opacity(0.92),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            HStack(spacing: 0) {
                AppPalette.brandTeal
                AppPalette.brandAmber
                AppPalette.brandLavender
            }
            .frame(width: 25, height: 9)
            .clipShape(Capsule())
            .rotationEffect(.degrees(-8))
            .overlay {
                Capsule()
                    .stroke(.black.opacity(0.25), lineWidth: 1)
                    .frame(width: 25, height: 9)
                    .rotationEffect(.degrees(-8))
            }
        }
        .frame(width: 34, height: 34)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: AppPalette.brandSlate.opacity(0.24), radius: 7, y: 3)
        .accessibilityHidden(true)
    }
}

private struct SensorStatusPanel: View {
    @EnvironmentObject private var store: SensorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusLine(
                title: "高级传感器",
                active: store.advancedSensorsActive,
                detail: store.advancedSensorsActive
                    ? "SPU + SMC"
                    : store.advancedAccessPending
                        ? "正在连接传感器…"
                        : "需要管理员授权"
            )
        }
        .font(.caption)
        .padding(11)
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 14)
        )
        .background(
            AppPalette.accent.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppPalette.cardBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
    }
}

private struct StatusLine: View {
    let title: String
    let active: Bool
    let detail: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(active ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(tr(title))
                    .fontWeight(.medium)
                Text(tr(detail))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
