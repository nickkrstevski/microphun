#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="${1:-$root/build}"
driver="$build/driver-root/MicrophunAudio.driver"
mkdir -p "$driver/Contents/MacOS"
clang++ -mmacosx-version-min=13.0 -std=c++17 -O2 -Wall -Wextra -fvisibility=hidden -bundle "$root/Driver/MicrophunDriver.cpp" -framework CoreFoundation -framework CoreAudio -o "$driver/Contents/MacOS/MicrophunAudio"
cp "$root/Driver/Info.plist" "$driver/Contents/Info.plist"
codesign --force --sign - "$driver"
codesign --verify --strict "$driver"
pkgbuild --root "$build/driver-root" --ownership recommended --install-location /Library/Audio/Plug-Ins/HAL --identifier com.nickkrstevski.microphun.driver.pkg --version 1.0 "$build/Microphun Audio Driver.pkg"
