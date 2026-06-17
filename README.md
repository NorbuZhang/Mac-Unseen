[README.md](https://github.com/user-attachments/files/29035324/README.md)
# Mac Unseen

[简体中文 Chinese Simplify Ver.](README.zh-CN.md)

Mac Unseen is a macOS hardware telemetry app for Apple Silicon Macs. It brings together system information, battery and power details, storage health, network state, trackpad touch data, and hidden read-only sensor readings in one native SwiftUI app.

The app is designed for inspection, not hardware control. It does not change fan curves, power limits, display brightness, keyboard brightness, or system settings, and it does not upload telemetry.

## Features

- System overview with live status for the Mac, battery, storage, network, trackpad, and hidden-sensor collector.
- Motion readings from internal Apple Silicon sensors, including accelerometer, gyroscope, orientation, vibration level, and adjustable sample rate.
- Display angle, ambient light, and raw spectral channel readings where the Mac exposes them.
- Trackpad touch stream with position, contact area, density, and relative pressure values.
- Temperature, fan, power, current, voltage, and SMC/HID telemetry through bundled read-only helper tools.
- Battery health details, cycle count, cell data, charge/discharge power, adapter information, and USB-C power negotiation.
- Storage information, NVMe SMART health, lifetime reads and writes, power-on hours, and media error counters.
- Network, Wi-Fi, VPN, USB-C, Thunderbolt, and connected peripheral status.

Some readings depend on model support. Apple does not document several of the interfaces used here, so values may be missing or change across macOS releases.

## Requirements

- Apple Silicon Mac
- macOS 15 or later
- Xcode command line tools or Xcode, if building from source

## Download Options

The current version requires a Python3 environment to run. As a result, release builds may be offered in two variants:

- Standard build: smaller download. It uses the Python runtime already available on the Mac to run the hidden-sensor collector.
- Python-included build: larger download. It bundles a Python framework for Macs where the required Python runtime is missing, restricted, or unreliable.

If you are not sure which one to choose, try the standard build first. Use the Python-included build if the app opens but hidden sensors do not start because Python is unavailable.

## Running the App

If you download a built app, unzip it and move `Mac Unseen.app` to `Applications` if you want to keep it installed or run it directly.

Because community builds may not be notarized, macOS can block the first launch. If that happens:

<img width="265" height="290" alt="image" src="https://github.com/user-attachments/assets/42c05292-a2bb-4aca-b941-195d020b4308" />

1. Open `System Settings`.
2. Go to `Privacy & Security`.
3. Scroll to the security message for Mac Unseen.
4. Choose `Open Anyway`, then confirm the next launch prompt.
<img width="1442" height="940" alt="image" src="https://github.com/user-attachments/assets/7648f782-7a78-4478-b6da-64da43eda9cc" />

You can also try right-clicking the app and choosing `Open`, but newer macOS versions may still ask you to approve it in `Privacy & Security`.

Most basic pages work without administrator access. Hidden sensors, fan telemetry, SMC power data, and full internal NVMe SMART data need an administrator prompt because macOS does not expose those readings through ordinary public APIs. In the app, choose `Enable Hidden Sensors` and approve the macOS prompt when it appears.

Wi-Fi SSID display may also require Location permission. macOS treats the current Wi-Fi network name as location-sensitive data. Mac Unseen only shows it locally.

## Build From Source

The project is a Swift Package:

```sh
swift build -c release
```

To create an app bundle, run:

```sh
scripts/build_app.sh
```

The bundle script expects the vendored third-party inputs under `work/vendor/`. This upload copy keeps only the vendor files needed by the current packaging path, not local build caches or prior release outputs.

## Privacy and Safety

Mac Unseen reads local hardware and sensor data. It does not send data to a server, install a background service, or keep a privileged daemon running after the helper exits.

The hidden-sensor collector is started only after user approval. It writes a local JSON snapshot under `/tmp/MacUnseen-<uid>/` for the Swift app to read.

## License

Unless a file or directory says otherwise, this repository's original Mac Unseen source code is licensed under the Mozilla Public License 2.0. See `LICENSE`.

Different files can use different licenses. This repository uses SPDX file headers and third-party notice files to make those boundaries explicit:

- Mac Unseen Swift, Python, C bridge, packaging, and app resources: `MPL-2.0`, except where stated otherwise.
- `Tools/fan_speed_probe.c`: `GPL-3.0-only`.
- `work/vendor/iSMC` and `work/vendor/ismc-release`: `GPL-3.0-only`.
- `work/vendor/smartmontools-7.5`: `GPL-2.0-or-later`.
- `work/vendor/apple-silicon-accelerometer` and `work/vendor/OpenMultitouchSupport` license notices: MIT.
- iSMC runtime dependency notices are collected under `LICENSES/iSMC-Dependencies/`.
- Python Runtime builds bundle Python 3.14 under the Python Software Foundation License Version 2 and related bundled notices.

`OPEN_SOURCE_COMPLIANCE.md` and `Resources/Attributions.txt` describe the current dependency audit and release obligations. GPL-covered command-line tools must remain under their GPL licenses, and complete corresponding source must be made available with binary releases.
