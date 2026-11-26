#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 m1ll3t
set -euo pipefail
cd "${0:A:h}"
export CLANG_MODULE_CACHE_PATH=/tmp/wemacro-clang
swift build --disable-sandbox -c release --scratch-path .build
app="$PWD/dist/WeMacro 1.1.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/WeMacroMac "$app/Contents/MacOS/WeMacroMac"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
cp NOTICE "$app/Contents/Resources/NOTICE.txt"
cat > "$app/Contents/Resources/SOURCE.txt" <<'SOURCE'
WeMacroMac is licensed under GPL-3.0-only.
Corresponding source and build instructions for this distribution:
https://github.com/m1ll3t/WeMacroMac/tree/v1.1.0-beta.3
https://github.com/m1ll3t/WeMacroMac/releases/download/v1.1.0-beta.3/WeMacro-1.1-source.zip
SOURCE
iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"
icon_png="$PWD/Resources/AppIcon.png"
for spec in '16 16' '32 32' '64 32' '128 128' '256 128' '256 256' '512 256' '512 512' '1024 512'; do
  set -- $=spec
  pixels="$1"; base="$2"
  suffix=""
  (( pixels > base )) && suffix="@2x"
  sips -s format png -z "$pixels" "$pixels" "$icon_png" --out "$iconset/icon_${base}x${base}${suffix}.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "${iconset:h}"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>WeMacroMac</string>
<key>CFBundleIdentifier</key><string>local.millet.wemacromac.preview</string>
<key>CFBundleName</key><string>WeMacro</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>CFBundleVersion</key><string>112</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 m1ll3t. GPL-3.0-only.</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSBluetoothAlwaysUsageDescription</key><string>连接 WeMacro HC-08 控制器，控制滑轨移动和相机快门。</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
echo "$app"
