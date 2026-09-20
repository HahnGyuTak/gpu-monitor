// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GPUMonitor",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "GPUMonitor", targets: ["GPUMonitor"])],
    targets: [
        .executableTarget(name: "GPUMonitor", resources: [.copy("Resources/collector.py"), .copy("Resources/host_pid_map.py"), .copy("Resources/tmux_sessions.py")])
    ]
)
