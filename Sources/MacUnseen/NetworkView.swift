// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct NetworkView: View {
    @EnvironmentObject private var store: SensorStore

    private var primaryInterface: NetworkInterfaceSnapshot? {
        store.network.interfaces.first
    }

    var body: some View {
        Page(
            title: "网络与接口",
            subtitle: "当前 IP、Wi-Fi 协议、网络流量和 USB-C / 雷雳连接状态"
        ) {
            Card(
                title: "网络状态",
                symbol: "network",
                tint: store.network.connected ? .green : .secondary
            ) {
                MetricGrid(
                    metrics: [
                        Metric(
                            name: "连接状态",
                            value: store.network.connected ? "已连接" : "未连接",
                            info: "只根据当前活动网络接口及其 IP 地址判断，不会向互联网发送探测请求。"
                        ),
                        Metric(
                            name: "活动接口",
                            value: primaryInterface?.name ?? "-",
                            detail: primaryInterface?.displayName
                        ),
                        Metric(
                            name: "当前 IPv4",
                            value: primaryInterface?.ipv4.first ?? "-",
                            info: "这是 Mac 当前网络接口的本机 IPv4 地址，不一定是路由器之外可见的公网 IP。"
                        ),
                        Metric(
                            name: "当前 IPv6",
                            value: primaryInterface?.ipv6.first ?? "-",
                            info: "显示首个非链路本地 IPv6 地址。仅以 fe80 开头的本地链路地址不会在这里显示。"
                        ),
                        Metric(
                            name: "VPN 隧道",
                            value: store.network.vpnInterfaceCount == 0
                                ? "未检测到"
                                : (
                                    AppLocalization.language == .english
                                        ? "\(store.network.vpnInterfaceCount) active interfaces"
                                        : "\(store.network.vpnInterfaceCount) 个活动接口"
                                ),
                            info: "根据活动的 utun 系统隧道接口统计。部分 Apple 系统服务也可能使用 utun，因此它不一定全部来自传统 VPN 软件。"
                        ),
                    ],
                    tint: .green
                )
            }

            Card(
                title: "Wi-Fi",
                symbol: "wifi",
                tint: store.network.wifi.connected ? .blue : .secondary,
                info: "SSID 等无线网络信息可能受 macOS 定位服务和隐私权限影响；协议、信道和速率以系统当前报告为准。"
            ) {
                MetricGrid(
                    metrics: [
                        Metric(
                            name: "Wi-Fi 状态",
                            value: store.network.wifi.connected ? "已连接" : "未连接",
                            detail: store.network.wifi.interfaceName
                        ),
                        Metric(
                            name: "网络名称",
                            value: emptyFallback(store.network.wifi.networkName),
                            detail: store.network.wifi.connected
                                && store.network.wifi.networkName.isEmpty
                                ? "允许定位权限后显示"
                                : nil,
                            info: "macOS 要求应用获得定位权限后才能读取当前 Wi-Fi 名称。应用只在本机显示名称，不记录或上传位置信息。"
                        ),
                        Metric(
                            name: "无线协议",
                            value: wifiProtocolName(
                                store.network.wifi.protocolName
                            ),
                            info: "例如 802.11ax 对应 Wi-Fi 6 / 6E，802.11ac 对应 Wi-Fi 5。具体是否为 6E 还取决于当前频段。"
                        ),
                        Metric(
                            name: "信道",
                            value: emptyFallback(store.network.wifi.channel)
                        ),
                        Metric(
                            name: "发送速率",
                            value: emptyFallback(store.network.wifi.transmitRate),
                            unit: store.network.wifi.transmitRate.isEmpty
                                ? ""
                                : "Mb/s",
                            info: "这是无线链路当前协商或报告的发送速率，不等同于实际下载速度。"
                        ),
                        Metric(
                            name: "信号 / 噪声",
                            value: emptyFallback(store.network.wifi.signalNoise),
                            info: "通常以 dBm 表示。信号越接近 0 越强，信号与噪声之间的差距越大，一般代表链路质量越好。"
                        ),
                        Metric(
                            name: "网络安全",
                            value: emptyFallback(store.network.wifi.security)
                        ),
                    ],
                    tint: .blue
                )
            }

            if !store.network.interfaces.isEmpty {
                Card(
                    title: "活动网络接口",
                    symbol: "arrow.up.arrow.down.circle",
                    tint: .teal,
                    info: "收发流量从本次开机后开始累计，接口重建或系统重启后可能重新计数。"
                ) {
                    ForEach(store.network.interfaces) { interface in
                        NetworkInterfaceRow(interface: interface)
                        if interface.id != store.network.interfaces.last?.id {
                            SoftDivider()
                        }
                    }
                }
            }

            Card(
                title: "USB-C 与雷雳接口",
                symbol: "cable.connector",
                tint: .indigo,
                info: "断开时显示的是端口能力上限；连接后显示系统实际识别到的设备和报告速度。仅凭 40 Gb/s 有时无法可靠区分雷雳 3、雷雳 4 与 USB4，因此不会强行猜测版本。"
            ) {
                if store.network.ports.isEmpty {
                    Text(tr("未读取到 USB-C / 雷雳端口状态。"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.network.ports) { port in
                        ConnectionStatusRow(
                            title: port.name,
                            connected: port.connected,
                            subtitle: port.connected
                                ? emptyFallback(port.deviceName, fallback: "已连接设备")
                                : "未连接设备",
                            trailing: [port.protocolName, port.speed]
                                .filter { !$0.isEmpty }
                                .joined(separator: " · ")
                        )
                        if port.id != store.network.ports.last?.id {
                            SoftDivider()
                        }
                    }
                }
            }

            Card(
                title: "已连接外设",
                symbol: "externaldrive.connected.to.line.below",
                tint: .purple
            ) {
                if store.network.peripherals.isEmpty {
                    Text(tr("当前没有通过 USB 或雷雳识别到外接设备。"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.network.peripherals) { device in
                        ConnectionStatusRow(
                            title: device.name,
                            connected: true,
                            subtitle: emptyFallback(
                                device.vendor,
                                fallback: device.protocolName
                            ),
                            trailing: [
                                device.protocolName,
                                device.speed,
                                device.power,
                            ]
                                .filter { !$0.isEmpty }
                                .joined(separator: " · ")
                        )
                        if device.id != store.network.peripherals.last?.id {
                            SoftDivider()
                        }
                    }
                }
            }

            HardwareUpdatedLabel(date: store.network.updatedAt)
        }
    }
}

private struct NetworkInterfaceRow: View {
    let interface: NetworkInterfaceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(interface.name)
                        .font(.headline.monospaced())
                    Text(tr(interface.displayName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(interface.ipv4.first ?? interface.ipv6.first ?? "-")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
            MetricGrid(
                metrics: [
                    Metric(
                        name: "本次开机已接收",
                        value: formatBytes(interface.receivedBytes)
                    ),
                    Metric(
                        name: "本次开机已发送",
                        value: formatBytes(interface.sentBytes)
                    ),
                ],
                tint: .teal
            )
        }
        .padding(.vertical, 3)
    }
}

private struct ConnectionStatusRow: View {
    let title: String
    let connected: Bool
    let subtitle: String
    let trailing: String

    var body: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(connected ? Color.green : Color.secondary.opacity(0.45))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr(title))
                    .fontWeight(.medium)
                Text(tr(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(trailing)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}
