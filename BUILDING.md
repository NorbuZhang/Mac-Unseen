# Building Mac Unseen 0.2.0

Use an Apple Silicon Mac with Xcode/Swift 6.2 or newer and a macOS SDK supporting
the package. The app targets macOS 15 and later.

## Source and tests

```sh
swift build -c release
swift test
python3 Tests/AdvancedSensorHelperTests.py
```

## App bundles

Download `Mac-Unseen-0.2.0-build-inputs.tar.xz` and `SHA256SUMS.txt` from the
0.2.0 Release. Check the archive's SHA-256 against that file, then extract it
**at the repository root**:

```sh
tar -xJf /path/to/Mac-Unseen-0.2.0-build-inputs.tar.xz
scripts/build_app.sh
```

This supplies the exact `work/vendor/` inputs expected by the script: iSMC source
and its official binary, smartctl and its source archive, and license files.
Outputs appear under `outputs/`. Packaging uses local ad-hoc signing; it does
not perform Developer ID signing or Apple notarization.

The Python Runtime package additionally needs the python.org Python 3.14 framework
at `/Library/Frameworks/Python.framework`. The prepared 0.2.0 binaries use 3.14.7.

```sh
scripts/build_python_runtime.sh
```

To rebuild iSMC from the included source without fetching modules, use Go 1.26
or newer with Xcode command line tools:

```sh
cd work/vendor/iSMC
GOPROXY=off GOSUMDB=off go build -mod=vendor -trimpath -o iSMC .
```

This verifies source completeness; it is not a claim of bit-for-bit reproduction
of the upstream release binary. Keep all third-party notices and source materials
when redistributing. See `OPEN_SOURCE_COMPLIANCE.md` and `Resources/Attributions.txt`.

<details>
<summary>简体中文</summary>

在 Apple Silicon Mac 上使用 Xcode／Swift 6.2 或更新版本。先按上面的命令构建或运行测试。
生成应用包前，下载同一 Release 的 `Mac-Unseen-0.2.0-build-inputs.tar.xz`，
核对 `SHA256SUMS.txt` 后在仓库根目录解压，再运行 `scripts/build_app.sh`。
产物位于 `outputs/`；脚本使用本地临时签名，不包含 Apple 公证。

打包内置 Python 版还需要安装 python.org 的 Python 3.14 framework；本次发布使用 3.14.7。
随后运行 `scripts/build_python_runtime.sh`。源码材料保留了 iSMC 所需的 Go 依赖，
可离线编译；这不代表与上游二进制逐字节一致。分发时请一并保留第三方许可和源码材料。

</details>
