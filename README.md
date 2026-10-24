# Mac Unseen

[简体中文](README.zh-CN.md) · [Download](https://github.com/NorbuZhang/Mac-Unseen/releases) · [What's new in 0.2.0](RELEASE_NOTES_v0.2.0.md)

See what your Mac is doing—from CPU and memory usage to battery details, temperatures, and sensors macOS usually keeps out of sight. Built with SwiftUI for Apple Silicon Macs.

<img width="1280" alt="Mac Unseen overview in an earlier version" src="https://github.com/user-attachments/assets/52edfa9b-ab73-4547-b5d3-7e7d15fe4345" />

## What you can see

- **Performance:** CPU and GPU activity, memory pressure, disk I/O, and network throughput. View processes individually or grouped by app, with search and sortable columns.
- **Battery and power:** macOS battery health, full-charge capacity, Qmax, cycle count, cell readings, charging power, and available MagSafe firmware details. Health and capacity ratios are shown separately.
- **Hardware:** temperatures, fan speeds, storage health, Wi-Fi, ports, and connected devices. Specifications sit alongside live readings; software and system reports are searchable.
- **Sensors:** motion, vibration, lid angle, ambient light, and trackpad contacts. There are a few extras to discover, including a lid-powered accordion.

Live monitoring pauses when its page is no longer active. Memory-pressure history is kept for the current app session. Standard Design is the default; switch to Accent Design from the toolbar palette.

Some readings use undocumented Apple interfaces, so availability varies by model and macOS version.

<details>
<summary>More screenshots (earlier versions)</summary>

<img width="1280" alt="Mac Unseen hardware readings" src="https://github.com/user-attachments/assets/e4d9f803-294b-4b4d-b2d0-4f8e0d635e17" />
<img width="1280" alt="Mac Unseen sensor view" src="https://github.com/user-attachments/assets/03151b3c-0560-43aa-8182-7543397fdc05" />
<img width="1280" alt="Mac Unseen detail view" src="https://github.com/user-attachments/assets/50b0ebba-1af2-4699-8f63-c112b41bd344" />

</details>

## Download and run

Requires **Apple Silicon and macOS 15 or later**. Download a ZIP from [Releases](https://github.com/NorbuZhang/Mac-Unseen/releases), unzip it, and move the app to Applications.

| Build | Which to choose |
| --- | --- |
| Standard | Smaller download. Uses an installed Python 3 for advanced sensors. |
| Python Runtime | Includes Python. Choose this if you do not have Python or are unsure. |

Basic monitoring does not need Python. These builds are not notarized; if macOS blocks the first launch, go to **System Settings → Privacy & Security → Open Anyway**.

Most readings need no administrator access. Choose **Enable Hidden Sensors** when you want advanced sensor, fan, power, or full NVMe SMART readings, then approve the macOS prompt. Wi-Fi network names may also need Location permission.

## Privacy

Hardware readings stay on your Mac. The app does not upload telemetry or change fan speeds, power limits, or brightness. The advanced collector runs after authorization and does not install a persistent service.

## Build from source

Use Xcode with Swift 6.2 or newer:

```sh
swift build -c release
swift test
```

To package an app, first extract the release's `Mac-Unseen-0.2.0-build-inputs.tar.xz` at the repository root, then run `scripts/build_app.sh`. See [BUILDING.md](BUILDING.md) for dependencies and the Python Runtime build.

## Feedback and credits

Found a bug or have an idea? [Open an issue](https://github.com/NorbuZhang/Mac-Unseen/issues). If you would like to support development, **Buy me a coffee** in the app offers WeChat, Alipay, and PayPal.

Mac Unseen's original code is licensed under [MPL-2.0](LICENSE). Third-party components retain their own licenses; see [attributions](Resources/Attributions.txt) and [source-distribution notes](OPEN_SOURCE_COMPLIANCE.md).
