// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BarManager",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BarManager",
            path: "Sources/BarManager"
        ),
        .testTarget(
            name: "BarManagerTests",
            dependencies: ["BarManager"],
            path: "Tests/BarManagerTests"
        ),
    ]
)
