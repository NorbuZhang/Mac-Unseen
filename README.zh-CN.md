# Mac Unseen

[English](README.md) · [下载](https://github.com/NorbuZhang/Mac-Unseen/releases) · [0.2.0 更新日志](RELEASE_NOTES_v0.2.0.md)

看看你的 Mac 正在做什么：从 CPU、内存占用，到电池、温度和系统里不容易找到的传感器数据。Mac Unseen 使用 SwiftUI 开发，适用于 Apple Silicon Mac。


## 能看什么

- **性能与进程**：CPU、GPU、内存压力、磁盘读写和网络吞吐量。进程可单独查看或按软件归并，支持搜索和点击表头排序。
- **电池与供电**：系统健康度、满充容量、Qmax、循环次数、电芯数据、充电功率，以及可读取的 MagSafe 固件。健康度和容量比例分开显示。
- **硬件与系统**：温度、风扇、存储健康、Wi-Fi、端口和外设。硬件规格与实时读数放在一起，软件和系统报告支持筛选。
- **交互传感器**：运动、震动、屏幕开合角度、环境光和触控板触点。也藏了几个小功能，比如用屏幕开合来演奏的手风琴。

离开对应页面后，实时监控会暂停；内存压力保留本次运行的历史。默认使用标准设计，也可以通过工具栏的调色板切换到强调色设计。

部分读数依赖 Apple 未公开的接口，是否可用取决于机型和 macOS 版本。

<details>
<summary>更多截图（较早版本）</summary>

<img width="1280" alt="Mac Unseen 硬件读数" src="https://github.com/user-attachments/assets/28342cf7-7bf2-4a2b-b800-2f43dcdb9155" />
<img width="1280" alt="Mac Unseen 传感器页面" src="https://github.com/user-attachments/assets/48321922-7116-4edb-9f5b-87750bb9c8ed" />
<img width="1280" alt="Mac Unseen 详细信息" src="https://github.com/user-attachments/assets/578fc39b-e4f2-4418-a3f2-abcb43409c82" />

</details>

## 下载与使用

需要 **Apple Silicon Mac 和 macOS 15 或更新版本**。从 [Releases](https://github.com/NorbuZhang/Mac-Unseen/releases) 下载 ZIP，解压后将应用移到“应用程序”文件夹。

| 版本 | 怎么选 |
| --- | --- |
| 标准版 | 下载更小，适用于已安装Python 3的Mac。 |
| 内置 Python 版 | 自带 Python；没装 Python，或不确定有没有，选这个即可。 |

基础监控不需要 Python。当前发布包未经过 Apple 公证，首次打开若被 macOS 拦截，可前往 **系统设置 → 隐私与安全性 → 仍要打开**。

大多数读数无需管理员权限。需要高级传感器、风扇、功耗或完整 NVMe SMART 数据时，点击 **启用隐藏传感器**，按系统提示授权。显示 Wi-Fi 名称可能还需要定位权限。

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

## 隐私

硬件数据只在本机显示，不会上传。应用不会调整风扇转速、功耗限制或亮度。高级采集器在授权后启动，不会安装常驻服务。

## 从源码构建

使用带有 Swift 6.2 或更新版本的 Xcode：

```sh
swift build -c release
swift test
```

生成应用包前，将同一 Release 的 `Mac-Unseen-0.2.0-build-inputs.tar.xz` 解压到仓库根目录，再运行 `scripts/build_app.sh`。依赖和内置 Python 版的打包步骤见 [BUILDING.md](BUILDING.md)。

## 反馈与许可

发现 Bug 或有好的建议，欢迎[提交 Issue](https://github.com/NorbuZhang/Mac-Unseen/issues)。想支持后续开发，也可以在应用内的“请我喝杯奶茶”页面使用微信、支付宝或 PayPal。

Mac Unseen 的原创代码使用 [MPL-2.0](LICENSE)。第三方组件保留各自的许可，详见[致谢与来源](Resources/Attributions.txt)和[源码分发说明](OPEN_SOURCE_COMPLIANCE.md)。
