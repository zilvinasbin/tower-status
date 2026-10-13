// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TowerBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TowerCore"),
        .executableTarget(name: "TowerBar", dependencies: ["TowerCore"]),
        .testTarget(name: "TowerCoreTests", dependencies: ["TowerCore"], resources: [.copy("Fixtures")]),
    ]
)
