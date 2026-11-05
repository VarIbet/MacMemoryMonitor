// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "MemoryMonitor", platforms: [.macOS(.v14)], products: [.executable(name: "MemoryMonitor", targets: ["MemoryMonitor"])], targets: [
    .target(name: "MemoryCore"),
    .executableTarget(name: "MemoryMonitor", dependencies: ["MemoryCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(name: "MemoryDiagnostics", dependencies: ["MemoryCore"])
])
