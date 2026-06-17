# Mac Unseen

[English Ver.](README.md)

Mac Unseen 是一款给 Apple Silicon Mac 使用的 macOS 硬件遥测工具。它把系统信息、电池与供电、存储健康、网络状态、触控板触摸数据，以及一些隐藏的只读传感器读数放在同一个原生 SwiftUI 应用里。

这个应用的定位是“查看”，不是“控制硬件”。它不会修改风扇曲线、功耗限制、屏幕亮度、键盘亮度或系统设置，也不会上传遥测数据。

## 功能

- 总览页显示 Mac、电池、存储、网络、触控板和隐藏传感器采集器的实时状态。
- 读取 Apple Silicon 内部运动传感器，包括加速度计、陀螺仪、姿态、震动强度和可调采样率。
- 在机型支持时显示屏幕开合角度、环境光和原始光谱通道数据。
- 显示触控板原始触摸流，包括位置、接触面积、密度和相对压力值。
- 通过随包提供的只读辅助工具读取温度、风扇、功耗、电流、电压和 SMC/HID 遥测。
- 查看电池健康度、循环次数、电芯数据、充放电功率、充电器信息和 USB-C 供电协商状态。
- 查看存储信息、NVMe SMART 健康度、终身读写量、通电小时数和介质错误计数。
- 查看网络、Wi-Fi、VPN、USB-C、Thunderbolt 和外接设备状态。

部分读数取决于具体机型。这里用到的一些接口 Apple 没有公开文档，所以不同 macOS 版本或不同 Mac 上可能会缺少某些数据，也可能出现变化。
我也在这个小工具中埋下了点有趣的小彩蛋，可以尝试探索一下。

## 系统要求

- Apple Silicon Mac
- macOS 15 或更新版本
- 如果从源码构建，需要安装 Xcode 或 Xcode Command Line Tools

## 下载版本

当前版本依赖Python3环境运行，因此发布包会提供两个版本：

- 标准版：体积更小。它会使用 Mac 上已有的 Python 运行隐藏传感器采集器。
- 内置 Python 版：体积更大。它会随 App 带上 Python framework，适合没有可用 Python、Python 受限，或标准版无法启动隐藏传感器的 Mac。

如果不确定该下载哪个，建议先试标准版。如果 App 可以打开，但隐藏传感器因为 Python 不可用而启动失败，再换内置 Python 版。

## 运行方式

如果你下载的是已经打包好的 App，解压后可以把 `Mac Unseen.app` 移到 `Applications` 里或直接运行。
社区构建版本可能没有经过 Apple notarization，第一次打开时 macOS 可能会拦截。如果遇到这种情况：

<img width="269" height="243" alt="image" src="https://github.com/user-attachments/assets/1b356c3d-ab7a-4569-86c3-e3a23d974f58" />

1. 打开 `系统设置`。
2. 进入 `隐私与安全性`。
3. 滚动到和 Mac Unseen 相关的安全提示。
4. 选择 `仍要打开`，然后在下一次启动提示里确认。
<img width="1436" height="1238" alt="image" src="https://github.com/user-attachments/assets/a1adc774-ccca-42ac-97ae-3057de35f82f" />


也可以先尝试右键点击 App 选择 `打开`，但较新的 macOS 版本仍然可能要求你到 `隐私与安全性` 里确认。

大多数基础页面不需要管理员权限。隐藏传感器、风扇遥测、SMC 功耗数据，以及内置 NVMe SSD 的完整 SMART 数据需要管理员授权，因为 macOS 没有通过普通公开 API 暴露这些读数。在应用里点击 `启用隐藏传感器`，然后批准 macOS 弹出的授权提示即可。

Wi-Fi 名称显示可能还需要定位权限。macOS 会把当前 Wi-Fi 名称视为和位置相关的数据。Mac Unseen 只在本机显示这项信息。

## 从源码构建

这个项目是一个 Swift Package：

```sh
swift build -c release
```

如果要生成 `.app` 包，运行：

```sh
scripts/build_app.sh
```

打包脚本会读取 `work/vendor/` 下的第三方输入。这个上传用目录只保留了当前打包路径需要的 vendor 文件，没有带上本地构建缓存或旧的发布产物。

## 隐私与安全

Mac Unseen 只读取本机硬件和传感器数据。它不会把数据发送到服务器，不会安装后台服务，也不会让特权守护进程在辅助采集器退出后继续常驻。

隐藏传感器采集器只会在用户授权后启动。它会在 `/tmp/MacUnseen-<uid>/` 下写入本地 JSON 快照，供 Swift 主程序读取。

## License

除非文件或目录另有说明，本仓库中 Mac Unseen 自己编写的源代码默认使用 Mozilla Public License 2.0。完整文本见 `LICENSE`。

同一个仓库里可以按文件或目录使用不同 license。本仓库通过 SPDX 文件头和第三方 notice 文件明确这些边界：

- Mac Unseen 的 Swift、Python、C bridge、打包脚本和应用资源：默认 `MPL-2.0`，除非文件中另有说明。
- `Tools/fan_speed_probe.c`：`GPL-3.0-only`。
- `work/vendor/iSMC` 和 `work/vendor/ismc-release`：`GPL-3.0-only`。
- `work/vendor/smartmontools-7.5`：`GPL-2.0-or-later`。
- `work/vendor/apple-silicon-accelerometer` 和 `work/vendor/OpenMultitouchSupport` 的 license notice：MIT。
- iSMC 运行时依赖的 notice 放在 `LICENSES/iSMC-Dependencies/`。
- 内置 Python 版随包包含 Python 3.14，按 Python Software Foundation License Version 2 及其随附 notice 分发。

`OPEN_SOURCE_COMPLIANCE.md` 和 `Resources/Attributions.txt` 记录了当前的依赖审计和发布义务。GPL 覆盖的命令行工具必须继续按对应 GPL 分发，发布二进制时也必须提供完整对应源码。
