// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MaoShot",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MaoShotCore"),
        .executableTarget(name: "MaoShot", dependencies: ["MaoShotCore"]),
        .testTarget(name: "MaoShotCoreTests", dependencies: ["MaoShotCore"]),
    ]
)
