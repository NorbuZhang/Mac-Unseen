#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
SERVICE="$ROOT/Tools/FanService"
PAYLOAD="$ROOT/work/fan-package-root"
BUILD="$ROOT/work/fan-build"
OUTPUT="$1"
swift build -c release --package-path "$SERVICE" --scratch-path "$BUILD" --product fanctld
BIN="$(swift build -c release --package-path "$SERVICE" --scratch-path "$BUILD" --show-bin-path)"
label=com.norbu.MacUnseen.fanctld
mkdir -p "$PAYLOAD/Library/LaunchDaemons" "$PAYLOAD/Library/PrivilegedHelperTools"
install -m 755 "$BIN/fanctld" "$PAYLOAD/Library/PrivilegedHelperTools/$label"
codesign --force --sign - --identifier "$label" "$PAYLOAD/Library/PrivilegedHelperTools/$label"
install -m 644 "$SERVICE/$label.plist" "$PAYLOAD/Library/LaunchDaemons/$label.plist"
pkgbuild --root "$PAYLOAD" --ownership recommended --scripts "$SERVICE/installer" \
    --identifier "$label" --version 25 --install-location / "$OUTPUT"
