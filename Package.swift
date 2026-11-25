// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BarManager",
    platforms: [.macOS(.v14)],
    dependencies: [
        // In-app updates. scripts/build.sh copies Sparkle.framework into the app.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "BarManager",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/BarManager"
        ),
        .testTarget(
            name: "BarManagerTests",
            dependencies: ["BarManager"],
            path: "Tests/BarManagerTests"
        ),
    ]
)
