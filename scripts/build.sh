#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" .build/cache
swift build -c release --arch arm64 --disable-sandbox --cache-path "$PWD/.build/cache"
APP="$PWD/dist/Memory Monitor.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/arm64-apple-macosx/release/MemoryMonitor "$APP/Contents/MacOS/MemoryMonitor"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "$APP"
