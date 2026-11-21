#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="${1:-$root/build}"
mkdir -p "$build"
build="$(cd "$build" && pwd)"
app="$build/Microphun.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers" "$build/cache"
export MACOSX_DEPLOYMENT_TARGET=13.0
mkdir -p "$build/rnnoise"
for source in "$root"/Vendor/rnnoise/src/*.c; do
    object="$(basename "$source" .c).o"
    clang -O3 -std=gnu99 -I"$root/Vendor/rnnoise/include" -c "$source" -o "$build/rnnoise/$object"
done
clang++ -std=c++17 -O2 -Wall -Wextra -c "$root/Sources/Mixer.cpp" -o "$build/Mixer.o"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$build/cache" -import-objc-header "$root/Sources/Mixer.h" "$root/Shared/CommandWire.swift" "$root"/Sources/*.swift "$build/Mixer.o" "$build"/rnnoise/*.o -lc++ -framework AudioToolbox -framework CoreAudio -framework AVFoundation -framework AppKit -framework SwiftUI -o "$app/Contents/MacOS/Microphun"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$build/cache" "$root/Shared/CommandWire.swift" "$root/CLI/main.swift" -framework AppKit -o "$app/Contents/Helpers/microphun"
codesign --force --sign - "$app/Contents/Helpers/microphun"
cp "$root/Resources/Info.plist" "$app/Contents/"
cp "$root/Vendor/rnnoise/COPYING" "$app/Contents/Resources/RNNoise-LICENSE.txt"
cp "$root/Resources/SoundCredits.txt" "$app/Contents/Resources/"
cp "$root/Resources/Microphun.icns" "$app/Contents/Resources/"
ditto "$root/Resources/Sounds" "$app/Contents/Resources/Sounds"
codesign --force --sign - --identifier com.nickkrstevski.microphun "$app"
codesign --verify --strict "$app"
echo "$app"
