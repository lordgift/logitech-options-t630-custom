// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LogiSwipe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "LogiSwipe", path: "Sources/LogiSwipe"),
    ]
)
