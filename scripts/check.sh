#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build --disable-sandbox --cache-path "$PWD/.build/cache"
swiftc -O -swift-version 5 -I .build/arm64-apple-macosx/debug/MemoryCore.build -module-cache-path .build/module-cache Sources/MemoryMonitor/Models.swift Sources/MemoryMonitor/ProcessIconResolver.swift Tests/HistoryChecks.swift .build/arm64-apple-macosx/debug/MemoryCore.build/MemoryCore.c.o -o .build/HistoryChecks
.build/HistoryChecks
.build/arm64-apple-macosx/debug/MemoryDiagnostics
