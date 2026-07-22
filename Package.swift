// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AIUsageBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AIUsageBar",
            path: "Sources/AIUsageBar"
        ),
        .testTarget(
            name: "AIUsageBarTests",
            dependencies: ["AIUsageBar"],
            path: "Tests/AIUsageBarTests"
        )
    ]
)
