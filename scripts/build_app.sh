#!/bin/zsh
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/work/.build"
PACKAGE_DIR="$ROOT/work/package"
APP_NAME="Mac Unseen"
EXECUTABLE_NAME="MacUnseen"
STAGE_APP="$PACKAGE_DIR/$APP_NAME.app"
OUTPUT_APP="$ROOT/outputs/$APP_NAME.app"
OUTPUT_ZIP="$ROOT/outputs/$APP_NAME.zip"
CONTENTS="$STAGE_APP/Contents"
RESOURCES="$CONTENTS/Resources"
ICONSET="$PACKAGE_DIR/AppIcon.iconset"
ICON_PNG="$PACKAGE_DIR/AppIcon-1024.png"
FAN_PROBE="$PACKAGE_DIR/FanSpeedProbe"
SOURCE_STAGE="$PACKAGE_DIR/source-stage"

mkdir -p "$ROOT/outputs" "$ROOT/work/cache/clang" "$PACKAGE_DIR"
rm -rf \
    "$STAGE_APP" "$OUTPUT_APP" "$OUTPUT_ZIP" "$ICONSET" "$ICON_PNG" \
    "$FAN_PROBE" "$SOURCE_STAGE"

export CLANG_MODULE_CACHE_PATH="$ROOT/work/cache/clang"
swift build -c release --scratch-path "$BUILD_DIR"
BIN_DIR="$(swift build -c release --scratch-path "$BUILD_DIR" --show-bin-path)"

mkdir -p \
    "$CONTENTS/MacOS" \
    "$RESOURCES/Licenses/iSMC-Dependencies" \
    "$RESOURCES/Source/FanSpeedProbe"
install -m 755 "$BIN_DIR/$EXECUTABLE_NAME" "$CONTENTS/MacOS/$EXECUTABLE_NAME"
install -m 755 "$ROOT/Resources/advanced_sensor_helper.py" \
    "$RESOURCES/advanced_sensor_helper.py"
install -m 755 "$ROOT/work/vendor/ismc-release/iSMC" "$RESOURCES/iSMC"
/usr/bin/lipo "$RESOURCES/iSMC" -thin arm64 -output "$RESOURCES/iSMC.arm64"
mv "$RESOURCES/iSMC.arm64" "$RESOURCES/iSMC"
install -m 755 "$ROOT/work/vendor/smartmontools-7.5/smartctl" \
    "$RESOURCES/smartctl"
xcrun clang -Os \
    -I "$ROOT/work/vendor/iSMC/gosmc" \
    "$ROOT/Tools/fan_speed_probe.c" \
    "$ROOT/work/vendor/iSMC/gosmc/smc.c" \
    -framework IOKit \
    -framework CoreFoundation \
    -o "$FAN_PROBE"
install -m 755 "$FAN_PROBE" "$RESOURCES/FanSpeedProbe"
strip -x \
    "$CONTENTS/MacOS/$EXECUTABLE_NAME" \
    "$RESOURCES/iSMC" \
    "$RESOURCES/smartctl" \
    "$RESOURCES/FanSpeedProbe"
install -m 644 "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
install -m 644 "$ROOT/Resources/Attributions.txt" "$RESOURCES/Attributions.txt"
install -m 644 "$ROOT/OPEN_SOURCE_COMPLIANCE.md" \
    "$RESOURCES/OPEN_SOURCE_COMPLIANCE.md"
install -m 644 "$ROOT/work/vendor/apple-silicon-accelerometer/LICENSE" \
    "$RESOURCES/Licenses/apple-silicon-accelerometer-MIT.txt"
install -m 644 "$ROOT/work/vendor/OpenMultitouchSupport/LICENSE" \
    "$RESOURCES/Licenses/OpenMultitouchSupport-MIT.txt"
install -m 644 "$ROOT/work/vendor/ismc-release/LICENSE" \
    "$RESOURCES/Licenses/iSMC-GPL-3.0.txt"
install -m 644 "$ROOT/work/vendor/smartmontools-7.5/COPYING" \
    "$RESOURCES/Licenses/smartmontools-GPL-2.0.txt"
for license in "$ROOT/Resources/Licenses/iSMC-Dependencies/"*.txt
do
    install -m 644 "$license" "$RESOURCES/Licenses/iSMC-Dependencies/"
done

COPYFILE_DISABLE=1 XZ_OPT=-9e /usr/bin/tar \
    --exclude=.git \
    -cJf "$RESOURCES/Source/iSMC-v0.16.5-source.tar.xz" \
    -C "$ROOT/work/vendor" iSMC
mkdir -p "$SOURCE_STAGE"
COPYFILE_DISABLE=1 XZ_OPT=-9e /usr/bin/tar \
    -xzf "$ROOT/work/vendor/smartmontools-7.5/smartmontools-7.5-source.tar.gz" \
    -C "$SOURCE_STAGE"
COPYFILE_DISABLE=1 /usr/bin/tar \
    -cJf "$RESOURCES/Source/smartmontools-7.5-source.tar.xz" \
    -C "$SOURCE_STAGE" smartmontools-7.5
rm -rf "$SOURCE_STAGE"
install -m 644 "$ROOT/Tools/fan_speed_probe.c" \
    "$RESOURCES/Source/FanSpeedProbe/fan_speed_probe.c"
install -m 644 "$ROOT/work/vendor/iSMC/gosmc/smc.c" \
    "$RESOURCES/Source/FanSpeedProbe/smc.c"
install -m 644 "$ROOT/work/vendor/iSMC/gosmc/smc.h" \
    "$RESOURCES/Source/FanSpeedProbe/smc.h"
install -m 644 "$ROOT/work/vendor/iSMC/gosmc/LICENSE" \
    "$RESOURCES/Source/FanSpeedProbe/LICENSE"
install -m 644 "$ROOT/Resources/FanSpeedProbe-BUILDING.txt" \
    "$RESOURCES/Source/FanSpeedProbe/BUILDING.txt"

mkdir -p "$ICONSET" "$ROOT/work/cache/icon"
xcrun swift -module-cache-path "$ROOT/work/cache/icon" \
    "$ROOT/scripts/make_icon.swift" \
    "$ROOT/Resources/AppIcon-1024.png" \
    "$ICON_PNG"

for item in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"
do
    size="${item%% *}"
    name="${item#* }"
    sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET/$name" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"

/usr/libexec/PlistBuddy -c \
    "Add :BuildMachineModel string $(sysctl -n hw.model)" \
    "$CONTENTS/Info.plist"

PYTHONPYCACHEPREFIX="$ROOT/work/pycache" \
    /usr/bin/python3 -m py_compile "$RESOURCES/advanced_sensor_helper.py"
plutil -lint "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$STAGE_APP"
codesign --verify --deep --strict --verbose=2 "$STAGE_APP"

ditto "$STAGE_APP" "$OUTPUT_APP"
ditto -c -k --norsrc --noextattr --keepParent \
    --zlibCompressionLevel 9 "$OUTPUT_APP" "$OUTPUT_ZIP"

echo "$OUTPUT_APP"
